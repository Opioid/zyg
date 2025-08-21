const base = @import("base");
const enc = base.encoding;
const math = base.math;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;

pub const Photon = struct {
    data: [6]f32,
    oct: [2]u16,
    volumetric: bool,

    pub fn init(pos: Vec4f, wi_: Vec4f, radiance: Vec4f, volumetric: bool) Photon {
        return .{
            .data = .{ pos[0], pos[1], pos[2], radiance[0], radiance[1], radiance[2] },
            .oct = enc.floatToSnorm16_2(math.smpl.octEncode(wi_)),
            .volumetric = volumetric,
        };
    }

    pub inline fn position(self: Photon) Vec4f {
        return self.data[0..4].*;
    }

    pub inline fn wi(self: Photon) Vec4f {
        return math.smpl.octDecode(enc.snorm16ToFloat2(self.oct));
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
