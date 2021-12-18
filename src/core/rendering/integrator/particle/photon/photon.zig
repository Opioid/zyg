const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub const Photon = struct {
    p: Vec4f,
    wi: Vec4f,
    alpha: [3]f32,
    volumetric: bool,
};
