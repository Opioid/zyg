const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const Flags = base.flags.Flags;

pub const Result = struct {
    reflection: Vec4f,

    pub fn init(reflection: Vec4f, p: f32) Result {
        return .{ .reflection = .{ reflection[0], reflection[1], reflection[2], p } };
    }

    pub fn pdf(self: Result) f32 {
        return self.reflection[3];
    }

    pub fn setPdf(self: *Result, p: f32) void {
        self.reflection[3] = p;
    }
};

pub const Type = enum(u32) {
    Reflection = 1 << 0,
    Transmission = 1 << 1,
    Diffuse = 1 << 2,
    Glossy = 1 << 3,
    Specular = 1 << 4,
    Straight = 1 << 5,

    // diffuse_reflection = @enumToInt(.Reflection) | @enumToInt(.Diffuse),
    // Glossy_reflection = .Reflection | .Glossy,
    // Specular_reflection = .Reflection | .Specular,
    // Diffuse_transmission = .Transmission | .Diffuse,
    // Glossy_transmission = .Transmission | .Glossy,
    // Specular_transmission = .Transmission | .Specular,
    // Straight_transmission = .Transmission | .Straight,
};

const TypeFlag = Flags(Type);

pub const Sample = struct {
    reflection: Vec4f = undefined,
    wi: Vec4f = undefined,
    h: Vec4f = undefined, // intermediate result, convenient to store here
    pdf: f32 = undefined,
    h_dot_wi: f32 = undefined, // intermediate result, convenient to store here

    typef: TypeFlag = undefined,
};
