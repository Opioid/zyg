const base = @import("base");
const math = base.math;
const Vec2u = math.Vec2u;
const Vec2f = math.Vec2f;
const Vec4u = math.Vec4u;
const Vec4f = math.Vec4f;

pub const Sobol = struct {
    buffer: [5]f32,

    sample: u32,
    dimension: u32,
    start_seed: u32,
    run_seed: u32,

    const Self = @This();

    pub fn startPixel(self: *Self, sample: u32, seed: u32) void {
        self.sample = sample;
        self.dimension = 5;
        const hashed = hash(seed);
        self.start_seed = hashed;
        self.run_seed = hashed;
    }

    pub fn incrementSample(self: *Self) void {
        self.sample +%= 1;
        self.dimension = 5;
        self.run_seed = self.start_seed;
    }

    pub fn incrementPadding(self: *Self) void {
        self.dimension = 5;
    }

    fn incrementSeed(self: *Self) void {
        const S: f32 = 1.0 / @as(f32, @floatFromInt(1 << 32));

        const s = self.run_seed;
        const i = nestedUniformScrambleBase2(self.sample, s);

        const sob = sobol5(i);

        {
            const hc = hashCombine4(s, 0);
            const nus = nestedUniformScrambleBase2(@as(Vec4u, sob[0..4].*), hc);

            self.buffer[0..4].* = @as(Vec4f, @floatFromInt(nus)) * @as(Vec4f, @splat(S));
        }

        {
            const hc = hashCombine(s, 4);
            const nus = nestedUniformScrambleBase2(sob[4], hc);

            self.buffer[4] = @as(f32, @floatFromInt(nus)) * S;
        }

        self.run_seed = hash(s +% 1);
        self.dimension = 0;
    }

    pub fn sample1D(self: *Self) f32 {
        if (self.dimension >= 5) {
            self.incrementSeed();
        }

        const d = self.dimension;
        self.dimension = d + 1;

        return self.buffer[d];
    }

    pub fn sample2D(self: *Self) Vec2f {
        if (self.dimension >= 4) {
            self.incrementSeed();
        }

        const d = self.dimension;
        self.dimension = d + 2;

        return .{ self.buffer[d], self.buffer[d + 1] };
    }

    pub fn sample3D(self: *Self) Vec4f {
        if (self.dimension >= 3) {
            self.incrementSeed();
        }

        const d = self.dimension;
        self.dimension = d + 3;

        return .{ self.buffer[d], self.buffer[d + 1], self.buffer[d + 2], 0 };
    }

    pub fn sample4D(self: *Self) Vec4f {
        if (self.dimension >= 2) {
            self.incrementSeed();
        }

        const d = self.dimension;
        self.dimension = d + 4;

        return .{ self.buffer[d], self.buffer[d + 1], self.buffer[d + 2], self.buffer[d + 3] };
    }
};

fn hash(i: u32) u32 {
    // finalizer from murmurhash3
    // var x = i ^ (i >> 16);
    // x *%= 0x85ebca6b;
    // x ^= x >> 13;
    // x *%= 0xc2b2ae35;
    // x ^= x >> 16;
    // return x;

    // https://github.com/skeeto/hash-prospector

    var x = i ^ (i >> 16);
    x *%= 0x7feb352d;
    x ^= x >> 15;
    x *%= 0x846ca68b;
    x ^= x >> 16;
    return x;
}

fn hashCombine(seed: u32, v: comptime_int) u32 {
    return seed ^ (v +% (seed << 6) +% (seed >> 2));
}

fn hashCombine4(seed: u32, v: comptime_int) Vec4u {
    const seed4: Vec4u = @splat(seed);
    const v4 = @as(Vec4u, @splat(v)) + Vec4u{ 0, 1, 2, 3 };
    return seed4 ^ (v4 +% (seed4 << @as(@Vector(4, u5), @splat(6))) +% (seed4 >> @as(@Vector(4, u5), @splat(2))));
}

fn nestedUniformScrambleBase2(x: anytype, seed: anytype) @TypeOf(x, seed) {
    var o = @bitReverse(x);
    o = laineKarrasPermutation(o, seed);
    return @bitReverse(o);
}

fn laineKarrasPermutation(i: anytype, seed: anytype) @TypeOf(i, seed) {
    // var x = i +% seed;
    // x ^= x *% 0x6c50b47c;
    // x ^= x *% 0xb82f1e52;
    // x ^= x *% 0xc7afe638;
    // x ^= x *% 0x8d22f6e6;
    // return x;

    // https://psychopath.io/post/2021_01_30_building_a_better_lk_hash

    switch (@typeInfo(@TypeOf(i))) {
        .int => {
            var x = i ^ (i *% 0x3d20adea);
            x +%= seed;
            x *%= (seed >> 16) | 1;
            x ^= x *% 0x05526c56;
            x ^= x *% 0x53a22864;
            return x;
        },
        .vector => |v| {
            const V = @TypeOf(i);

            var x = i ^ (i *% @as(V, @splat(@as(u32, 0x3d20adea))));
            x +%= seed;
            x *%= (seed >> @as(@Vector(v.len, u5), @splat(16))) | @as(V, @splat(1));
            x ^= x *% @as(V, @splat(0x05526c56));
            x ^= x *% @as(V, @splat(0x53a22864));
            return x;
        },

        else => comptime unreachable,
    }
}

