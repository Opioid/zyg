const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2ul = math.Vec2ul;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;

const std = @import("std");

pub const TileQueue = struct {
    crop: Vec4i,

    tile_dimensions: i32,
    filter_radius: i32,
    tiles_per_row: i32,
    num_tiles: i32,

    current_consume: i32,

    const Self = @This();

    pub fn configure(self: *Self, crop: Vec4i, tile_dimensions: i32, filter_radius: i32) void {
        self.crop = crop;
        self.tile_dimensions = tile_dimensions;
        self.filter_radius = filter_radius;

        const xy = Vec2i{ crop[0], crop[1] };
        const zw = Vec2i{ crop[2], crop[3] };
        const dim: Vec2f = @floatFromInt(zw - xy);
        const tdf: f32 = @floatFromInt(tile_dimensions);

        const tiles_per_row: i32 = @intFromFloat(@ceil(dim[0] / tdf));
        const tiles_per_col: i32 = @intFromFloat(@ceil(dim[1] / tdf));

        self.tiles_per_row = tiles_per_row;
        self.num_tiles = tiles_per_row * tiles_per_col;
        self.current_consume = 0;
    }

    pub fn size(self: Self) u32 {
        return @intCast(self.num_tiles);
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
        const filter_radius = self.filter_radius;

        var start: Vec2i = undefined;
        start[1] = @divTrunc(current, self.tiles_per_row);
        start[0] = current - start[1] * self.tiles_per_row;

        start *= @splat(tile_dimensions);
        start += Vec2i{ crop[0], crop[1] };

        var end = @min(start + @as(Vec2i, @splat(tile_dimensions)), Vec2i{ crop[2], crop[3] });

        if (crop[1] == start[1]) {
            start[1] -= filter_radius;
        }

        if (crop[3] == end[1]) {
            end[1] += filter_radius;
        }

        if (crop[0] == start[0]) {
            start[0] -= filter_radius;
        }

        if (crop[2] == end[0]) {
            end[0] += filter_radius;
        }

        const back = end - @as(Vec2i, @splat(1));
        return Vec4i{ start[0], start[1], back[0], back[1] };
    }
};

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
        self.num_ranges0 = @intFromFloat(@ceil(@as(f32, @floatFromInt(total0)) / @as(f32, @floatFromInt(range_size))));
        self.num_ranges1 = @intFromFloat(@ceil(@as(f32, @floatFromInt(total1)) / @as(f32, @floatFromInt(range_size))));
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
