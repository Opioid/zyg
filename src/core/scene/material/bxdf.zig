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

    pub fn mulAssignPdf(self: *Result, p: f32) void {
        self.reflection[3] *= p;
    }
};

const Reflection = 1 << 0;
const Transmission = 1 << 1;
const Diffuse = 1 << 2;
const Glossy = 1 << 3;
const Specular = 1 << 4;
const Straight = 1 << 5;

pub const Type = enum(u32) {
    Reflection = Reflection,
    Transmission = Transmission,
    Diffuse = Diffuse,
    Glossy = Glossy,
    Specular = Specular,
    Straight = Straight,

    DiffuseReflection = Reflection | Diffuse,
    GlossyReflection = Reflection | Glossy,
    SpecularReflection = Reflection | Specular,
    DiffuseTransmission = Transmission | Diffuse,
    GlossyTransmission = Transmission | Glossy,
    SpecularTransmission = Transmission | Specular,
    StraightTransmission = Transmission | Straight,
};

pub const TypeFlag = Flags(Type);

pub const Sample = struct {
    reflection: Vec4f = undefined,
    wi: Vec4f = undefined,
    h: Vec4f = undefined, // intermediate result, convenient to store here
    pdf: f32 = 0.0,
    h_dot_wi: f32 = undefined, // intermediate result, convenient to store here
    typef: TypeFlag = undefined,
};
