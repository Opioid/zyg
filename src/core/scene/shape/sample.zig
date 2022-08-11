const Trafo = @import("../composed_transformation.zig").ComposedTransformation;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const To = struct {
    wi: Vec4f,
    n: Vec4f,
    uvw: Vec4f,
    trafo: Trafo,

    pub fn init(wi: Vec4f, n: Vec4f, uvw: Vec4f, trafo: Trafo, pdf_: f32, off: f32) To {
        return .{
            .wi = .{ wi[0], wi[1], wi[2], pdf_ },
            .n = .{ n[0], n[1], n[2], off },
            .uvw = uvw,
            .trafo = trafo,
        };
    }

    pub fn pdf(self: To) f32 {
        return self.wi[3];
    }

    pub fn mulAssignPdf(self: *To, s: f32) void {
        self.wi[3] *= s;
    }

    pub fn offset(self: To) f32 {
        return self.n[3];
    }
};

pub const From = struct {
    p: Vec4f,
    n: Vec4f,
    dir: Vec4f,
    uvw: Vec4f,
    xy: Vec2f,
    trafo: Trafo,

    pub fn init(p: Vec4f, dir: Vec4f, n: Vec4f, uvw: Vec4f, xy: Vec2f, trafo: Trafo, pdf_: f32) From {
        return .{
            .p = .{ p[0], p[1], p[2], pdf_ },
            .n = n,
            .dir = dir,
            .uvw = uvw,
            .xy = xy,
            .trafo = trafo,
        };
    }

    pub fn pdf(self: From) f32 {
        return self.p[3];
    }

    pub fn mulAssignPdf(self: *From, s: f32) void {
        self.p[3] *= s;
    }
};

pub const DifferentialSurface = struct {
    dpdu: Vec4f,
    dpdv: Vec4f,
};
