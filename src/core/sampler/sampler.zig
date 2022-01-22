const CameraSample = @import("camera_sample.zig").CameraSample;
pub const GoldenRatio = @import("golden_ratio.zig").GoldenRatio;

const base = @import("base");
const math = base.math;
const RNG = base.rnd.Generator;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;

const Allocator = @import("std").mem.Allocator;

pub const Sampler = union(enum) {
    Random,
    GoldenRatio: GoldenRatio,

    pub fn deinit(self: *Sampler, alloc: Allocator) void {
        switch (self.*) {
            .Random => {},
            .GoldenRatio => |*gr| gr.deinit(alloc),
        }
    }

    pub fn startPixel(self: *Sampler, num_samples: u32) void {
        switch (self.*) {
            .Random => {},
            .GoldenRatio => |*gr| gr.startPixel(num_samples),
        }
    }

    pub fn sample1D(self: *Sampler, rng: *RNG, dimension: usize) f32 {
        return switch (self.*) {
            .Random => rng.randomFloat(),
            .GoldenRatio => |*gr| gr.sample1D(rng, @intCast(u32, dimension)),
        };
    }

    pub fn sample2D(self: *Sampler, rng: *RNG, dimension: usize) Vec2f {
        return switch (self.*) {
            .Random => .{ rng.randomFloat(), rng.randomFloat() },
            .GoldenRatio => |*gr| gr.sample2D(rng, @intCast(u32, dimension)),
        };
    }

    pub fn cameraSample(self: *Sampler, rng: *RNG, pixel: Vec2i) CameraSample {
        return .{
            .pixel = pixel,
            .pixel_uv = self.sample2D(rng, 0),
            .lens_uv = self.sample2D(rng, 1),
            .time = self.sample1D(rng, 0),
        };
    }
};

pub const Factory = union(enum) {
    Random,
    GoldenRatio,

    pub fn create(
        self: Factory,
        alloc: Allocator,
        num_dimensions_1D: u32,
        num_dimensions_2D: u32,
        max_samples: u32,
    ) !Sampler {
        return switch (self) {
            .Random => Sampler{ .Random = {} },
            .GoldenRatio => Sampler{
                .GoldenRatio = try GoldenRatio.init(alloc, num_dimensions_1D, num_dimensions_2D, max_samples),
            },
        };
    }
};
