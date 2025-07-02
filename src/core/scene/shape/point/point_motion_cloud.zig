const MotionData = @import("point_motion_data.zig").MotionData;
const Tree = @import("point_motion_tree.zig").Tree;
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const int = @import("../intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Probe = @import("../probe.zig").Probe;
const Scene = @import("../../scene.zig").Scene;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
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

    pub fn aabb(self: *const Self, frame_duration: u64) AABB {
        _ = frame_duration;
        return self.tree.nodes[0].aabb();
    }

    pub fn intersect(self: *const Self, probe: Probe, trafo: Trafo, current_time_start: u64, isec: *Intersection) bool {
        return self.tree.intersect(probe, trafo, current_time_start, isec);
    }

    pub fn fragment(self: *const Self, probe: Probe, current_time_start: u64, frag: *Fragment) void {
        const seconds: Vec4f = @splat(Scene.secondsSince(probe.time, current_time_start));

        const p = probe.ray.point(frag.isec.t);

        const positions = self.tree.data.positions;
        const velocities = self.tree.data.velocities;

        const origin_o: Vec4f = positions[frag.isec.primitive * 3 ..][0..4].*;
        const vel: Vec4f = velocities[frag.isec.primitive * 3 ..][0..4].*;
        const iorigin_o = origin_o + math.lerp(@as(Vec4f, @splat(0.0)), vel, seconds);

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

    pub fn intersectP(self: *const Self, probe: Probe, trafo: Trafo, current_time_start: u64) bool {
        return self.tree.intersectP(probe, trafo, current_time_start);
    }
};
