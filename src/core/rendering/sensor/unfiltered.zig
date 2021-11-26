const cs = @import("../../sampler/camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const Clamp = @import("clamp.zig").Clamp;

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;

pub fn Unfiltered(comptime T: type) type {
    return struct {
        sensor: T = .{},

        clamp: Clamp,

        const Self = @This();

        pub fn addSample(self: *Self, sample: Sample, color: Vec4f, offset: Vec2i) void {
            const pixel = sample.pixel + offset;

            self.sensor.addPixel(pixel, self.clamp.clamp(color), 1.0);
        }

        pub fn splatSample(self: *Self, sample: SampleTo, color: Vec4f, offset: Vec2i) void {
            self.sensor.splatPixelAtomic(sample.pixel + offset, self.clamp.clamp(color), 1.0);
        }
    };
}
