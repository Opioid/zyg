const sample = @import("../sample_base.zig");
const Base = sample.Base;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const bxdf = @import("../bxdf.zig");

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Sample = struct {
    pub const MaxP = 3;

    const AP = struct {
        reflection: [MaxP + 1]Vec4f,
        pdf: [MaxP + 1]f32,
    };

    super: Base,

    ior: f32,
    h: f32,

    sin_theta_o: f32,
    cos_theta_o: f32,
    phi_o: f32,
    gamma_o: f32,

    v: [3]f32,
    s: f32,

    sin2k_alpha: [3]f32,
    cos2k_alpha: [3]f32,

    ap: AP,

    pub fn init(
        rs: Renderstate,
        wo: Vec4f,
        color: Vec4f,
        ior: f32,
        v: [3]f32,
        s: f32,
        sin2k_alpha: [3]f32,
        cos2k_alpha: [3]f32,
    ) Sample {
        var super = Base.init(rs, wo, color, @splat(1.0), 0);

        super.properties.translucent = true;
        super.frame = .{ .x = rs.t, .y = rs.b, .z = rs.n };

        const wo_l = super.frame.worldToFrame(wo);

        const sin_theta_o = math.clamp(wo_l[0], -1.0, 1.0);
        const cos_theta_o = @sqrt(1.0 - sin_theta_o * sin_theta_o);
        const phi_o = std.math.atan2(wo_l[2], wo_l[1]);

        const h = math.clamp(2.0 * (rs.uvw[1] - 0.5), -1.0, 1.0);

        const eta = ior;
        const etap = @sqrt(eta * eta - (sin_theta_o * sin_theta_o)) / cos_theta_o;
        const sin_gamma_t = h / etap;
        const cos_gamma_t = @sqrt(1.0 - sin_gamma_t * sin_gamma_t);

        // Compute the transmittance tr of a single path through the cylinder
        // We store absorption coefficient in albedo for this material!
        const sin_theta_t = sin_theta_o / eta;
        const cos_theta_t = @sqrt(1.0 - sin_theta_t * sin_theta_t);
        const tr = @exp(-color * @as(Vec4f, @splat(2.0 * cos_gamma_t / cos_theta_t)));
        const ap = apFunc(cos_theta_o, eta, h, tr);

        return .{
            .super = super,
            .ior = ior,
            .h = h,
            .sin_theta_o = sin_theta_o,
            .cos_theta_o = cos_theta_o,
            .phi_o = phi_o,
            .gamma_o = std.math.asin(h),
            .v = v,
            .s = s,
            .sin2k_alpha = sin2k_alpha,
            .cos2k_alpha = cos2k_alpha,
            .ap = ap,
        };
    }

    pub fn evaluate(self: *const Sample, wi: Vec4f) bxdf.Result {
        const wi_l = self.super.frame.worldToFrame(wi);

        const sin_theta_o = self.sin_theta_o;
        const cos_theta_o = self.cos_theta_o;
        const phi_o = self.phi_o;

        const sin_theta_i = math.clamp(wi_l[0], -1.0, 1.0);
        const cos_theta_i = @sqrt(1.0 - sin_theta_i * sin_theta_i);
        const phi_i = std.math.atan2(wi_l[2], wi_l[1]);

        const eta = self.ior;
        const etap = @sqrt(eta * eta - (sin_theta_o * sin_theta_o)) / cos_theta_o;
        const sin_gamma_t = self.h / etap;
        const gamma_t = std.math.asin(sin_gamma_t);

        const phi = phi_i - phi_o;

        return self.eval(cos_theta_i, cos_theta_o, sin_theta_i, sin_theta_o, phi, self.gamma_o, gamma_t);
    }

    fn eval(
        self: *const Sample,
        cos_theta_i: f32,
        cos_theta_o: f32,
        sin_theta_i: f32,
        sin_theta_o: f32,
        phi: f32,
        gamma_o: f32,
        gamma_t: f32,
    ) bxdf.Result {
        const v = self.v;
        const s = self.s;
        const ap = self.ap;

        var fsum: Vec4f = @splat(0.0);
        var pdf_sum: f32 = 0.0;

        for (0..MaxP) |p| {
            var sin_thetap_o: f32 = undefined;
            var cos_thetap_o: f32 = undefined;

            if (0 == p) {
                sin_thetap_o = sin_theta_o * self.cos2k_alpha[1] - cos_theta_o * self.sin2k_alpha[1];
                cos_thetap_o = cos_theta_o * self.cos2k_alpha[1] + sin_theta_o * self.sin2k_alpha[1];
            } else if (1 == p) {
                sin_thetap_o = sin_theta_o * self.cos2k_alpha[0] + cos_theta_o * self.sin2k_alpha[0];
                cos_thetap_o = cos_theta_o * self.cos2k_alpha[0] - sin_theta_o * self.sin2k_alpha[0];
            } else if (p == 2) {
                sin_thetap_o = sin_theta_o * self.cos2k_alpha[2] + cos_theta_o * self.sin2k_alpha[2];
                cos_thetap_o = cos_theta_o * self.cos2k_alpha[2] - sin_theta_o * self.sin2k_alpha[2];
            } else {
                sin_thetap_o = sin_theta_o;
                cos_thetap_o = cos_theta_o;
            }

            // Handle out-of-range cos_thetap_o from scale adjustment
            cos_thetap_o = @abs(cos_thetap_o);

            const tmp = mp(cos_theta_i, cos_thetap_o, sin_theta_i, sin_thetap_o, v[@min(p, 2)]);
            const tnp = np(phi, @floatFromInt(p), s, gamma_o, gamma_t);
            const ta_reflection = ap.reflection[p];
            const ta_pdf = ap.pdf[p];
            const mnp = tmp * tnp;

            fsum += @as(Vec4f, @splat(mnp)) * ta_reflection;
            pdf_sum += mnp * ta_pdf;
        }

        // Compute contribution of remaining terms after _pMax_
        const tmp = mp(cos_theta_i, cos_theta_o, sin_theta_i, sin_theta_o, v[2]);
        const ta_reflection = ap.reflection[MaxP];
        const ta_pdf = ap.pdf[MaxP];

        fsum += @as(Vec4f, @splat(tmp)) * ta_reflection;
        pdf_sum += tmp * ta_pdf;

        return bxdf.Result.init(fsum, pdf_sum);
    }

    pub fn sample(self: *const Sample, sampler: *Sampler) bxdf.Sample {
        const sin_theta_o = self.sin_theta_o;
        const cos_theta_o = self.cos_theta_o;
        const phi_o = self.phi_o;

        const eta = self.ior;
        const etap = @sqrt(eta * eta - sin_theta_o * sin_theta_o) / cos_theta_o;
        const sin_gamma_t = self.h / etap;
        const gamma_t = std.math.asin(sin_gamma_t);

        const r = sampler.sample1D();

        var p: u32 = MaxP;
        var cdf: f32 = 0.0;
        for (self.ap.pdf, 0..) |ae_pdf, i| {
            cdf += ae_pdf;
            if (cdf >= r) {
                p = @intCast(i);
                break;
            }
        }

        var sin_thetap_o: f32 = undefined;
        var cos_thetap_o: f32 = undefined;

        if (0 == p) {
            sin_thetap_o = sin_theta_o * self.cos2k_alpha[1] - cos_theta_o * self.sin2k_alpha[1];
            cos_thetap_o = cos_theta_o * self.cos2k_alpha[1] + sin_theta_o * self.sin2k_alpha[1];
        } else if (1 == p) {
            sin_thetap_o = sin_theta_o * self.cos2k_alpha[0] + cos_theta_o * self.sin2k_alpha[0];
            cos_thetap_o = cos_theta_o * self.cos2k_alpha[0] - sin_theta_o * self.sin2k_alpha[0];
        } else if (p == 2) {
            sin_thetap_o = sin_theta_o * self.cos2k_alpha[2] + cos_theta_o * self.sin2k_alpha[2];
            cos_thetap_o = cos_theta_o * self.cos2k_alpha[2] - sin_theta_o * self.sin2k_alpha[2];
        } else {
            sin_thetap_o = sin_theta_o;
            cos_thetap_o = cos_theta_o;
        }

        // Handle out-of-range cos_thetap_o from scale adjustment
        cos_thetap_o = @abs(cos_thetap_o);

        const s3d = sampler.sample3D();

        const vp = self.v[@min(p, 2)];
        const cos_theta = 1.0 + vp * @log(math.max(s3d[0], 1e-5) + (1.0 - s3d[0]) * @exp(-2.0 / vp));
        const sin_theta = @sqrt(1.0 - cos_theta * cos_theta);
        const cos_phi = @cos(2.0 * std.math.pi * s3d[1]);
        const sin_theta_i = math.clamp(-cos_theta * sin_thetap_o + sin_theta * cos_phi * cos_thetap_o, -1.0, 1.0);
        const cos_theta_i = @sqrt(1.0 - sin_theta_i * sin_theta_i);

        var phi: f32 = undefined;
        if (p < MaxP) {
            phi = phiFunc(@floatFromInt(p), self.gamma_o, gamma_t) + sampleTrimmedLogistic(s3d[2], self.s, -std.math.pi, std.math.pi);
        } else {
            phi = (2.0 * std.math.pi) * s3d[2];
        }

        // Compute wi from sampled hair scattering angles
        const phi_i = phi_o + phi;
        const is = Vec4f{ sin_theta_i, cos_theta_i * @cos(phi_i), cos_theta_i * @sin(phi_i), 0.0 };
        const wi = math.normalize3(self.super.frame.frameToWorld(is));

        const er = self.eval(cos_theta_i, cos_theta_o, sin_theta_i, sin_theta_o, phi, self.gamma_o, gamma_t);

        return .{
            .reflection = er.reflection,
            .wi = wi,
            .pdf = er.pdf,
            .split_weight = 1.0,
            .wavelength = 0.0,
            .class = .{ .glossy = true, .reflection = true },
        };
    }

    fn mp(cos_theta_i: f32, cos_theta_o: f32, sin_theta_i: f32, sin_theta_o: f32, v: f32) f32 {
        const a = cos_theta_i * cos_theta_o / v;
        const b = sin_theta_i * sin_theta_o / v;

        return if (v <= 0.1) (@exp(logI0(a) - b - 1.0 / v + 0.6931 + @log(1.0 / (2.0 * v)))) else (@exp(-b) * I0(a)) / (std.math.sinh(1.0 / v) * 2.0 * v);
    }

    fn phiFunc(p: f32, gamma_o: f32, gamma_t: f32) f32 {
        return 2.0 * p * gamma_t - 2.0 * gamma_o + p * std.math.pi;
    }

    fn np(phi: f32, p: f32, s: f32, gamma_o: f32, gamma_t: f32) f32 {
        var dphi = phi - phiFunc(p, gamma_o, gamma_t);

        while (dphi > std.math.pi) {
            dphi -= 2.0 * std.math.pi;
        }

        while (dphi < -std.math.pi) {
            dphi += 2.0 * std.math.pi;
        }

        return trimmedLogistic(dphi, s, -std.math.pi, std.math.pi);
    }

    fn apFunc(cos_theta_o: f32, eta: f32, h: f32, tr: Vec4f) AP {
        var result: AP = undefined;

        //  Compute $p=0$ attenuation at initial cylinder intersection
        const cos_gamma_o = @sqrt(1.0 - h * h);
        const cos_theta = cos_theta_o * cos_gamma_o;
        const f = fresnel(cos_theta, eta);
        const vf: Vec4f = @splat(f);
        result.reflection[0] = vf;
        var asum = f;

        // Compute $p=1$ attenuation term
        const f1 = @as(Vec4f, @splat(math.pow2(1 - f))) * tr;
        result.reflection[1] = f1;
        asum += math.average3(f1);

        const ftr = vf * tr;

        // Compute attenuation terms up to $p=_pMax_$
        for (result.reflection[2..MaxP], 2..) |*r, p| {
            const fx = result.reflection[p - 1] * ftr;
            r.* = fx;
            asum += math.average3(fx);
        }

        // Compute attenuation term accounting for remaining orders of scattering
        const fx = result.reflection[MaxP - 1] * ftr / math.max4(@as(Vec4f, @splat(1.0)) - ftr, @splat(0.999));
        result.reflection[MaxP] = fx;
        asum += math.average3(fx);

        const norm = 1.0 / asum;
        for (result.reflection, &result.pdf) |ref, *p| {
            p.* = math.average3(ref) * norm;
        }

        return result;
    }

    fn I0(x: f32) f32 {
        var val: f32 = 0.0;
        var x2i: f32 = 1.0;
        var ifact: i64 = 1;
        var ifour: i64 = 1;

        for (0..10) |i| {
            if (i > 1) {
                ifact *= @intCast(i);
            }

            val += x2i / @as(f32, @floatFromInt(ifour * ifact * ifact));
            x2i *= x * x;
            ifour *= 4;
        }

        return val;
    }

    fn logI0(x: f32) f32 {
        if (x > 12.0) {
            return x + 0.5 * (-@log(2.0 * std.math.pi) + @log(1.0 / x) + 1.0 / (8.0 * x));
        } else {
            return @log(I0(x));
        }
    }

    fn logistic(x: f32, s: f32) f32 {
        const ax = @abs(x);
        return @exp(-ax / s) / (s * math.pow2(1.0 + @exp(-ax / s)));
    }

    fn logisticCDF(x: f32, s: f32) f32 {
        return 1.0 / (1.0 + @exp(-x / s));
    }

    fn sampleLogistic(u: f32, s: f32) f32 {
        return -s * @log(1.0 / u - 1.0);
    }

    fn trimmedLogistic(x: f32, s: f32, a: f32, b: f32) f32 {
        return logistic(x, s) / (logisticCDF(b, s) - logisticCDF(a, s));
    }

    fn sampleTrimmedLogistic(u: f32, s: f32, a: f32, b: f32) f32 {
        const lu = math.lerp(invertLogisticSample(a, s), invertLogisticSample(b, s), u);
        const x = sampleLogistic(lu, s);

        return math.clamp(x, a, b);
    }

    fn invertLogisticSample(x: f32, s: f32) f32 {
        return 1.0 / (1.0 + @exp(-x / s));
    }

    fn fresnel(cos_theta: f32, eta_x: f32) f32 {
        //cosTheta_i = Clamp(cosTheta_i, -1, 1);

        var cos_theta_i = cos_theta;
        var eta = eta_x;

        // Potentially flip interface orientation for Fresnel equations
        if (cos_theta_i < 0.0) {
            eta = 1.0 / eta;
            cos_theta_i = -cos_theta_i;
        }

        const sin2_theta_i = 1.0 - cos_theta_i * cos_theta_i;
        const sin2_theta_t = sin2_theta_i / (eta * eta);

        if (sin2_theta_t >= 1.0) {
            return 1.0;
        }

        const cos_theta_t = @sqrt(1.0 - sin2_theta_t);

        const r_parl = (eta * cos_theta_i - cos_theta_t) / (eta * cos_theta_i + cos_theta_t);
        const r_perp = (cos_theta_i - eta * cos_theta_t) / (cos_theta_i + eta * cos_theta_t);
        return 0.5 * (r_parl * r_parl + r_perp * r_perp);
    }
};
