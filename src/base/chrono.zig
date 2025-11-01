const std = @import("std");
const Io = std.Io;

pub fn now(io: Io) Io.Timestamp {
    return std.Io.Clock.now(.real, io) catch .zero;
}

pub fn secondsSince(io: Io, timestamp: Io.Timestamp) f32 {
    return @as(f32, @floatFromInt(timestamp.durationTo(now(io)).toMilliseconds())) / 1000.0;
}
