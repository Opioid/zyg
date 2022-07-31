const Texture = @import("../../image/texture/texture.zig").Texture;
const ts = @import("../../image/texture/sampler.zig");
const Scene = @import("../scene.zig").Scene;

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

    value: Vec4f = @splat(4, @as(f32, 0.0)),
    profile: Texture = .{},
    cos_a: f32 = 0.0,
    quantity: Quantity = .Radiance,

    // unit: lumen
    pub fn setLuminousFlux(self: *Emittance, color: Vec4f, value: f32, cos_a: f32) void {
        const luminance = spectrum.luminance(color);

        self.value = @splat(4, value / (std.math.pi * luminance)) * color;
        self.cos_a = cos_a;
        self.quantity = .Intensity;
    }

    // unit: lumen per unit solid angle (lm / sr == candela (cd))
    pub fn setLuminousIntensity(self: *Emittance, color: Vec4f, value: f32, cos_a: f32) void {
        const luminance = spectrum.luminance(color);

        self.value = @splat(4, value / luminance) * color;
        self.cos_a = cos_a;
        self.quantity = .Intensity;
    }

    // unit: lumen per unit solid angle per unit projected area (lm / sr / m^2 == cd / m^2)
    pub fn setLuminance(self: *Emittance, color: Vec4f, value: f32, cos_a: f32) void {
        const luminance = spectrum.luminance(color);

        self.value = @splat(4, value / luminance) * color;
        self.cos_a = cos_a;
        self.quantity = .Radiance;
    }

    // unit: watt per unit solid angle (W / sr)
    pub fn setRadiantIntensity(self: *Emittance, radi: Vec4f, cos_a: f32) void {
        self.value = radi;
        self.cos_a = cos_a;
        self.quantity = Quantity.Intensity;
    }

    // unit: watt per unit solid angle per unit projected area (W / sr / m^2)
    pub fn setRadiance(self: *Emittance, rad: Vec4f, cos_a: f32) void {
        self.value = rad;
        self.cos_a = cos_a;
        self.quantity = Quantity.Radiance;
    }

    fn dirToLatlongUv(v: Vec4f) Vec2f {
        return .{
            std.math.atan2(f32, -v[0], -v[2]) / (2.0 * std.math.pi) + 0.5,
            std.math.acos(v[1]) / std.math.pi,
        };
    }

    pub fn radiance(
        self: Emittance,
        wi: Vec4f,
        t: Vec4f,
        b: Vec4f,
        n: Vec4f,
        area: f32,
        filter: ?ts.Filter,
        scene: Scene,
    ) Vec4f {
        var pf: f32 = 1.0;
        if (self.profile.valid()) {
            const wt = wi * t;
            const wb = wi * b;
            const wn = wi * n;

            const lwi = Vec4f{
                wt[0] + wt[1] + wt[2],
                wb[0] + wb[1] + wb[2],
                wn[0] + wn[1] + wn[2],
                0.0,
            };

            const key = ts.Key{
                .filter = filter orelse .Linear,
                .address = .{ .u = .Repeat, .v = .Clamp },
            };

            pf = ts.sample2D_1(key, self.profile, dirToLatlongUv(lwi), scene);
        }

        if (@fabs(math.dot3(wi, n)) < self.cos_a) {
            return @splat(4, @as(f32, 0.0));
        }

        if (self.quantity == .Intensity) {
            return @splat(4, pf / area) * self.value;
        }

        return @splat(4, pf) * self.value;
    }

    pub fn averageRadiance(self: Emittance, area: f32) Vec4f {
        if (self.quantity == .Intensity) {
            return self.value / @splat(4, area);
        }

        return self.value;
    }
};
