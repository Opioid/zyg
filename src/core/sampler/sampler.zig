usingnamespace @import("camera_sample.zig");

const base = @import("base");
const RNG = base.rnd.Generator;

usingnamespace base.math;

pub const Sampler = union(enum) {
    Random,

    pub fn sample2D(self: *Sampler, rng: *RNG) Vec2f {
        return switch (self.*) {
            .Random => Vec2f.init2(rng.randomFloat(), rng.randomFloat()),
        };
    }

    pub fn sample(self: *Sampler, rng: *RNG, pixel: Vec2i) Camera_sample {
        return .{
            .pixel = pixel,
            .pixel_uv = self.sample2D(rng),
        };
    }
};
