pub const Vec2b = @Vector(2, u8);
pub const Vec2i = @Vector(2, i32);
pub const Vec2u = @Vector(2, u32);
pub const Vec2f = @Vector(2, f32);
pub const Vec2ul = @Vector(2, u64);

pub inline fn dot2(a: Vec2f, b: Vec2f) f32 {
    return a[0] * b[0] + a[1] * b[1];
}

pub inline fn length2(v: Vec2f) f32 {
    return @sqrt(dot2(v, v));
}

pub inline fn normalize2(v: Vec2f) Vec2f {
    const i = 1.0 / length2(v);
    return @splat(2, i) * v;
}

pub inline fn vec2fTo2i(v: Vec2f) Vec2i {
    return .{ @floatToInt(i32, v[0]), @floatToInt(i32, v[1]) };
}

pub inline fn vec2fTo2u(v: Vec2f) Vec2u {
    return .{ @floatToInt(u32, v[0]), @floatToInt(u32, v[1]) };
}

pub inline fn vec2iTo2f(v: Vec2i) Vec2f {
    return .{ @intToFloat(f32, v[0]), @intToFloat(f32, v[1]) };
}

pub inline fn vec2uTo2f(v: Vec2u) Vec2f {
    return .{ @intToFloat(f32, v[0]), @intToFloat(f32, v[1]) };
}
