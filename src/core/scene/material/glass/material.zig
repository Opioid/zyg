const Base = @import("../material_base.zig").Base;
const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Scene = @import("../../scene.zig").Scene;
const ts = @import("../../../image/texture/sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const fresnel = @import("../fresnel.zig");
const hlp = @import("../material_helper.zig");
const ggx = @import("../ggx.zig");
const inthlp = @import("../../../rendering/integrator/helper.zig");

const math = @import("base").math;
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
        self.super.properties.two_sided = self.thickness > 0.0;
        self.super.properties.caustic = self.roughness <= ggx.Min_roughness;
    }

    pub fn setRoughness(self: *Material, roughness: Base.MappedValue(f32)) void {
        self.roughness_map = roughness.texture;
        const r = roughness.value;
        self.roughness = if (r > 0.0) ggx.clampRoughness(r) else 0.0;
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, scene: Scene) Sample {
        const key = ts.resolveKey(self.super.sampler_key, rs.filter);

        const r = if (self.roughness_map.valid())
            ggx.mapRoughness(ts.sample2D_1(key, self.roughness_map, rs.uv, scene))
        else
            self.roughness;

        var result = Sample.init(
            rs,
            wo,
            self.super.cc.a,
            self.super.ior,
            rs.ior(),
            r * r,
            self.thickness,
            self.abbe,
            rs.wavelength(),
        );

        if (self.normal_map.valid()) {
            const n = hlp.sampleNormal(wo, rs, self.normal_map, key, scene);
            const tb = math.orthonormalBasis3(n);

            result.super.frame.setTangentFrame(tb[0], tb[1], n);
        } else {
            result.super.frame.setTangentFrame(rs.t, rs.b, rs.n);
        }

        return result;
    }

    pub fn visibility(self: Material, wi: Vec4f, n: Vec4f, uv: Vec2f, filter: ?ts.Filter, scene: Scene) ?Vec4f {
        const o = self.super.opacity(uv, filter, scene);

        if (self.thickness > 0.0) {
            const eta_i: f32 = 1.0;
            const eta_t = self.super.ior;

            const n_dot_wo = std.math.min(@fabs(math.dot3(n, wi)), 1.0);
            const eta = eta_i / eta_t;
            const sint2 = (eta * eta) * (1.0 - n_dot_wo * n_dot_wo);

            if (sint2 >= 1.0) {
                if (o < 1.0) {
                    return @splat(4, 1.0 - o);
                }

                return null;
            }

            const n_dot_t = @sqrt(1.0 - sint2);
            const f = fresnel.dielectric(n_dot_wo, n_dot_t, eta_i, eta_t);

            const n_dot_wi = hlp.clamp(n_dot_wo);
            const approx_dist = self.thickness / n_dot_wi;

            const attenuation = inthlp.attenuation3(self.super.cc.a, approx_dist);

            const ta = @minimum(@splat(4, 1.0 - o) + attenuation, @splat(4, @as(f32, 1.0)));

            return @splat(4, 1.0 - f) * ta;
        }

        if (o < 1.0) {
            return @splat(4, 1.0 - o);
        }

        return null;
    }
};
