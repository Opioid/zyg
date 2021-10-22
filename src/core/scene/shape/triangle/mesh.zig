const Transformation = @import("../../composed_transformation.zig").ComposedTransformation;
const Worker = @import("../../worker.zig").Worker;
const Filter = @import("../../../image/texture/sampler.zig").Filter;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const NodeStack = @import("../node_stack.zig").NodeStack;
const int = @import("../intersection.zig");
const Intersection = int.Intersection;
const Interpolation = int.Interpolation;
const SampleTo = @import("../sample.zig").To;
pub const bvh = @import("bvh/tree.zig");
const ro = @import("../../ray_offset.zig");
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

const Part = struct {
    const Variant = struct {
        distribution: Distribution1D = .{},

        pub fn deinit(self: *Variant, alloc: *Allocator) void {
            self.distribution.deinit(alloc);
        }
    };

    material: u32 = undefined,
    num_triangles: u32 = 0,
    area: f32 = undefined,

    triangle_mapping: []u32 = &.{},
    aabbs: []AABB = &.{},
    cones: []Vec4f = &.{},

    variants: std.ArrayListUnmanaged(Variant) = .{},

    pub fn deinit(self: *Part, alloc: *Allocator) void {
        for (self.variants.items) |*v| {
            v.deinit(alloc);
        }

        self.variants.deinit(alloc);

        alloc.free(self.cones);
        alloc.free(self.aabbs);
        alloc.free(self.triangle_mapping);
    }

    pub fn configure(self: *Part, alloc: *Allocator, part: u32, tree: bvh.Tree, threads: *Threads) !u32 {
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

        const v = @intCast(u32, self.variants.items.len);

        const context = Context{
            .powers = try alloc.alloc(f32, num),
            .triangle_mapping = self.triangle_mapping,
            .tree = &tree,
        };
        defer {
            alloc.free(context.powers);
        }

        _ = threads.runRange(&context, Context.run, 0, num);

        var variant = Variant{};

        try variant.distribution.configure(alloc, context.powers, 0);

        try self.variants.append(alloc, variant);

        return v;
    }

    pub fn lightCone(self: Part, light: u32) Vec4f {
        return self.cones[light];
    }

    const Context = struct {
        powers: []f32,
        triangle_mapping: []u32,
        tree: *const bvh.Tree,

        pub fn run(context: Threads.Context, id: u32, begin: u32, end: u32) void {
            _ = id;

            const self = @intToPtr(*Context, context);

            var i = begin;
            while (i < end) : (i += 1) {
                const t = self.triangle_mapping[i];
                const area = self.tree.data.area(t);

                self.powers[i] = area;
            }
        }
    };

    const Discrete = struct {
        global: u32,
        local: u32,
        pdf: f32,
    };

    pub fn sampleSpatial(self: Part, variant: u32, p: Vec4f, n: Vec4f, total_sphere: bool, r: f32) Discrete {
        _ = p;
        _ = n;
        _ = total_sphere;

        return self.sampleRandom(variant, r);
    }

    pub fn sampleRandom(self: Part, variant: u32, r: f32) Discrete {
        const result = self.variants.items[variant].distribution.sampleDiscrete(r);
        const relative_area = self.aabbs[result.offset].bounds[1][3];

        return .{
            .global = self.triangle_mapping[result.offset],
            .local = result.offset,
            .pdf = result.pdf * relative_area,
        };
    }

    pub fn pdfSpatial(self: Part, variant: u32, p: Vec4f, n: Vec4f, total_sphere: bool, id: u32) f32 {
        _ = p;
        _ = n;
        _ = total_sphere;

        return self.pdfRandom(variant, id);
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

    pub fn init(alloc: *Allocator, num_parts: u32) !Mesh {
        const parts = try alloc.alloc(Part, num_parts);
        std.mem.set(Part, parts, .{});

        return Mesh{ .parts = parts };
    }

    pub fn deinit(self: *Mesh, alloc: *Allocator) void {
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

    pub fn partIdToMaterialId(self: Mesh, part: u32) u32 {
        return self.parts[part].material;
    }

    pub fn setMaterialForPart(self: *Mesh, part: usize, material: u32) void {
        self.parts[part].material = material;
    }

    pub fn area(self: Mesh, part: u32, scale: Vec4f) f32 {
        // HACK: This only really works for uniform scales!
        return self.parts[part].area * (scale[0] * scale[1]);
    }

    pub fn intersect(
        self: Mesh,
        ray: *Ray,
        trafo: Transformation,
        nodes: *NodeStack,
        ipo: Interpolation,
        isec: *Intersection,
    ) bool {
        var tray = Ray.init(
            trafo.world_to_object.transformPoint(ray.origin),
            trafo.world_to_object.transformVector(ray.direction),
            ray.minT(),
            ray.maxT(),
        );

        if (self.tree.intersect(&tray, nodes)) |hit| {
            ray.setMaxT(tray.maxT());

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

    pub fn intersectP(self: Mesh, ray: Ray, trafo: Transformation, nodes: *NodeStack) bool {
        var tray = Ray.init(
            trafo.world_to_object.transformPoint(ray.origin),
            trafo.world_to_object.transformVector(ray.direction),
            ray.minT(),
            ray.maxT(),
        );

        return self.tree.intersectP(tray, nodes);
    }

    pub fn visibility(
        self: Mesh,
        ray: Ray,
        trafo: Transformation,
        entity: usize,
        filter: ?Filter,
        worker: *Worker,
    ) ?Vec4f {
        var tray = Ray.init(
            trafo.world_to_object.transformPoint(ray.origin),
            trafo.world_to_object.transformVector(ray.direction),
            ray.minT(),
            ray.maxT(),
        );

        return self.tree.visibility(&tray, entity, filter, worker);
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
        sampler_d: usize,
    ) ?SampleTo {
        const r = sampler.sample1D(rng, sampler_d);
        const r2 = sampler.sample2D(rng, sampler_d);

        const op = trafo.worldToObjectPoint(p);
        const on = trafo.worldToObjectNormal(n);
        const s = self.parts[part].sampleSpatial(variant, op, on, total_sphere, r);

        if (0.0 == s.pdf) {
            return null;
        }

        var sv: Vec4f = undefined;
        var tc: Vec2f = undefined;
        self.tree.data.sample(s.global, r2, &sv, &tc);
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

    pub fn prepareSampling(self: *Mesh, alloc: *Allocator, part: u32, threads: *Threads) !u32 {
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

        return try self.parts[part].configure(alloc, part, self.tree, threads);
    }
};
