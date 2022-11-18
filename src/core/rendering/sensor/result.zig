const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub const Result = struct {
    last: Vec4f,
    mean: Vec4f,
};
