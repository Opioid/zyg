const CameraSample = @import("camera_sample.zig").CameraSample;
pub const Sobol = @import("sobol.zig").Sobol;

const base = @import("base");
const math = base.math;
const RNG = base.rnd.Generator;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;

pub const Sampler = union(enum) {
    Random,
    Sobol: Sobol,

    pub inline fn startPixel(self: *Sampler, sample: u32, seed: u32) void {
        switch (self.*) {
            .Random => {},
            .Sobol => |*s| s.startPixel(sample, seed),
        }
    }

    pub inline fn incrementSample(self: *Sampler) void {
        switch (self.*) {
            .Random => {},
            .Sobol => |*s| s.incrementSample(),
        }
    }

    pub inline fn incrementPadding(self: *Sampler) void {
        switch (self.*) {
            .Random => {},
            .Sobol => |*s| s.incrementPadding(),
        }
    }

    pub inline fn sample1D(self: *Sampler, rng: *RNG) f32 {
        return switch (self.*) {
            .Random => rng.randomFloat(),
            .Sobol => |*s| s.sample1D(),
        };
    }

    pub inline fn sample2D(self: *Sampler, rng: *RNG) Vec2f {
        return switch (self.*) {
            .Random => .{ rng.randomFloat(), rng.randomFloat() },
            .Sobol => |*s| s.sample2D(),
        };
    }

    pub inline fn sample3D(self: *Sampler, rng: *RNG) Vec4f {
        return switch (self.*) {
            .Random => .{ rng.randomFloat(), rng.randomFloat(), rng.randomFloat(), 0.0 },
            .Sobol => |*s| s.sample3D(),
        };
    }

    pub inline fn sample4D(self: *Sampler, rng: *RNG) Vec4f {
        return switch (self.*) {
            .Random => .{
                rng.randomFloat(),
                rng.randomFloat(),
                rng.randomFloat(),
                rng.randomFloat(),
            },
            .Sobol => |*s| s.sample4D(),
        };
    }

    pub inline fn cameraSample(self: *Sampler, rng: *RNG, pixel: Vec2i) CameraSample {
        const s4 = self.sample4D(rng);

        const sample = CameraSample{
            .pixel = pixel,
            .pixel_uv = .{ s4[0], s4[1] },
            .lens_uv = .{ s4[2], s4[3] },
            .time = self.sample1D(rng),
        };

        self.incrementSample();

        return sample;
    }
};

pub const Factory = union(enum) {
    Random,
    Sobol,

    pub fn create(self: Factory) Sampler {
        return switch (self) {
            .Random => Sampler{ .Random = {} },
            .Sobol => Sampler{ .Sobol = .{} },
        };
    }
};
