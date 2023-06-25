pub inline fn min(x: f32, y: f32) f32 {
    return if (x < y) x else y;
}

pub inline fn max(x: f32, y: f32) f32 {
    return if (y < x) x else y;
}
