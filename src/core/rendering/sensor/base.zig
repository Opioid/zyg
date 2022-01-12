const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;

pub const Base = struct {
    dimensions: Vec2i = @splat(2, @as(i32, 0)),

    ee: []f32 = &.{},
    dee: []f32 = &.{},

    pub fn deinit(self: *Base, alloc: Allocator) void {
        alloc.free(self.dee);
        alloc.free(self.ee);
    }

    pub fn resize(self: *Base, alloc: Allocator, dimensions: Vec2i) !void {
        self.dimensions = dimensions;

        const len = @intCast(usize, dimensions[0] * dimensions[1]);

        if (len > self.ee.len) {
            self.ee = try alloc.realloc(self.ee, len);
            self.dee = try alloc.realloc(self.dee, len);
        }
    }

    pub fn errorEstimate(self: Base, pixel: Vec2i) f32 {
        const d = self.dimensions;
        const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);
        return self.dee[i];
    }

    pub fn setErrorEstimate(self: *Base, pixel: Vec2i, s: f32) void {
        const d = self.dimensions;
        const i = @intCast(usize, d[0] * pixel[1] + pixel[0]);
        self.ee[i] = s;
    }

    pub fn diluteErrorEstimate(self: *Base) void {
        const d = self.dimensions;

        var y: i32 = 0;
        while (y < d[1]) : (y += 1) {
            var x: i32 = 0;
            while (x < d[0]) : (x += 1) {
                const dest = @intCast(usize, d[0] * y + x);

                var e: f32 = 0.0;

                var sy: i32 = -1;
                while (sy <= 1) : (sy += 1) {
                    const oy = y + sy;

                    if (oy < 0 or oy >= d[1]) {
                        continue;
                    }

                    var sx: i32 = -1;
                    while (sx <= 1) : (sx += 1) {
                        const ox = x + sx;

                        if (ox < 0 or ox >= d[0]) {
                            continue;
                        }

                        const source = @intCast(usize, d[0] * oy + ox);

                        e = @maximum(e, self.ee[source]);
                    }

                    self.dee[dest] = e;
                }
            }
        }
    }

    pub const Result = struct {
        last: Vec4f,
        mean: Vec4f,
    };
};
