const base = @import("base");
const enc = base.encoding;
const math = base.math;
const Vec2us = math.Vec2us;
const Vec4f = math.Vec4f;

pub const Photon = struct {
    data: [6]f32,
    oct: Vec2us,
    volumetric: bool,

    pub fn init(pos: Vec4f, wi_: Vec4f, radiance: Vec4f, volumetric: bool) Photon {
        return .{
            .data = .{ pos[0], pos[1], pos[2], radiance[0], radiance[1], radiance[2] },
            .oct = enc.floatToSnorm16(enc.octEncode(wi_)),
            .volumetric = volumetric,
        };
    }

    pub inline fn position(self: Photon) Vec4f {
        return self.data[0..4].*;
    }

    pub inline fn wi(self: Photon) Vec4f {
        return enc.octDecode(enc.snorm16ToFloat(self.oct));
    }

    pub inline fn alpha(self: Photon) Vec4f {
        return .{ self.data[3], self.data[4], self.data[5], 0.0 };
    }

    pub fn marked(self: Photon) bool {
        return self.data[3] < 0.0;
    }

    pub fn mark(self: *Photon) void {
        self.data[3] = -1.0;
    }
};
