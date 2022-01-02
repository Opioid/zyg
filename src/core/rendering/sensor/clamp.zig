const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub const Clamp = union(enum) {
    Identity,
    Max: Max,
    Luminance: Luminance,

    pub fn clamp(self: Clamp, color: Vec4f) Vec4f {
        return switch (self) {
            .Identity => color,
            .Max => |m| m.clamp(color),
            .Luminance => |l| l.clamp(color),
        };
    }
};

const Max = struct {
    max: Vec4f,

    pub fn clamp(self: Max, color: Vec4f) Vec4f {
        return @minimum(color, self.max);
    }
};

const Luminance = struct {
    max: f32,

    pub fn clamp(self: Luminance, color: Vec4f) Vec4f {
        const mc = math.maxComponent3(color);

        if (mc > self.max) {
            const r = self.max / mc;
            const s = @splat(4, r) * color;
            return .{ s[0], s[1], s[2], color[3] };
        }

        return color;
    }
};
