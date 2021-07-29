const RNG = @import("generator.zig").Generator;

const std = @import("std");

pub fn biasedShuffle(comptime T: type, data: []T, rng: *RNG) void {
    var i = @intCast(u64, data.len - 1);
    while (i > 0) : (i -= 1) {
        const r = @intCast(u64, rng.randomUint());
        const m = r * (i + 1);
        const o = m >> 32;

        std.mem.swap(T, &data[i], &data[o]);
    }
}
