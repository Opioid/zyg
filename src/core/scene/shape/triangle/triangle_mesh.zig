const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const Context = @import("../../context.zig").Context;
const Scene = @import("../../scene.zig").Scene;
const Vertex = @import("../../vertex.zig").Vertex;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const NodeStack = @import("../../bvh/node_stack.zig").NodeStack;
const int = @import("../intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Volume = int.Volume;
const DifferentialSurface = int.DifferentialSurface;
const Probe = @import("../probe.zig").Probe;
const smpl = @import("../sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const Tree = @import("triangle_tree.zig").Tree;
const tri = @import("triangle.zig");
const LightTree = @import("../../light/light_tree.zig").PrimitiveTree;
const LightTreeBuilder = @import("../../light/light_tree_builder.zig").Builder;
const LightProperties = @import("../../light/light.zig").Properties;
const ro = @import("../../ray_offset.zig");
const Material = @import("../../material/material.zig").Material;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Frame = math.Frame;
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
            if (!lm.emissionImageMapped() and !emission_map) {
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

    variants: std.ArrayListUnmanaged(Variant) = .empty,

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
                if (tree.data.trianglePart(t) == part) {
                    triangle_mapping[mt] = t;
                    mt += 1;
                }
            }

            self.num_alloc = num;
            self.triangle_mapping = triangle_mapping;
            self.tree = tree;
        }

        const m = scene.material(material);

        const emission_map = m.emissionImageMapped();
        const two_sided = m.twoSided();

        for (self.variants.items, 0..) |v, i| {
            if (v.matches(material, emission_map, two_sided, scene)) {
                return @intCast(i);
            }
        }

        const dimensions: Vec4i = if (m.usefulTexture()) |t| t.dimensions(scene) else @splat(0);
        var context = EvalContext{
            .temps = try alloc.alloc(Temp, threads.numThreads()),
            .powers = try alloc.alloc(f32, num),
            .part = self,
            .m = m,
            .tree = tree,
            .scene = scene,
            .estimate_area = @as(f32, @floatFromInt(dimensions[0] * dimensions[1])) / 4.0,
        };
        defer {
            alloc.free(context.powers);
            alloc.free(context.temps);
        }

        const num_tasks = threads.runRange(&context, EvalContext.run, 0, num, 0);

        var temp: Temp = .{};
        for (context.temps[0..num_tasks]) |t| {
            temp.bb.mergeAssign(t.bb);
            temp.dominant_axis += t.dominant_axis;
            temp.total_power += t.total_power;
        }

        var cone: Vec4f = undefined;

        if (temp.dominant_axis[0] == temp.dominant_axis[1] and temp.dominant_axis[1] == temp.dominant_axis[2]) {
            // There are meshes where the dominant axis comes out as [0, 0, 0], because they emit equally in every direction
            cone = .{ 0.0, 0.0, 1.0, -1.0 };
        } else {
            const da = math.normalize3(temp.dominant_axis / @as(Vec4f, @splat(temp.total_power)));
            var angle: f32 = 0.0;
            for (self.triangle_mapping[0..self.num_alloc]) |t| {
                const n = self.tree.data.normal(self.tree.data.indexTriangle(t));
                const c = math.dot3(da, n);
                angle = math.max(angle, std.math.acos(c));
            }

            cone = .{ da[0], da[1], da[2], @cos(angle) };
        }

        const v: u32 = @intCast(self.variants.items.len);

        try self.variants.append(alloc, .{
            .aabb = temp.bb,
            .cone = cone,
            .material = material,
            .two_sided = two_sided,
        });

        var variant = &self.variants.items[v];

        try variant.distribution.configure(alloc, context.powers, 0);
        try builder.buildPrimitive(alloc, &variant.light_tree, self, v, threads);
        return v;
    }

    pub fn aabb(self: *const Part, variant: u32) AABB {
        return self.variants.items[variant].aabb;
    }

    pub fn power(self: *const Part, variant: u32) f32 {
        return self.variants.items[variant].distribution.integral;
    }

    pub fn totalCone(self: *const Part, variant: u32) Vec4f {
        return self.variants.items[variant].cone;
    }

    pub fn lightAabb(self: *const Part, light: u32) AABB {
        const global = self.triangle_mapping[light];
        const abc = self.tree.data.triangleP(self.tree.data.indexTriangle(global));
        return AABB.init(tri.min(abc[0], abc[1], abc[2]), tri.max(abc[0], abc[1], abc[2]));
    }

    pub fn lightCone(self: *const Part, light: u32) Vec4f {
        const global = self.triangle_mapping[light];
        const n = self.tree.data.normal(self.tree.data.indexTriangle(global));
        return .{ n[0], n[1], n[2], 1.0 };
    }

    pub fn lightTwoSided(self: *const Part, variant: u32, light: u32) bool {
        _ = light;
        return self.variants.items[variant].two_sided;
    }

    pub fn lightPower(self: *const Part, variant: u32, light: u32) f32 {
        // I think it is fine to just give the primitives relative power in this case
        const dist = self.variants.items[variant].distribution;
        return dist.pdfI(light);
    }

    pub fn lightProperties(self: *const Part, light: u32, variant: u32) LightProperties {
        const global = self.triangle_mapping[light];

        const abc = self.tree.data.triangleP(self.tree.data.indexTriangle(global));

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
        bb: AABB = .empty,
        dominant_axis: Vec4f = @splat(0.0),
        total_power: f32 = 0.0,
    };

    const EvalContext = struct {
        temps: []Temp,
        powers: []f32,
        part: *const Part,
        m: *const Material,
        tree: *const Tree,
        scene: *const Scene,
        estimate_area: f32,

        pub fn run(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            const self: *EvalContext = @ptrCast(context);

            const emission_map = self.m.emissionImageMapped();

            var temp: Temp = .{};

            for (begin..end) |i| {
                const t = self.part.triangle_mapping[i];
                const itri = self.tree.data.indexTriangle(t);
                const area = self.tree.data.triangleArea(itri);

                var pow: f32 = undefined;
                if (emission_map) {
                    var rng = RNG.init(0, i);

                    var sampler = Sampler{ .Random = .{ .rng = &rng } };

                    const puv = self.tree.data.trianglePuv(itri);
                    const uv_area = triangleArea(puv.uv[0], puv.uv[1], puv.uv[2]);
                    const num_samples = @max(@as(u32, @intFromFloat(@round(uv_area * self.estimate_area + 0.5))), 1);

                    var radiance: Vec4f = @splat(0.0);

                    var j: u32 = 0;
                    while (j < num_samples) : (j += 1) {
                        const xi = math.distr.hammersley(j, num_samples, 0);
                        const s2 = math.smpl.triangleUniform(xi);
                        const uv = self.tree.data.interpolateUv(itri, s2[0], s2[1]);

                        radiance += self.m.imageRadiance(uv, &sampler, self.scene);
                    }

                    pow = if (math.hmax3(radiance) > 0.0) area else 0.0;
                } else {
                    pow = area;
                }

                self.powers[i] = pow;

                if (pow > 0.0) {
                    const n = self.tree.data.normal(itri);
                    temp.dominant_axis += @as(Vec4f, @splat(pow)) * n;

                    temp.bb.mergeAssign(self.part.lightAabb(@intCast(i)));
                    temp.total_power += pow;
                }
            }

            self.temps[id] = temp;
        }

        fn triangleArea(a: Vec2f, b: Vec2f, c: Vec2f) f32 {
            const x = b - a;
            const y = c - a;

            return 0.5 * @abs(x[0] * y[1] - x[1] * y[0]);
        }
    };

    pub fn sampleSpatial(
        self: *const Part,
        variant: u32,
        p: Vec4f,
        n: Vec4f,
        total_sphere: bool,
        r: f32,
        split_threshold: f32,
        buffer: *LightTree.Samples,
    ) []Distribution1D.Discrete {
        // _ = p;
        // _ = n;
        // _ = total_sphere;

        // return self.sampleRandom(variant, r);

        return self.variants.items[variant].light_tree.randomLight(p, n, total_sphere, r, split_threshold, self, variant, buffer);
    }

    pub fn sampleRandom(self: *const Part, variant: u32, r: f32) Distribution1D.Discrete {
        return self.variants.items[variant].distribution.sampleDiscrete(r);
    }

    pub fn pdfSpatial(self: *const Part, variant: u32, p: Vec4f, n: Vec4f, total_sphere: bool, split_threshold: f32, id: u32) f32 {
        // _ = p;
        // _ = n;
        // _ = total_sphere;

        // return self.variants.items[variant].distribution.pdfI(id);

        return self.variants.items[variant].light_tree.pdf(p, n, total_sphere, split_threshold, id, self, variant);
    }
};

