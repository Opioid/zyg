const Base = @import("../material_base.zig").Base;
const SampleCoating = @import("coating.zig").Coating;
const hlp = @import("../material_helper.zig");
const ggx = @import("../ggx.zig");
const fresnel = @import("../fresnel.zig");
const Sample = @import("../sample.zig").Sample;
const Frame = @import("../sample_base.zig").Frame;
const Surface = @import("sample.zig").Sample;
const Volumetric = @import("../volumetric/sample.zig").Sample;
const Renderstate = @import("../../renderstate.zig").Renderstate;
const Worker = @import("../../worker.zig").Worker;
const Scene = @import("../../scene.zig").Scene;
const Trafo = @import("../../composed_transformation.zig").ComposedTransformation;
const ts = @import("../../../image/texture/texture_sampler.zig");
const Texture = @import("../../../image/texture/texture.zig").Texture;
const ccoef = @import("../collision_coefficients.zig");

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

const Coating = struct {};

pub const Material = struct {
    super: Base = .{},

    normal_map: Texture = .{},
    surface_map: Texture = .{},
    rotation_map: Texture = .{},
    emission_map: Texture = .{},
    coating_normal_map: Texture = .{},
    coating_thickness_map: Texture = .{},
    coating_roughness_map: Texture = .{},

    color: Vec4f = @splat(4, @as(f32, 0.5)),
    checkers: Vec4f = @splat(4, @as(f32, 0.0)),
    coating_absorption_coef: Vec4f = @splat(4, @as(f32, 0.0)),
    flakes_color: Vec4f = @splat(4, @as(f32, 0.8)),

    roughness: f32 = 0.8,
    anisotropy: f32 = 0.0,
    rotation: f32 = 0.0,
    metallic: f32 = 0.0,
    thickness: f32 = 0.0,
    transparency: f32 = 0.0,
    coating_thickness: f32 = 0.0,
    coating_ior: f32 = 1.5,
    coating_roughness: f32 = 0.2,
    flakes_coverage: f32 = 0.0,
    flakes_alpha: f32 = 0.01,
    flakes_res: f32 = 0.0,

    pub fn commit(self: *Material) void {
        self.super.properties.emission_map = self.emission_map.valid();
        self.super.properties.caustic = self.roughness <= ggx.Min_roughness;

        const thickness = self.thickness;
        const transparent = thickness > 0.0;
        const attenuation_distance = self.super.attenuation_distance;
        self.super.properties.two_sided = self.super.properties.two_sided or transparent;
        self.transparency = if (transparent) @exp(-thickness * (1.0 / attenuation_distance)) else 0.0;
    }

    pub fn prepareSampling(self: *const Material, area: f32, scene: *const Scene) Vec4f {
        const rad = self.super.emittance.averageRadiance(area);
        if (self.emission_map.valid()) {
            return rad * self.emission_map.average_3(scene);
        }

        return rad;
    }

    pub fn setColor(self: *Material, color: Base.MappedValue(Vec4f)) void {
        self.super.color_map = color.texture;
        self.color = color.value;
    }

    pub fn setRoughness(self: *Material, roughness: Base.MappedValue(f32)) void {
        self.surface_map = roughness.texture;
        self.roughness = ggx.clampRoughness(roughness.value);
    }

    pub fn setRotation(self: *Material, rotation: Base.MappedValue(f32)) void {
        self.rotation_map = rotation.texture;
        self.rotation = rotation.value * (2.0 * std.math.pi);
    }

    pub fn setCheckers(self: *Material, color_a: Vec4f, color_b: Vec4f, scale: f32) void {
        self.color = color_a;
        self.checkers = Vec4f{ color_b[0], color_b[1], color_b[2], scale };
    }

    pub fn setCoatingAttenuation(self: *Material, color: Vec4f, distance: f32) void {
        self.coating_absorption_coef = ccoef.attenuationCoefficient(color, distance);
    }

    pub fn setCoatingThickness(self: *Material, thickness: Base.MappedValue(f32)) void {
        self.coating_thickness_map = thickness.texture;
        self.coating_thickness = thickness.value;
    }

    pub fn setCoatingRoughness(self: *Material, roughness: Base.MappedValue(f32)) void {
        self.coating_roughness_map = roughness.texture;
        self.coating_roughness = ggx.clampRoughness(roughness.value);
    }

    pub fn setFlakesRoughness(self: *Material, roughness: f32) void {
        const r = ggx.clampRoughness(roughness);
        self.flakes_alpha = r * r;
    }

    pub fn setFlakesSize(self: *Material, size: f32) void {
        const N = 1.5396 / (size * size);
        const K = 4.0;

        self.flakes_res = std.math.max(4.0, @ceil(@sqrt(N / K)));
    }

    pub fn sample(self: *const Material, wo: Vec4f, rs: *const Renderstate, worker: *const Worker) Sample {
        if (rs.subsurface) {
            const g = self.super.volumetric_anisotropy;
            return .{ .Volumetric = Volumetric.init(wo, rs, g) };
        }

        const key = ts.resolveKey(self.super.sampler_key, rs.filter);

        const color = if (self.checkers[3] > 0.0) self.analyticCheckers(
            rs,
            key,
            worker,
        ) else if (self.super.color_map.valid()) ts.sample2D_3(
            key,
            self.super.color_map,
            rs.uv,
            worker.scene,
        ) else self.color;

        var rad = self.super.emittance.radiance(
            rs.p,
            -wo,
            rs.trafo,
            worker.scene.lightArea(rs.prop, rs.part),
            rs.filter,
            worker.scene,
        );
        if (self.emission_map.valid()) {
            rad *= ts.sample2D_3(key, self.emission_map, rs.uv, worker.scene);
        }

        var roughness: f32 = undefined;
        var metallic: f32 = undefined;

        const nc = self.surface_map.numChannels();
        if (nc >= 2) {
            const surface = ts.sample2D_2(key, self.surface_map, rs.uv, worker.scene);
            roughness = ggx.mapRoughness(surface[0]);
            metallic = surface[1];
        } else if (1 == nc) {
            roughness = ggx.mapRoughness(ts.sample2D_1(key, self.surface_map, rs.uv, worker.scene));
            metallic = self.metallic;
        } else {
            roughness = self.roughness;
            metallic = self.metallic;
        }

        const alpha = anisotropicAlpha(roughness, self.anisotropy);

        var coating_thickness: f32 = undefined;
        var coating_weight: f32 = undefined;
        var coating_ior: f32 = undefined;
        if (self.coating_thickness_map.valid()) {
            const relative_thickness = ts.sample2D_1(key, self.super.color_map, rs.uv, worker.scene);
            coating_thickness = self.coating_thickness * relative_thickness;
            coating_weight = if (relative_thickness > 0.1) 1.0 else relative_thickness;
            coating_ior = math.lerp(rs.ior(), self.coating_ior, coating_weight);
        } else {
            coating_thickness = self.coating_thickness;
            coating_weight = 1.0;
            coating_ior = self.coating_ior;
        }

        const ior = self.super.ior;
        const ior_outer = if (coating_thickness > 0.0) coating_ior else rs.ior();
        const attenuation_distance = self.super.attenuation_distance;

        var result = Surface.init(
            rs,
            wo,
            color,
            rad,
            alpha,
            ior,
            ior_outer,
            rs.ior(),
            metallic,
            attenuation_distance > 0.0,
        );

        if (self.normal_map.valid()) {
            const n = hlp.sampleNormal(wo, rs, self.normal_map, key, worker.scene);
            result.super.frame.setNormal(n);
        } else {
            result.super.frame.setTangentFrame(rs.t, rs.b, rs.n);
        }

        const thickness = self.thickness;
        if (thickness > 0.0) {
            result.setTranslucency(color, thickness, attenuation_distance, self.transparency);
        }

        if (coating_thickness > 0.0) {
            if (self.normal_map.equal(self.coating_normal_map)) {
                result.coating.frame = result.super.frame;
            } else if (self.coating_normal_map.valid()) {
                const n = hlp.sampleNormal(wo, rs, self.coating_normal_map, key, worker.scene);
                result.coating.frame.setNormal(n);
            } else {
                result.coating.frame.setTangentFrame(rs.t, rs.b, rs.n);
            }

            const r = if (self.coating_roughness_map.valid())
                ggx.mapRoughness(ts.sample2D_1(key, self.coating_roughness_map, rs.uv, worker.scene))
            else
                self.coating_roughness;

            result.coating.absorption_coef = self.coating_absorption_coef;
            result.coating.thickness = coating_thickness;
            result.coating.ior = coating_ior;
            result.coating.f0 = fresnel.Schlick.F0(coating_ior, rs.ior());
            result.coating.alpha = r * r;
            result.coating.weight = coating_weight;

            const n_dot_wo = result.coating.frame.clampAbsNdot(wo);
            result.super.radiance *= result.coating.singleAttenuation(n_dot_wo);
        }

        // Apply rotation to base frame after coating is calculated, so that coating is not affected
        const rotation = if (self.rotation_map.valid())
            ts.sample2D_1(key, self.rotation_map, rs.uv, worker.scene) * (2.0 * std.math.pi)
        else
            self.rotation;

        if (rotation > 0.0) {
            result.super.frame.rotateTangenFrame(rotation);
        }

        const flakes_coverage = self.flakes_coverage;
        if (flakes_coverage > 0.0) {
            const op = rs.trafo.worldToObjectPoint(rs.p);
            const on = rs.trafo.worldToObjectNormal(result.super.frame.n);

            const uv = hlp.triplanarMapping(op, on);

            const flake = sampleFlake(uv, self.flakes_res, flakes_coverage);

            const weight = flake.o;
            if (weight > 0.0) {
                const fa = self.flakes_alpha;
                const a2_cone = flakesA2cone(fa);
                const fa2 = fa - a2_cone;
                const cos_cone = 1.0 - (2.0 * a2_cone) / (1.0 + a2_cone);

                var n_dot_h: f32 = undefined;
                const m = ggx.Aniso.sample(wo, @splat(2, fa2), flake.r, result.super.frame, &n_dot_h);

                result.flakes_weight = weight;
                result.flakes_color = self.flakes_color;
                result.flakes_normal = m;
                result.flakes_cos_cone = cos_cone;
            }
        }

        return Sample{ .Substitute = result };
    }

    fn flakesA2cone(alpha: f32) f32 {
        comptime var target_angle = math.solidAngleCone(@cos(math.degreesToRadians(7.0)));
        comptime var limit = target_angle / ((4.0 * std.math.pi) - target_angle);

        return std.math.min(limit, 0.5 * alpha);
    }

    fn gridCell(uv: Vec2f, res: f32) Vec2i {
        const i: i32 = @floatToInt(i32, res * @mod(uv[0], 1.0));
        const j: i32 = @floatToInt(i32, res * @mod(uv[1], 1.0));
        return .{ i, j };
    }

    const Flake = struct {
        o: f32,
        r: Vec2f,
    };

    fn sampleFlake(uv: Vec2f, res: f32, coverage: f32) Flake {
        const ij = gridCell(uv, res);

        var nearest_d: f32 = std.math.f32_max;
        var nearest_r: [3]f32 = undefined;

        var ii = ij[0] - 1;
        while (ii <= ij[0] + 1) : (ii += 1) {
            var jj = ij[1] - 1;
            while (jj <= ij[1] + 1) : (jj += 1) {
                var rng = initRNG(hashyBashy(ii, jj));

                var fl: u32 = 0;
                while (fl < 4) : (fl += 1) {
                    const p = Vec2f{ randomFloat(&rng), randomFloat(&rng) };
                    const r = [3]f32{ randomFloat(&rng), randomFloat(&rng), randomFloat(&rng) };

                    const vcd = math.squaredLength2(uv - p);
                    if (vcd < nearest_d) {
                        nearest_d = vcd;

                        nearest_r[0] = r[0];
                        nearest_r[1] = r[1];
                        nearest_r[2] = r[2];
                    }
                }
            }
        }

        return .{
            .o = if (nearest_r[2] < coverage) 1.0 else 0.0,
            .r = .{ nearest_r[0], nearest_r[1] },
        };
    }

    fn hashyBashy(a: i32, b: i32) u32 {
        // const hb = hash(@bitCast(u32, a));
        // const ha = hash(@bitCast(u32, b));
        // return hashCombine(hb, ha);

        const sa = @intCast(i16, a);
        const sb = @intCast(i16, b);
        return @as(u32, @bitCast(u16, sa)) << 16 | @as(u32, @bitCast(u16, sb));
    }

    fn hash(i: u32) u32 {
        var x = i ^ (i >> 16);
        x *%= 0x7feb352d;
        x ^= x >> 15;
        x *%= 0x846ca68b;
        x ^= x >> 16;
        return x;
    }

    fn hashCombine(seed: u32, v: u32) u32 {
        return seed ^ (v +% (seed << 6) +% (seed >> 2));
    }

    fn initRNG(seed: u32) u64 {
        var state: u64 = 0;

        _ = advanceRNG(&state);
        state += seed;
        _ = advanceRNG(&state);
        return state;
    }

    fn advanceRNG(state: *u64) u32 {
        const old = state.*;

        // Advance internal state
        state.* = old *% 6364136223846793005 + 1;

        // Calculate output function (XSH RR), uses old state for max ILP
        const xrs = @truncate(u32, ((old >> 18) ^ old) >> 27);
        const rot = @truncate(u5, old >> 59);

        return (xrs >> rot) | (xrs << ((0 -% rot) & 31));
    }

    fn randomFloat(state: *u64) f32 {
        var bits = advanceRNG(state);

        bits &= 0x007FFFFF;
        bits |= 0x3F800000;

        return @bitCast(f32, bits) - 1.0;
    }

    pub fn evaluateRadiance(
        self: *const Material,
        p: Vec4f,
        wi: Vec4f,
        n: Vec4f,
        uv: Vec2f,
        trafo: Trafo,
        extent: f32,
        filter: ?ts.Filter,
        scene: *const Scene,
    ) Vec4f {
        const key = ts.resolveKey(self.super.sampler_key, .Nearest);

        var rad = self.super.emittance.radiance(p, wi, trafo, extent, filter, scene);
        if (self.emission_map.valid()) {
            rad *= ts.sample2D_3(key, self.emission_map, uv, scene);
        }

        var coating_thickness: f32 = undefined;
        if (self.coating_thickness_map.valid()) {
            const relative_thickness = ts.sample2D_1(key, self.super.color_map, uv, scene);
            coating_thickness = self.coating_thickness * relative_thickness;
        } else {
            coating_thickness = self.coating_thickness;
        }

        if (coating_thickness > 0.0) {
            const n_dot_wi = hlp.clampAbsDot(wi, n);
            const att = SampleCoating.singleAttenuationStatic(
                self.coating_absorption_coef,
                self.coating_thickness,
                n_dot_wi,
            );

            return att * rad;
        }

        return rad;
    }

    fn anisotropicAlpha(r: f32, anisotropy: f32) Vec2f {
        if (anisotropy > 0.0) {
            const rv = ggx.clampRoughness(r * (1.0 - anisotropy));
            return .{ r * r, rv * rv };
        }

        return @splat(2, r * r);
    }

    // https://www.iquilezles.org/www/articles/checkerfiltering/checkerfiltering.htm

    fn analyticCheckers(self: *const Material, rs: *const Renderstate, sampler_key: ts.Key, worker: *const Worker) Vec4f {
        const checkers_scale = self.checkers[3];

        const dd = @splat(4, checkers_scale) * worker.screenspaceDifferential(rs);

        const t = checkersGrad(
            @splat(2, checkers_scale) * sampler_key.address.address2(rs.uv),
            .{ dd[0], dd[1] },
            .{ dd[2], dd[3] },
        );

        return math.lerp(self.color, self.checkers, t);
    }

    fn checkersGrad(uv: Vec2f, ddx: Vec2f, ddy: Vec2f) f32 {
        // filter kernel
        const w = math.max2(@fabs(ddx), @fabs(ddy)) + @splat(2, @as(f32, 0.0001));

        // analytical integral (box filter)
        const i = (tri(uv + @splat(2, @as(f32, 0.5)) * w) - tri(uv - @splat(2, @as(f32, 0.5)) * w)) / w;

        // xor pattern
        return 0.5 - 0.5 * i[0] * i[1];
    }

    // triangular signal
    fn tri(x: Vec2f) Vec2f {
        const hx = math.frac(x[0] * 0.5) - 0.5;
        const hy = math.frac(x[1] * 0.5) - 0.5;
        return .{ 1.0 - 2.0 * @fabs(hx), 1.0 - 2.0 * @fabs(hy) };
    }
};
