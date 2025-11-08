const math = @import("vector4.zig");
const Vec4f = math.Vec4f;
const safe = @import("safe.zig");

pub const Frame = struct {
    x: Vec4f,
    y: Vec4f,
    z: Vec4f,

    pub fn init(n: Vec4f) Frame {
        const tb = math.orthonormalBasis3(n);
        return .{ .x = tb[0], .y = tb[1], .z = n };
    }

    pub fn swapped(self: Frame, same_side: bool) Frame {
        if (same_side) {
            return self;
        }

        return .{ .x = self.x, .y = self.y, .z = -self.z };
    }

    pub fn frameToWorld(self: Frame, v: Vec4f) Vec4f {
        // return .{
        //     v[0] * self.t[0] + v[1] * self.b[0] + v[2] * self.n[0],
        //     v[0] * self.t[1] + v[1] * self.b[1] + v[2] * self.n[1],
        //     v[0] * self.t[2] + v[1] * self.b[2] + v[2] * self.n[2],
        //     0.0,
        // };

        var result: Vec4f = @splat(v[0]); // @shuffle(f32, v, v, [4]i32{ 0, 0, 0, 0 });
        result = result * self.x;
        var temp: Vec4f = @splat(v[1]); // @shuffle(f32, v, v, [4]i32{ 1, 1, 1, 1 });
        result = @mulAdd(Vec4f, temp, self.y, result);
        temp = @splat(v[2]); // @shuffle(f32, v, v, [4]i32{ 2, 2, 2, 2 });
        return @mulAdd(Vec4f, temp, self.z, result);
    }

    pub fn worldToFrame(self: Frame, v: Vec4f) Vec4f {
        const t = v * self.x;
        const b = v * self.y;
        const n = v * self.z;

        return .{
            t[0] + t[1] + t[2],
            b[0] + b[1] + b[2],
            n[0] + n[1] + n[2],
            0.0,
        };
    }

    pub fn nDot(self: Frame, v: Vec4f) f32 {
        return math.dot3(self.z, v);
    }

    pub fn clampNdot(self: Frame, v: Vec4f) f32 {
        return safe.clampDot(self.z, v);
    }

    pub fn clampAbsNdot(self: Frame, v: Vec4f) f32 {
        return safe.clampAbsDot(self.z, v);
    }

    pub fn rotateTangenFrame(self: *Frame, a: f32) void {
        const t = self.x;
        const b = self.y;

        const sin_a: Vec4f = @splat(@sin(a));
        const cos_a: Vec4f = @splat(@cos(a));

        self.x = cos_a * t + sin_a * b;
        self.y = -sin_a * t + cos_a * b;
    }
};
