const bxdf = @import("../bxdf.zig");
const ccoef = @import("../collision_coefficients.zig");
const fresnel = @import("../fresnel.zig");
const ggx = @import("../ggx.zig");
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Frame = math.Frame;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Coating = struct {
    n: Vec4f = undefined,

    absorption_coef: Vec4f = undefined,

    thickness: f32 = 0.0,
    f0: f32 = undefined,
    alpha: f32 = undefined,
    weight: f32 = undefined,

    const Self = @This();

    const Result = struct {
        reflection: Vec4f,
        attenuation: Vec4f,
        f: f32,
        pdf: f32,
    };

    pub fn evaluate(self: *const Self, wi: Vec4f, wo: Vec4f, h: Vec4f, wo_dot_h: f32, avoid_caustics: bool) Result {
        const n = self.n;

        const n_dot_wi = math.safe.clampDot(n, wi);
        const n_dot_wo = math.safe.clampAbsDot(n, wo);

        const att = self.attenuation(n_dot_wi, n_dot_wo);

        if (avoid_caustics and self.alpha <= ggx.Min_alpha) {
            return .{ .reflection = @splat(0.0), .attenuation = att, .f = 0.0, .pdf = 0.0 };
        }

        const schlick = fresnel.Schlick.init(@splat(self.f0));

        const gg = ggx.Iso.reflectionF(
            h,
            n,
            n_dot_wi,
            n_dot_wo,
            wo_dot_h,
            self.alpha,
            schlick,
        );

        const ep = ggx.ilmEpDielectric(n_dot_wo, self.alpha, self.f0);
        return .{
            .reflection = @as(Vec4f, @splat(ep * self.weight * n_dot_wi)) * gg.r.reflection,
            .attenuation = att,
            .f = gg.f[0],
            .pdf = gg.r.pdf(),
        };
    }

    pub fn reflect(
        self: *const Self,
        wo: Vec4f,
        h: Vec4f,
        n_dot_wo: f32,
        n_dot_h: f32,
        wo_dot_h: f32,
        result: *bxdf.Sample,
    ) Vec4f {
        const n_dot_wi = ggx.Iso.reflectNoFresnel(
            wo,
            h,
            n_dot_wo,
            n_dot_h,
            wo_dot_h,
            self.alpha,
            Frame.init(self.n),
            result,
        );

        const ep = ggx.ilmEpDielectric(n_dot_wo, self.alpha, self.f0);
        result.reflection *= @splat(ep * self.weight * n_dot_wi);

        return self.attenuation(n_dot_wi, n_dot_wo);
    }

    pub fn sample(self: *const Self, wo: Vec4f, xi: Vec2f, n_dot_h: *f32) ggx.Micro {
        const h = ggx.Aniso.sample(wo, @splat(self.alpha), xi, Frame.init(self.n), n_dot_h);

        const wo_dot_h = math.safe.clampDot(wo, h);
        const f = fresnel.schlick1(wo_dot_h, self.f0);

        return .{ .h = h, .n_dot_wi = f, .h_dot_wi = wo_dot_h };
    }

    pub fn singleAttenuationStatic(absorption_coef: Vec4f, thickness: f32, n_dot_wo: f32) Vec4f {
        const d = thickness * (1.0 / n_dot_wo);

        return ccoef.attenuation3(absorption_coef, d);
    }

    pub fn singleAttenuation(self: *const Self, n_dot_wo: f32) Vec4f {
        return singleAttenuationStatic(self.absorption_coef, self.thickness, n_dot_wo);
    }

    pub fn attenuation(self: *const Self, n_dot_wi: f32, n_dot_wo: f32) Vec4f {
        const f = self.weight * fresnel.schlick1(math.min(n_dot_wi, n_dot_wo), self.f0);
        const d = self.thickness * (1.0 / n_dot_wi + 1.0 / n_dot_wo);

        const absorption = ccoef.attenuation3(self.absorption_coef, d);
        return @as(Vec4f, @splat(1.0 - f)) * absorption;
    }
};
