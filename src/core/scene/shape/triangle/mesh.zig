const Transformation = @import("../../composed_transformation.zig").ComposedTransformation;
const Worker = @import("../../worker.zig").Worker;
const Scene = @import("../../scene.zig").Scene;
const Filter = @import("../../../image/texture/sampler.zig").Filter;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const NodeStack = @import("../../bvh/node_stack.zig").NodeStack;
const int = @import("../intersection.zig");
const Intersection = int.Intersection;
const Interpolation = int.Interpolation;
const smpl = @import("../sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const DifferentialSurface = smpl.DifferentialSurface;
const bvh = @import("bvh/tree.zig");
const LightTree = @import("../../light/tree.zig").PrimitiveTree;
const LightTreeBuilder = @import("../../light/tree_builder.zig").Builder;
const ro = @import("../../ray_offset.zig");
const Material = @import("../../material/material.zig").Material;
const Dot_min = @import("../../material/sample_helper.zig").Dot_min;

const base = @import("base");
const RNG = base.rnd.Generator;
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;
const Distribution1D = math.Distribution1D;
const Threads = base.thread.Pool;

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

        pub fn matches(self: Variant, m: u32, emission_map: bool, two_sided: bool, scene: Scene) bool {
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
    area: f32 = undefined,

    triangle_mapping: []u32 = &.{},
    aabbs: []AABB = &.{},
    cones: []Vec4f = &.{},

    variants: std.ArrayListUnmanaged(Variant) = .{},

    pub fn deinit(self: *Part, alloc: Allocator) void {
        for (self.variants.items) |*v| {
            v.deinit(alloc);
        }

        self.variants.deinit(alloc);

        alloc.free(self.cones);
        alloc.free(self.aabbs);
        alloc.free(self.triangle_mapping);
    }

    pub fn configure(
        self: *Part,
        alloc: Allocator,
        part: u32,
        material: u32,
        tree: bvh.Tree,
        builder: *LightTreeBuilder,
        scene: Scene,
        threads: *Threads,
    ) !u32 {
        const num = self.num_triangles;

        if (0 == self.triangle_mapping.len) {
            var total_area: f32 = 0.0;

            const triangle_mapping = try alloc.alloc(u32, num);
            const aabbs = try alloc.alloc(AABB, num);
            const cones = try alloc.alloc(Vec4f, num);

            var t: u32 = 0;
            var mt: u32 = 0;
            const len = tree.numTriangles();
            while (t < len) : (t += 1) {
                if (tree.data.part(t) == part) {
                    const area = tree.data.area(t);
                    total_area += area;

                    triangle_mapping[mt] = t;

                    const vabc = tree.data.triangleP(t);

                    var box = math.aabb.empty;
                    box.insert(vabc[0]);
                    box.insert(vabc[1]);
                    box.insert(vabc[2]);
                    box.cacheRadius();
                    box.bounds[1][3] = area;

                    aabbs[mt] = box;

                    const n = tree.data.normal(t);
                    cones[mt] = Vec4f{ n[0], n[1], n[2], 1.0 };

                    mt += 1;
                }
            }

            for (aabbs) |*b| {
                b.bounds[1][3] = total_area / b.bounds[1][3];
            }

            self.area = total_area;
            self.triangle_mapping = triangle_mapping;
            self.aabbs = aabbs;
            self.cones = cones;
        }

        const m = scene.materialPtr(material);

        const emission_map = m.emissionMapped();
        const two_sided = m.twoSided();

        for (self.variants.items) |v, i| {
            if (v.matches(material, emission_map, two_sided, scene)) {
                return @intCast(u32, i);
            }
        }

        const dimensions = m.usefulTextureDescription(scene).dimensions;

        const context = Context{
            .temps = try alloc.alloc(Temp, threads.numThreads()),
            .powers = try alloc.alloc(f32, num),
            .part = self,
            .m = m,
            .tree = &tree,
            .scene = &scene,
            .estimate_area = @intToFloat(f32, dimensions.v[0] * dimensions.v[1]) / 4.0,
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

        const da = math.normalize3(temp.dominant_axis / @splat(4, temp.total_power));

        var angle: f32 = 0.0;
        for (self.cones) |n| {
            const c = math.dot3(da, n);
            angle = std.math.max(angle, std.math.acos(c));
        }

        const v = @intCast(u32, self.variants.items.len);

        try self.variants.append(alloc, .{
            .aabb = temp.bb,
            .cone = .{ da[0], da[1], da[2], @cos(angle) },
            .material = material,
            .two_sided = two_sided,
        });

        var variant = &self.variants.items[v];
        try variant.distribution.configure(alloc, context.powers, 0);
        try builder.buildPrimitive(alloc, &variant.light_tree, self.*, v, threads);
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
        return self.aabbs[light];
    }

    pub fn lightCone(self: Part, light: u32) Vec4f {
        return self.cones[light];
    }

    pub fn lightTwoSided(self: Part, variant: u32, light: u32) bool {
        _ = light;
        return self.variants.items[variant].two_sided;
    }

    pub fn lightPower(self: Part, variant: u32, light: u32) f32 {
        const dist = self.variants.items[variant].distribution;
        return dist.pdfI(light) * dist.integral;
    }

    const Temp = struct {
        bb: AABB = math.aabb.empty,
        dominant_axis: Vec4f = @splat(4, @as(f32, 0.0)),
        total_power: f32 = 0.0,
    };

    const Context = struct {
        temps: []Temp,
        powers: []f32,
        part: *const Part,
        m: *const Material,
        tree: *const bvh.Tree,
        scene: *const Scene,
        estimate_area: f32,

        const Up = Vec4f{ 0.0, 1.0, 0.0, 0.0 };

        pub fn run(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            const self = @intToPtr(*Context, context);

            const emission_map = self.m.emissionMapped();

            var temp: Temp = .{};

            var i = begin;
            while (i < end) : (i += 1) {
                const t = self.part.triangle_mapping[i];
                const area = self.tree.data.area(t);

                var pow: f32 = undefined;
                if (emission_map) {
                    const puv = self.tree.data.trianglePuv(t);
                    const uv_area = triangleArea(puv.uv[0], puv.uv[1], puv.uv[2]);
                    const num_samples = std.math.max(@floatToInt(u32, @round(uv_area * self.estimate_area + 0.5)), 1);

                    var radiance = @splat(4, @as(f32, 0.0));

                    var j: u32 = 0;
                    while (j < num_samples) : (j += 1) {
                        const xi = math.hammersley(j, num_samples, 0);
                        const s2 = math.smpl.triangleUniform(xi);
                        const uv = self.tree.data.interpolateUv(s2[0], s2[1], t);
                        radiance += self.m.evaluateRadiance(
                            Up,
                            Up,
                            .{ uv[0], uv[1], 0.0, 0.0 },
                            1.0,
                            null,
                            self.scene.*,
                        );
                    }

                    const weight = math.maxComponent3(radiance) / @intToFloat(f32, num_samples);
                    pow = weight * area;
                } else {
                    pow = area;
                }

                self.powers[i] = pow;

                if (pow > 0.0) {
                    const n = self.part.cones[i];
                    temp.dominant_axis += @splat(4, pow) * n;
                    temp.bb.mergeAssign(self.part.aabbs[i]);
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

    const Discrete = struct {
        global: u32,
        local: u32,
        pdf: f32,
    };

    pub fn sampleSpatial(self: Part, variant: u32, p: Vec4f, n: Vec4f, total_sphere: bool, r: f32) Discrete {
        // _ = p;
        // _ = n;
        // _ = total_sphere;

        // return self.sampleRandom(variant, r);

        const pick = self.variants.items[variant].light_tree.randomLight(p, n, total_sphere, r, self, variant);
        const relative_area = self.aabbs[pick.offset].bounds[1][3];

        return .{
            .global = self.triangle_mapping[pick.offset],
            .local = pick.offset,
            .pdf = pick.pdf * relative_area,
        };
    }

    pub fn sampleRandom(self: Part, variant: u32, r: f32) Discrete {
        const pick = self.variants.items[variant].distribution.sampleDiscrete(r);
        const relative_area = self.aabbs[pick.offset].bounds[1][3];

        return .{
            .global = self.triangle_mapping[pick.offset],
            .local = pick.offset,
            .pdf = pick.pdf * relative_area,
        };
    }

    pub fn pdfSpatial(self: Part, variant: u32, p: Vec4f, n: Vec4f, total_sphere: bool, id: u32) f32 {
        // _ = p;
        // _ = n;
        // _ = total_sphere;

        // return self.pdfRandom(variant, id);

        const pdf = self.variants.items[variant].light_tree.pdf(p, n, total_sphere, id, self, variant);
        const relative_area = self.aabbs[id].bounds[1][3];

        return pdf * relative_area;
    }

    pub fn pdfRandom(self: Part, variant: u32, id: u32) f32 {
        const pdf = self.variants.items[variant].distribution.pdfI(id);
        const relative_area = self.aabbs[id].bounds[1][3];

        return pdf * relative_area;
    }
};

pub const Mesh = struct {
    tree: bvh.Tree = .{},

    parts: []Part,

    primitive_mapping: []u32 = &.{},

    pub fn init(alloc: Allocator, num_parts: u32) !Mesh {
        const parts = try alloc.alloc(Part, num_parts);
        std.mem.set(Part, parts, .{});

        return Mesh{ .parts = parts };
    }

    pub fn deinit(self: *Mesh, alloc: Allocator) void {
        alloc.free(self.primitive_mapping);

        for (self.parts) |*p| {
            p.deinit(alloc);
        }

        alloc.free(self.parts);
        self.tree.deinit(alloc);
    }

    pub fn numParts(self: Mesh) u32 {
        return @intCast(u32, self.parts.len);
    }

    pub fn numMaterials(self: Mesh) u32 {
        var id: u32 = 0;

        for (self.parts) |p| {
            id = std.math.max(id, p.material);
        }

        return id + 1;
    }

    pub fn partMaterialId(self: Mesh, part: u32) u32 {
        return self.parts[part].material;
    }

    pub fn setMaterialForPart(self: *Mesh, part: usize, material: u32) void {
        self.parts[part].material = material;
    }

    pub fn area(self: Mesh, part: u32, scale: Vec4f) f32 {
        // HACK: This only really works for uniform scales!
        return self.parts[part].area * (scale[0] * scale[1]);
    }

    pub fn partAabb(self: Mesh, part: u32, variant: u32) AABB {
        return self.parts[part].aabb(variant);
    }

    pub fn cone(self: Mesh, part: u32) Vec4f {
        return self.parts[part].variants.items[0].cone;
    }

    pub fn intersect(
        self: Mesh,
        ray: *Ray,
        trafo: Transformation,
        ipo: Interpolation,
        isec: *Intersection,
    ) bool {
        const tray = Ray.init(
            trafo.world_to_object.transformPoint(ray.origin),
            trafo.world_to_object.transformVector(ray.direction),
            ray.minT(),
            ray.maxT(),
        );

        if (self.tree.intersect(tray)) |hit| {
            ray.setMaxT(hit.t);

            const p = self.tree.data.interpolateP(hit.u, hit.v, hit.index);
            isec.p = trafo.objectToWorldPoint(p);

            const geo_n = self.tree.data.normal(hit.index);
            isec.geo_n = trafo.rotation.transformVector(geo_n);

            isec.part = self.tree.data.part(hit.index);
            isec.primitive = hit.index;

            if (.All == ipo) {
                var t: Vec4f = undefined;
                var n: Vec4f = undefined;
                var uv: Vec2f = undefined;
                self.tree.data.interpolateData(hit.u, hit.v, hit.index, &t, &n, &uv);

                const t_w = trafo.rotation.transformVector(t);
                const n_w = trafo.rotation.transformVector(n);
                const b_w = @splat(4, self.tree.data.bitangentSign(hit.index)) * math.cross3(n_w, t_w);

                isec.t = t_w;
                isec.b = b_w;
                isec.n = n_w;
                isec.uv = uv;
            } else if (.NoTangentSpace == ipo) {
                const uv = self.tree.data.interpolateUv(hit.u, hit.v, hit.index);
                isec.uv = uv;
            } else {
                const n = self.tree.data.interpolateShadingNormal(hit.u, hit.v, hit.index);
                const n_w = trafo.rotation.transformVector(n);
                isec.n = n_w;
            }

            return true;
        }

        return false;
    }

    pub fn intersectP(self: Mesh, ray: Ray, trafo: Transformation) bool {
        var tray = Ray.init(
            trafo.world_to_object.transformPoint(ray.origin),
            trafo.world_to_object.transformVector(ray.direction),
            ray.minT(),
            ray.maxT(),
        );

        return self.tree.intersectP(tray);
    }

    pub fn visibility(
        self: Mesh,
        ray: Ray,
        trafo: Transformation,
        entity: usize,
        filter: ?Filter,
        worker: *Worker,
    ) ?Vec4f {
        const tray = Ray.init(
            trafo.world_to_object.transformPoint(ray.origin),
            trafo.world_to_object.transformVector(ray.direction),
            ray.minT(),
            ray.maxT(),
        );

        return self.tree.visibility(tray, entity, filter, worker);
    }

    pub fn sampleTo(
        self: Mesh,
        part: u32,
        variant: u32,
        p: Vec4f,
        n: Vec4f,
        trafo: Transformation,
        extent: f32,
        two_sided: bool,
        total_sphere: bool,
        sampler: *Sampler,
        rng: *RNG,
    ) ?SampleTo {
        const r = sampler.sample3D(rng);

        const op = trafo.worldToObjectPoint(p);
        const on = trafo.worldToObjectNormal(n);
        const s = self.parts[part].sampleSpatial(variant, op, on, total_sphere, r[0]);

        if (0.0 == s.pdf) {
            return null;
        }

        var sv: Vec4f = undefined;
        var tc: Vec2f = undefined;
        self.tree.data.sample(s.global, .{ r[1], r[2] }, &sv, &tc);
        const v = trafo.objectToWorldPoint(sv);
        const sn = self.parts[part].lightCone(s.local);
        var wn = trafo.rotation.transformVector(sn);

        if (two_sided and math.dot3(wn, v - p) > 0.0) {
            wn = -wn;
        }

        const axis = ro.offsetRay(v, wn) - p;
        const sl = math.squaredLength3(axis);
        const d = @sqrt(sl);
        const dir = axis / @splat(4, d);
        const c = -math.dot3(wn, dir);

        if (c < Dot_min) {
            return null;
        }

        const angle_pdf = sl / (c * extent);

        return SampleTo.init(
            dir,
            wn,
            .{ tc[0], tc[1], 0.0, 0.0 },
            angle_pdf * s.pdf,
            d,
        );
    }

    pub fn sampleFrom(
        self: Mesh,
        part: u32,
        variant: u32,
        trafo: Transformation,
        extent: f32,
        two_sided: bool,
        sampler: *Sampler,
        rng: *RNG,
        uv: Vec2f,
        importance_uv: Vec2f,
    ) ?SampleFrom {
        const r = sampler.sample1D(rng);
        const s = self.parts[part].sampleRandom(variant, r);

        var sv: Vec4f = undefined;
        var tc: Vec2f = undefined;
        self.tree.data.sample(s.global, uv, &sv, &tc);
        const ws = trafo.objectToWorldPoint(sv);
        const sn = self.parts[part].lightCone(s.local);
        var wn = trafo.rotation.transformVector(sn);

        const xy = math.orthonormalBasis3(wn);
        var dir = math.smpl.orientedHemisphereUniform(importance_uv, xy[0], xy[1], wn);

        //  if (two_sided and sampler.sample1D(rng, sampler_d) > 0.5) {
        if (two_sided and rng.randomFloat() > 0.5) {
            wn = -wn;
            dir = -dir;
        }

        return SampleFrom.init(
            ro.offsetRay(ws, wn),
            wn,
            dir,
            .{ tc[0], tc[1], 0.0, 0.0 },
            importance_uv,
            s.pdf / (std.math.pi * extent),
        );
    }

    pub fn pdf(
        self: Mesh,
        variant: u32,
        ray: Ray,
        n: Vec4f,
        isec: Intersection,
        trafo: Transformation,
        extent: f32,
        two_sided: bool,
        total_sphere: bool,
    ) f32 {
        var c = -math.dot3(isec.geo_n, ray.direction);

        if (two_sided) {
            c = @fabs(c);
        }

        const sl = ray.maxT() * ray.maxT();
        const angle_pdf = sl / (c * extent);

        const op = trafo.worldToObjectPoint(ray.origin);
        const on = trafo.worldToObjectNormal(n);

        const pm = self.primitive_mapping[isec.primitive];
        const tri_pdf = self.parts[isec.part].pdfSpatial(variant, op, on, total_sphere, pm);

        return angle_pdf * tri_pdf;
    }

    pub fn prepareSampling(
        self: *Mesh,
        alloc: Allocator,
        part: u32,
        material: u32,
        builder: *LightTreeBuilder,
        scene: Scene,
        threads: *Threads,
    ) !u32 {
        // This counts the triangles for _every_ part as an optimization
        if (0 == self.primitive_mapping.len) {
            const num_triangles = self.tree.numTriangles();

            self.primitive_mapping = try alloc.alloc(u32, num_triangles);

            var i: u32 = 0;
            while (i < num_triangles) : (i += 1) {
                const p = &self.parts[self.tree.data.part(i)];
                const pm = p.num_triangles;
                p.num_triangles = pm + 1;
                self.primitive_mapping[i] = pm;
            }
        }

        return try self.parts[part].configure(alloc, part, material, self.tree, builder, scene, threads);
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
                dpdu = Vec4f{ -ng[2], 0, ng[0], 0.0 } / @splat(4, @sqrt(ng[0] * ng[0] + ng[2] * ng[2]));
            } else {
                dpdu = Vec4f{ 0, ng[2], -ng[1], 0.0 } / @splat(4, @sqrt(ng[1] * ng[1] + ng[2] * ng[2]));
            }

            dpdv = math.cross3(ng, dpdu);
        } else {
            const invdet = 1.0 / determinant;

            dpdu = @splat(4, invdet) * (@splat(4, duv12[1]) * dp02 - @splat(4, duv02[1]) * dp12);
            dpdv = @splat(4, invdet) * (@splat(4, -duv12[0]) * dp02 + @splat(4, duv02[0]) * dp12);
        }

        return .{ .dpdu = dpdu, .dpdv = dpdv };
    }
};
