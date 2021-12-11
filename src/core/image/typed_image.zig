const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec3i = math.Vec3i;
const Vec4i = math.Vec4i;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Description = struct {
    dimensions: Vec3i = Vec3i.init1(0),

    pub fn init2D(dim: Vec2i) Description {
        return .{ .dimensions = Vec3i.init3(dim[0], dim[1], 1) };
    }

    pub fn init3D(dim: Vec3i) Description {
        return .{ .dimensions = dim };
    }

    pub fn numPixels(self: Description) u64 {
        return @intCast(u64, self.dimensions.v[0]) *
            @intCast(u64, self.dimensions.v[1]) *
            @intCast(u64, self.dimensions.v[2]);
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

        pub fn get1D(self: Self, x: i32) T {
            return self.pixels[@intCast(usize, x)];
        }

        pub fn set1D(self: *Self, x: i32, v: T) void {
            self.pixels[@intCast(usize, x)] = v;
        }

        pub fn get2D(self: Self, x: i32, y: i32) T {
            const i = y * self.description.dimensions.v[0] + x;

            return self.pixels[@intCast(usize, i)];
        }

        pub fn set2D(self: *Self, x: i32, y: i32, v: T) void {
            const i = y * self.description.dimensions.v[0] + x;

            self.pixels[@intCast(usize, i)] = v;
        }

        pub fn gather2D(self: Self, xy_xy1: Vec4i) [4]T {
            const width = self.description.dimensions.v[0];
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
            const i = (@intCast(u64, z) * @intCast(u64, d.v[1]) + @intCast(u64, y)) *
                @intCast(u64, d.v[0]) + @intCast(u64, x);

            return self.pixels[i];
        }

        pub fn gather3D(self: Self, xyz: Vec3i, xyz1: Vec3i) [8]T {
            const dim = self.description.dimensions;
            const w = @as(i64, dim.v[0]);
            const h = @as(i64, dim.v[1]);

            const x = @as(i64, xyz.v[0]);
            const y = @as(i64, xyz.v[1]);
            const z = @as(i64, xyz.v[2]);

            const x1 = @as(i64, xyz1.v[0]);
            const y1 = @as(i64, xyz1.v[1]);
            const z1 = @as(i64, xyz1.v[2]);

            const d = z * h;
            const d1 = z1 * h;

            return .{
                self.pixels[@intCast(usize, (d + y) * w + x)],
                self.pixels[@intCast(usize, (d + y) * w + x1)],
                self.pixels[@intCast(usize, (d + y1) * w + x)],
                self.pixels[@intCast(usize, (d + y1) * w + x1)],
                self.pixels[@intCast(usize, (d1 + y) * w + x)],
                self.pixels[@intCast(usize, (d1 + y) * w + x1)],
                self.pixels[@intCast(usize, (d1 + y1) * w + x)],
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

        num_cells: Vec3i,

        cells: []Cell,

        const Log2_cell_dim = 4;
        const Cell_dim = 1 << Log2_cell_dim;

        const Self = @This();

        pub fn init(alloc: Allocator, description: Description) !Self {
            const d = description.dimensions;

            var num_cells = d.shiftRight(Log2_cell_dim);
            num_cells.addAssign(d.sub(num_cells.shiftLeft(Log2_cell_dim)).min1(1));

            const cells_len = @intCast(usize, num_cells.v[0] * num_cells.v[1] * num_cells.v[2]);

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
            const cc = c.shiftRight(Log2_cell_dim);

            const cell_index = (cc.v[2] * self.num_cells.v[1] + cc.v[1]) * self.num_cells.v[0] + cc.v[0];

            const cell_len = comptime Cell_dim * Cell_dim * Cell_dim;

            var cell = &self.cells[@intCast(usize, cell_index)];

            if (null == cell.data) {
                const data = try alloc.alloc(T, cell_len);
                std.mem.set(u8, std.mem.sliceAsBytes(data), 0);
                cell.data = data.ptr;
            }

            if (cell.data) |data| {
                const cs = cc.shiftLeft(Log2_cell_dim);
                const cxyz = c.sub(cs);
                const ci = (((cxyz.v[2] << Log2_cell_dim) + cxyz.v[1]) << Log2_cell_dim) + cxyz.v[0];

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
            const c = Vec3i.init3(x, y, z);
            const cc = c.shiftRight(Log2_cell_dim);

            const cell_index = (cc.v[2] * self.num_cells.v[1] + cc.v[1]) * self.num_cells.v[0] + cc.v[0];

            var cell = &self.cells[@intCast(usize, cell_index)];

            if (cell.data) |data| {
                const cs = cc.shiftLeft(Log2_cell_dim);
                const cxyz = c.sub(cs);
                const ci = (((cxyz.v[2] << Log2_cell_dim) + cxyz.v[1]) << Log2_cell_dim) + cxyz.v[0];
                return data[@intCast(usize, ci)];
            }

            return cell.value;
        }

        pub fn gather3D(self: Self, xyz: Vec3i, xyz1: Vec3i) [8]T {
            const cc0 = xyz.shiftRight(Log2_cell_dim);
            const cc1 = xyz1.shiftRight(Log2_cell_dim);

            if (cc0.equal(cc1)) {
                const cell_index = (cc0.v[2] * self.num_cells.v[1] + cc0.v[1]) * self.num_cells.v[0] + cc0.v[0];

                const cell = self.cells[@intCast(usize, cell_index)];

                if (cell.data) |data| {
                    const cs = cc0.shiftLeft(Log2_cell_dim);

                    const d0 = (xyz.v[2] - cs.v[2]) << Log2_cell_dim;
                    const d1 = (xyz1.v[2] - cs.v[2]) << Log2_cell_dim;

                    const csxy = Vec2i{ cs.v[0], cs.v[1] };

                    var result: [8]T = undefined;
                    {
                        const cxy = Vec2i{ xyz.v[0], xyz.v[1] } - csxy;
                        const ci = ((d0 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[0] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz1.v[0], xyz.v[1] } - csxy;
                        const ci = ((d0 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[1] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz.v[0], xyz1.v[1] } - csxy;
                        const ci = ((d0 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[2] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz1.v[0], xyz1.v[1] } - csxy;
                        const ci = ((d0 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[3] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz.v[0], xyz.v[1] } - csxy;
                        const ci = ((d1 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[4] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz1.v[0], xyz.v[1] } - csxy;
                        const ci = ((d1 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[5] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz.v[0], xyz1.v[1] } - csxy;
                        const ci = ((d1 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[6] = data[@intCast(usize, ci)];
                    }

                    {
                        const cxy = Vec2i{ xyz1.v[0], xyz1.v[1] } - csxy;
                        const ci = ((d1 + cxy[1]) << Log2_cell_dim) + cxy[0];
                        result[7] = data[@intCast(usize, ci)];
                    }

                    return result;
                }

                const v = cell.value;
                return .{ v, v, v, v, v, v, v, v };
            }

            return .{
                self.get3D(xyz.v[0], xyz.v[1], xyz.v[2]),
                self.get3D(xyz1.v[0], xyz.v[1], xyz.v[2]),
                self.get3D(xyz.v[0], xyz1.v[1], xyz.v[2]),
                self.get3D(xyz1.v[0], xyz1.v[1], xyz.v[2]),
                self.get3D(xyz.v[0], xyz.v[1], xyz1.v[2]),
                self.get3D(xyz1.v[0], xyz.v[1], xyz1.v[2]),
                self.get3D(xyz.v[0], xyz1.v[1], xyz1.v[2]),
                self.get3D(xyz1.v[0], xyz1.v[1], xyz1.v[2]),
            };
        }

        fn coordinates3(self: Self, index: i64) Vec3i {
            const w = @as(i64, self.description.dimensions.v[0]);
            const h = @as(i64, self.description.dimensions.v[1]);

            const area = w * h;
            const c2 = @divTrunc(index, area);
            const t = c2 * area;
            const c1 = @divTrunc(index - t, w);

            return Vec3i.init3(@intCast(i32, index - (t + c1 * w)), @intCast(i32, c1), @intCast(i32, c2));
        }
    };
}
