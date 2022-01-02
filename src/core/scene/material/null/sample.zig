const Base = @import("../sample_base.zig").SampleBase;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub const Sample = struct {
    super: Base,

    factor: f32,

    pub fn init(wo: Vec4f, rs: Renderstate) Sample {
        var super = Base.init(
            rs,
            wo,
            @splat(4, @as(f32, 0.0)),
            @splat(4, @as(f32, 0.0)),
            @splat(2, @as(f32, 1.0)),
        );
        super.properties.unset(.CanEvaluate);
        return .{ .super = super, .factor = 1.0 };
    }

    pub fn initFactor(wo: Vec4f, geo_n: Vec4f, n: Vec4f, alpha: f32, factor: f32) Sample {
        var super = Base.initN(wo, geo_n, n, alpha);
        super.properties.unset(.CanEvaluate);
        return .{ .super = super, .factor = factor };
    }

    pub fn sample(self: Sample) bxdf.Sample {
        return .{
            .reflection = @splat(4, self.factor),
            .wi = -self.super.wo,
            .h = undefined,
            .pdf = 1.0,
            .wavelength = 0.0,
            .h_dot_wi = undefined,
            .typef = bxdf.TypeFlag.init1(.StraightTransmission),
        };
    }
};