fn sobol5(index: u32) [5]u32 {
    var x0: u32 = 0;
    var x1: u32 = 0;
    var x2: u32 = 0;
    var x3: u32 = 0;
    var x4: u32 = 0;
    var bit: u32 = 0;
    while (bit < 32) : (bit += 1) {
        const mask = (index >> @as(u5, @truncate(bit))) & 1;
        x0 ^= mask * Directions[0][bit];
        x1 ^= mask * Directions[1][bit];
        x2 ^= mask * Directions[2][bit];
        x3 ^= mask * Directions[3][bit];
        x4 ^= mask * Directions[4][bit];
    }
    return .{ x0, x1, x2, x3, x4 };
}

const Directions = [5][32]u32{
    .{
        0x80000000, 0x40000000, 0x20000000, 0x10000000,
        0x08000000, 0x04000000, 0x02000000, 0x01000000,
        0x00800000, 0x00400000, 0x00200000, 0x00100000,
        0x00080000, 0x00040000, 0x00020000, 0x00010000,
        0x00008000, 0x00004000, 0x00002000, 0x00001000,
        0x00000800, 0x00000400, 0x00000200, 0x00000100,
        0x00000080, 0x00000040, 0x00000020, 0x00000010,
        0x00000008, 0x00000004, 0x00000002, 0x00000001,
    },
    .{
        0x80000000, 0xc0000000, 0xa0000000, 0xf0000000,
        0x88000000, 0xcc000000, 0xaa000000, 0xff000000,
        0x80800000, 0xc0c00000, 0xa0a00000, 0xf0f00000,
        0x88880000, 0xcccc0000, 0xaaaa0000, 0xffff0000,
        0x80008000, 0xc000c000, 0xa000a000, 0xf000f000,
        0x88008800, 0xcc00cc00, 0xaa00aa00, 0xff00ff00,
        0x80808080, 0xc0c0c0c0, 0xa0a0a0a0, 0xf0f0f0f0,
        0x88888888, 0xcccccccc, 0xaaaaaaaa, 0xffffffff,
    },
    .{
        0x80000000, 0xc0000000, 0x60000000, 0x90000000,
        0xe8000000, 0x5c000000, 0x8e000000, 0xc5000000,
        0x68800000, 0x9cc00000, 0xee600000, 0x55900000,
        0x80680000, 0xc09c0000, 0x60ee0000, 0x90550000,
        0xe8808000, 0x5cc0c000, 0x8e606000, 0xc5909000,
        0x6868e800, 0x9c9c5c00, 0xeeee8e00, 0x5555c500,
        0x8000e880, 0xc0005cc0, 0x60008e60, 0x9000c590,
        0xe8006868, 0x5c009c9c, 0x8e00eeee, 0xc5005555,
    },
    .{
        0x80000000, 0xc0000000, 0x20000000, 0x50000000,
        0xf8000000, 0x74000000, 0xa2000000, 0x93000000,
        0xd8800000, 0x25400000, 0x59e00000, 0xe6d00000,
        0x78080000, 0xb40c0000, 0x82020000, 0xc3050000,
        0x208f8000, 0x51474000, 0xfbea2000, 0x75d93000,
        0xa0858800, 0x914e5400, 0xdbe79e00, 0x25db6d00,
        0x58800080, 0xe54000c0, 0x79e00020, 0xb6d00050,
        0x800800f8, 0xc00c0074, 0x200200a2, 0x50050093,
    },
    .{
        0x80000000, 0x40000000, 0x20000000, 0xb0000000,
        0xf8000000, 0xdc000000, 0x7a000000, 0x9d000000,
        0x5a800000, 0x2fc00000, 0xa1600000, 0xf0b00000,
        0xda880000, 0x6fc40000, 0x81620000, 0x40bb0000,
        0x22878000, 0xb3c9c000, 0xfb65a000, 0xddb2d000,
        0x78022800, 0x9c0b3c00, 0x5a0fb600, 0x2d0ddb00,
        0xa2878080, 0xf3c9c040, 0xdb65a020, 0x6db2d0b0,
        0x800228f8, 0x400b3cdc, 0x200fb67a, 0xb00ddb9d,
    },
};
