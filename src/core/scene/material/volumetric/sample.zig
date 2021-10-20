const Base = @import("../sample_base.zig").SampleBase;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");

pub const Sample = struct {
    super: Base,

    anisotropy: f32,

    pub fn init(wo: Vec4f, rs: Renderstate, anisotropy: f32) Sample {
        var super = Base.init(
            rs,
            wo,
            @splat(4, @as(f32, 0.0)),
            @splat(4, @as(f32, 0.0)),
            @splat(2, @as(f32, 1.0)),
        );

        super.properties.set(.Translucent, true);

        return .{
            .super = super,
            .anisotropy = anisotropy,
        };
    }

    pub fn evaluate(self: Sample, wi: Vec4f) bxdf.Result {
        const wo_dot_wi = math.dot3(self.super.wo, wi);
        const g = self.anisotropy;

        const phase = phaseHg(wo_dot_wi, g);

        return bxdf.Result.init(@splat(4, phase), phase);
    }

    pub fn sample(self: Sample, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        const r2 = sampler.sample2D(rng, 0);

        const g = self.anisotropy;

        var cos_theta: f32 = undefined;
        if (@fabs(g) < 0.001) {
            cos_theta = 1.0 - 2.0 * r2[0];
        } else {
            const gg = g * g;
            const sqr = (1.0 - gg) / (1.0 - g + 2.0 * g * r2[0]);
            cos_theta = (1.0 + gg - sqr * sqr) / (2.0 * g);
        }

        const sin_theta = @sqrt(std.math.max(0.0, 1.0 - cos_theta * cos_theta));
        const phi = r2[1] * (2.0 * std.math.pi);

        const wo = self.super.wo;
        const tb = math.orthonormalBasis3(wo);

        const wi = math.smpl.sphereDirection(sin_theta, cos_theta, phi, tb[0], tb[1], -wo);

        const phase = phaseHg(-cos_theta, g);

        return .{
            .reflection = @splat(4, phase),
            .wi = wi,
            .h = undefined,
            .pdf = phase,
            .h_dot_wi = undefined,
            .typef = bxdf.TypeFlag.init1(.DiffuseReflection),
        };
    }

    fn phaseHg(cos_theta: f32, g: f32) f32 {
        const gg = g * g;
        const denom = 1.0 + gg + 2.0 * g * cos_theta;
        return (1.0 / (4.0 * std.math.pi)) * (1.0 - gg) / (denom / @sqrt(denom));
    }
};
