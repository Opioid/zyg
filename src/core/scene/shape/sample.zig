const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const To = struct {
    wi: Vec4f,
    n: Vec4f,
    uvw: Vec4f,

    pub fn init(wi: Vec4f, n: Vec4f, uvw: Vec4f, pdf_: f32, t_: f32) To {
        return .{
            .wi = .{ wi[0], wi[1], wi[2], pdf_ },
            .n = .{ n[0], n[1], n[2], t_ },
            .uvw = uvw,
        };
    }

    pub fn pdf(self: To) f32 {
        return self.wi[3];
    }

    pub fn mulAssignPdf(self: *To, s: f32) void {
        self.wi[3] *= s;
    }

    pub fn t(self: To) f32 {
        return self.n[3];
    }
};

pub const From = struct {
    p: Vec4f,
    n: Vec4f,
    dir: Vec4f,
    uv: Vec2f,
    xy: Vec2f,

    pub fn init(p: Vec4f, n: Vec4f, dir: Vec4f, uv: Vec2f, xy: Vec2f, pdf_: f32) From {
        return .{
            .p = .{ p[0], p[1], p[2], pdf_ },
            .n = n,
            .dir = dir,
            .uv = uv,
            .xy = xy,
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
