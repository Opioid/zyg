const cs = @import("../../sampler/camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const AovValue = @import("aov/aov_value.zig").Value;

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

        pub fn addSample(self: *Self, sample: Sample, color: Vec4f, aov: AovValue) void {
            const pixel = sample.pixel;

            self.sensor.addPixel(pixel, self.sensor.base.clamp(color), 1.0);

            if (aov.active()) {
                const len = AovValue.Num_classes;
                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const class = @intToEnum(AovValue.Class, i);
                    if (aov.activeClass(class)) {
                        const value = aov.values[i];

                        if (.Depth == class) {
                            self.sensor.base.lessAov(pixel, i, value[0]);
                        } else if (.MaterialId == class) {
                            self.sensor.base.overwriteAov(pixel, i, value[0], 1.0);
                        } else {
                            self.sensor.base.addAov(pixel, i, value, 1.0);
                        }
                    }
                }
            }
        }

        pub fn splatSample(self: *Self, sample: SampleTo, color: Vec4f) void {
            self.sensor.splatPixelAtomic(sample.pixel, self.sensor.base.clamp(color), 1.0);
        }
    };
}
