const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub const Result = struct {
    reflection: Vec4f,
    pdf: f32,

    pub fn init(reflection: Vec4f, pdf: f32) Result {
        return .{ .reflection = reflection, .pdf = pdf };
    }

    pub fn empty() Result {
        return .{ .reflection = @splat(0.0), .pdf = 0.0 };
    }
};

pub const Sample = struct {
    pub const Class = packed struct {
        reflection: bool = false,
        transmission: bool = false,
        diffuse: bool = false,
        glossy: bool = false,
        specular: bool = false,
        straight: bool = false,
    };

    reflection: Vec4f,
    wi: Vec4f,
    pdf: f32,
    split_weight: f32,
    wavelength: f32,
    class: Class,
};

pub const Samples = [2]Sample;
