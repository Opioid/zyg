const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec3i = math.Vec3i;
const Vec4i = math.Vec4i;

const Allocator = @import("std").mem.Allocator;

pub const Description = struct {
    dimensions: Vec3i = Vec3i.init1(0),

    pub fn init2D(dim: Vec2i) Description {
        return .{ .dimensions = Vec3i.init2_1(dim, 1) };
    }

    pub fn numPixels(self: Description) u64 {
        return @intCast(u64, self.dimensions.v[0]) *
            @intCast(u64, self.dimensions.v[1]) *
            @intCast(u64, self.dimensions.v[2]);
    }
};

pub fn Typed_image(comptime T: type) type {
    return struct {
        description: Description = .{},

        pixels: []T = &.{},

        const Self = @This();

        pub fn init(alloc: *Allocator, description: Description) !Typed_image(T) {
            return Typed_image(T){
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

        pub fn gather2D(self: Self, xy_xy1: Vec4i) [4]T {
            const width = self.description.dimensions.v[0];
            const y0 = width * xy_xy1.v[1];
            const y1 = width * xy_xy1.v[3];

            return .{
                self.pixels[@intCast(usize, y0 + xy_xy1.v[0])],
                self.pixels[@intCast(usize, y0 + xy_xy1.v[2])],
                self.pixels[@intCast(usize, y1 + xy_xy1.v[0])],
                self.pixels[@intCast(usize, y1 + xy_xy1.v[2])],
            };
        }

        pub fn get3D(self: Self, x: i32, y: i32, z: i32) T {
            const d = self.description.dimensions.xy();
            const i = (@intCast(u64, z) * @intCast(u64, d.v[1]) + @intCast(u64, y)) * @intCast(u64, d.v[0]) + @intCast(u64, x);

            return self.pixels[@intCast(usize, i)];
        }
    };
}
