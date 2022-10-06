const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub const Result = struct {
    reflection: Vec4f,

    pub fn init(reflection: Vec4f, p: f32) Result {
        return .{ .reflection = .{ reflection[0], reflection[1], reflection[2], p } };
    }

    pub fn empty() Result {
        return .{ .reflection = @splat(4, @as(f32, 0.0)) };
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

    pub fn blend(self: *Result, other: Vec4f, w: f32) void {
        const r = self.reflection;
        const n = math.lerp4(r, other, w);
        self.reflection = .{ n[0], n[1], n[2], r[3] };
    }
};

pub const Class = packed struct {
    reflection: bool = false,
    transmission: bool = false,
    diffuse: bool = false,
    glossy: bool = false,
    specular: bool = false,
    straight: bool = false,
};

pub const Sample = struct {
    pub const StraightTransmission = Class{ .transmission = true, .straight = true };

    reflection: Vec4f = undefined,
    wi: Vec4f = undefined,
    h: Vec4f = undefined, // intermediate result, convenient to store here
    pdf: f32 = 0.0,
    wavelength: f32 = undefined,
    h_dot_wi: f32 = undefined, // intermediate result, convenient to store here
    class: Class = undefined,

    pub fn blend(self: *Sample, other: Vec4f, w: f32) void {
        self.reflection = math.lerp4(self.reflection, other, w);
    }
};
