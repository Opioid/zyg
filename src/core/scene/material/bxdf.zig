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

    pub const Path = struct {
        reg_alpha: f32,
        scattering: Scattering,
        event: Event,

        pub const straight: Path = .{ .reg_alpha = 1.0, .scattering = .None, .event = .Straight };
        pub const singularReflection: Path = .{ .reg_alpha = 0.0, .scattering = .Specular, .event = .Reflection };
        pub const singularTransmission: Path = .{ .reg_alpha = 0.0, .scattering = .Specular, .event = .Transmission };
        pub const diffuseReflection: Path = .{ .reg_alpha = 1.0, .scattering = .Diffuse, .event = .Reflection };

        pub fn reflection(alpha: f32, specular_threshold: f32) Path {
            return .{
                .reg_alpha = alpha,
                .scattering = if (alpha <= specular_threshold) .Specular else .Glossy,
                .event = .Reflection,
            };
        }

        pub fn transmission(alpha: f32, specular_threshold: f32) Path {
            return .{
                .reg_alpha = alpha,
                .scattering = if (alpha <= specular_threshold) .Specular else .Glossy,
                .event = .Transmission,
            };
        }

        pub fn singular(self: Path) bool {
            return 0.0 == self.reg_alpha;
        }
    };

    reflection: Vec4f,
    wi: Vec4f,
    pdf: f32,
    split_weight: f32,
    wavelength: f32,
    path: Path,
};

pub const Samples = [4]Sample;
