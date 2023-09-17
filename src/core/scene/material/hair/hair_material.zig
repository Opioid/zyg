const Base = @import("../material_base.zig").Base;
const Sample = @import("hair_sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Material = struct {
    super: Base = .{},

    color: Vec4f = @splat(0.5),
    mu_a: Vec4f = @splat(-1.0),

    roughness: Vec2f = @splat(0.3),

    v: [3]f32 = undefined,

    s: f32 = undefined,
    alpha: f32 = math.degreesToRadians(2.0),

    sin2k_alpha: [3]f32 = undefined,
    cos2k_alpha: [3]f32 = undefined,

    pub fn commit(self: *Material) void {
        const beta_m = self.roughness[0];
        self.v[0] = math.pow2(0.726 * beta_m + 0.812 * math.pow2(beta_m) + 3.7 * math.pow20(beta_m));
        self.v[1] = 0.25 * self.v[0];
        self.v[2] = 4.0 * self.v[0];

        const beta_n = self.roughness[1];
        const sqrt_pi_over8 = comptime 0.626657069;
        self.s = sqrt_pi_over8 * (0.265 * beta_n + 1.194 * math.pow2(beta_n) + 5.372 * math.pow22(beta_n));

        if (self.mu_a[0] < 0.0) {
            const denom = 5.969 -
                0.215 * beta_n +
                2.532 * math.pow2(beta_n) -
                10.73 * math.pow3(beta_n) +
                5.574 * math.pow4(beta_n) +
                0.245 * math.pow5(beta_n);

            const sqrt_mu_a = @log(self.color) / @as(Vec4f, @splat(denom));
            self.mu_a = (sqrt_mu_a * sqrt_mu_a);
        }

        self.sin2k_alpha[0] = @sin(self.alpha);
        self.cos2k_alpha[0] = @sqrt(1.0 - self.sin2k_alpha[0] * self.sin2k_alpha[0]);

        for (1..3) |i| {
            self.sin2k_alpha[i] = 2.0 * self.cos2k_alpha[i - 1] * self.sin2k_alpha[i - 1];
            self.cos2k_alpha[i] = math.pow2(self.cos2k_alpha[i - 1]) - math.pow2(self.sin2k_alpha[i - 1]);
        }
    }

    pub fn setMelanin(self: *Material, eumelanin: f32, pheomelanin: f32) void {
        self.mu_a = absorptionFromMelanin(eumelanin, pheomelanin);
    }

    pub fn sample(self: *const Material, wo: Vec4f, rs: Renderstate, sampler: *Sampler) Sample {
        _ = sampler;

        return Sample.init(rs, wo, self.mu_a, self.super.ior, self.v, self.s, self.sin2k_alpha, self.cos2k_alpha);
    }

    fn absorptionFromMelanin(ce: f32, cp: f32) Vec4f {
        const eumelanin_a = Vec4f{ 0.419, 0.697, 1.37, 0.0 };
        const pheomelanin_a = Vec4f{ 0.187, 0.4, 1.05, 0.0 };
        return @as(Vec4f, @splat(ce)) * eumelanin_a + @as(Vec4f, @splat(cp)) * pheomelanin_a;
    }
};
