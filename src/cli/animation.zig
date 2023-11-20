const Graph = @import("scene_graph.zig").Graph;

const math = @import("base").math;
const Transformation = math.Transformation;
const Vec4f = math.Vec4f;

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
        num_frames: u32,
        num_interpolated_frames: u32,
    ) !Animation {
        return Animation{
            .entity = Graph.Null,
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
        const frames_back = self.num_frames - 1;

        const interpolated_frames = self.frames + self.num_frames;

        var last_frame = if (self.last_frame > 2) self.last_frame - 2 else 0;

        var time = start;
        var i: u32 = 0;

        while (time <= end) : (time += frame_length) {
            var j = last_frame;
            while (j < frames_back) : (j += 1) {
                const a_time = self.times[j];
                const b_time = self.times[j + 1];

                const f1 = self.frames[j];
                const f2 = self.frames[j + 1];

                if (time >= a_time and time < b_time) {
                    const f0 = if (j > 0) self.frames[j - 1] else extrapolate(f2, f1);
                    const f3 = if (j < frames_back - 1) self.frames[j + 2] else extrapolate(f1, f2);

                    const range = b_time - a_time;
                    const delta = time - a_time;

                    const t: f32 = @floatCast(@as(f64, @floatFromInt(delta)) / @as(f64, @floatFromInt(range)));

                    interpolated_frames[i] = interpolate(f0, f1, f2, f3, t);

                    break;
                }

                if (j + 1 == frames_back) {
                    interpolated_frames[i] = f2;
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

fn getT(p0: Vec4f, p1: Vec4f, t: f32, alpha: f32) f32 {
    const d = p1 - p0;
    const a = math.dot3(d, d);
    const b = std.math.pow(f32, a, alpha * 0.5);
    return b + t;
}

// Centripetal Catmull–Rom spline
fn catmullRom(p0: Vec4f, p1: Vec4f, p2: Vec4f, p3: Vec4f, t: f32, alpha: f32) Vec4f {
    const t0: f32 = 0.0;
    const t1 = getT(p0, p1, t0, alpha);
    const t2 = getT(p1, p2, t1, alpha);
    const t3 = getT(p2, p3, t2, alpha);
    const tt = math.lerp(t1, t2, t);

    if (0.0 == t1) {
        return p1;
    }

    const A1 = @as(Vec4f, @splat((t1 - tt) / (t1 - t0))) * p0 + @as(Vec4f, @splat((tt - t0) / (t1 - t0))) * p1;
    const A2 = @as(Vec4f, @splat((t2 - tt) / (t2 - t1))) * p1 + @as(Vec4f, @splat((tt - t1) / (t2 - t1))) * p2;
    const A3 = @as(Vec4f, @splat((t3 - tt) / (t3 - t2))) * p2 + @as(Vec4f, @splat((tt - t2) / (t3 - t2))) * p3;
    const B1 = @as(Vec4f, @splat((t2 - tt) / (t2 - t0))) * A1 + @as(Vec4f, @splat((tt - t0) / (t2 - t0))) * A2;
    const B2 = @as(Vec4f, @splat((t3 - tt) / (t3 - t1))) * A2 + @as(Vec4f, @splat((tt - t1) / (t3 - t1))) * A3;
    const C = @as(Vec4f, @splat((t2 - tt) / (t2 - t1))) * B1 + @as(Vec4f, @splat((tt - t1) / (t2 - t1))) * B2;

    return C;
}

fn interpolate(f0: Transformation, f1: Transformation, f2: Transformation, f3: Transformation, t: f32) Transformation {
    return .{
        .position = catmullRom(f0.position, f1.position, f2.position, f3.position, t, 0.5),
        .scale = math.lerp(f1.scale, f2.scale, @as(Vec4f, @splat(t))),
        .rotation = math.quaternion.slerp(f1.rotation, f2.rotation, t),
    };
}

fn extrapolate(f1: Transformation, f2: Transformation) Transformation {
    return .{
        .position = f2.position + (f2.position - f1.position),
        .scale = f2.scale + (f2.scale - f1.scale),
        .rotation = f1.rotation,
    };
}
