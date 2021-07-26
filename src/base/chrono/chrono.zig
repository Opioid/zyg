const std = @import("std");

pub fn secondsSince(time_point: i64) f32 {
    return @intToFloat(f32, std.time.milliTimestamp() - time_point) / 1000.0;
}
