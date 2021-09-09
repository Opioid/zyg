const Base = @import("tonemapper_base.zig").Base;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const spectrum = base.spectrum;
const ThreadContext = base.thread.Pool.Context;

// https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl

pub const ACES = struct {
    super: Base,

    pub fn init(exposure: f32) ACES {
        return .{ .super = Base.init(exposure) };
    }

    pub fn applyRange(context: ThreadContext, id: u32, begin: u32, end: u32) void {
        _ = id;

        const self = @intToPtr(*ACES, context);

        const factor = self.super.exposure_factor;

        for (self.super.source.pixels[begin..end]) |p, i| {
            const scaled = p.mulScalar3(factor);

            const rrt = spectrum.AP1toRRT_SAT(scaled);
            const odt = spectrum.RRTandODT(rrt);
            const srgb = spectrum.ODTSATtosRGB(odt);

            const j = begin + i;
            self.super.destination.pixels[j] = Vec4f.init3_1(srgb, p.v[3]);
        }
    }
};
