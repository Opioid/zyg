const Sample = @import("../../sampler/camera_sample.zig").CameraSample;

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;

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
