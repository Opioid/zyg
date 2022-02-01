const CameraSample = @import("camera_sample.zig").CameraSample;
pub const Sobol = @import("sobol.zig").Sobol;

const base = @import("base");
const math = base.math;
const RNG = base.rnd.Generator;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;

const Allocator = @import("std").mem.Allocator;

pub const Sampler = union(enum) {
    Random,
    Sobol: Sobol,

    pub fn startPixel(self: *Sampler, seed: u32) void {
        switch (self.*) {
            .Random => {},
            .Sobol => |*s| s.startPixel(seed),
        }
    }

    pub fn incrementSample(self: *Sampler) void {
        switch (self.*) {
            .Random => {},
            .Sobol => |*s| s.incrementSample(),
        }
    }

    pub fn incrementBounce(self: *Sampler) void {
        switch (self.*) {
            .Random => {},
            .Sobol => |*s| s.incrementBounce(),
        }
    }

    pub fn sample1D(self: *Sampler, rng: *RNG) f32 {
        return switch (self.*) {
            .Random => rng.randomFloat(),
            .Sobol => |*s| s.sample1D(),
        };
    }

    pub fn sample2D(self: *Sampler, rng: *RNG) Vec2f {
        return switch (self.*) {
            .Random => .{ rng.randomFloat(), rng.randomFloat() },
            .Sobol => |*s| s.sample2D(),
        };
    }

    pub fn cameraSample(self: *Sampler, rng: *RNG, pixel: Vec2i) CameraSample {
        const sample = CameraSample{
            .pixel = pixel,
            .pixel_uv = self.sample2D(rng),
            .lens_uv = self.sample2D(rng),
            .time = self.sample1D(rng),
        };

        self.incrementSample();

        return sample;
    }
};

pub const Factory = union(enum) {
    Random,
    Sobol,

    pub fn create(
        self: Factory,
        alloc: Allocator,
        num_dimensions_1D: u32,
        num_dimensions_2D: u32,
        max_samples: u32,
    ) Sampler {
        _ = alloc;
        _ = num_dimensions_1D;
        _ = num_dimensions_2D;
        _ = max_samples;

        return switch (self) {
            .Random => Sampler{ .Random = {} },
            .Sobol => Sampler{ .Sobol = .{} },
        };
    }
};
