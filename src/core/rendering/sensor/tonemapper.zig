const agx = @import("agx.zig");

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const spectrum = base.spectrum;

pub const Tonemapper = struct {
    pub const Class = union(enum) { ACES, AgX: agx.Look, Linear, PbrNeutral };

    class: Class,
    exposure_factor: f32,

    pub fn init(class: Class, exposure: f32) Tonemapper {
        return .{ .class = class, .exposure_factor = @exp2(exposure) };
    }

    pub fn tonemap(self: Tonemapper, color: Vec4f) Vec4f {
        const factor: Vec4f = @splat(self.exposure_factor);
        const scaled = factor * color;

        switch (self.class) {
            .ACES => {
                const rrt = spectrum.AP1toRRT_SAT(scaled);
                const odt = spectrum.RRTandODT(rrt);
                const srgb = spectrum.ODTSATtosRGB(odt);
                return .{ srgb[0], srgb[1], srgb[2], color[3] };
            },
            .AgX => |a| {
                const in = spectrum.AP1tosRGB(scaled);
                const x = agx.agx(in);
                const l = agx.look(x, a);
                const e = math.max4(agx.eotf(l), @splat(0.0));
                return .{ e[0], e[1], e[2], color[3] };
            },
            .Linear => {
                const srgb = spectrum.AP1tosRGB(scaled);
                return .{ srgb[0], srgb[1], srgb[2], color[3] };
            },
            .PbrNeutral => {
                const srgb = spectrum.AP1tosRGB(scaled);
                const pbr = pbrNeutral(srgb);
                return .{ pbr[0], pbr[1], pbr[2], color[3] };
            },
        }
    }
};

// Input color is non-negative and resides in the Linear Rec. 709 color space.
// Output color is also Linear Rec. 709, but in the [0, 1] range.

fn pbrNeutral(in: Vec4f) Vec4f {
    const start_compression: f32 = 0.8 - 0.04;
    const desaturation: f32 = 0.15;

    const x = math.hmin3(in);
    const offset = if (x < 0.08) x - 6.25 * x * x else 0.04;
    var color = in - @as(Vec4f, @splat(offset));

    const peak = math.hmax3(color);
    if (peak < start_compression) {
        return color;
    }

    const d = 1.0 - start_compression;
    const new_peak = 1.0 - d * d / (peak + d - start_compression);
    color *= @splat(new_peak / peak);

    const g = 1.0 - 1.0 / (desaturation * (peak - new_peak) + 1.0);
    return math.lerp(color, @as(Vec4f, @splat(new_peak)), @as(Vec4f, @splat(g)));
}
