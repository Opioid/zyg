const agx = @import("agx.zig");

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const spectrum = base.spectrum;

pub const Tonemapper = struct {
    pub const Class = union(enum) {
        ACES,
        AgX: agx.Look,
        Linear,
    };

    class: Class,
    exposure_factor: f32,
    white_point: f32,

    pub fn init(class: Class, exposure: f32) Tonemapper {
        return .{ .class = class, .exposure_factor = @exp2(exposure), .white_point = 12.0 };
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
        }
    }
};
