const Debug = @import("debug/debug_sample.zig").Sample;
const Glass = @import("glass/glass_sample.zig").Sample;
const Hair = @import("hair/hair_sample.zig").Sample;
const Light = @import("light/light_sample.zig").Sample;
const Null = @import("null/null_sample.zig").Sample;
const Substitute = @import("substitute/substitute_sample.zig").Sample;
const Volumetric = @import("volumetric/volumetric_sample.zig").Sample;
const Base = @import("sample_base.zig").Base;
const bxdf = @import("bxdf.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub const Sample = union(enum) {
    Debug: Debug,
    Glass: Glass,
    Hair: Hair,
    Light: Light,
    Null: Null,
    Substitute: Substitute,
    Volumetric: Volumetric,

    pub fn super(self: *const Sample) *const Base {
        return switch (self.*) {
            inline else => |*s| &s.super,
        };
    }

    pub fn isPureEmissive(self: *const Sample) bool {
        return switch (self.*) {
            .Light => true,
            else => false,
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

    pub fn evaluate(self: *const Sample, wi: Vec4f, split: bool) bxdf.Result {
        return switch (self.*) {
            .Light, .Null => bxdf.Result.init(@splat(0.0), 0.0),
            .Glass => |*s| s.evaluate(wi, split),
            inline else => |*s| s.evaluate(wi),
        };
    }

    pub fn sample(self: *const Sample, sampler: *Sampler, split: bool, buffer: *bxdf.Samples) []bxdf.Sample {
        return switch (self.*) {
            .Light => {
                buffer[0] = Light.sample();
                return buffer[0..1];
            },
            .Null => |*s| {
                buffer[0] = s.sample();
                return buffer[0..1];
            },
            inline .Glass, .Volumetric => |*s| {
                return s.sample(sampler, split, buffer);
            },
            inline else => |*s| {
                buffer[0] = s.sample(sampler);
                return buffer[0..1];
            },
        };
    }
};
