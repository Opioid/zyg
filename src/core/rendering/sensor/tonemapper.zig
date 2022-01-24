const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const spectrum = base.spectrum;

const std = @import("std");

pub const Tonemapper = struct {
    pub const Type = enum {
        ACES,
        Linear,
    };

    typef: Type,
    exposure_factor: f32,

    pub fn init(typef: Type, exposure: f32) Tonemapper {
        return .{ .typef = typef, .exposure_factor = std.math.exp2(exposure) };
    }

    pub fn tonemap(self: Tonemapper, color: Vec4f) Vec4f {
        const factor = self.exposure_factor;
        const scaled = @splat(4, factor) * color;

        switch (self.typef) {
            .ACES => {
                const rrt = spectrum.AP1toRRT_SAT(scaled);
                const odt = spectrum.RRTandODT(rrt);
                const srgb = spectrum.ODTSATtosRGB(odt);
                return .{ srgb[0], srgb[1], srgb[2], color[3] };
            },
            .Linear => {
                const srgb = spectrum.AP1tosRGB(scaled);
                return .{ srgb[0], srgb[1], srgb[2], color[3] };
            },
        }
    }
};
