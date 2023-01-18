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

pub const Sample = union(enum) {
    pub const BxdfSamples = [2]bxdf.Sample;

    Debug: Debug,
    Glass: Glass,
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
            .Substitute => |*s| math.lerp(s.super.albedo, s.f0, s.metallic),
            inline else => |*s| s.super.albedo,
        };
    }

    pub fn evaluate(self: *const Sample, wi: Vec4f) bxdf.Result {
        return switch (self.*) {
            .Light, .Null => bxdf.Result.init(@splat(4, @as(f32, 0.0)), 0.0),
            inline else => |*s| s.evaluate(wi),
        };
    }

    pub fn sample(self: *const Sample, sampler: *Sampler, split: bool, buffer: *BxdfSamples) []bxdf.Sample {
        _ = split;

        buffer[0] = switch (self.*) {
            .Light => Light.sample(),
            .Null => |*s| s.sample(),
            inline else => |*s| s.sample(sampler),
        };

        return buffer[0..1];
    }
};
