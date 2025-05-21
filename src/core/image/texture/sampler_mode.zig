const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

pub const Mode = packed struct {
    pub const Filter = enum(u1) {
        Nearest,
        LinearStochastic,
    };

    pub const TexCoord = enum(u2) {
        UV0,
        Triplanar,
        ObjectPos,
    };

    pub const Address = enum(u1) {
        Clamp,
        Repeat,

        pub fn f(m: Address, x: f32) f32 {
            return switch (m) {
                .Clamp => math.clamp(x, 0.0, 1.0),
                .Repeat => math.frac(x),
            };
        }

        pub fn f3(m: Address, x: Vec4f) Vec4f {
            return switch (m) {
                .Clamp => math.clamp4(x, 0.0, 1.0),
                .Repeat => math.frac(x),
            };
        }

        pub fn coord(m: Address, c: i32, end: i32) i32 {
            return switch (m) {
                .Clamp => Clamp.coord(c, end),
                .Repeat => @mod(c, end),
            };
        }

        pub fn coord3(m: Address, c: Vec4i, end: Vec4i) Vec4i {
            return switch (m) {
                .Clamp => Clamp.coord3(c, end),
                .Repeat => @mod(c, end),
            };
        }
    };

    uv_set: TexCoord,
    u: Address,
    v: Address,
    filter: Filter,

    const Self = @This();

    pub fn address2(self: Self, uv: Vec2f) Vec2f {
        return .{ self.u.f(uv[0]), self.v.f(uv[1]) };
    }

    pub fn address3(self: Self, uvw: Vec4f) Vec4f {
        return self.u.f3(uvw);
    }

    pub fn coord2(self: Self, c: Vec2i, end: Vec2i) Vec2i {
        return .{ self.u.coord(c[0], end[0]), self.v.coord(c[1], end[1]) };
    }
};

const Clamp = struct {
    pub fn coord(c: i32, end: i32) i32 {
        const max = end - 1;
        return @max(@min(c, max), 0);
    }

    pub fn coord3(c: Vec4i, end: Vec4i) Vec4i {
        const max = end - Vec4i{ 1, 1, 1, 0 };
        return @max(@min(c, max), @as(Vec4i, @splat(0)));
    }
};
