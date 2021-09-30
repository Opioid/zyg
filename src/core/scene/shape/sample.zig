const math = @import("base").math;
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
