pub const Ray_max_t = 3.4027715434167032e+38;

pub const Units_per_second: u64 = 705600000;

pub fn time(dtime: f64) u64 {
    return @floatToInt(u64, @round(@intToFloat(f64, Units_per_second) * dtime));
}
