const Debug = @import("debug/debug_sample.zig").Sample;
const Glass = @import("glass/glass_sample.zig").Sample;
pub const Hair = @import("hair/hair_sample.zig").Sample;
const Light = @import("light/light_sample.zig").Sample;
pub const Substitute = @import("substitute/substitute_sample.zig").Sample;
const Volumetric = @import("volumetric/volumetric_sample.zig").Sample;
const Base = @import("sample_base.zig").Base;
const bxdf = @import("bxdf.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const CC = @import("collision_coefficients.zig").CC;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub const Sample = union(enum) {
    Debug: Debug,
    Glass: Glass,
    Hair: Hair,
    Light: Light,
    Substitute: Substitute,
    Volumetric: Volumetric,

    pub fn super(self: *const Sample) *const Base {
        return switch (self.*) {
            inline else => |*s| &s.super,
        };
    }

    pub fn isTranslucent(self: *const Sample) bool {
        return self.super().properties.translucent;
    }

    pub fn canEvaluate(self: *const Sample) bool {
        return self.super().properties.can_evaluate;
    }

    pub fn aovAlbedo(self: *const Sample) Vec4f {
        return switch (self.*) {
            .Substitute => |*s| math.lerp(s.super.albedo, s.f0, @as(Vec4f, @splat(s.metallic))),
            inline else => |*s| s.super.albedo,
        };
    }

    pub fn evaluate(self: *const Sample, wi: Vec4f, max_splits: u32, force_disable_caustics: bool) bxdf.Result {
        return switch (self.*) {
            .Light => bxdf.Result.init(@splat(0.0), 0.0),
            inline .Glass, .Substitute => |*s| s.evaluate(wi, max_splits, force_disable_caustics),
            inline else => |*s| s.evaluate(wi),
        };
    }

    pub fn sample(self: *const Sample, sampler: *Sampler, max_splits: u32, buffer: *bxdf.Samples) []bxdf.Sample {
        return switch (self.*) {
            .Light => {
                return buffer[0..0];
            },
            inline .Glass, .Substitute, .Volumetric => |*s| {
                return s.sample(sampler, max_splits, buffer);
            },
            inline else => |*s| {
                buffer[0] = s.sample(sampler);
                return buffer[0..1];
            },
        };
    }

    pub fn collisionCoefficients(self: *const Sample) CC {
        return switch (self.*) {
            .Glass => |s| .{ .a = s.absorption_coef, .s = @splat(0.0) },
            .Substitute => |s| s.cc,
            else => undefined,
        };
    }
};
