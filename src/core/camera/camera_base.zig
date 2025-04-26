const Prop = @import("../scene/prop/prop.zig").Prop;
const MediumStack = @import("../scene/prop/medium.zig").Stack;
const Scene = @import("../scene/scene.zig").Scene;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;

pub const Base = struct {
    const DefaultFrameTime = Scene.UnitsPerSecond / 60;

    entity: u32 = Prop.Null,

    sample_spacing: f32 = undefined,

    resolution: Vec2i = @splat(0),
    crop: Vec4i = @splat(0),

    frame_step: u64 = DefaultFrameTime,
    frame_duration: u64 = DefaultFrameTime,

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

    pub fn absoluteTime(self: Self, frame: u32, frame_delta: f32) u64 {
        const delta: f64 = @floatCast(frame_delta);
        const duration: f64 = @floatFromInt(self.frame_duration);

        const fdi: u64 = @intFromFloat(@round(delta * duration));

        return @as(u64, frame) * self.frame_step + fdi;
    }
};
