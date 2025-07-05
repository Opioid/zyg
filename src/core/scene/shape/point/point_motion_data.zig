const Scene = @import("../../scene.zig").Scene;

const base = @import("base");
const math = base.math;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MotionData = struct {
    const FrameDuration = Scene.TickDuration / 2;

    num_frames: u32 = 0,
    num_vertices: u32 = 0,

    radius: f32 = undefined,

    positions: [*]f32 = undefined,

    const Self = @This();

    pub fn allocatePoints(self: *Self, alloc: Allocator, radius: f32, positions: [][]Pack3f) !void {
        const num_frames: u32 = @truncate(positions.len);
        const num_vertices: u32 = @truncate(positions[0].len);

        const num_frame_components = num_vertices * 3;
        const num_components = num_frames * num_frame_components;

        self.num_frames = num_frames;
        self.num_vertices = num_vertices;
        self.radius = radius;

        self.positions = (try alloc.alloc(f32, num_components + 1)).ptr;

        var begin: u32 = 0;
        var end: u32 = num_frame_components;

        for (positions) |p| {
            @memcpy(self.positions[begin..end], @as([*]const f32, @ptrCast(p.ptr))[0..num_frame_components]);

            begin += num_frame_components;
            end += num_frame_components;
        }

        self.positions[num_components] = 0.0;
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        const num_components = self.num_frames + self.num_vertices * 3 + 1;
        alloc.free(self.positions[0..num_components]);
    }

    pub fn positionAt(self: Self, index: u32, time: u64, frame_start: u64) Vec4f {
        const i = (time - frame_start) / FrameDuration;
        const a_time = frame_start + i * FrameDuration;
        const delta = time - a_time;

        const t: f32 = @floatCast(@as(f64, @floatFromInt(delta)) / @as(f64, @floatFromInt(FrameDuration)));

        const offset0 = i * (self.num_vertices * 3);
        const pos0: Vec4f = self.positions[offset0 + index * 3 ..][0..4].*;

        const offset1 = (i + 1) * self.num_vertices * 3;
        const pos1: Vec4f = self.positions[offset1 + index * 3 ..][0..4].*;

        return math.lerp(pos0, pos1, @as(Vec4f, @splat(t)));
    }
};
