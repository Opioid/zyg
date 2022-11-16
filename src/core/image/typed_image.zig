const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Description = struct {
    dimensions: Vec4i = @splat(4, @as(i32, 0)),

    pub fn init2D(dim: Vec2i) Description {
        return .{ .dimensions = .{ dim[0], dim[1], 1, 0 } };
    }

    pub fn init3D(dim: Vec4i) Description {
        return .{ .dimensions = dim };
    }

    pub fn numPixels(self: Description) u64 {
        return @intCast(u64, self.dimensions[0]) *
            @intCast(u64, self.dimensions[1]) *
            @intCast(u64, self.dimensions[2]);
    }
};

pub fn TypedImage(comptime T: type) type {
    return struct {
        description: Description = .{},

        pixels: []T = &.{},

        const Self = @This();

        pub fn init(alloc: Allocator, description: Description) !TypedImage(T) {
            return TypedImage(T){
                .description = description,
                .pixels = try alloc.alloc(T, description.numPixels()),
            };
        }

        pub fn initFromBytes(description: Description, data: []align(@alignOf(T)) u8) TypedImage(T) {
            return TypedImage(T){
                .description = description,
                .pixels = std.mem.bytesAsSlice(T, data),
            };
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            alloc.free(self.pixels);
        }

        pub fn resize(self: *Self, alloc: Allocator, description: Description) !void {
            self.description = description;

            const len = description.numPixels();
            if (self.pixels.len < len) {
                self.pixels = try alloc.realloc(self.pixels, len);
            }
        }

        pub fn get2D(self: Self, x: i32, y: i32) T {
            const i = y * self.description.dimensions[0] + x;

            return self.pixels[@intCast(usize, i)];
        }

        pub fn set2D(self: *Self, x: i32, y: i32, v: T) void {
            const i = y * self.description.dimensions[0] + x;

            self.pixels[@intCast(usize, i)] = v;
        }

        pub fn gather2D(self: Self, xy_xy1: Vec4i) [4]T {
            const width = self.description.dimensions[0];
            const y0 = width * xy_xy1[1];
            const y1 = width * xy_xy1[3];

            return .{
                self.pixels[@intCast(usize, y0 + xy_xy1[0])],
                self.pixels[@intCast(usize, y0 + xy_xy1[2])],
                self.pixels[@intCast(usize, y1 + xy_xy1[0])],
                self.pixels[@intCast(usize, y1 + xy_xy1[2])],
            };
        }

        pub fn get3D(self: Self, x: i32, y: i32, z: i32) T {
            const d = self.description.dimensions;
            const i = (@intCast(u64, z) * @intCast(u64, d[1]) + @intCast(u64, y)) *
                @intCast(u64, d[0]) + @intCast(u64, x);

            return self.pixels[i];
        }

        pub fn gather3D(self: Self, xyz: Vec4i, xyz1: Vec4i) [8]T {
            const dim = self.description.dimensions;
            const w = @as(i64, dim[0]);
            const h = @as(i64, dim[1]);

            const x = @as(i64, xyz[0]);
            const y = @as(i64, xyz[1]);
            const z = @as(i64, xyz[2]);

            const x1 = @as(i64, xyz1[0]);
            const y1 = @as(i64, xyz1[1]);
            const z1 = @as(i64, xyz1[2]);

            const d = z * h;
            const d1 = z1 * h;

            return .{
                self.pixels[@intCast(usize, (d + y) * w + x)],
                self.pixels[@intCast(usize, (d1 + y) * w + x)],
                self.pixels[@intCast(usize, (d + y) * w + x1)],
                self.pixels[@intCast(usize, (d1 + y) * w + x1)],
                self.pixels[@intCast(usize, (d + y1) * w + x)],
                self.pixels[@intCast(usize, (d1 + y1) * w + x)],
                self.pixels[@intCast(usize, (d + y1) * w + x1)],
                self.pixels[@intCast(usize, (d1 + y1) * w + x1)],
            };
        }
    };
}

