const Texture = @import("../../image/texture/texture.zig").Texture;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const ts = @import("../../image/texture/texture_sampler.zig");
const Renderstate = @import("../renderstate.zig").Renderstate;
const Context = @import("../context.zig").Context;
const Scene = @import("../scene.zig").Scene;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const spectrum = base.spectrum;

const std = @import("std");

pub const Emittance = struct {
    const Quantity = enum {
        Flux,
        Intensity,
        Radiosity,
        Radiance,
    };

    emission_map: Texture = Texture.initUniform1(1.0),
    value: Vec4f = @splat(0.0),
    profile: Texture = .{},
    cos_a: f32 = -1.0,
    quantity: Quantity = .Radiance,
    num_samples: u32 = 1,

    // unit: lumen
    pub fn setLuminousFlux(self: *Emittance, color: Vec4f, value: f32, cos_a: f32) void {
        const luminance = spectrum.AP1toLuminance(color);

        self.value = @as(Vec4f, @splat(value / (std.math.pi * luminance))) * color;
        self.cos_a = cos_a;
        self.quantity = .Intensity;
    }

    // unit: lumen per unit solid angle (lm / sr == candela (cd))
    pub fn setLuminousIntensity(self: *Emittance, color: Vec4f, value: f32, cos_a: f32) void {
        const luminance = spectrum.AP1toLuminance(color);

        self.value = @as(Vec4f, @splat(value / luminance)) * color;
        self.cos_a = cos_a;
        self.quantity = .Intensity;
    }

    // unit: lumen per unit solid angle per unit projected area (lm / sr / m^2 == cd / m^2)
    pub fn setLuminance(self: *Emittance, color: Vec4f, value: f32, cos_a: f32) void {
        const luminance = spectrum.AP1toLuminance(color);

        self.value = @as(Vec4f, @splat(value / luminance)) * color;
        self.cos_a = cos_a;
        self.quantity = .Radiance;
    }

    // unit: watt per unit solid angle (W / sr)
    pub fn setRadiantIntensity(self: *Emittance, radi: Vec4f, cos_a: f32) void {
        self.value = radi;
        self.cos_a = cos_a;
        self.quantity = .Intensity;
    }

    // unit: watt per unit solid angle per unit projected area (W / sr / m^2)
    pub fn setRadiance(self: *Emittance, rad: Vec4f, cos_a: f32) void {
        self.value = rad;
        self.cos_a = cos_a;
        self.quantity = .Radiance;
    }

    pub fn radiance(
        self: Emittance,
        wi: Vec4f,
        rs: Renderstate,
        key: ts.Key,
        sampler: *Sampler,
        context: Context,
    ) Vec4f {
        var pf: f32 = 1.0;
        if (self.profile.isImage()) {
            const profile_key = ts.Key{
                .filter = ts.DefaultFilter,
                .address = .{ .u = .Clamp, .v = .Clamp },
            };

            const lwi = -math.normalize3(rs.trafo.worldToObjectPoint(rs.origin));
            const o = math.smpl.octEncode(lwi);
            const ouv = (o + @as(Vec2f, @splat(1.0))) * @as(Vec2f, @splat(0.5));

            pf = ts.sampleImage2D_1(profile_key, self.profile, ouv, sampler, context.scene);
        }

        if (-math.dot3(wi, rs.trafo.rotation.r[2]) < self.cos_a) {
            return @splat(0.0);
        }

        const intensity = self.value * ts.sample2D_3(key, self.emission_map, rs, sampler, context);

        if (self.quantity == .Intensity) {
            const area = context.scene.propShape(rs.prop).area(rs.part, rs.trafo.scale());
            return @as(Vec4f, @splat(pf / area)) * intensity;
        }

        return @as(Vec4f, @splat(pf)) * intensity;
    }

    pub fn averageRadiance(self: Emittance, area: f32) Vec4f {
        if (self.quantity == .Intensity) {
            return self.value / @as(Vec4f, @splat(area));
        }

        return self.value;
    }

    pub fn imageRadiance(self: Emittance, uv: Vec2f, key: ts.Key, sampler: *Sampler, scene: *const Scene) Vec4f {
        return self.value * ts.sampleImage2D_3(key, self.emission_map, uv, sampler, scene);
    }

    pub fn angleFromProfile(self: Emittance, scene: *const Scene) f32 {
        if (!self.profile.isImage()) {
            return std.math.pi;
        }

        const d = self.profile.description(scene).dimensions;

        const idf = @as(Vec2f, @splat(1.0)) / Vec2f{
            @floatFromInt(d[0]),
            @floatFromInt(d[1]),
        };

        var cos_a: f32 = 1.0;

        var y: i32 = 0;
        while (y < d[1]) : (y += 1) {
            const v = idf[1] * (@as(f32, @floatFromInt(y)) + 0.5);

            var x: i32 = 0;
            while (x < d[0]) : (x += 1) {
                const u = idf[0] * (@as(f32, @floatFromInt(x)) + 0.5);

                const s = self.profile.image2D_1(x, y, scene);

                if (s > 0.0) {
                    const dir = math.smpl.octDecode(@as(Vec2f, @splat(2.0)) * (Vec2f{ u, v } - @as(Vec2f, @splat(0.5))));
                    cos_a = math.min(cos_a, -dir[2]);
                }
            }
        }

        return std.math.acos(math.max(cos_a - math.max(idf[0], idf[1]), -1.0));
    }
};
