const Scene = @import("../scene.zig").Scene;
const math = @import("base").math;
const Transformation = math.Transformation;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Keyframe = struct {
    k: Transformation,
    time: u64,
};

pub const Animation = struct {
    entity: u32,
    last_frame: u32,

    times: []u64,
    frames: []Transformation,

    pub fn init(
        alloc: *Allocator,
        entity: u32,
        num_frames: u32,
        num_interpolated_frames: u32,
    ) !Animation {
        return Animation{
            .entity = entity,
            .last_frame = 0,
            .times = try alloc.alloc(u64, num_frames),
            .frames = try alloc.alloc(Transformation, num_frames + num_interpolated_frames),
        };
    }

    pub fn deinit(self: *Animation, alloc: *Allocator) void {
        alloc.free(self.frames);
        alloc.free(self.times);
    }

    pub fn set(self: *Animation, index: u32, keyframe: Keyframe) void {
        self.times[index] = keyframe.time;
        self.frames[index] = keyframe.k;
    }

    pub fn resample(self: *Animation, start: u64, end: u64, frame_length: u64) void {
        _ = self;
        _ = start;
        _ = end;
        _ = frame_length;
    }

    pub fn update(self: Animation, scene: *Scene) void {
        _ = self;
        _ = scene;
    }
};
