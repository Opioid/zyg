pub fn floatToUnorm(x: f32) u8 {
    return @floatToInt(u8, x * 255.0 + 0.5);
}