pub const Mesh = struct {
    const HackArea = 0.00001;
    const HackDistance = 0.0005;

    tree: Tree = .{},

    num_parts: u32,
    num_primitives: u32 = 0,

    parts: [*]Part,
    primitive_mapping: [*]u32 = undefined,

    pub fn init(alloc: Allocator, num_parts: u32) !Mesh {
        const parts = try alloc.alloc(Part, num_parts);
        @memset(parts, .{});

        return Mesh{ .num_parts = num_parts, .parts = parts.ptr };
    }

    pub fn deinit(self: *Mesh, alloc: Allocator) void {
        alloc.free(self.primitive_mapping[0..self.num_primitives]);

        const parts = self.parts[0..self.num_parts];

        for (parts) |*p| {
            p.deinit(alloc);
        }

        alloc.free(parts);
        self.tree.deinit(alloc);
    }

    pub fn numParts(self: *const Mesh) u32 {
        return self.num_parts;
    }

    pub fn numMaterials(self: *const Mesh) u32 {
        var id: u32 = 0;

        for (self.parts[0..self.num_parts]) |p| {
            id = @max(id, p.material);
        }

        return id + 1;
    }

    pub fn partMaterialId(self: *const Mesh, part: u32) u32 {
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

    pub fn partCone(self: *const Mesh, part: u32, variant: u32) Vec4f {
        return self.parts[part].totalCone(variant);
    }

    pub fn intersect(self: *const Mesh, ray: Ray, trafo: Trafo, isec: *Intersection) bool {
        return self.tree.intersect(ray, trafo, isec);
    }

    pub fn intersectOpacity(
        self: *const Mesh,
        ray: Ray,
        trafo: Trafo,
        entity: u32,
        sampler: *Sampler,
        scene: *const Scene,
        isec: *Intersection,
    ) bool {
        return self.tree.intersectOpacity(ray, trafo, entity, sampler, scene, isec);
    }

    pub fn fragment(self: *const Mesh, frag: *Fragment) void {
        const data = self.tree.data;

        frag.part = data.trianglePart(frag.isec.primitive);

        const hit_u = frag.isec.u;
        const hit_v = frag.isec.v;

        const itri = data.indexTriangle(frag.isec.primitive);

        const geo_n = data.normal(itri);
        frag.geo_n = frag.isec.trafo.objectToWorldNormal(geo_n);

        var p: Vec4f = undefined;
        var t: Vec4f = undefined;
        var b: Vec4f = undefined;
        var n: Vec4f = undefined;
        var uv: Vec2f = undefined;
        data.interpolateData(itri, hit_u, hit_v, &p, &t, &b, &n, &uv);

        frag.p = frag.isec.trafo.objectToWorldPoint(p);
        frag.t = frag.isec.trafo.objectToWorldNormal(t);
        frag.b = frag.isec.trafo.objectToWorldNormal(b);
        frag.n = frag.isec.trafo.objectToWorldNormal(n);
        frag.uvw = .{ uv[0], uv[1], 0.0, 0.0 };
    }

    pub fn intersectP(self: *const Mesh, ray: Ray, trafo: Trafo) bool {
        const local_ray = trafo.worldToObjectRay(ray);
        return self.tree.intersectP(local_ray);
    }

    pub fn visibility(
        self: *const Mesh,
        ray: Ray,
        trafo: Trafo,
        entity: u32,
        sampler: *Sampler,
        context: Context,
        tr: *Vec4f,
    ) bool {
        const local_ray = trafo.worldToObjectRay(ray);
        return self.tree.visibility(local_ray, entity, sampler, context, tr);
    }

    pub fn transmittance(
        self: *const Mesh,
        probe: Probe,
        trafo: Trafo,
        entity: u32,
        sampler: *Sampler,
        context: Context,
        tr: *Vec4f,
    ) bool {
        return self.tree.transmittance(probe.ray, trafo, entity, probe.depth.volume, sampler, context, tr);
    }

    pub fn scatter(
        self: *const Mesh,
        probe: Probe,
        trafo: Trafo,
        throughput: Vec4f,
        entity: u32,
        sampler: *Sampler,
        context: Context,
    ) Volume {
        return self.tree.scatter(probe.ray, trafo, throughput, entity, probe.depth.volume, sampler, context);
    }

    pub fn emission(
        self: *const Mesh,
        vertex: *const Vertex,
        frag: *Fragment,
        split_threshold: f32,
        sampler: *Sampler,
        context: Context,
    ) Vec4f {
        const local_ray = frag.isec.trafo.worldToObjectRay(vertex.probe.ray);
        return self.tree.emission(local_ray, vertex, frag, split_threshold, sampler, context);
    }

    //Gram-Schmidt method
    fn orthogonalize(a: Vec4f, b: Vec4f) Vec4f {
        //we assume that a is normalized
        return math.normalize3(b - @as(Vec4f, @splat(math.dot3(a, b))) * a);
    }

    const SphericalSample = struct {
        dir: Vec4f,
        uv: Vec2f,
        pdf: f32,
    };

    // Stratified Sampling of Spherical Triangles, James Arvo
    fn sampleSpherical(pos: Vec4f, pa: Vec4f, pb: Vec4f, pc: Vec4f, r2: Vec2f) ?SphericalSample {
        const pap = pa - pos;
        const pbp = pb - pos;
        const pcp = pc - pos;

        const A = math.normalize3(pap);
        const B = math.normalize3(pbp);
        const C = math.normalize3(pcp);

        //calculate internal angles of spherical triangle: alpha, beta and gamma
        const BA = orthogonalize(A, B - A);
        const CA = orthogonalize(A, C - A);
        const AB = orthogonalize(B, A - B);
        const CB = orthogonalize(B, C - B);
        const BC = orthogonalize(C, B - C);
        const AC = orthogonalize(C, A - C);
        const cos_alpha = math.clamp(math.dot3(BA, CA), -1.0, 1.0);
        const alpha = std.math.acos(cos_alpha);
        const beta = std.math.acos(math.clamp(math.dot3(AB, CB), -1.0, 1.0));
        const gamma = std.math.acos(math.clamp(math.dot3(BC, AC), -1.0, 1.0));

        const sarea = alpha + beta + gamma - std.math.pi;

        if (0.0 == sarea) {
            return null;
        }

        //calculate arc lengths for edges of spherical triangle
        const cos_c = math.clamp(math.dot3(A, B), -1.0, 1.0);

        //Use one random variable to select the new area.
        const area_S = r2[0] * sarea;

        //Save the sine and cosine of the angle delta
        const angle_delta = area_S - alpha;
        const p = @sin(angle_delta);
        const q = @cos(angle_delta);

        // Compute the pair(u; v) that determines sin(beta_s) and cos(beta_s)
        const sin_alpha = @sqrt(1.0 - cos_alpha * cos_alpha);
        const u = q - cos_alpha;
        const v = p + sin_alpha * cos_c;

        const s = math.clamp(((v * q - u * p) * cos_alpha - v) / ((v * p + u * q) * sin_alpha), -1.0, 1.0);
        const C_s = @as(Vec4f, @splat(s)) * A + @as(Vec4f, @splat(@sqrt(1.0 - s * s))) * orthogonalize(A, C);

        //Compute the t coordinate using C_s and Xi2
        const cs_b = math.dot3(C_s, B);

        const z = 1.0 - r2[1] * (1.0 - cs_b);
        const P = @as(Vec4f, @splat(z)) * B + @as(Vec4f, @splat(@sqrt(1.0 - z * z))) * orthogonalize(B, C_s);

        const bary_uv = tri.barycentricCoords(P, pap, pbp, pcp);

        return .{
            .dir = P,
            .uv = bary_uv,
            .pdf = 1.0 / sarea,
        };
    }

    fn pdfSpherical(pos: Vec4f, pa: Vec4f, pb: Vec4f, pc: Vec4f) f32 {
        const pap = pa - pos;
        const pbp = pb - pos;
        const pcp = pc - pos;

        const A = math.normalize3(pap);
        const B = math.normalize3(pbp);
        const C = math.normalize3(pcp);

        //calculate internal angles of spherical triangle: alpha, beta and gamma
        const BA = orthogonalize(A, B - A);
        const CA = orthogonalize(A, C - A);
        const AB = orthogonalize(B, A - B);
        const CB = orthogonalize(B, C - B);
        const BC = orthogonalize(C, B - C);
        const AC = orthogonalize(C, A - C);
        const cos_alpha = math.clamp(math.dot3(BA, CA), -1.0, 1.0);
        const alpha = std.math.acos(cos_alpha);
        const beta = std.math.acos(math.clamp(math.dot3(AB, CB), -1.0, 1.0));
        const gamma = std.math.acos(math.clamp(math.dot3(BC, AC), -1.0, 1.0));

        const sarea = alpha + beta + gamma - std.math.pi;

        return 1.0 / sarea;
    }

    const Area_distance_ratio = 0.001;

    pub fn sampleTo(
        self: *const Mesh,
        part_id: u32,
        variant: u32,
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        two_sided: bool,
        total_sphere: bool,
        split_threshold: f32,
        sampler: *Sampler,
        buffer: *Scene.SamplesTo,
    ) []SampleTo {
        const op = trafo.worldToObjectPoint(p);
        const on = trafo.worldToObjectNormal(n);

        const part = self.parts[part_id];

        var samples_buffer: LightTree.Samples = undefined;
        const samples = part.sampleSpatial(variant, op, on, total_sphere, sampler.sample1D(), split_threshold, &samples_buffer);

        var current_sample: u32 = 0;

        for (samples) |s| {
            const global = part.triangle_mapping[s.offset];

            const puv = self.tree.data.trianglePuv(self.tree.data.indexTriangle(global));

            const a = puv.p[0];
            const b = puv.p[1];
            const c = puv.p[2];

            const e1 = b - a;
            const e2 = c - a;

            const cross_axis = math.cross3(e1, e2);

            const ca = (trafo.scale() * trafo.scale()) * cross_axis;
            const lca = math.length3(ca);
            const sn = ca / @as(Vec4f, @splat(lca));
            var wn = trafo.objectToWorldNormal(sn);

            const tri_area = 0.5 * lca;

            const center = (a + b + c) / @as(Vec4f, @splat(3.0));

            var dir: Vec4f = undefined;
            var v: Vec4f = undefined;
            var bary_uv: Vec2f = undefined;
            var sample_pdf: f32 = undefined;
            var n_dot_dir: f32 = undefined;

            if (tri_area / math.distance3(center, op) > Area_distance_ratio) {
                const sample = sampleSpherical(op, a, b, c, sampler.sample2D()) orelse continue;

                if (math.dot3(sample.dir, on) <= 0.0 and !total_sphere) {
                    continue;
                }

                bary_uv = sample.uv;

                dir = trafo.objectToWorldNormal(sample.dir);

                const sv = tri.interpolate3(a, b, c, bary_uv[0], bary_uv[1]);
                v = trafo.objectToWorldPoint(sv);
                sample_pdf = s.pdf * sample.pdf;

                if (two_sided and math.dot3(wn, dir) > 0.0) {
                    wn = -wn;
                }

                n_dot_dir = -math.dot3(wn, dir);
            } else {
                bary_uv = math.smpl.triangleUniform(sampler.sample2D());

                const sv = tri.interpolate3(a, b, c, bary_uv[0], bary_uv[1]);
                v = trafo.objectToWorldPoint(sv);

                const axis = v - p;

                const sl = math.squaredLength3(axis);
                const d = @sqrt(sl);
                dir = axis / @as(Vec4f, @splat(d));

                if (math.dot3(dir, n) <= 0.0 and !total_sphere) {
                    continue;
                }

                if (two_sided and math.dot3(wn, dir) > 0.0) {
                    wn = -wn;
                }

                n_dot_dir = -math.dot3(wn, dir);

                const hack_bias: f32 = if (tri_area < HackArea) HackDistance else 0.0;
                const biased_sl = math.max(sl, hack_bias);

                sample_pdf = (s.pdf * biased_sl) / (n_dot_dir * tri_area);
            }

            if (n_dot_dir < math.safe.DotMin) {
                continue;
            }

            const tc = tri.interpolate2(puv.uv[0], puv.uv[1], puv.uv[2], bary_uv[0], bary_uv[1]);

            buffer[current_sample] = SampleTo.init(
                v,
                wn,
                dir,
                .{ tc[0], tc[1], 0.0, 0.0 },
                sample_pdf,
            );
            current_sample += 1;
        }

        return buffer[0..current_sample];
    }

    pub fn sampleFrom(
        self: *const Mesh,
        trafo: Trafo,
        uv: Vec2f,
        importance_uv: Vec2f,
        part_id: u32,
        variant: u32,
        two_sided: bool,
        sampler: *Sampler,
    ) ?SampleFrom {
        const r = sampler.sample1D();

        const part = self.parts[part_id];
        const s = part.sampleRandom(variant, r);

        const global = part.triangle_mapping[s.offset];
        const itri = self.tree.data.indexTriangle(global);

        var sv: Vec4f = undefined;
        var tc: Vec2f = undefined;
        self.tree.data.sample(itri, uv, &sv, &tc);
        const ws = trafo.objectToWorldPoint(sv);

        const ca = (trafo.scale() * trafo.scale()) * self.tree.data.crossAxis(itri);
        const lca = math.length3(ca);
        const sn = ca / @as(Vec4f, @splat(lca));
        var wn = trafo.objectToWorldNormal(sn);

        const dir_l = math.smpl.hemisphereUniform(importance_uv);
        const frame = Frame.init(wn);
        var dir = frame.frameToWorld(dir_l);

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
        self: *const Mesh,
        part_id: u32,
        variant: u32,
        dir: Vec4f,
        p: Vec4f,
        n: Vec4f,
        frag: *const Fragment,
        total_sphere: bool,
        splt_threshold: f32,
    ) f32 {
        const n_dot_dir = @abs(math.dot3(frag.geo_n, dir));

        const op = frag.isec.trafo.worldToObjectPoint(p);
        const on = frag.isec.trafo.worldToObjectNormal(n);

        const pm = self.primitive_mapping[frag.isec.primitive];

        const part = self.parts[part_id];
        const tri_pdf = part.pdfSpatial(variant, op, on, total_sphere, splt_threshold, pm);

        const ps = self.tree.data.triangleP(self.tree.data.indexTriangle(frag.isec.primitive));

        const a = ps[0];
        const b = ps[1];
        const c = ps[2];

        const e1 = b - a;
        const e2 = c - a;

        const cross_axis = math.cross3(e1, e2);

        const ca = (frag.isec.trafo.scale() * frag.isec.trafo.scale()) * cross_axis;
        const tri_area = 0.5 * math.length3(ca);

        const center = (a + b + c) / @as(Vec4f, @splat(3.0));

        if (tri_area / math.distance3(center, op) > Area_distance_ratio) {
            return tri_pdf * pdfSpherical(op, a, b, c);
        } else {
            const sl = math.squaredDistance3(p, frag.p);

            const hack_bias: f32 = if (tri_area < HackArea) HackDistance else 0.0;
            const biased_sl = math.max(sl, hack_bias);

            return (biased_sl * tri_pdf) / (n_dot_dir * tri_area);
        }
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
            const trip = self.tree.data.trianglePart(t);
            const itri = self.tree.data.indexTriangle(t);
            self.parts[trip].area += self.tree.data.triangleArea(itri);
        }
    }

    pub fn prepareSampling(
        self: *Mesh,
        alloc: Allocator,
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
                const trip = self.tree.data.trianglePart(i);
                const p = &self.parts[trip];
                const pm = p.num_triangles;
                p.num_triangles = pm + 1;
                primitive_mapping[i] = pm;
            }

            self.primitive_mapping = primitive_mapping;
        }

        return try self.parts[part].configure(alloc, part, material, &self.tree, builder, scene, threads);
    }

    pub fn surfaceDifferentials(self: *const Mesh, primitive: u32, trafo: Trafo) DifferentialSurface {
        const puv = self.tree.data.trianglePuv(self.tree.data.indexTriangle(primitive));

        const dpdu, const dpdv = tri.positionDifferentials(puv.p[0], puv.p[1], puv.p[2], puv.uv[0], puv.uv[1], puv.uv[2]);

        const dpdu_w = trafo.objectToWorldVector(dpdu);
        const dpdv_w = trafo.objectToWorldVector(dpdv);

        return .{ .dpdu = dpdu_w, .dpdv = dpdv_w };
    }
};
