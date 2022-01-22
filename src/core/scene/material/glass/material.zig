const Base = @import("../material_base.zig").Base;
const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Worker = @import("../../worker.zig").Worker;
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
    super: Base,

    normal_map: Texture = .{},
    roughness_map: Texture = .{},

    thickness: f32 = 0.0,
    alpha: f32 = 0.0,
    abbe: f32 = 0.0,

    pub fn init(sampler_key: ts.Key) Material {
        return .{ .super = Base.init(sampler_key, false) };
    }

    pub fn commit(self: *Material) void {
        self.super.properties.set(.TwoSided, self.thickness > 0.0);
        self.super.properties.set(.Caustic, self.alpha <= ggx.Min_alpha);
    }

    pub fn setRoughness(self: *Material, roughness: f32) void {
        self.alpha = roughness * roughness;
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: *Worker) Sample {
        const key = ts.resolveKey(self.super.sampler_key, rs.filter);

        var alpha: f32 = undefined;

        if (self.roughness_map.valid()) {
            const roughness = ts.sample2D_1(key, self.roughness_map, rs.uv, worker.scene.*);
            const r = ggx.mapRoughness(roughness);
            alpha = r * r;
        } else {
            alpha = self.alpha;
        }

        var result = Sample.init(
            rs,
            wo,
            self.super.cc.a,
            self.super.ior,
            rs.ior(),
            alpha,
            self.thickness,
            self.abbe,
            rs.wavelength(),
        );

        if (self.normal_map.valid()) {
            const n = hlp.sampleNormal(wo, rs, self.normal_map, key, worker.scene.*);
            const tb = math.orthonormalBasis3(n);

            result.super.layer.setTangentFrame(tb[0], tb[1], n);
        } else {
            result.super.layer.setTangentFrame(rs.t, rs.b, rs.n);
        }

        return result;
    }

    pub fn visibility(self: Material, wi: Vec4f, n: Vec4f, uv: Vec2f, filter: ?ts.Filter, worker: Worker) ?Vec4f {
        const o = self.super.opacity(uv, filter, worker);

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
