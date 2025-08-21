const Texture = @import("../../texture/texture.zig").Texture;
const ts = @import("../../texture/texture_sampler.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Renderstate = @import("../renderstate.zig").Renderstate;
const Context = @import("../context.zig").Context;
const Scene = @import("../scene.zig").Scene;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;

const base = @import("base");
const enc = base.encoding;
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const spectrum = base.spectrum;

const std = @import("std");

pub const Emittance = struct {
    emission_map: Texture = Texture.initUniform1(1.0),
    profile: Texture = Texture.initUniform1(0.0),

    value: Vec4f = @splat(0.0),

    camera_weight: f32 = 1.0,
    cos_a: f32 = -1.0,
    num_samples: u32 = 1,
    normalize: bool = false,

    pub fn radiance(
        self: Emittance,
        wi: Vec4f,
        rs: Renderstate,
        in_camera: bool,
        sampler: *Sampler,
        context: Context,
    ) Vec4f {
        if (-math.dot3(wi, rs.trafo.rotation.r[2]) < self.cos_a) {
            return @splat(0.0);
        }

        var factor: f32 = if (in_camera) self.camera_weight else 1.0;

        if (self.profile.isImage()) {
            const lwi = -math.normalize3(rs.trafo.worldToObjectPoint(rs.origin));
            const o = enc.octEncode(lwi);
            const ouv = (o + @as(Vec2f, @splat(1.0))) * @as(Vec2f, @splat(0.5));

            factor *= ts.sampleImage2D_1(self.profile, ouv, rs.stochastic_r, context.scene);
        }

        const intensity = self.value * ts.sample2D_3(self.emission_map, rs, sampler, context);

        if (self.normalize) {
            const area = context.scene.propShape(rs.prop).area(rs.part, rs.trafo.scale());
            return @as(Vec4f, @splat(factor / area)) * intensity;
        }

        return @as(Vec4f, @splat(factor)) * intensity;
    }

    pub fn averageRadiance(self: Emittance, area: f32) Vec4f {
        if (self.normalize) {
            return self.value / @as(Vec4f, @splat(area));
        }

        return self.value;
    }

    pub fn imageRadiance(self: Emittance, uv: Vec2f, sampler: *Sampler, scene: *const Scene) Vec4f {
        return self.value * ts.sampleImage2D_3(self.emission_map, uv, sampler.sample1D(), scene);
    }

    pub fn angleFromProfile(self: Emittance, scene: *const Scene) f32 {
        if (!self.profile.isImage()) {
            return std.math.pi;
        }

        const d = self.profile.dimensions(scene);

        const idf = @as(Vec4f, @splat(1.0)) / @as(Vec4f, @floatFromInt(d));

        var cos_a: f32 = 1.0;

        var y: i32 = 0;
        while (y < d[1]) : (y += 1) {
            const v = idf[1] * (@as(f32, @floatFromInt(y)) + 0.5);

            var x: i32 = 0;
            while (x < d[0]) : (x += 1) {
                const u = idf[0] * (@as(f32, @floatFromInt(x)) + 0.5);

                const s = self.profile.image2D_1(x, y, scene);

                if (s > 0.0) {
                    const dir = enc.octDecode(@as(Vec2f, @splat(2.0)) * (Vec2f{ u, v } - @as(Vec2f, @splat(0.5))));
                    cos_a = math.min(cos_a, -dir[2]);
                }
            }
        }

        return std.math.acos(math.max(cos_a - math.max(idf[0], idf[1]), -1.0));
    }
};
