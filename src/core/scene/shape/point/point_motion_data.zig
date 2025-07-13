const motion = @import("../../motion.zig");

const base = @import("base");
const math = base.math;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MotionData = struct {
    const Frame = motion.Frame;

    frame_duration: u32 = 0,
    start_frame: u32 = 0,
    num_frames: u32 = 0,
    num_vertices: u32 = 0,

    radius: f32 = undefined,

    positions: [*]f32 = undefined,
    radii: ?[*]f32 = undefined,

    const Self = @This();

    pub fn allocatePoints(self: *Self, alloc: Allocator, radius: f32, positions: [][]Pack3f, radii: [][]f32) !void {
        const num_frames: u32 = @truncate(positions.len);
        const num_vertices: u32 = @truncate(positions[0].len);

        self.num_frames = num_frames;
        self.num_vertices = num_vertices;
        self.radius = radius;

        {
            const num_frame_point_components = num_vertices * 3;
            const num_point_components = num_frames * num_frame_point_components;

            self.positions = (try alloc.alloc(f32, num_point_components + 1)).ptr;

            var begin: u32 = 0;
            var end: u32 = num_frame_point_components;

            for (positions) |p| {
                @memcpy(self.positions[begin..end], @as([*]const f32, @ptrCast(p.ptr))[0..num_frame_point_components]);

                begin += num_frame_point_components;
                end += num_frame_point_components;
            }

            self.positions[num_point_components] = 0.0;
        }

        if (radii.len > 0) {
            const num_radius_components = num_frames * num_vertices;

            var dest_radii = (try alloc.alloc(f32, num_radius_components)).ptr;

            var begin: u32 = 0;
            var end: u32 = num_vertices;

            for (radii) |r| {
                @memcpy(dest_radii[begin..end], @as([*]const f32, @ptrCast(r.ptr))[0..num_vertices]);

                begin += num_vertices;
                end += num_vertices;
            }

            self.radii = dest_radii;
        } else {
            self.radii = null;
        }
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        const num_point_components = self.num_frames + self.num_vertices * 3 + 1;
        alloc.free(self.positions[0..num_point_components]);
    }

    pub fn frameAt(self: Self, time: u64) Frame {
        return motion.frameAt(time, self.frame_duration, self.start_frame);
    }

    pub fn positionAndRadiusAt(self: Self, index: u32, frame: Frame) Vec4f {
        const num_vertices = self.num_vertices;
        const i = frame.f;

        const offset0 = i * (num_vertices * 3);
        var pos0: Vec4f = self.positions[offset0 + index * 3 ..][0..4].*;

        const offset1 = (i + 1) * num_vertices * 3;
        var pos1: Vec4f = self.positions[offset1 + index * 3 ..][0..4].*;

        if (self.radii) |radii| {
            pos0[3] = radii[i * num_vertices + index];
            pos1[3] = radii[(i + 1) * num_vertices + index];
        } else {
            const r = self.radius;
            pos0[3] = r;
            pos1[3] = r;
        }

        return math.lerp(pos0, pos1, @as(Vec4f, @splat(frame.w)));
    }
};
