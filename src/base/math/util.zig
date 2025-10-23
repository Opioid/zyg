const builtin = @import("builtin");

pub inline fn lerp(a: anytype, b: anytype, t: anytype) @TypeOf(a, b, t) {
    switch (@typeInfo(@TypeOf(a))) {
        inline .comptime_float, .float => {
            const u = 1.0 - t;
            return @mulAdd(f32, u, a, t * b);
        },
        .vector => {
            const u = @as(@TypeOf(a), @splat(1.0)) - t;
            return @mulAdd(@TypeOf(a), u, a, t * b);
        },
        else => comptime unreachable,
    }
}

pub inline fn min(x: f32, y: f32) f32 {
    return switch (builtin.target.cpu.arch) {
        .aarch64, .aarch64_be => @min(x, y),
        inline else => if (x < y) x else y,
    };
}

pub inline fn max(x: f32, y: f32) f32 {
    return switch (builtin.target.cpu.arch) {
        .aarch64, .aarch64_be => @max(x, y),
        inline else => if (y < x) x else y,
    };
}

pub inline fn clamp(x: f32, mi: f32, ma: f32) f32 {
    return min(max(x, mi), ma);
}
