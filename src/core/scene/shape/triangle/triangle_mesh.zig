const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const Scene = @import("../../scene.zig").Scene;
const Worker = @import("../../../rendering/worker.zig").Worker;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const NodeStack = @import("../../bvh/node_stack.zig").NodeStack;
const int = @import("../intersection.zig");
const Intersection = int.Intersection;
const Interpolation = int.Interpolation;
const Volume = int.Volume;
const smpl = @import("../sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const DifferentialSurface = smpl.DifferentialSurface;
const Tree = @import("bvh/triangle_tree.zig").Tree;
const tri = @import("triangle.zig");
const LightTree = @import("../../light/light_tree.zig").PrimitiveTree;
const LightTreeBuilder = @import("../../light/light_tree_builder.zig").Builder;
const LightProperties = @import("../../light/light.zig").Properties;
const ro = @import("../../ray_offset.zig");
const Material = @import("../../material/material.zig").Material;
const Dot_min = @import("../../material/sample_helper.zig").Dot_min;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Mat3x3 = math.Mat3x3;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Vec4i = math.Vec4i;
const Ray = math.Ray;
const Distribution1D = math.Distribution1D;
const Threads = base.thread.Pool;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Part = struct {
    const Variant = struct {
        distribution: Distribution1D = .{},

        light_tree: LightTree = .{},

        aabb: AABB,
        cone: Vec4f,

        material: u32,
        two_sided: bool,

        pub fn deinit(self: *Variant, alloc: Allocator) void {
            self.light_tree.deinit(alloc);
            self.distribution.deinit(alloc);
        }

        pub fn matches(self: Variant, m: u32, emission_map: bool, two_sided: bool, scene: *const Scene) bool {
            if (self.material == m) {
                return true;
            }

            const lm = scene.material(self.material);
            if (!lm.emissionMapped() and !emission_map) {
                return self.two_sided == two_sided;
            }

            return false;
        }
    };

    material: u32 = 0,
    num_triangles: u32 = 0,
    num_alloc: u32 = 0,
    area: f32 = undefined,

    triangle_mapping: [*]u32 = undefined,

    tree: *const Tree = undefined,

    variants: std.ArrayListUnmanaged(Variant) = .{},

    pub fn deinit(self: *Part, alloc: Allocator) void {
        for (self.variants.items) |*v| {
            v.deinit(alloc);
        }

        self.variants.deinit(alloc);

        const num = self.num_alloc;
        alloc.free(self.triangle_mapping[0..num]);
    }

    pub fn configure(
        self: *Part,
        alloc: Allocator,
        prop: u32,
        part: u32,
        material: u32,
        tree: *const Tree,
        builder: *LightTreeBuilder,
        scene: *const Scene,
        threads: *Threads,
    ) !u32 {
        const num = self.num_triangles;

        if (0 == self.num_alloc) {
            const triangle_mapping = (try alloc.alloc(u32, num)).ptr;

            var t: u32 = 0;
            var mt: u32 = 0;
            const len = tree.numTriangles();
            while (t < len) : (t += 1) {
                if (tree.data.part(t) == part) {
                    triangle_mapping[mt] = t;
                    mt += 1;
                }
            }

            self.num_alloc = num;
            self.triangle_mapping = triangle_mapping;
            self.tree = tree;
        }

        const m = scene.material(material);

        const emission_map = m.emissionMapped();
        const two_sided = m.twoSided();

        for (self.variants.items, 0..) |v, i| {
            if (v.matches(material, emission_map, two_sided, scene)) {
                return @intCast(i);
            }
        }

        const dimensions: Vec4i = if (m.usefulTexture()) |t| t.description(scene).dimensions else @splat(0);
        var context = Context{
            .temps = try alloc.alloc(Temp, threads.numThreads()),
            .powers = try alloc.alloc(f32, num),
            .part = self,
            .m = m,
            .tree = tree,
            .scene = scene,
            .prop_id = prop,
            .part_id = part,
            .estimate_area = @as(f32, @floatFromInt(dimensions[0] * dimensions[1])) / 4.0,
        };
        defer {
            alloc.free(context.powers);
            alloc.free(context.temps);
        }

        const num_tasks = threads.runRange(&context, Context.run, 0, num, 0);

        var temp: Temp = .{};
        for (context.temps[0..num_tasks]) |t| {
            temp.bb.mergeAssign(t.bb);
            temp.dominant_axis += t.dominant_axis;
            temp.total_power += t.total_power;
        }

        const da = math.normalize3(temp.dominant_axis / @as(Vec4f, @splat(temp.total_power)));

        var angle: f32 = 0.0;
        for (self.triangle_mapping[0..self.num_alloc]) |t| {
            const n = self.tree.data.normal(t);
            const c = math.dot3(da, n);
            angle = math.max(angle, std.math.acos(c));
        }

        const v = @as(u32, @intCast(self.variants.items.len));

        try self.variants.append(alloc, .{
            .aabb = temp.bb,
            .cone = .{ da[0], da[1], da[2], @cos(angle) },
            .material = material,
            .two_sided = two_sided,
        });

        var variant = &self.variants.items[v];
        try variant.distribution.configure(alloc, context.powers, 0);
        try builder.buildPrimitive(alloc, &variant.light_tree, self, v, threads);
        return v;
    }

    pub fn aabb(self: Part, variant: u32) AABB {
        return self.variants.items[variant].aabb;
    }

    pub fn power(self: Part, variant: u32) f32 {
        return self.variants.items[variant].distribution.integral;
    }

    pub fn cone(self: Part, variant: u32) Vec4f {
        return self.variants.items[variant].cone;
    }

    pub fn lightAabb(self: Part, light: u32) AABB {
        const global = self.triangle_mapping[light];
        const abc = self.tree.data.triangleP(global);
        return AABB.init(tri.min(abc[0], abc[1], abc[2]), tri.max(abc[0], abc[1], abc[2]));
    }

    pub fn lightCone(self: Part, light: u32) Vec4f {
        const global = self.triangle_mapping[light];
        const n = self.tree.data.normal(global);
        return .{ n[0], n[1], n[2], 1.0 };
    }

    pub fn lightTwoSided(self: Part, variant: u32, light: u32) bool {
        _ = light;
        return self.variants.items[variant].two_sided;
    }

    pub fn lightPower(self: Part, variant: u32, light: u32) f32 {
        // I think it is fine to just give the primitives relative power in this case
        const dist = self.variants.items[variant].distribution;
        return dist.pdfI(light);
    }

    pub fn lightProperties(self: Part, light: u32, variant: u32) LightProperties {
        const global = self.triangle_mapping[light];

        const abc = self.tree.data.triangleP(global);

        const center = (abc[0] + abc[1] + abc[2]) / @as(Vec4f, @splat(3.0));

        const sra = math.squaredLength3(abc[0] - center);
        const srb = math.squaredLength3(abc[1] - center);
        const src = math.squaredLength3(abc[2] - center);

        const radius = @sqrt(math.max(sra, math.max(srb, src)));

        const e1 = abc[1] - abc[0];
        const e2 = abc[2] - abc[0];
        const n = math.normalize3(math.cross3(e1, e2));

        // I think it is fine to just give the primitives relative power in this case
        const dist = self.variants.items[variant].distribution;
        const pow = dist.pdfI(light);

        return .{
            .sphere = .{ center[0], center[1], center[2], radius },
            .cone = .{ n[0], n[1], n[2], 1.0 },
            .power = pow,
            .two_sided = self.variants.items[variant].two_sided,
        };
    }

    const Temp = struct {
        bb: AABB = math.aabb.Empty,
        dominant_axis: Vec4f = @splat(0.0),
        total_power: f32 = 0.0,
    };

    const Context = struct {
        temps: []Temp,
        powers: []f32,
        part: *const Part,
        m: *const Material,
        tree: *const Tree,
        scene: *const Scene,
        estimate_area: f32,
        prop_id: u32,
        part_id: u32,

        const Pos = Vec4f{ 0.0, 0.0, 0.0, 0.0 };
        const Dir = Vec4f{ 0.0, 0.0, 1.0, 0.0 };

        const IdTrafo = Trafo{
            .rotation = Mat3x3.init9(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0),
            .position = @splat(0.0),
        };

        pub fn run(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            const self = @as(*Context, @ptrCast(context));

            const emission_map = self.m.emissionMapped();

            var temp: Temp = .{};

            for (begin..end) |i| {
                const t = self.part.triangle_mapping[i];
                const area = self.tree.data.area(t);

                var pow: f32 = undefined;
                if (emission_map) {
                    var rng = RNG{};
                    rng.start(0, i);

                    var sampler = Sampler{ .Random = .{ .rng = &rng } };

                    const puv = self.tree.data.trianglePuv(t);
                    const uv_area = triangleArea(puv.uv[0], puv.uv[1], puv.uv[2]);
                    const num_samples = @max(@as(u32, @intFromFloat(@round(uv_area * self.estimate_area + 0.5))), 1);

                    var radiance: Vec4f = @splat(0.0);

                    var j: u32 = 0;
                    while (j < num_samples) : (j += 1) {
                        const xi = math.hammersley(j, num_samples, 0);
                        const s2 = math.smpl.triangleUniform(xi);
                        const uv = self.tree.data.interpolateUv(s2[0], s2[1], t);
                        radiance += self.m.evaluateRadiance(
                            Pos,
                            Dir,
                            Dir,
                            .{ uv[0], uv[1], 0.0, 0.0 },
                            IdTrafo,
                            self.prop_id,
                            self.part_id,
                            &sampler,
                            self.scene,
                        );
                    }

                    pow = if (math.hmax3(radiance) > 0.0) area else 0.0;
                } else {
                    pow = area;
                }

                self.powers[i] = pow;

                if (pow > 0.0) {
                    const n = self.tree.data.normal(t);
                    temp.dominant_axis += @as(Vec4f, @splat(pow)) * n;
                    temp.bb.mergeAssign(self.part.lightAabb(@as(u32, @intCast(i))));
                    temp.total_power += pow;
                }
            }

            self.temps[id] = temp;
        }

        fn triangleArea(a: Vec2f, b: Vec2f, c: Vec2f) f32 {
            const x = b - a;
            const y = c - a;

            return 0.5 * @fabs(x[0] * y[1] - x[1] * y[0]);
        }
    };

    pub fn sampleSpatial(self: Part, variant: u32, p: Vec4f, n: Vec4f, total_sphere: bool, r: f32) Distribution1D.Discrete {
        // _ = p;
        // _ = n;
        // _ = total_sphere;

        // return self.sampleRandom(variant, r);

        return self.variants.items[variant].light_tree.randomLight(p, n, total_sphere, r, &self, variant);
    }

    pub fn sampleRandom(self: Part, variant: u32, r: f32) Distribution1D.Discrete {
        return self.variants.items[variant].distribution.sampleDiscrete(r);
    }

    pub fn pdfSpatial(self: Part, variant: u32, p: Vec4f, n: Vec4f, total_sphere: bool, id: u32) f32 {
        // _ = p;
        // _ = n;
        // _ = total_sphere;

        // return self.variants.items[variant].distribution.pdfI(id);

        return self.variants.items[variant].light_tree.pdf(p, n, total_sphere, id, &self, variant);
    }
};

pub const Mesh = struct {
    tree: Tree = .{},

    num_parts: u32 = 0,
    num_primitives: u32 = 0,

    parts: [*]Part = undefined,
    primitive_mapping: [*]u32 = undefined,

    pub fn init(alloc: Allocator, num_parts: u32) !Mesh {
        const parts = try alloc.alloc(Part, num_parts);
        @memset(parts, .{});

        return Mesh{ .num_parts = num_parts, .parts = parts.ptr };
    }

    pub fn deinit(self: *Mesh, alloc: Allocator) void {
        alloc.free(self.primitive_mapping[0..self.num_primitives]);

        var parts = self.parts[0..self.num_parts];

        for (parts) |*p| {
            p.deinit(alloc);
        }

        alloc.free(parts);
        self.tree.deinit(alloc);
    }

    pub fn numParts(self: Mesh) u32 {
        return self.num_parts;
    }

    pub fn numMaterials(self: Mesh) u32 {
        var id: u32 = 0;

        for (self.parts[0..self.num_parts]) |p| {
            id = @max(id, p.material);
        }

        return id + 1;
    }

    pub fn partMaterialId(self: Mesh, part: u32) u32 {
        return self.parts[part].material;
    }

    pub fn setMaterialForPart(self: *Mesh, part: usize, material: u32) void {
        self.parts[part].material = material;
    }

    pub fn area(self: *const Mesh, part: u32, scale: Vec4f) f32 {
        // HACK: This only really works for uniform scales!
        return self.parts[part].area * (scale[0] * scale[1]);
    }

    pub fn partAabb(self: *const Mesh, part: u32, variant: u32) AABB {
        return self.parts[part].aabb(variant);
    }

    pub fn cone(self: *const Mesh, part: u32, variant: u32) Vec4f {
        return self.parts[part].cone(variant);
    }

    pub fn intersect(self: Mesh, ray: *Ray, trafo: Trafo, ipo: Interpolation, isec: *Intersection) bool {
        const tray = trafo.worldToObjectRay(ray.*);

        if (self.tree.intersect(tray)) |hit| {
            const data = self.tree.data;

            ray.setMaxT(hit.t);

            const p = data.interpolateP(hit.u, hit.v, hit.index);
            isec.p = trafo.objectToWorldPoint(p);

            const geo_n = data.normal(hit.index);
            isec.geo_n = trafo.rotation.transformVector(geo_n);

            isec.part = data.part(hit.index);
            isec.primitive = hit.index;

            if (.All == ipo) {
                var t: Vec4f = undefined;
                var n: Vec4f = undefined;
                var uv: Vec2f = undefined;
                data.interpolateData(hit.u, hit.v, hit.index, &t, &n, &uv);

                const t_w = trafo.rotation.transformVector(t);
                const n_w = trafo.rotation.transformVector(n);
                const b_w = @as(Vec4f, @splat(data.bitangentSign(hit.index))) * math.cross3(n_w, t_w);

                isec.t = t_w;
                isec.b = b_w;
                isec.n = n_w;
                isec.uv = uv;
            } else if (.NoTangentSpace == ipo) {
                const uv = data.interpolateUv(hit.u, hit.v, hit.index);
                isec.uv = uv;
            } else {
                const n = data.interpolateShadingNormal(hit.u, hit.v, hit.index);
                const n_w = trafo.rotation.transformVector(n);
                isec.n = n_w;
            }

            return true;
        }

        return false;
    }

    pub fn intersectP(self: Mesh, ray: Ray, trafo: Trafo) bool {
        const tray = trafo.worldToObjectRay(ray);
        return self.tree.intersectP(tray);
    }

    pub fn visibility(
        self: Mesh,
        ray: Ray,
        trafo: Trafo,
        entity: u32,
        sampler: *Sampler,
        scene: *const Scene,
    ) ?Vec4f {
        const tray = trafo.worldToObjectRay(ray);
        return self.tree.visibility(tray, entity, sampler, scene);
    }

    pub fn transmittance(
        self: Mesh,
        ray: Ray,
        trafo: Trafo,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        worker: *Worker,
    ) ?Vec4f {
        const tray = trafo.worldToObjectRay(ray);
        return self.tree.transmittance(tray, entity, depth, sampler, worker);
    }

    pub fn scatter(
        self: Mesh,
        ray: Ray,
        trafo: Trafo,
        throughput: Vec4f,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        worker: *Worker,
    ) Volume {
        const tray = trafo.worldToObjectRay(ray);
        return self.tree.scatter(tray, throughput, entity, depth, sampler, worker);
    }

    pub fn sampleTo(
        self: Mesh,
        part_id: u32,
        variant: u32,
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        two_sided: bool,
        total_sphere: bool,
        sampler: *Sampler,
    ) ?SampleTo {
        const r = sampler.sample3D();

        const op = trafo.worldToObjectPoint(p);
        const on = trafo.worldToObjectNormal(n);

        const part = self.parts[part_id];
        const s = part.sampleSpatial(variant, op, on, total_sphere, r[0]);
        if (0.0 == s.pdf) {
            return null;
        }

        const global = part.triangle_mapping[s.offset];

        var sv: Vec4f = undefined;
        var tc: Vec2f = undefined;
        self.tree.data.sample(global, .{ r[1], r[2] }, &sv, &tc);
        const v = trafo.objectToWorldPoint(sv);

        const ca = (trafo.scale() * trafo.scale()) * self.tree.data.crossAxis(global);
        const lca = math.length3(ca);
        const sn = ca / @as(Vec4f, @splat(lca));
        var wn = trafo.rotation.transformVector(sn);

        if (two_sided and math.dot3(wn, v - p) > 0.0) {
            wn = -wn;
        }

        const axis = ro.offsetRay(v, wn) - p;
        const sl = math.squaredLength3(axis);
        const d = @sqrt(sl);
        const dir = axis / @as(Vec4f, @splat(d));
        const c = -math.dot3(wn, dir);

        if (c < Dot_min) {
            return null;
        }

        const tri_area = 0.5 * lca;

        return SampleTo.init(
            dir,
            wn,
            .{ tc[0], tc[1], 0.0, 0.0 },
            trafo,
            (sl * s.pdf) / (c * tri_area),
            d,
        );
    }

    pub fn sampleFrom(
        self: Mesh,
        part_id: u32,
        variant: u32,
        trafo: Trafo,
        two_sided: bool,
        sampler: *Sampler,
        uv: Vec2f,
        importance_uv: Vec2f,
    ) ?SampleFrom {
        const r = sampler.sample1D();

        const part = self.parts[part_id];
        const s = part.sampleRandom(variant, r);

        const global = part.triangle_mapping[s.offset];

        var sv: Vec4f = undefined;
        var tc: Vec2f = undefined;
        self.tree.data.sample(global, uv, &sv, &tc);
        const ws = trafo.objectToWorldPoint(sv);

        const ca = (trafo.scale() * trafo.scale()) * self.tree.data.crossAxis(global);
        const lca = math.length3(ca);
        const sn = ca / @as(Vec4f, @splat(lca));
        var wn = trafo.rotation.transformVector(sn);

        const xy = math.orthonormalBasis3(wn);
        var dir = math.smpl.orientedHemisphereUniform(importance_uv, xy[0], xy[1], wn);

        if (two_sided and sampler.sample1D() > 0.5) {
            wn = -wn;
            dir = -dir;
        }

        const tri_area = 0.5 * lca;

        const extent = @as(f32, if (two_sided) 2.0 else 1.0) * tri_area;

        return SampleFrom.init(
            ro.offsetRay(ws, wn),
            wn,
            dir,
            .{ tc[0], tc[1], 0.0, 0.0 },
            importance_uv,
            trafo,
            s.pdf / (std.math.pi * extent),
        );
    }

    pub fn pdf(
        self: Mesh,
        part_id: u32,
        variant: u32,
        ray: Ray,
        n: Vec4f,
        isec: Intersection,
        two_sided: bool,
        total_sphere: bool,
    ) f32 {
        var c = -math.dot3(isec.geo_n, ray.direction);

        if (two_sided) {
            c = @fabs(c);
        }

        const sl = ray.maxT() * ray.maxT();

        const op = isec.trafo.worldToObjectPoint(ray.origin);
        const on = isec.trafo.worldToObjectNormal(n);

        const pm = self.primitive_mapping[isec.primitive];

        const part = self.parts[part_id];
        const tri_pdf = part.pdfSpatial(variant, op, on, total_sphere, pm);

        const ca = (isec.trafo.scale() * isec.trafo.scale()) * self.tree.data.crossAxis(isec.primitive);
        const tri_area = 0.5 * math.length3(ca);

        return (sl * tri_pdf) / (c * tri_area);
    }

    pub fn calculateAreas(self: *Mesh) void {
        var p: u32 = 0;
        const np = self.num_parts;
        while (p < np) : (p += 1) {
            self.parts[p].area = 0.0;
        }

        var t: u32 = 0;
        const nt = self.tree.numTriangles();
        while (t < nt) : (t += 1) {
            self.parts[self.tree.data.part(t)].area += self.tree.data.area(t);
        }
    }

    pub fn prepareSampling(
        self: *Mesh,
        alloc: Allocator,
        prop: u32,
        part: u32,
        material: u32,
        builder: *LightTreeBuilder,
        scene: *const Scene,
        threads: *Threads,
    ) !u32 {
        // This counts the triangles for _every_ part as an optimization
        if (0 == self.num_primitives) {
            const num_triangles = self.tree.numTriangles();

            self.num_primitives = num_triangles;
            var primitive_mapping = (try alloc.alloc(u32, num_triangles)).ptr;

            var i: u32 = 0;
            while (i < num_triangles) : (i += 1) {
                const p = &self.parts[self.tree.data.part(i)];
                const pm = p.num_triangles;
                p.num_triangles = pm + 1;
                primitive_mapping[i] = pm;
            }

            self.primitive_mapping = primitive_mapping;
        }

        return try self.parts[part].configure(alloc, prop, part, material, &self.tree, builder, scene, threads);
    }

    pub fn differentialSurface(self: Mesh, primitive: u32) DifferentialSurface {
        const puv = self.tree.data.trianglePuv(primitive);

        const duv02 = puv.uv[0] - puv.uv[2];
        const duv12 = puv.uv[1] - puv.uv[2];
        const determinant = duv02[0] * duv12[1] - duv02[1] * duv12[0];

        var dpdu: Vec4f = undefined;
        var dpdv: Vec4f = undefined;

        const dp02 = puv.p[0] - puv.p[2];
        const dp12 = puv.p[1] - puv.p[2];

        if (0.0 == @fabs(determinant)) {
            const ng = math.normalize3(math.cross3(puv.p[2] - puv.p[0], puv.p[1] - puv.p[0]));

            if (@fabs(ng[0]) > @fabs(ng[1])) {
                dpdu = Vec4f{ -ng[2], 0, ng[0], 0.0 } / @as(Vec4f, @splat(@sqrt(ng[0] * ng[0] + ng[2] * ng[2])));
            } else {
                dpdu = Vec4f{ 0, ng[2], -ng[1], 0.0 } / @as(Vec4f, @splat(@sqrt(ng[1] * ng[1] + ng[2] * ng[2])));
            }

            dpdv = math.cross3(ng, dpdu);
        } else {
            const invdet = 1.0 / determinant;

            dpdu = @as(Vec4f, @splat(invdet)) * (@as(Vec4f, @splat(duv12[1])) * dp02 - @as(Vec4f, @splat(duv02[1])) * dp12);
            dpdv = @as(Vec4f, @splat(invdet)) * (@as(Vec4f, @splat(-duv12[0])) * dp02 + @as(Vec4f, @splat(duv02[0])) * dp12);
        }

        return .{ .dpdu = dpdu, .dpdv = dpdv };
    }
};
