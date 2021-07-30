usingnamespace @import("camera_sample.zig");
pub const Golden_ratio = @import("golden_ratio.zig").Golden_ratio;

const base = @import("base");
const RNG = base.rnd.Generator;

usingnamespace base.math;

const Allocator = @import("std").mem.Allocator;

pub const Sampler = union(enum) {
    Random,
    Golden_ratio: Golden_ratio,

    pub fn deinit(self: *Sampler, alloc: *Allocator) void {
        switch (self.*) {
            .Random => {},
            .Golden_ratio => |*gr| gr.deinit(alloc),
        }
    }

    pub fn startPixel(self: *Sampler) void {
        switch (self.*) {
            .Random => {},
            .Golden_ratio => |*gr| gr.startPixel(),
        }
    }

    pub fn sample2D(self: *Sampler, rng: *RNG, dimension: u32) Vec2f {
        return switch (self.*) {
            .Random => Vec2f.init2(rng.randomFloat(), rng.randomFloat()),
            .Golden_ratio => |*gr| gr.sample2D(rng, dimension),
        };
    }

    pub fn sample(self: *Sampler, rng: *RNG, pixel: Vec2i) Camera_sample {
        return .{
            .pixel = pixel,
            .pixel_uv = self.sample2D(rng, 0),
        };
    }
};

pub const Factory = union(enum) {
    Random,
    Golden_ratio,

    pub fn create(
        self: Factory,
        alloc: *Allocator,
        num_dimensions_1D: u32,
        num_dimensions_2D: u32,
        max_samples: u32,
    ) !Sampler {
        return switch (self) {
            .Random => Sampler{ .Random = {} },
            .Golden_ratio => Sampler{
                .Golden_ratio = try Golden_ratio.init(alloc, num_dimensions_1D, num_dimensions_2D, max_samples),
            },
        };
    }
};