pub fn TypedSparseImage(comptime T: type) type {
    return struct {
        const Cell = struct {
            data: ?[*]T,
            value: T,
        };

        description: Description = .{},

        num_cells: Vec4i,

        cells: []Cell,

        const Log2_cell_dim: u5 = 4;
        const Log2_cell_dim4 = std.meta.Vector(4, u5){ Log2_cell_dim, Log2_cell_dim, Log2_cell_dim, 0 };
        const Cell_dim: u32 = 1 << Log2_cell_dim;

        const Self = @This();

        pub fn init(alloc: Allocator, description: Description) !Self {
            const d = description.dimensions;

            var num_cells = d >> Log2_cell_dim4;
            num_cells += @min(d - (num_cells << Log2_cell_dim4), @splat(4, @as(i32, 1)));

            const cells_len = @intCast(usize, num_cells[0] * num_cells[1] * num_cells[2]);

            var result = Self{
                .description = description,
                .num_cells = num_cells,
                .cells = try alloc.alloc(Cell, cells_len),
            };

            for (result.cells) |*c| {
                c.data = null;
                std.mem.set(u8, std.mem.asBytes(&c.value), 0);
            }

            return result;
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            const cell_len = comptime Cell_dim * Cell_dim * Cell_dim;

            for (self.cells) |c| {
                if (c.data) |data| {
                    alloc.free(data[0..cell_len]);
                }
            }

            alloc.free(self.cells);
        }

        pub fn storeSequentially(self: *Self, alloc: Allocator, index: i64, v: T) !void {
            const c = self.coordinates3(index);
            const cc = c >> Log2_cell_dim4;

            const cell_index = (cc[2] * self.num_cells[1] + cc[1]) * self.num_cells[0] + cc[0];

            const cell_len = comptime Cell_dim * Cell_dim * Cell_dim;

            var cell = &self.cells[@intCast(usize, cell_index)];

            if (null == cell.data) {
                const data = try alloc.alloc(T, cell_len);
                std.mem.set(u8, std.mem.sliceAsBytes(data), 0);
                cell.data = data.ptr;
            }

            if (cell.data) |data| {
                const cs = cc << Log2_cell_dim4;
                const cxyz = c - cs;
                const ci = (((cxyz[2] << Log2_cell_dim) + cxyz[1]) << Log2_cell_dim) + cxyz[0];

                data[@intCast(usize, ci)] = v;

                if (ci == cell_len - 1) {
                    var homogeneous = true;
                    const value = data[0];

                    for (data[0..cell_len]) |cd| {
                        if (value != cd) {
                            homogeneous = false;
                            break;
                        }
                    }

                    if (homogeneous) {
                        alloc.free(data[0..cell_len]);
                        cell.data = null;
                        cell.value = value;
                    }
                }
            }
        }

        pub fn get3D(self: Self, x: i32, y: i32, z: i32) T {
            const c = Vec4i{ x, y, z, 0 };
            const cc = c >> Log2_cell_dim4;

            const cell_index = (cc[2] * self.num_cells[1] + cc[1]) * self.num_cells[0] + cc[0];

            var cell = &self.cells[@intCast(usize, cell_index)];

            if (cell.data) |data| {
                const cs = cc << Log2_cell_dim4;
                const cxyz = c - cs;
                const ci = (((cxyz[2] << Log2_cell_dim) + cxyz[1]) << Log2_cell_dim) + cxyz[0];
                return data[@intCast(usize, ci)];
            }

            return cell.value;
        }

        pub fn gather3D(self: Self, xyz: Vec4i, xyz1: Vec4i) [8]T {
            const cc0 = xyz >> Log2_cell_dim4;
            const cc1 = xyz1 >> Log2_cell_dim4;

            if (math.equal4i(cc0, cc1)) {
                const num_cells = self.num_cells;
                const cell_index = (cc0[2] * num_cells[1] + cc0[1]) * num_cells[0] + cc0[0];

                const cell = self.cells[@intCast(usize, cell_index)];

                if (cell.data) |data| {
                    const cs = cc0 << Log2_cell_dim4;

                    const d0 = (xyz[2] - cs[2]) << Log2_cell_dim;
                    const d1 = (xyz1[2] - cs[2]) << Log2_cell_dim;

                    const csxy = Vec2i{ cs[0], cs[1] };

                    var result: [8]T = undefined;
                    {
                        const cxy = Vec2i{ xyz[0], xyz[1] } - csxy;
                        const ci = ((d0 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[0] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz[0], xyz[1] } - csxy;
                        const ci = ((d1 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[1] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz1[0], xyz[1] } - csxy;
                        const ci = ((d0 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[2] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz1[0], xyz[1] } - csxy;
                        const ci = ((d1 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[3] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz[0], xyz1[1] } - csxy;
                        const ci = ((d0 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[4] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz[0], xyz1[1] } - csxy;
                        const ci = ((d1 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[5] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz1[0], xyz1[1] } - csxy;
                        const ci = ((d0 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[6] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz1[0], xyz1[1] } - csxy;
                        const ci = ((d1 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[7] = data[@intCast(usize, ci)];
                    }

                    return result;
                }

                const v = cell.value;
                return .{ v, v, v, v, v, v, v, v };
            }

            return .{
                self.get3D(xyz[0], xyz[1], xyz[2]),
                self.get3D(xyz[0], xyz[1], xyz1[2]),
                self.get3D(xyz1[0], xyz[1], xyz[2]),
                self.get3D(xyz1[0], xyz[1], xyz1[2]),
                self.get3D(xyz[0], xyz1[1], xyz[2]),
                self.get3D(xyz[0], xyz1[1], xyz1[2]),
                self.get3D(xyz1[0], xyz1[1], xyz[2]),
                self.get3D(xyz1[0], xyz1[1], xyz1[2]),
            };
        }

        fn coordinates3(self: Self, index: i64) Vec4i {
            const d = self.description.dimensions;
            const w = @as(i64, d[0]);
            const h = @as(i64, d[1]);

            const area = w * h;
            const c2 = @divTrunc(index, area);
            const t = c2 * area;
            const c1 = @divTrunc(index - t, w);

            return Vec4i{ @intCast(i32, index - (t + c1 * w)), @intCast(i32, c1), @intCast(i32, c2), 0 };
        }
    };
}
