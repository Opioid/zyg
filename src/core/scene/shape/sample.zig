const Trafo = @import("../composed_transformation.zig").ComposedTransformation;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const To = struct {
    p: Vec4f,
    n: Vec4f,
    wi: Vec4f,
    uvw: Vec4f,

    pub fn init(p: Vec4f, n: Vec4f, wi: Vec4f, uvw: Vec4f, pdf_: f32) To {
        return .{
            .p = .{ p[0], p[1], p[2], pdf_ },
            .n = n,
            .wi = wi,
            .uvw = uvw,
        };
    }

    pub fn pdf(self: To) f32 {
        return self.p[3];
    }

    pub fn mulAssignPdf(self: *To, s: f32) void {
        self.p[3] *= s;
    }
};

pub const From = struct {
    p: Vec4f,
    n: Vec4f,
    dir: Vec4f,
    uvw: Vec4f,
    xy: Vec2f,
    trafo: Trafo,

    pub fn init(p: Vec4f, n: Vec4f, dir: Vec4f, uvw: Vec4f, xy: Vec2f, trafo: Trafo, pdf_: f32) From {
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
