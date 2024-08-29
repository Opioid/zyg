const math = @import("math/vector4.zig");
const Vec4us = math.Vec4us;
const Vec4f = math.Vec4f;

pub fn floatToUnorm8(x: f32) u8 {
    return @intFromFloat(x * 255.0 + 0.5);
}

pub fn unorm8ToFloat(norm: u8) f32 {
    return @as(f32, @floatFromInt(norm)) * (1.0 / 255.0);
}

pub fn floatToSnorm8(x: f32) u8 {
    return @intFromFloat((x + 1.0) * (if (x > 0.0) @as(f32, 127.5) else @as(f32, 128.0)));
}

pub fn snorm8ToFloat(byte: u8) f32 {
    return @as(f32, @floatFromInt(byte)) * (1.0 / 128.0) - 1.0;
}

pub fn floatToUnorm16(x: f32) u16 {
    return @intFromFloat(x * 65535.0 + 0.5);
}

pub fn floatToUnorm16_4(x: Vec4f) Vec4us {
    return @intFromFloat(x * @as(Vec4f, @splat(65535.0)) + @as(Vec4f, @splat(0.5)));
}

pub fn unorm16ToFloat(norm: u16) f32 {
    return @as(f32, @floatFromInt(norm)) * (1.0 / 65535.0);
}

pub fn unorm16ToFloat4(norm: Vec4us) Vec4f {
    return @as(Vec4f, @floatFromInt(norm)) * @as(Vec4f, @splat(1.0 / 65535.0));
}

pub fn floatToSnorm16(x: f32) u16 {
    return @intFromFloat((x + 1.0) * (if (x > 0.0) @as(f32, 32767.5) else @as(f32, 32768.0)));
}

pub fn snorm16ToFloat(norm: u16) f32 {
    return @as(f32, @floatFromInt(norm)) * (1.0 / 32768.0) - 1.0;
}

pub fn snorm16ToFloat4(norm: Vec4us) Vec4f {
    return @as(Vec4f, @floatFromInt(norm)) * @as(Vec4f, @splat(1.0 / 32768.0)) - @as(Vec4f, @splat(1.0));
}
