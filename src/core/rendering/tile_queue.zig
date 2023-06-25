const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2ul = math.Vec2ul;
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
        const mc = @mod(Vec4i{ crop[0], crop[1], -crop[2], -crop[3] }, @splat(4, @as(i32, 4)));

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
        const tdf = @floatFromInt(f32, tile_dimensions);

        const tiles_per_row = @intFromFloat(i32, @ceil(dim[0] / tdf));
        const tiles_per_col = @intFromFloat(i32, @ceil(dim[1] / tdf));

        self.tiles_per_row = tiles_per_row;
        self.num_tiles = tiles_per_row * tiles_per_col;
        self.current_consume = 0;
    }

    pub fn size(self: Self) u32 {
        return @intCast(u32, self.num_tiles);
    }

    pub fn restart(self: *Self) void {
        self.current_consume = 0;
    }

    pub fn pop(self: *Self) ?Vec4i {
        const current = @atomicRmw(i32, &self.current_consume, .Add, 1, .Monotonic);

        if (current >= self.num_tiles) {
            return null;
        }

        const crop = self.crop;
        const tile_dimensions = self.tile_dimensions;

        var start: Vec2i = undefined;
        start[1] = @divTrunc(current, self.tiles_per_row);
        start[0] = current - start[1] * self.tiles_per_row;

        start *= @splat(2, tile_dimensions);
        start += Vec2i{ crop[0], crop[1] };

        const end = @min(start + @splat(2, tile_dimensions), Vec2i{ crop[2], crop[3] });

        const back = end - @splat(2, @as(i32, 1));
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
        self.num_ranges0 = @intFromFloat(u32, @ceil(@floatFromInt(f32, total0) / @floatFromInt(f32, range_size)));
        self.num_ranges1 = @intFromFloat(u32, @ceil(@floatFromInt(f32, total1) / @floatFromInt(f32, range_size)));
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
        const current = @atomicRmw(u32, &self.current_consume, .Add, 1, .Monotonic);

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
