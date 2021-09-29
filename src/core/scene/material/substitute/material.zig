const Base = @import("../material_base.zig").Base;
const hlp = @import("../material_helper.zig");
const ggx = @import("../ggx.zig");
const fresnel = @import("../fresnel.zig");
const Sample = @import("sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Worker = @import("../../worker.zig").Worker;
const Scene = @import("../../scene.zig").Scene;
const ts = @import("../../../image/texture/sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

//const std = @import("std");

pub const Material = struct {
    super: Base = undefined,

    normal_map: Texture = undefined,
    surface_map: Texture = undefined,
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

    pub fn prepareSampling(self: Material, scene: Scene) Vec4f {
        if (self.emission_map.isValid()) {
            return @splat(4, self.emission_factor) * self.emission_map.average_3(scene);
        }

        return @splat(4, self.emission_factor) * self.super.emission;
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
            worker.scene.*,
        ) else self.color;

        const ef = @splat(4, self.emission_factor);
        const radiance = if (self.emission_map.isValid()) ef * ts.sample2D_3(
            key,
            self.emission_map,
            rs.uv,
            worker.scene.*,
        ) else ef * self.super.emission;

        var alpha: Vec2f = undefined;
        var metallic: f32 = undefined;

        const nc = self.surface_map.numChannels();
        if (nc >= 2) {
            const surface = ts.sample2D_2(key, self.surface_map, rs.uv, worker.scene.*);
            const r = ggx.mapRoughness(surface[0]);
            alpha = anisotropicAlpha(r, self.anisotropy);
            metallic = surface[1];
        } else if (1 == nc) {
            const r = ggx.mapRoughness(ts.sample2D_1(key, self.surface_map, rs.uv, worker.scene.*));
            alpha = anisotropicAlpha(r, self.anisotropy);
            metallic = self.metallic;
        } else {
            alpha = self.alpha;
            metallic = self.metallic;
        }

        var result = Sample.init(
            rs,
            wo,
            color,
            radiance,
            alpha,
            fresnel.Schlick.F0(self.super.ior, 1.0),
            metallic,
        );

        if (self.normal_map.isValid()) {
            const n = hlp.sampleNormal(wo, rs, self.normal_map, key, worker.scene.*);
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
            return ef * ts.sample2D_3(key, self.emission_map, .{ uvw[0], uvw[1] }, worker.scene.*);
        }

        return ef * self.super.emission;
    }

    fn anisotropicAlpha(r: f32, anisotropy: f32) Vec2f {
        if (anisotropy > 0.0) {
            const rv = ggx.clampRoughness(r * (1.0 - anisotropy));
            return .{ r * r, rv * rv };
        }

        return @splat(2, r * r);
    }
};
