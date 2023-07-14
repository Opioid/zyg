const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const spectrum = base.spectrum;

pub const Tonemapper = struct {
    pub const Class = enum {
        ACES,
        Linear,
    };

    class: Class,
    exposure_factor: f32,

    pub fn init(class: Class, exposure: f32) Tonemapper {
        return .{ .class = class, .exposure_factor = @exp2(exposure) };
    }

    pub fn tonemap(self: Tonemapper, color: Vec4f) Vec4f {
        const factor = self.exposure_factor;
        const scaled = @as(Vec4f, @splat(factor)) * color;

        switch (self.class) {
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
