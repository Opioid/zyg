const Base = @import("../sample_base.zig").Base;
const bxdf = @import("../bxdf.zig");

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub const Sample = struct {
    super: Base,

    pub fn init(wo: Vec4f, geo_n: Vec4f, n: Vec4f, factor: f32, alpha: f32) Sample {
        return .{ .super = Base.initN(wo, geo_n, n, factor, alpha) };
    }

    pub fn sample(self: *const Sample) bxdf.Sample {
        return .{
            .reflection = self.super.albedo,
            .wi = -self.super.wo,
            .pdf = 1.0,
            .split_weight = 1.0,
            .wavelength = 0.0,
            .class = .{ .straight = true, .transmission = true },
        };
    }
};
