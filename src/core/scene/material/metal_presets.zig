const math = @import("base").math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub fn iorAndAbsorption(name: []const u8) [2]Vec4f {
    if (std.mem.eql(u8, "Aluminium", name)) {
        return .{
            .{ 1.50694, 0.926041, 0.68251, 0.0 },
            .{ 7.6307, 6.3849, 5.6230, 0.0 },
        };
    }

    if (std.mem.eql(u8, "Gold", name)) {
        return .{
            .{ 0.18267, 0.49447, 1.3761, 0.0 },
            .{ 3.1178, 2.3515, 1.8324, 0.0 },
        };
    }

    if (std.mem.eql(u8, "Silver", name)) {
        return .{
            .{ 0.13708, 0.12945, 0.14075, 0.0 },
            .{ 4.0625, 3.1692, 2.6034, 0.0 },
        };
    }

    return .{
        .{ 1.5, 1.5, 1.5, 0.0 },
        .{ 1.0, 1.0, 1.0, 0.0 },
    };
}
