const Base = @import("../sample_base.zig").Base;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Frame = math.Frame;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Sample = struct {
    super: Base,

    anisotropy: f32,

    pub fn init(wo: Vec4f, rs: Renderstate, anisotropy: f32) Sample {
        var super = Base.initTBN(rs, wo, @splat(1.0), 0, true);

        super.properties.translucent = true;

        return .{
            .super = super,
            .anisotropy = anisotropy,
        };
    }

    pub fn evaluate(self: *const Sample, wi: Vec4f) bxdf.Result {
        const wo_dot_wi = math.dot3(self.super.wo, wi);
        const g = self.anisotropy;

        const phase = phaseHg(wo_dot_wi, g);

        return bxdf.Result.init(@splat(phase), phase);
    }

    pub fn sample(self: *const Sample, sampler: *Sampler, max_splits: u32, buffer: *bxdf.Samples) []bxdf.Sample {
        const g = self.anisotropy;

        const split_weight = 1.0 / @as(f32, @floatFromInt(max_splits));

        const frame = Frame.init(-self.super.wo);

        for (0..max_splits) |i| {
            const r2 = sampler.sample2D();

            var cos_theta: f32 = undefined;
            if (@abs(g) < 0.001) {
                cos_theta = 1.0 - 2.0 * r2[0];
            } else {
                const gg = g * g;
                const sqr = (1.0 - gg) / (1.0 - g + 2.0 * g * r2[0]);
                cos_theta = (1.0 + gg - sqr * sqr) / (2.0 * g);
            }

            const sin_theta = @sqrt(math.max(0.0, @mulAdd(f32, cos_theta, -cos_theta, 1.0)));
            const phi = r2[1] * (2.0 * std.math.pi);

            const wil = math.smpl.sphereDirection(sin_theta, cos_theta, phi);
            const wi = frame.frameToWorld(wil);

            const phase = phaseHg(-cos_theta, g);

            buffer[i] = .{
                .reflection = @splat(phase),
                .wi = wi,
                .pdf = phase,
                .split_weight = split_weight,
                .wavelength = 0.0,
                .path = .diffuseReflection,
            };
        }

        return buffer[0..max_splits];
    }

    fn phaseHg(cos_theta: f32, g: f32) f32 {
        // const gg = g * g;
        // const denom = 1.0 + gg + 2.0 * g * cos_theta;

        const denom = @mulAdd(f32, g, g, @mulAdd(f32, 2.0 * g, cos_theta, 1.0));

        return @mulAdd(f32, g, -g, 1.0) / ((4.0 * std.math.pi) * denom * @sqrt(denom));
    }
};
