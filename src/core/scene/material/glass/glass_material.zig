const Base = @import("../material_base.zig").Base;
const Sample = @import("glass_sample.zig").Sample;
const Context = @import("../../context.zig").Context;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const ts = @import("../../../texture/texture_sampler.zig");
const Texture = @import("../../../texture/texture.zig").Texture;
const Sampler = @import("../../../sampler/sampler.zig").Sampler;
const fresnel = @import("../fresnel.zig");
const ccoef = @import("../collision_coefficients.zig");
const hlp = @import("../material_helper.zig");
const ggx = @import("../ggx.zig");

const math = @import("base").math;
const Frame = math.Frame;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Material = struct {
    super: Base = .{},

    normal_map: Texture = Texture.initUniform1(0.0),
    roughness: Texture = Texture.initUniform1(0.0),
    specular: Texture = Texture.initUniform1(1.0),

    absorption: Vec4f = undefined,
    attenuation_distance: f32 = 1.0,
    ior: f32 = 1.46,
    thickness: f32 = 0.0,
    abbe: f32 = 0.0,

    pub fn commit(self: *Material) void {
        const properties = &self.super.properties;

        const thin = self.thickness > 0.0;
        properties.two_sided = thin;
        properties.evaluate_visibility = thin or self.super.mask.isImage();
        properties.caustic = self.roughness.isUniform() and self.roughness.uniform1() <= ggx.MinRoughness;
    }

    pub fn setVolumetric(self: *Material, attenuation_color: Vec4f, distance: f32) void {
        self.absorption = ccoef.attenuationCoefficient(attenuation_color, distance);
        self.attenuation_distance = distance;
    }

    pub fn sample(self: *const Material, wo: Vec4f, rs: Renderstate, sampler: *Sampler, context: Context) Sample {
        const use_roughness = !self.super.properties.caustic and (0.0 == self.thickness or rs.primary);
        const r = if (use_roughness)
            ggx.clampRoughness(ts.sample2D_1(self.roughness, rs, sampler, context))
        else
            0.0;

        const specular = ts.sample2D_1(self.specular, rs, sampler, context);

        var result = Sample.init(
            rs,
            wo,
            self.absorption,
            self.ior,
            rs.ior,
            r * r,
            specular,
            self.thickness,
            self.abbe,
            rs.wavelength,
            self.super.priority,
        );

        if (!self.normal_map.isUniform()) {
            const n = hlp.sampleNormal(wo, rs, self.normal_map, sampler, context);
            result.super.frame = Frame.init(n);
        } else {
            result.super.frame = .{ .x = rs.t, .y = rs.b, .z = rs.n };
        }

        return result;
    }

    pub fn visibility(self: *const Material, wi: Vec4f, rs: Renderstate, sampler: *Sampler, context: Context, tr: *Vec4f) bool {
        const o = self.super.opacity(rs.uv(), sampler, context.scene);

        if (self.thickness > 0.0) {
            const eta_i: f32 = 1.0;
            const eta_t = self.ior;

            const n_dot_wo = math.min(@abs(math.dot3(rs.geo_n, wi)), 1.0);
            const eta = eta_i / eta_t;
            const sint2 = (eta * eta) * (1.0 - n_dot_wo * n_dot_wo);

            if (sint2 >= 1.0) {
                if (o < 1.0) {
                    tr.* *= @splat(1.0 - o);
                    return true;
                }

                return false;
            }

            const n_dot_t = @sqrt(1.0 - sint2);
            const f = fresnel.dielectric(n_dot_wo, n_dot_t, eta_i, eta_t);

            const n_dot_wi = math.safe.clamp(n_dot_wo);
            const approx_dist = self.thickness / n_dot_wi;

            const attenuation = ccoef.attenuation3(self.absorption, approx_dist);

            const ta = math.min4(@as(Vec4f, @splat(1.0 - o)) + attenuation, @splat(1.0));

            tr.* *= @as(Vec4f, @splat(1.0 - f)) * ta;
            return true;
        }

        if (o < 1.0) {
            tr.* *= @splat(1.0 - o);
            return true;
        }

        return false;
    }
};
