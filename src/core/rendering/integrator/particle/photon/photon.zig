const base = @import("base");
const math = base.math;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;

pub const Photon = struct {
    data: [9]f32,
    volumetric: bool,

    pub fn init(pos: Vec4f, wi_: Vec4f, radiance: Vec4f, volumetric: bool) Photon {
        return .{
            .data = .{ pos[0], pos[1], pos[2], wi_[0], wi_[1], wi_[2], radiance[0], radiance[1], radiance[2] },
            .volumetric = volumetric,
        };
    }

    pub inline fn position(self: Photon) Vec4f {
        return self.data[0..4].*;
    }

    pub inline fn wi(self: Photon) Vec4f {
        return self.data[3..7].*;
    }

    pub inline fn alpha(self: Photon) Vec4f {
        return .{ self.data[6], self.data[7], self.data[8], 0.0 };

        // return @as([*]const f32, @ptrCast(&self.data[6]))[0..4].*;
    }

    pub fn marked(self: Photon) bool {
        return self.data[6] < 0.0;
    }

    pub fn mark(self: *Photon) void {
        self.data[6] = -1.0;
    }
};
