const Graph = @import("scene_graph.zig").Graph;

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
    num_frames: u32,

    times: [*]u64,
    frames: [*]Transformation,

    pub fn init(
        alloc: Allocator,
        entity: u32,
        num_frames: u32,
        num_interpolated_frames: u32,
    ) !Animation {
        return Animation{
            .entity = entity,
            .last_frame = 0,
            .num_frames = num_frames,
            .times = (try alloc.alloc(u64, num_frames)).ptr,
            .frames = (try alloc.alloc(Transformation, num_frames + num_interpolated_frames)).ptr,
        };
    }

    pub fn deinit(self: Animation, alloc: Allocator, num_interpolated_frames: u32) void {
        alloc.free(self.frames[0 .. self.num_frames + num_interpolated_frames]);
        alloc.free(self.times[0..self.num_frames]);
    }

    pub fn set(self: *Animation, index: usize, keyframe: Keyframe) void {
        self.times[index] = keyframe.time;
        self.frames[index] = keyframe.k;
    }

    pub fn resample(self: *Animation, start: u64, end: u64, frame_length: u64) void {
        const keyframes_back = self.num_frames - 1;

        const interpolated_frames = self.frames + self.num_frames;

        var last_frame = if (self.last_frame > 2) self.last_frame - 2 else 0;

        var time = start;
        var i: u32 = 0;

        while (time <= end) : (time += frame_length) {
            var j = last_frame;
            while (j < keyframes_back) : (j += 1) {
                const a_time = self.times[j];
                const b_time = self.times[j + 1];

                const a_frame = self.frames[j];
                const b_frame = self.frames[j + 1];

                if (time >= a_time and time < b_time) {
                    const range = b_time - a_time;
                    const delta = time - a_time;

                    const t = @floatCast(f32, @intToFloat(f64, delta) / @intToFloat(f64, range));

                    interpolated_frames[i] = a_frame.lerp(b_frame, t);

                    break;
                }

                if (j + 1 == keyframes_back) {
                    interpolated_frames[i] = b_frame;
                    break;
                }

                last_frame += 1;
            }

            i += 1;
        }
    }

    pub fn update(self: Animation, graph: *Graph) void {
        const interpolated = self.frames + self.num_frames;
        graph.propSetFrames(self.entity, interpolated);
    }
};
