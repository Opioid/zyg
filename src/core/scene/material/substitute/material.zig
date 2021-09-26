const Base = @import("../material_base.zig").Base;
const hlp = @import("../material_helper.zig");
const ggx = @import("../ggx.zig");
const fresnel = @import("../fresnel.zig");
const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Worker = @import("../../worker.zig").Worker;
const ts = @import("../../../image/texture/sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

//const std = @import("std");

pub const Material = struct {
    super: Base = undefined,

    normal_map: Texture = undefined,
    emission_map: Texture = undefined,

    color: Vec4f = undefined,

    alpha: Vec2f = undefined,

    anisotropy: f32 = undefined,
    rotation: f32 = undefined,
    metallic: f32 = undefined,
    emission_factor: f32 = undefined,

    pub fn init(sampler_key: ts.Key, two_sided: bool) Material {
        return .{ .super = Base.init(sampler_key, two_sided) };
    }

    pub fn commit(self: *Material) void {
        self.super.properties.set(.EmissionMap, self.emission_map.isValid());
    }

    pub fn setRoughness(self: *Material, roughness: f32, anisotropy: f32) void {
        const r = ggx.clampRoughness(roughness);

        if (anisotropy > 0.0) {
            const rv = ggx.clampRoughness(roughness * (1.0 - anisotropy));
            self.alpha = .{ r * r, rv * rv };
        } else {
            self.alpha = @splat(2, r * r);
        }

        self.anisotropy = anisotropy;
    }

    pub fn sample(self: Material, wo: Vec4f, rs: Renderstate, worker: *Worker) Sample {
        const key = ts.resolveKey(self.super.sampler_key, rs.filter);

        const color = if (self.super.color_map.isValid()) ts.sample2D_3(
            key,
            self.super.color_map,
            rs.uv,
            worker.scene,
        ) else self.color;

        const ef = @splat(4, self.emission_factor);
        const radiance = if (self.emission_map.isValid()) ef * ts.sample2D_3(
            key,
            self.emission_map,
            rs.uv,
            worker.scene,
        ) else ef * self.super.emission;

        var result = Sample.init(
            rs,
            wo,
            color,
            radiance,
            self.alpha,
            fresnel.Schlick.F0(self.super.ior, 1.0),
            self.metallic,
        );

        if (self.normal_map.isValid()) {
            const n = hlp.sampleNormal(wo, rs, self.normal_map, key, worker.scene);
            const tb = math.orthonormalBasis3(n);

            result.super.layer.setTangentFrame(tb[0], tb[1], n);
        } else {
            result.super.layer.setTangentFrame(rs.t, rs.b, rs.n);
        }

        if (self.rotation > 0.0) {
            result.super.layer.rotateTangenFrame(self.rotation);
        }

        return result;
    }

    pub fn evaluateRadiance(self: Material, uvw: Vec4f, filter: ?ts.Filter, worker: Worker) Vec4f {
        const ef = @splat(4, self.emission_factor);
        if (self.emission_map.isValid()) {
            const key = ts.resolveKey(self.super.sampler_key, filter);
            return ef * ts.sample2D_3(key, self.emission_map, .{ uvw[0], uvw[1] }, worker.scene);
        }

        return ef * self.super.emission;
    }
};
