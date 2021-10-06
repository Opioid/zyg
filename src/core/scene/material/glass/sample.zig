const Base = @import("../sample_base.zig").SampleBase;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const bxdf = @import("../bxdf.zig");
const fresenel = @import("../fresnel.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");

pub const Sample = struct {
    super: Base,

    ior: f32,
    ior_outside: f32,

    pub fn init(rs: Renderstate, wo: Vec4f, ior: f32, ior_outside: f32) Sample {
        return .{
            .super = Base.init(
                rs,
                wo,
                @splat(4, @as(f32, 1.0)),
                @splat(4, @as(f32, 0.0)),
                @splat(2, @as(f32, 1.0)),
            ),
            .ior = ior,
            .ior_outside = ior_outside,
        };
    }

    pub fn sample(self: Sample, sampler: *Sampler, rng: *RNG) bxdf.Sample {
        const p = sampler.sample1D(rng, 0);

        return self.sampleInt(self.ior, p);
    }

    fn sampleInt(self: Sample, ior: f32, p: f32) bxdf.Sample {
        var eta_i = self.ior_outside;
        var eta_t = ior;

        if (eta_i == eta_t) {
            return .{
                .reflection = self.super.albedo,
                .wi = -self.super.wo,
                .pdf = 1.0,
                .typef = bxdf.TypeFlag.init1(.SpecularTransmission),
            };
        }

        const wo = self.super.wo;

        var n = self.super.layer.n;

        if (!self.super.sameHemisphere(wo)) {
            n = -n;
            std.mem.swap(f32, &eta_i, &eta_t);
        }

        const n_dot_wo = std.math.min(@fabs(math.dot3(n, wo)), 1.0);
        const eta = eta_i / eta_t;
        const sint2 = (eta * eta) * (1.0 - n_dot_wo * n_dot_wo);

        var n_dot_t: f32 = undefined;
        var f: f32 = undefined;
        if (sint2 >= 1.0) {
            n_dot_t = 0.0;
            f = 1.0;
        } else {
            n_dot_t = @sqrt(1.0 - sint2);
            f = fresenel.dielectric(n_dot_wo, n_dot_t, eta_i, eta_t);
        }

        if (p < f) {
            return reflect(wo, n, n_dot_wo);
        } else {
            return refract(wo, n, n_dot_wo, n_dot_t, eta);
        }
    }

    fn reflect(wo: Vec4f, n: Vec4f, n_dot_wo: f32) bxdf.Sample {
        return .{
            .reflection = @splat(4, @as(f32, 1.0)),
            .wi = math.normalize3(@splat(4, 2.0 * n_dot_wo) * n - wo),
            .pdf = 1.0,
            .typef = bxdf.TypeFlag.init1(.SpecularReflection),
        };
    }

    fn refract(wo: Vec4f, n: Vec4f, n_dot_wo: f32, n_dot_t: f32, eta: f32) bxdf.Sample {
        return .{
            .reflection = @splat(4, @as(f32, 1.0)),
            .wi = math.normalize3(@splat(4, eta * n_dot_wo - n_dot_t) * n - @splat(4, eta) * wo),
            .pdf = 1.0,
            .typef = bxdf.TypeFlag.init1(.SpecularTransmission),
        };
    }
};
