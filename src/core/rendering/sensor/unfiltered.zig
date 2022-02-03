const cs = @import("../../sampler/camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;

pub fn Unfiltered(comptime T: type) type {
    return struct {
        sensor: T = .{},

        const Self = @This();

        pub fn init(clamp_max: f32) Self {
            return .{ .sensor = .{ .base = .{ .max = clamp_max } } };
        }

        pub fn addSample(self: *Self, sample: Sample, color: Vec4f, offset: Vec2i) void {
            const pixel = sample.pixel + offset;

            self.sensor.addPixel(pixel, self.sensor.base.clamp(color), 1.0);
        }

        pub fn splatSample(self: *Self, sample: SampleTo, color: Vec4f, offset: Vec2i) void {
            self.sensor.splatPixelAtomic(sample.pixel + offset, self.sensor.base.clamp(color), 1.0);
        }
    };
}
