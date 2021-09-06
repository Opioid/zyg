const Debug = @import("debug/sample.zig").Sample;
const Glass = @import("glass/sample.zig").Sample;
const Light = @import("light/sample.zig").Sample;
const Substitute = @import("substitute/sample.zig").Sample;
const Base = @import("sample_base.zig").SampleBase;
const bxdf = @import("bxdf.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;

const base = @import("base");
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Sample = union(enum) {
    Debug: Debug,
    Glass: Glass,
    Light: Light,
    Substitute: Substitute,

    pub fn deinit(self: *Sample, alloc: *Allocator) void {
        _ = self;
        _ = alloc;
    }

    pub fn super(self: Sample) Base {
        return switch (self) {
            .Debug => |d| d.super,
            .Glass => |g| g.super,
            .Light => |l| l.super,
            .Substitute => |s| s.super,
        };
    }

    pub fn isPureEmissive(self: Sample) bool {
        return switch (self) {
            .Light => true,
            else => false,
        };
    }

    pub fn sample(self: Sample, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        return switch (self) {
            .Debug => |d| d.sample(sampler, rng),
            .Glass => |g| g.sample(sampler, rng),
            .Light => Light.sample(),
            .Substitute => |s| s.sample(sampler, rng),
        };
    }
};
