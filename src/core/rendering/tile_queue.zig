const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2ul = math.Vec2ul;
const Vec4s = math.Vec4s;
const Vec4i = math.Vec4i;

const std = @import("std");

pub const TileQueue = struct {
    crop: Vec4i,

    tile_dimensions: i32,
    tiles_per_row: i32,
    num_tiles: i32,

    current_consume: i32,

    const Self = @This();

    pub fn configure(self: *Self, dimensions: Vec2i, crop: Vec4i, tile_dimensions: i32) void {
        const mc = @mod(Vec4i{ crop[0], crop[1], -crop[2], -crop[3] }, @as(Vec4i, @splat(4)));

        var padded_crop: Vec4i = undefined;
        padded_crop[0] = @max(crop[0] - mc[0], 0);
        padded_crop[1] = @max(crop[1] - mc[1], 0);
        padded_crop[2] = @min(crop[2] + mc[2], dimensions[0]);
        padded_crop[3] = @min(crop[3] + mc[3], dimensions[1]);

        self.crop = padded_crop;
        self.tile_dimensions = tile_dimensions;

        const xy = Vec2i{ padded_crop[0], padded_crop[1] };
        const zw = Vec2i{ padded_crop[2], padded_crop[3] };
        const dim = math.vec2iTo2f(zw - xy);
        const tdf = @as(f32, @floatFromInt(tile_dimensions));

        const tiles_per_row = @as(i32, @intFromFloat(@ceil(dim[0] / tdf)));
        const tiles_per_col = @as(i32, @intFromFloat(@ceil(dim[1] / tdf)));

        self.tiles_per_row = tiles_per_row;
        self.num_tiles = tiles_per_row * tiles_per_col;
        self.current_consume = 0;
    }

    pub fn size(self: Self) u32 {
        return @as(u32, @intCast(self.num_tiles));
    }

    pub fn restart(self: *Self) void {
        self.current_consume = 0;
    }

    pub fn pop(self: *Self) ?Vec4i {
        const current = @atomicRmw(i32, &self.current_consume, .Add, 1, .monotonic);

        if (current >= self.num_tiles) {
            return null;
        }

        const crop = self.crop;
        const tile_dimensions = self.tile_dimensions;

        var start: Vec2i = undefined;
        start[1] = @divTrunc(current, self.tiles_per_row);
        start[0] = current - start[1] * self.tiles_per_row;

        start *= @splat(tile_dimensions);
        start += Vec2i{ crop[0], crop[1] };

        const end = @min(start + @as(Vec2i, @splat(tile_dimensions)), Vec2i{ crop[2], crop[3] });
        const back = end - @as(Vec2i, @splat(1));

        return Vec4i{ start[0], start[1], back[0], back[1] };
    }
};

pub fn TileStackN(comptime Area: u32) type {
    return struct {
        current: u32,
        end: u32,

        buffer: [Area]Vec4s,

        const Self = @This();

        pub fn empty(self: Self) bool {
            return 0 == self.end;
        }

        pub fn clear(self: *Self) void {
            self.current = 0;
            self.end = 0;
        }

        pub fn push(self: *Self, tile: Vec4i) void {
            if (tile[0] <= tile[2] and tile[1] <= tile[3]) {
                self.buffer[self.end] = @truncate(tile);
                self.end += 1;
            }
        }

        pub fn pushQuartet(self: *Self, tile: Vec4i, comptime d: i32) void {
            const mx = @min(tile[0] + d, tile[2]);
            const my = @min(tile[1] + d, tile[3]);

            self.push(.{ tile[0], tile[1], mx, my });
            self.push(.{ mx + 1, tile[1], tile[2], my });
            self.push(.{ tile[0], my + 1, mx, tile[3] });
            self.push(.{ mx + 1, my + 1, tile[2], tile[3] });
        }

        pub fn pop(self: *Self) ?Vec4i {
            const current = self.current;

            if (current >= self.end) {
                return null;
            }

            self.current += 1;

            return self.buffer[current];
        }
    };
}

pub const RangeQueue = struct {
    pub const Result = struct {
        it: u32,
        range: Vec2ul,
    };

    total0: u64,
    total1: u64,

    range_size: u32,
    num_ranges0: u32,
    num_ranges1: u32,
    current_segment: u32,

    current_consume: u32,

    const Self = @This();

    pub fn configure(self: *Self, total0: u64, total1: u64, range_size: u32) void {
        self.total0 = total0;
        self.total1 = total1;
        self.range_size = range_size;
        self.num_ranges0 = @as(u32, @intFromFloat(@ceil(@as(f32, @floatFromInt(total0)) / @as(f32, @floatFromInt(range_size)))));
        self.num_ranges1 = @as(u32, @intFromFloat(@ceil(@as(f32, @floatFromInt(total1)) / @as(f32, @floatFromInt(range_size)))));
    }

    pub fn head(self: Self) u64 {
        return self.total0;
    }

    pub fn total(self: Self) u64 {
        return self.total0 + self.total1;
    }

    pub fn size(self: Self) u32 {
        return self.num_ranges0 + self.num_ranges1;
    }

    pub fn restart(self: *Self, segment: u32) void {
        self.current_segment = segment;
        self.current_consume = 0;
    }

    pub fn pop(self: *Self) ?Result {
        const current = @atomicRmw(u32, &self.current_consume, .Add, 1, .monotonic);

        const seg0 = 0 == self.current_segment;

        const cl = @as(u64, current);
        const start = cl * @as(u64, self.range_size) + (if (seg0) 0 else self.total0);

        const num_ranges = if (seg0) self.num_ranges0 else self.num_ranges1;

        if (current < num_ranges - 1) {
            return Result{ .it = current, .range = .{ start, start + self.range_size } };
        }

        if (current < num_ranges) {
            return Result{ .it = current, .range = .{ start, if (seg0) self.total0 else self.total1 } };
        }

        return null;
    }
};
