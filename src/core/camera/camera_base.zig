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

    pub fn setShutter(self: *Self, open: f32, close: f32, slope: []f32) void {
        const nf: f32 = @floatFromInt(N);

        var shutter_function: [N]f32 = undefined;

        for (0..N) |i| {
            const t = (@as(f32, @floatFromInt(i)) + 0.5) / nf;
            const f = evalShutter(open, close, slope, t);

            shutter_function[i] = f;
        }

        self.shutter_distribution.configure(shutter_function);
    }

    fn evalShutter(open: f32, close: f32, slope: []f32, t: f32) f32 {
        if (t < open) {
            if (slope.len >= 4) {
                return searchBezier(
                    .{ @splat(0.0), .{ slope[0], slope[1] }, .{ slope[2], slope[3] }, .{ open, 1.0 } },
                    t,
                );
            } else {
                return math.lerp(0.0, 1.0, t / open);
            }
        } else if (t > close) {
            if (slope.len >= 8) {
                return searchBezier(
                    .{ .{ close, 1.0 }, .{ slope[4], slope[5] }, .{ slope[6], slope[7] }, .{ 1.0, 0.0 } },
                    t,
                );
            } else {
                return math.lerp(1.0, 0.0, (t - close) / (1.0 - close));
            }
        }

        return 1.0;
    }

    fn searchBezier(cp: [4]Vec2f, x: f32) f32 {
        var u: f32 = 0.5;
        var step = u * 0.5;

        var c: Vec2f = undefined;

        for (0..16) |_| {
            c = cubicBezierEvaluate(cp, u);
            if (x < c[0]) {
                u -= step;
            } else if (x > c[0]) {
                u += step;
            } else {
                break;
            }

            step *= 0.5;
        }

        return c[1];
    }

    fn cubicBezierEvaluate(cp: [4]Vec2f, u: f32) Vec2f {
        const uv: Vec2f = @splat(u);

        const cp1: [3]Vec2f = .{
            math.lerp(cp[0], cp[1], uv),
            math.lerp(cp[1], cp[2], uv),
            math.lerp(cp[2], cp[3], uv),
        };

        const cp2: [2]Vec2f = .{
            math.lerp(cp1[0], cp1[1], uv),
            math.lerp(cp1[1], cp1[2], uv),
        };

        return math.lerp(cp2[0], cp2[1], uv);
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
