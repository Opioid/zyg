const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;

pub const Base = struct {
    dimensions: Vec2i = @splat(2, @as(i32, 0)),

    error_estimate: []f32 = &.{},

    pub fn deinit(self: *Base, alloc: Allocator) void {
        alloc.free(self.error_estimate);
    }

    pub fn resize(self: *Base, alloc: Allocator, dimensions: Vec2i) !void {
        self.dimensions = dimensions;

        const len = @intCast(usize, dimensions[0] * dimensions[1]);

        if (len > self.error_estimate.len) {
            self.error_estimate = try alloc.realloc(self.error_estimate, len);
        }
    }

    pub fn setErrorEstimate(self: *Base, pixel: Vec2i, s: f32) void {
        const d = self.dimensions;
        const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);
        self.error_estimate[i] = s;
    }

    pub const Result = struct {
        last: Vec4f,
        mean: Vec4f,
    };
};
