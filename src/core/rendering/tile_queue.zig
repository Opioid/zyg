usingnamespace @import("base").math;

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

        const dim = crop.zw().sub(crop.xy()).toVec2f();
        const tdf = @intToFloat(f32, tile_dimensions);

        const tiles_per_row = @floatToInt(i32, @ceil(dim.v[0] / tdf));
        const tiles_per_col = @floatToInt(i32, @ceil(dim.v[1] / tdf));

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
        const current = self.current_consume;

        self.current_consume += 1;

        if (current >= self.num_tiles) {
            return null;
        }

        const crop = self.crop;
        const tile_dimensions = self.tile_dimensions;
        const filter_radius = self.filter_radius;

        var start: Vec2i = undefined;
        start.v[1] = @divTrunc(current, self.tiles_per_row);
        start.v[0] = current - start.v[1] * self.tiles_per_row;

        start.mulAssignScalar(tile_dimensions);
        start.addAssign(crop.xy());

        var end = start.addScalar(tile_dimensions).min(crop.zw());

        if (crop.v[1] == start.v[1]) {
            start.v[1] -= filter_radius;
        }

        if (crop.v[3] == end.v[1]) {
            end.v[1] += filter_radius;
        }

        if (crop.v[0] == start.v[0]) {
            start.v[0] -= filter_radius;
        }

        if (crop.v[2] == end.v[0]) {
            end.v[0] += filter_radius;
        }

        return Vec4i.init2_2(start, end.subScalar(1));
    }
};
