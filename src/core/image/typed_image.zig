const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Description = struct {
    dimensions: Vec4i = @splat(0),

    pub fn init2D(dim: Vec2i) Description {
        return .{ .dimensions = .{ dim[0], dim[1], 1, 1 } };
    }

    pub fn init3D(dim: Vec4i) Description {
        return .{ .dimensions = dim };
    }

    pub fn numPixels(dim: Vec4i) u64 {
        return @as(u64, @intCast(dim[0])) *
            @as(u64, @intCast(dim[1])) *
            @as(u64, @intCast(dim[2]));
    }
};

pub fn TypedImage(comptime T: type) type {
    return struct {
        dimensions: Vec4i,

        pixels: []T,

        const Self = @This();

        pub fn initEmpty() Self {
            return Self{
                .dimensions = @splat(0.0),
                .pixels = &.{},
            };
        }

        pub fn init(alloc: Allocator, description: Description) !Self {
            const dim = description.dimensions;

            return Self{
                .dimensions = dim,
                .pixels = try alloc.alloc(T, Description.numPixels(dim)),
            };
        }

        pub fn initFromBytes(description: Description, data: []align(@alignOf(T)) u8) Self {
            return Self{
                .dimensions = description.dimensions,
                .pixels = std.mem.bytesAsSlice(T, data),
            };
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            alloc.free(self.pixels);
        }

        pub fn resize(self: *Self, alloc: Allocator, description: Description) !void {
            const dim = description.dimensions;

            self.dimensions = dim;

            const len = Description.numPixels(dim);
            if (self.pixels.len < len) {
                self.pixels = try alloc.realloc(self.pixels, len);
            }
        }

        pub fn get2D(self: Self, x: i32, y: i32) T {
            const i = y * self.dimensions[0] + x;

            return self.pixels[@intCast(i)];
        }

        pub fn set2D(self: *Self, x: i32, y: i32, v: T) void {
            const i = y * self.dimensions[0] + x;

            self.pixels[@intCast(i)] = v;
        }

        pub fn get3D(self: Self, x: i32, y: i32, z: i32) T {
            const d = self.dimensions;
            const i = (@as(u64, @intCast(z)) * @as(u64, @intCast(d[1])) + @as(u64, @intCast(y))) *
                @as(u64, @intCast(d[0])) + @as(u64, @intCast(x));

            return self.pixels[i];
        }
    };
}

pub fn TypedSparseImage(comptime T: type) type {
    return struct {
        const Cell = struct {
            data: ?[*]T,
            value: T,
        };

        dimensions: Vec4i,

        num_cells: Vec4i,

        cells: []Cell,

        const Log2_cell_dim: u5 = 4;
        const Log2_cell_dim4: @Vector(4, u5) = .{ Log2_cell_dim, Log2_cell_dim, Log2_cell_dim, 0 };
        const Cell_dim: u32 = 1 << Log2_cell_dim;

        const Self = @This();

        pub fn init(alloc: Allocator, description: Description) !Self {
            const d = description.dimensions;

            var num_cells = d >> Log2_cell_dim4;
            num_cells += @min(d - (num_cells << Log2_cell_dim4), @as(Vec4i, @splat(1)));

            const cells_len: usize = @intCast(num_cells[0] * num_cells[1] * num_cells[2]);

            const result = Self{
                .dimensions = d,
                .num_cells = num_cells,
                .cells = try alloc.alloc(Cell, cells_len),
            };

            for (result.cells) |*c| {
                c.data = null;
                @memset(std.mem.asBytes(&c.value), 0);
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

            var cell = &self.cells[@intCast(cell_index)];

            if (null == cell.data) {
                const data = try alloc.alloc(T, cell_len);
                @memset(std.mem.sliceAsBytes(data), 0);
                cell.data = data.ptr;
            }

            if (cell.data) |data| {
                const cs = cc << Log2_cell_dim4;
                const cxyz = c - cs;
                const ci = (((cxyz[2] << Log2_cell_dim) + cxyz[1]) << Log2_cell_dim) + cxyz[0];

                data[@intCast(ci)] = v;

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

            const cell = &self.cells[@intCast(cell_index)];

            if (cell.data) |data| {
                const cs = cc << Log2_cell_dim4;
                const cxyz = c - cs;
                const ci = (((cxyz[2] << Log2_cell_dim) + cxyz[1]) << Log2_cell_dim) + cxyz[0];
                return data[@intCast(ci)];
            }

            return cell.value;
        }

        fn coordinates3(self: Self, index: i64) Vec4i {
            const d = self.dimensions;
            const w: i64 = d[0];
            const h: i64 = d[1];

            const area = w * h;
            const c2 = @divTrunc(index, area);
            const t = c2 * area;
            const c1 = @divTrunc(index - t, w);

            return Vec4i{ @intCast(index - (t + c1 * w)), @intCast(c1), @intCast(c2), 0 };
        }
    };
}
