const Debug = @import("debug/sample.zig").Sample;
const Glass = @import("glass/sample.zig").Sample;
const Light = @import("light/sample.zig").Sample;
const Null = @import("null/sample.zig").Sample;
const Substitute = @import("substitute/sample.zig").Sample;
const Volumetric = @import("volumetric/sample.zig").Sample;
const Base = @import("sample_base.zig").SampleBase;
const bxdf = @import("bxdf.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Sample = union(enum) {
    Debug: Debug,
    Glass: Glass,
    Light: Light,
    Null: Null,
    Substitute: Substitute,
    Volumetric: Volumetric,

    pub fn deinit(self: *Sample, alloc: *Allocator) void {
        _ = self;
        _ = alloc;
    }

    pub fn super(self: *const Sample) *const Base {
        return switch (self.*) {
            .Debug => |*d| &d.super,
            .Glass => |*g| &g.super,
            .Light => |*l| &l.super,
            .Null => |*n| &n.super,
            .Substitute => |*s| &s.super,
            .Volumetric => |*v| &v.super,
        };
    }

    pub fn isPureEmissive(self: *const Sample) bool {
        return switch (self.*) {
            .Light => true,
            else => false,
        };
    }

    pub fn isTranslucent(self: *const Sample) bool {
        return self.super().properties.is(.Translucent);
    }

    pub fn canEvaluate(self: *const Sample) bool {
        return self.super().properties.is(.CanEvaluate);
    }

    pub fn evaluate(self: *const Sample, wi: Vec4f) bxdf.Result {
        return switch (self.*) {
            .Debug => |*s| s.evaluate(wi),
            .Glass => |*s| s.evaluate(wi),
            .Light, .Null => bxdf.Result.init(@splat(4, @as(f32, 0.0)), 0.0),
            .Substitute => |*s| s.evaluate(wi),
            .Volumetric => |*v| v.evaluate(wi),
        };
    }

    pub fn sample(self: *const Sample, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        return switch (self.*) {
            .Debug => |*m| m.sample(sampler, rng),
            .Glass => |*m| m.sample(sampler, rng),
            .Light => Light.sample(),
            .Null => |*m| m.sample(),
            .Substitute => |*m| m.sample(sampler, rng),
            .Volumetric => |*m| m.sample(sampler, rng),
        };
    }
};
