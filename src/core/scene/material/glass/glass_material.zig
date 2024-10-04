const Base = @import("../material_base.zig").Base;
const Sample = @import("glass_sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Scene = @import("../../scene.zig").Scene;
const ts = @import("../../../image/texture/texture_sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const fresnel = @import("../fresnel.zig");
const ccoef = @import("../collision_coefficients.zig");
const hlp = @import("../material_helper.zig");
const ggx = @import("../ggx.zig");

const math = @import("base").math;
const Frame = math.Frame;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Material = struct {
    super: Base = .{},

    normal_map: Texture = .{},
    roughness_map: Texture = .{},

    thickness: f32 = 0.0,
    roughness: f32 = 0.0,
    abbe: f32 = 0.0,

    pub fn commit(self: *Material) void {
        const thin = self.thickness > 0.0;
        self.super.properties.two_sided = thin;
        self.super.properties.evaluate_visibility = thin or self.super.mask.valid();
        self.super.properties.caustic = self.roughness <= ggx.Min_roughness;
    }

    pub fn setRoughness(self: *Material, roughness: Base.MappedValue(f32)) void {
        self.roughness_map = roughness.texture;
        const r = roughness.value;
        self.roughness = if (r > 0.0) ggx.clampRoughness(r) else 0.0;
    }

    pub fn sample(self: *const Material, wo: Vec4f, rs: Renderstate, sampler: *Sampler, scene: *const Scene) Sample {
        const key = self.super.sampler_key;

        const fat = 0.0 == self.thickness;

        const roughness = if (fat or rs.primary) self.roughness else 0.0;

        const r = if (self.roughness_map.valid() and rs.primary)
            ggx.mapRoughness(ts.sample2D_1(key, self.roughness_map, rs.uv, sampler, scene))
        else
            roughness;

        var result = Sample.init(
            rs,
            wo,
            self.super.cc.a,
            self.super.ior,
            rs.ior,
            r * r,
            self.thickness,
            self.abbe,
            rs.wavelength,
        );

        if (self.normal_map.valid()) {
            const n = hlp.sampleNormal(wo, rs, self.normal_map, key, sampler, scene);
            result.super.frame = Frame.init(n);
        } else {
            result.super.frame = .{ .x = rs.t, .y = rs.b, .z = rs.n };
        }

        return result;
    }

    pub fn visibility(self: *const Material, wi: Vec4f, n: Vec4f, uv: Vec2f, sampler: *Sampler, scene: *const Scene) ?Vec4f {
        const o = self.super.opacity(uv, sampler, scene);

        if (self.thickness > 0.0) {
            const eta_i: f32 = 1.0;
            const eta_t = self.super.ior;

            const n_dot_wo = math.min(@abs(math.dot3(n, wi)), 1.0);
            const eta = eta_i / eta_t;
            const sint2 = (eta * eta) * (1.0 - n_dot_wo * n_dot_wo);

            if (sint2 >= 1.0) {
                if (o < 1.0) {
                    return @as(Vec4f, @splat(1.0 - o));
                }

                return null;
            }

            const n_dot_t = @sqrt(1.0 - sint2);
            const f = fresnel.dielectric(n_dot_wo, n_dot_t, eta_i, eta_t);

            const n_dot_wi = math.safe.clamp(n_dot_wo);
            const approx_dist = self.thickness / n_dot_wi;

            const attenuation = ccoef.attenuation3(self.super.cc.a, approx_dist);

            const ta = math.min4(@as(Vec4f, @splat(1.0 - o)) + attenuation, @splat(1.0));

            return @as(Vec4f, @splat(1.0 - f)) * ta;
        }

        if (o < 1.0) {
            return @as(Vec4f, @splat(1.0 - o));
        }

        return null;
    }
};
