const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const rnd = base.rnd;
const RNG = rnd.Generator;

const Allocator = @import("std").mem.Allocator;

pub const GoldenRatio = struct {
    num_dimensions_1D: u32,
    num_dimensions_2D: u32,

    num_samples: u32,

    current_samples: []u32 = &.{},

    samples_1D: []f32 = &.{},
    samples_2D: []Vec2f = &.{},

    const Self = @This();

    pub fn init(alloc: *Allocator, num_dimensions_1D: u32, num_dimensions_2D: u32, max_samples: u32) !GoldenRatio {
        return GoldenRatio{
            .num_dimensions_1D = num_dimensions_1D,
            .num_dimensions_2D = num_dimensions_2D,
            .num_samples = max_samples,
            .current_samples = try alloc.alloc(u32, num_dimensions_1D + num_dimensions_2D),
            .samples_1D = try alloc.alloc(f32, num_dimensions_1D * max_samples),
            .samples_2D = try alloc.alloc(Vec2f, num_dimensions_2D * max_samples),
        };
    }

    pub fn deinit(self: *Self, alloc: *Allocator) void {
        alloc.free(self.samples_2D);
        alloc.free(self.samples_1D);
        alloc.free(self.current_samples);
    }

    pub fn startPixel(self: *Self) void {
        for (self.current_samples) |*s| {
            s.* = 0;
        }
    }

    pub fn sample2D(self: *Self, rng: *RNG, dimension: u32) Vec2f {
        var cs = &self.current_samples[self.num_dimensions_1D + dimension];

        const current = cs.*;
        cs.* += 1;

        if (0 == current) {
            self.generate2D(rng, dimension);
        }

        return self.samples_2D[dimension * self.num_samples + current];
    }

    fn generate2D(self: *Self, rng: *RNG, dimension: u32) void {
        const num_samples = self.num_samples;
        const begin = dimension * num_samples;
        const end = begin + num_samples;

        var slice = self.samples_2D[begin..end];

        const r = Vec2f.init2(rng.randomFloat(), rng.randomFloat());
        math.goldenRatio2D(slice, r);

        rnd.biasedShuffle(Vec2f, slice, rng);
    }
};
