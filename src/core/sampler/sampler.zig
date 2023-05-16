const CameraSample = @import("camera_sample.zig").CameraSample;
pub const Sobol = @import("sobol.zig").Sobol;

const base = @import("base");
const math = base.math;
const RNG = base.rnd.Generator;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;

const Random = struct {
    rng: *RNG,
};

pub const Sampler = union(enum) {
    Random: Random,
    Sobol: Sobol,

    pub fn startPixel(self: *Sampler, sample: u32, seed: u32) void {
        switch (self.*) {
            .Random => {},
            .Sobol => |*s| s.startPixel(sample, seed),
        }
    }

    pub fn incrementSample(self: *Sampler) void {
        switch (self.*) {
            .Random => {},
            .Sobol => |*s| s.incrementSample(),
        }
    }

    pub fn incrementPadding(self: *Sampler) void {
        switch (self.*) {
            .Random => {},
            .Sobol => |*s| s.incrementPadding(),
        }
    }

    pub fn sample1D(self: *Sampler) f32 {
        return switch (self.*) {
            .Random => |*r| r.rng.randomFloat(),
            .Sobol => |*s| s.sample1D(),
        };
    }

    pub fn sample2D(self: *Sampler) Vec2f {
        return switch (self.*) {
            .Random => |*r| .{ r.rng.randomFloat(), r.rng.randomFloat() },
            .Sobol => |*s| s.sample2D(),
        };
    }

    pub fn sample3D(self: *Sampler) Vec4f {
        return switch (self.*) {
            .Random => |*r| .{ r.rng.randomFloat(), r.rng.randomFloat(), r.rng.randomFloat(), 0.0 },
            .Sobol => |*s| s.sample3D(),
        };
    }

    pub fn sample4D(self: *Sampler) Vec4f {
        return switch (self.*) {
            .Random => |*r| .{
                r.rng.randomFloat(),
                r.rng.randomFloat(),
                r.rng.randomFloat(),
                r.rng.randomFloat(),
            },
            .Sobol => |*s| s.sample4D(),
        };
    }

    pub fn cameraSample(self: *Sampler, pixel: Vec2i) CameraSample {
        const s4 = self.sample4D();
        const s1 = self.sample1D();

        self.incrementPadding();

        return .{
            .pixel = pixel,
            .pixel_uv = .{ s4[0], s4[1] },
            .lens_uv = .{ s4[2], s4[3] },
            .time = s1,
        };
    }
};

pub const Factory = union(enum) {
    Random,
    Sobol,

    pub fn create(self: Factory, rng: *RNG) Sampler {
        return switch (self) {
            .Random => Sampler{ .Random = .{ .rng = rng } },
            .Sobol => Sampler{ .Sobol = .{} },
        };
    }
};
