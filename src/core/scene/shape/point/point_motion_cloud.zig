const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const Context = @import("../../context.zig").Context;
const Scene = @import("../../scene.zig").Scene;
const Vertex = @import("../../vertex.zig").Vertex;
const Tree = @import("point_motion_tree.zig").Tree;
const int = @import("../intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Probe = @import("../probe.zig").Probe;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const smpl = @import("../sample.zig");
const SampleTo = smpl.To;
const Material = @import("../../material/material.zig").Material;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Frame = math.Frame;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MotionCloud = struct {
    tree: Tree = .{},

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.tree.deinit(alloc);
    }

    pub fn area(self: *const Self, scale: Vec4f) f32 {
        const data = self.tree.data;

        if (data.radii) |radii| {
            var square_radius: f32 = 0.0;

            const num_radii = data.num_frames * data.num_vertices;
            for (radii[0..num_radii]) |r| {
                square_radius += r * r;
            }

            const sa = (4.0 * std.math.pi) * (scale[0] * scale[0]) * square_radius;

            return sa / @as(f32, @floatFromInt(data.num_frames));
        } else {
            const sa = (4.0 * std.math.pi) * math.pow2(data.radius * scale[0]);

            return @as(f32, @floatFromInt(data.num_vertices)) * sa;
        }
    }

    pub fn intersect(self: *const Self, probe: Probe, trafo: Trafo, isec: *Intersection) bool {
        return self.tree.intersect(probe, trafo, isec);
    }

    pub fn fragment(self: *const Self, probe: Probe, frag: *Fragment) void {
        const p = probe.ray.point(frag.isec.t);

        const frame = self.tree.data.frameAt(probe.time);
        const iorigin_o = self.tree.data.positionAndRadiusAt(frag.isec.primitive, frame);
        const origin_w = frag.isec.trafo.objectToWorldPoint(iorigin_o);

        const n = math.normalize3(p - origin_w);

        frag.p = p;
        frag.geo_n = n;
        frag.n = n;
        frag.part = 0;

        const tb = math.orthonormalBasis3(n);

        frag.t = tb[0];
        frag.b = tb[1];
        frag.uvw = @splat(0.0);
    }

    pub fn intersectP(self: *const Self, probe: Probe, trafo: Trafo) bool {
        return self.tree.intersectP(probe, trafo);
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

    pub fn sampleTo(
        self: *const Self,
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        time: u64,
        total_sphere: bool,
        split_threshold: f32,
        material: *const Material,
        sampler: *Sampler,
        buffer: *Scene.SamplesTo,
    ) []SampleTo {
        _ = split_threshold;
        _ = material;

        const num_points = self.tree.data.num_vertices;
        const points_back: f32 = @floatFromInt(num_points - 1);

        const s3 = sampler.sample3D();

        const point_index: u32 = @intFromFloat(s3[0] * points_back);
        const sample_frame = self.tree.data.frameAt(time);
        const point_pos_os = self.tree.data.positionAndRadiusAt(point_index, sample_frame);
        const point_pos_ws = trafo.objectToWorldPoint(point_pos_os);

        const v = point_pos_ws - p;
        const sl = math.squaredLength3(v);
        const l = @sqrt(sl);
        const r = point_pos_os[3] * trafo.scaleX();

        if (l <= (r + 0.0000001) or r <= 0.0) {
            return buffer[0..0];
        }

        const z = @as(Vec4f, @splat(1.0 / l)) * v;
        const frame = Frame.init(z);

        const w = math.smpl.hemisphereUniform(.{ s3[1], s3[2] });
        const wn = frame.frameToWorld(-w);

        const lp = point_pos_ws + @as(Vec4f, @splat(r)) * wn;

        const dir = math.normalize3(lp - p);

        const c = -math.dot3(wn, dir);

        if (c < math.safe.DotMin or (math.dot3(dir, n) <= 0.0 and !total_sphere)) {
            return buffer[0..0];
        }

        const p_area = (2.0 * std.math.pi) * (r * r);

        const sample_pdf = 1.0 / @as(f32, @floatFromInt(num_points));

        buffer[0] = SampleTo.init(
            lp,
            wn,
            dir,
            @splat(0.0),
            (sample_pdf * sl) / (c * p_area),
        );

        return buffer[0..1];
    }

    pub fn pdf(self: *const Self, dir: Vec4f, p: Vec4f, frag: *const Fragment, time: u64, splt_threshold: f32) f32 {
        _ = splt_threshold;

        const num_points = self.tree.data.num_vertices;

        const sample_pdf = 1.0 / @as(f32, @floatFromInt(num_points));

        const sl = math.squaredDistance3(p, frag.p);
        const c = -math.dot3(frag.geo_n, dir);

        const frame = self.tree.data.frameAt(time);
        const radius = self.tree.data.positionAndRadiusAt(frag.isec.primitive, frame)[3];

        const r = radius * frag.isec.trafo.scaleX();
        const p_area = (2.0 * std.math.pi) * (r * r);

        return (sample_pdf * sl) / (c * p_area);
    }
};
