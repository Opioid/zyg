const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub const Schlick = struct {
    f0: Vec4f,

    pub fn init(f0: Vec4f) Schlick {
        return .{ .f0 = f0 };
    }

    pub fn f(self: Schlick, wo_dot_h: f32) Vec4f {
        return self.f0 + @splat(4, math.pow5(1.0 - wo_dot_h)) * (@splat(4, @as(f32, 1.0)) - self.f0);
    }

    pub fn F0(n0: f32, n1: f32) f32 {
        const t = (n0 - n1) / (n0 + n1);
        return t * t;
    }
};
