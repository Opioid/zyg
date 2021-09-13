pub fn floatToUnorm(x: f32) u8 {
    return @floatToInt(u8, x * 255.0 + 0.5);
}

pub fn unormToFloat(byte: u8) f32 {
    return @intToFloat(f32, byte) * (1.0 / 255.0);
}

pub fn snormToFloat(byte: u8) f32 {
    return @intToFloat(f32, byte) * (1.0 / 128.0) - 1.0;
}
