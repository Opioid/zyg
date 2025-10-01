const Tree = @import("triangle_motion_tree.zig").Tree;
const tri = @import("triangle.zig");
const int = @import("../intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Volume = int.Volume;
const DifferentialSurface = int.DifferentialSurface;
const Probe = @import("../probe.zig").Probe;
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const Context = @import("../../context.zig").Context;
const Scene = @import("../../scene.zig").Scene;
const Vertex = @import("../../vertex.zig").Vertex;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MotionMesh = struct {
    tree: Tree = .{},

    num_parts: u32,

    part_materials: [*]u32,

    const Self = @This();

    pub fn init(alloc: Allocator, num_parts: u32) !MotionMesh {
        const part_materials = try alloc.alloc(u32, num_parts);

        return MotionMesh{ .num_parts = num_parts, .part_materials = part_materials.ptr };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.part_materials[0..self.num_parts]);
        self.tree.deinit(alloc);
    }

    pub fn numParts(self: *const Self) u32 {
        return self.num_parts;
    }

    pub fn partMaterialId(self: *const Self, part: u32) u32 {
        return self.part_materials[part];
    }

    pub fn setMaterialForPart(self: *Self, part: usize, material: u32) void {
        self.part_materials[part] = material;
    }

    pub fn intersect(self: *const Self, probe: Probe, trafo: Trafo, isec: *Intersection) bool {
        return self.tree.intersect(probe, trafo, isec);
    }

    pub fn intersectOpacity(
        self: *const Self,
        probe: Probe,
        trafo: Trafo,
        entity: u32,
        sampler: *Sampler,
        scene: *const Scene,
        isec: *Intersection,
    ) bool {
        return self.tree.intersectOpacity(probe, trafo, entity, sampler, scene, isec);
    }

    pub fn fragment(self: *const Self, time: u64, frag: *Fragment) void {
        const data = self.tree.data;

        frag.part = data.trianglePart(frag.isec.primitive);

        const hit_u = frag.isec.u;
        const hit_v = frag.isec.v;

        const itri = data.indexTriangle(frag.isec.primitive);

        const frame = data.frameAt(time);

        const geo_n = data.normal(frame, itri);
        frag.geo_n = frag.isec.trafo.objectToWorldNormal(geo_n);

        var p: Vec4f = undefined;
        var t: Vec4f = undefined;
        var b: Vec4f = undefined;
        var n: Vec4f = undefined;
        var uv: Vec2f = undefined;
        data.interpolateData(frame, itri, hit_u, hit_v, &p, &t, &b, &n, &uv);

        frag.p = frag.isec.trafo.objectToWorldPoint(p);
        frag.t = frag.isec.trafo.objectToWorldNormal(t);
        frag.b = frag.isec.trafo.objectToWorldNormal(b);
        frag.n = frag.isec.trafo.objectToWorldNormal(n);
        frag.uvw = .{ uv[0], uv[1], 0.0, 0.0 };
    }

    pub fn intersectP(self: *const Self, probe: Probe, trafo: Trafo) bool {
        return self.tree.intersectP(probe, trafo);
    }

    pub fn visibility(self: *const Self, probe: Probe, trafo: Trafo, entity: u32, sampler: *Sampler, context: Context, tr: *Vec4f) bool {
        const local_ray = trafo.worldToObjectRay(probe.ray);
        return self.tree.visibility(local_ray, probe.time, entity, sampler, context, tr);
    }

    pub fn transmittance(
        self: *const Self,
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
        self: *const Self,
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
        self: *const Self,
        vertex: *const Vertex,
        frag: *Fragment,
        split_threshold: f32,
        sampler: *Sampler,
        context: Context,
    ) Vec4f {
        const local_ray = frag.isec.trafo.worldToObjectRay(vertex.probe.ray);
        return self.tree.emission(local_ray, vertex, frag, split_threshold, sampler, context);
    }

    pub fn surfaceDifferentials(self: *const Self, primitive: u32, trafo: Trafo, time: u64) DifferentialSurface {
        const frame = self.tree.data.frameAt(time);

        const puv = self.tree.data.trianglePuv(frame, self.tree.data.indexTriangle(primitive));

        const dpdu, const dpdv = tri.positionDifferentials(puv.p[0], puv.p[1], puv.p[2], puv.uv[0], puv.uv[1], puv.uv[2]);

        const dpdu_w = trafo.objectToWorldVector(dpdu);
        const dpdv_w = trafo.objectToWorldVector(dpdv);

        return .{ .dpdu = dpdu_w, .dpdv = dpdv_w };
    }
};
