usingnamespace @import("base").math;

const Allocator = @import("std").mem.Allocator;

pub const Description = struct {
    dimensions: Vec3i = Vec3i.init1(0),

    pub fn init2D(dim: Vec2i) Description {
        return .{ .dimensions = Vec3i.init2_1(dim, 1) };
    }

    pub fn numPixels(self: Description) u64 {
        return @intCast(u64, self.dimensions.v[0]) * @intCast(u64, self.dimensions.v[1]) * @intCast(u64, self.dimensions.v[2]);
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

            if (len > self.pixels.len) {
                self.pixels = try alloc.realloc(self.pixels, len);
            }
        }

        pub fn getX(self: Self, x: i32) T {
            return self.pixels[@intCast(usize, x)];
        }

        pub fn setX(self: *Self, x: i32, v: T) void {
            self.pixels[@intCast(usize, x)] = v;
        }

        pub fn getXY(self: Self, x: i32, y: i32) T {
            const i = y * self.dimensions.v[1] + x;

            return self.pixels[@intCast(usize, i)];
        }

        pub fn getXYZ(self: Self, x: i32) T {
            const d = self.dimensions.xy();
            const i = (@intCast(u64, z) * @intCast(u64, d.v[1]) + @intCast(u64, y)) * @intCast(u64, d.v[0]) + @intCast(u64, x);

            return self.pixels[@intCast(usize, i)];
        }
    };
}
