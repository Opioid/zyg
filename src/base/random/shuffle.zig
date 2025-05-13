const RNG = @import("generator.zig").Generator;

const std = @import("std");

// Divisionless optimization with slight bias from
// https://lemire.me/blog/2016/06/30/fast-random-shuffling/
// (Upper variant has bias as well!)
// More related information:
// http://www.pcg-random.org/posts/bounded-rands.html

pub fn biasedShuffle(comptime T: type, data: []T, rng: *RNG) void {
    var i: u64 = @intCast(data.len - 1);
    while (i > 0) : (i -= 1) {
        const r: u64 = @intCast(rng.randomUint());
        const m = r * (i + 1);
        const o = m >> 32;

        std.mem.swap(T, &data[i], &data[o]);
    }
}
