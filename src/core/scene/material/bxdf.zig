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

    pub const Scattering = enum(u8) {
        Diffuse,
        Glossy,
        Specular,
        None,
    };

    pub const Event = enum(u8) {
        Reflection,
        Transmission,
        Straight,
    };

    pub const Path = packed struct {
        scattering: Scattering,
        event: Event,
    };

    reflection: Vec4f,
    wi: Vec4f,
    pdf: f32,
    split_weight: f32,
    wavelength: f32,
    path: Path,
};

pub const Samples = [4]Sample;
