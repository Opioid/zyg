pub fn floatToUnorm8(x: f32) u8 {
    return @intFromFloat(u8, x * 255.0 + 0.5);
}

pub fn unorm8ToFloat(norm: u8) f32 {
    return @floatFromInt(f32, norm) * (1.0 / 255.0);
}

pub fn floatToSnorm8(x: f32) u8 {
    return @intFromFloat(u8, (x + 1.0) * (if (x > 0.0) @as(f32, 127.5) else @as(f32, 128.0)));
}

pub fn snorm8ToFloat(byte: u8) f32 {
    return @floatFromInt(f32, byte) * (1.0 / 128.0) - 1.0;
}

pub fn floatToUnorm16(x: f32) u16 {
    return @intFromFloat(u16, x * 65535.0 + 0.5);
}

pub fn unorm16ToFloat(norm: u16) f32 {
    return @floatFromInt(f32, norm) * (1.0 / 65535.0);
}

pub fn floatToSnorm16(x: f32) u16 {
    return @intFromFloat(u16, (x + 1.0) * (if (x > 0.0) @as(f32, 32767.5) else @as(f32, 32768.0)));
}

pub fn snorm16ToFloat(norm: u16) f32 {
    return @floatFromInt(f32, norm) * (1.0 / 32768.0) - 1.0;
}
