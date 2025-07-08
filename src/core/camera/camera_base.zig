const Prop = @import("../scene/prop/prop.zig").Prop;
const MediumStack = @import("../scene/prop/medium.zig").Stack;
const Scene = @import("../scene/scene.zig").Scene;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;

const std = @import("std");

pub const Base = struct {
    const N = 63;

    const DefaultFrameTime = Scene.UnitsPerSecond / 60;

    entity: u32 = Prop.Null,

    sample_spacing: f32 = undefined,

    resolution: Vec2i = @splat(0),
    crop: Vec4i = @splat(0),

    frame_step: u64 = DefaultFrameTime,
    frame_duration: u64 = DefaultFrameTime,

    shutter_distribution: math.Distribution1DN(N) = .{},

    const Self = @This();

    pub fn setResolution(self: *Self, resolution: Vec2i, crop: Vec4i) void {
        self.resolution = resolution;

        var cc: Vec4i = @max(crop, @as(Vec4i, @splat(0)));
        cc[2] = @min(cc[2], resolution[0]);
        cc[3] = @min(cc[3], resolution[1]);
        cc[0] = @min(cc[0], cc[2]);
        cc[1] = @min(cc[1], cc[3]);
        self.crop = cc;
    }

    pub fn setShutter(self: *Self, shutter: Vec2f) void {
        var shutter_function: [N]f32 = undefined;

        for (0..N) |i| {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(N - 1));
            const f = evalShutter(shutter[0], shutter[1], t);

            shutter_function[i] = f;
        }

        self.shutter_distribution.configure(shutter_function);
    }

    fn evalShutter(open: f32, close: f32, t: f32) f32 {
        if (t < open) {
            return math.lerp(0.0, 1.0, t / open);
        } else if (t > close) {
            return math.lerp(1.0, 0.0, (t - close) / (1.0 - close));
        }

        return 1.0;
    }

    pub fn sampleShutterTime(self: Self, t: f32) f32 {
        if (self.shutter_distribution.integral < 0.0) {
            return t;
        }

        return self.shutter_distribution.sampleContinous(t).offset;
    }

    pub fn absoluteTime(self: Self, frame: u32, frame_delta: f32) u64 {
        const delta: f64 = @floatCast(frame_delta);
        const duration: f64 = @floatFromInt(self.frame_duration);

        const fdi: u64 = @intFromFloat(@round(delta * duration));

        return @as(u64, frame) * self.frame_step + fdi;
    }
};
