const Sample = @import("../../sampler/sampler.zig").Camera_sample;

const base = @import("base");
const Vec2i = base.math.Vec2i;
const Vec4f = base.math.Vec4f;

pub fn Unfiltered(comptime T: type) type {
    return struct {
        sensor: T = .{},

        const Self = @This();

        pub fn addSample(self: *Self, sample: Sample, color: Vec4f, offset: Vec2i) void {
            const pixel = sample.pixel.add(offset);

            self.sensor.addPixel(pixel, color, 1.0);
        }
    };
}
