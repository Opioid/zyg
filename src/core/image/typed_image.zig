const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec3i = math.Vec3i;
const Vec4i = math.Vec4i;

const Allocator = @import("std").mem.Allocator;

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

        pub fn init(alloc: *Allocator, description: Description) !TypedImage(T) {
            return TypedImage(T){
                .description = description,
                .pixels = try alloc.alloc(T, description.numPixels()),
            };
        }

        pub fn deinit(self: *Self, alloc: *Allocator) void {
            alloc.free(self.pixels);
        }

        pub fn resize(self: *Self, alloc: *Allocator, description: Description) !void {
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
