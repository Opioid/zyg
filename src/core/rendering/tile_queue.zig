const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;

pub const TileQueue = struct {
    crop: Vec4i,

    tile_dimensions: i32,
    filter_radius: i32,
    tiles_per_row: i32,
    num_tiles: i32,

    current_consume: i32,

    pub fn configure(self: *TileQueue, crop: Vec4i, tile_dimensions: i32, filter_radius: i32) void {
        self.crop = crop;
        self.tile_dimensions = tile_dimensions;
        self.filter_radius = filter_radius;

        const xy = Vec2i{ crop.v[0], crop.v[1] };
        const zw = Vec2i{ crop.v[2], crop.v[3] };
        const dim = math.vec2iTo2f(zw - xy);
        const tdf = @intToFloat(f32, tile_dimensions);

        const tiles_per_row = @floatToInt(i32, @ceil(dim[0] / tdf));
        const tiles_per_col = @floatToInt(i32, @ceil(dim[1] / tdf));

        self.tiles_per_row = tiles_per_row;
        self.num_tiles = tiles_per_row * tiles_per_col;
        self.current_consume = 0;
    }

    pub fn size(self: TileQueue) u32 {
        return @intCast(u32, self.num_tiles);
    }

    pub fn restart(self: *TileQueue) void {
        self.current_consume = 0;
    }

    pub fn pop(self: *TileQueue) ?Vec4i {
        const current = @atomicRmw(i32, &self.current_consume, .Add, 1, .Monotonic);

        if (current >= self.num_tiles) {
            return null;
        }

        const crop = self.crop;
        const tile_dimensions = self.tile_dimensions;
        const filter_radius = self.filter_radius;

        var start: Vec2i = undefined;
        start[1] = @divTrunc(current, self.tiles_per_row);
        start[0] = current - start[1] * self.tiles_per_row;

        start *= @splat(2, tile_dimensions);
        start += Vec2i{ crop.v[0], crop.v[1] };

        var end = math.min2(start + @splat(2, tile_dimensions), Vec2i{ crop.v[2], crop.v[3] });

        if (crop.v[1] == start[1]) {
            start[1] -= filter_radius;
        }

        if (crop.v[3] == end[1]) {
            end[1] += filter_radius;
        }

        if (crop.v[0] == start[0]) {
            start[0] -= filter_radius;
        }

        if (crop.v[2] == end[0]) {
            end[0] += filter_radius;
        }

        const back = end - @splat(2, @as(i32, 1));
        return Vec4i.init4(start[0], start[1], back[0], back[1]);
    }
};
