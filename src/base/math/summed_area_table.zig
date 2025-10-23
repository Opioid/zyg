const vec2 = @import("vector2.zig");
const Vec2i = vec2.Vec2i;
const Vec2f = vec2.Vec2f;
const Bounds2f = @import("bounds.zig").Bounds2f;
const math = @import("util.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const SummedAreaTable = struct {
    dim: Vec2i,
    buffer: [*]f32,

    const Self = @This();

    pub fn init(alloc: Allocator, dim: Vec2i, data: [*]f32) !Self {
        const len: usize = @intCast(dim[0] * dim[1]);

        var buffer = (try alloc.alloc(f32, len)).ptr;

        const w = dim[0];

        buffer[0] = data[0];

        // Compute sums along first row and column
        var x: i32 = 1;
        while (x < dim[0]) : (x += 1) {
            const i = index(x, 0, w);
            buffer[i] = data[i] + buffer[index(x - 1, 0, w)];
        }

        var y: i32 = 1;
        while (y < dim[1]) : (y += 1) {
            const i = index(0, y, w);
            buffer[i] = data[i] + buffer[index(0, y - 1, w)];
        }

        // Compute sums for the remainder of the entries
        y = 1;
        while (y < dim[1]) : (y += 1) {
            x = 1;
            while (x < dim[0]) : (x += 1) {
                const i = index(x, y, w);
                buffer[i] = data[i] + buffer[index(x - 1, y, w)] + buffer[index(x, y - 1, w)] - buffer[index(x - 1, y - 1, w)];
            }
        }

        return .{ .dim = dim, .buffer = buffer };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        const d = self.dim;
        const len: usize = @intCast(d[0] * d[1]);
        if (len > 0) {
            alloc.free(self.buffer[0..len]);
        }
    }

    //  Float Integral(Bounds2f extent) const {
    //     double s = (((double)Lookup(extent.pMax.x, extent.pMax.y) -
    //                  (double)Lookup(extent.pMin.x, extent.pMax.y)) +
    //                 ((double)Lookup(extent.pMin.x, extent.pMin.y) -
    //                  (double)Lookup(extent.pMax.x, extent.pMin.y)));
    //     return std::max<Float>(s / (sum.XSize() * sum.YSize()), 0);
    // }

    pub fn integral(self: Self, extent: Bounds2f) f32 {
        const s =
            (self.lookup(extent.bounds[1][0], extent.bounds[1][1]) -
                self.lookup(extent.bounds[0][0], extent.bounds[1][1])) +
            (self.lookup(extent.bounds[0][0], extent.bounds[0][1]) -
                self.lookup(extent.bounds[1][0], extent.bounds[0][1]));

        const d = self.dim;
        const area: f32 = @floatFromInt(d[0] * d[1]);
        return math.max(s / area, 0.0);
    }

    // Float Lookup(Float x, Float y) const {
    //     // Rescale $(x,y)$ to table resolution and compute integer coordinates
    //     x *= sum.XSize();
    //     y *= sum.YSize();
    //     int x0 = (int)x, y0 = (int)y;

    //     // Bilinearly interpolate between surrounding table values
    //     Float v00 = LookupInt(x0, y0), v10 = LookupInt(x0 + 1, y0);
    //     Float v01 = LookupInt(x0, y0 + 1), v11 = LookupInt(x0 + 1, y0 + 1);
    //     Float dx = x - int(x), dy = y - int(y);
    //     return (1 - dx) * (1 - dy) * v00 + (1 - dx) * dy * v01 + dx * (1 - dy) * v10 +
    //            dx * dy * v11;
    // }

    fn lookup(self: Self, fx: f32, fy: f32) f32 {
        const fd: Vec2f = @floatFromInt(self.dim);
        const x = fx * fd[0];
        const y = fy * fd[1];

        const x0: i32 = @intFromFloat(x);
        const y0: i32 = @intFromFloat(y);

        const v00 = self.lookupInt(x0, y0);
        const v10 = self.lookupInt(x0 + 1, y0);
        const v01 = self.lookupInt(x0, y0 + 1);
        const v11 = self.lookupInt(x0 + 1, y0 + 1);

        const dx = x - @as(f32, @floatFromInt(x0));
        const dy = y - @as(f32, @floatFromInt(y0));

        return (1.0 - dx) * (1.0 - dy) * v00 + (1.0 - dx) * dy * v01 + dx * (1.0 - dy) * v10 + dx * dy * v11;
    }

    // Float LookupInt(int x, int y) const {
    //     // Return zero at lower boundaries
    //     if (x == 0 || y == 0)
    //         return 0;

    //     // Reindex $(x,y)$ and return actual stored value
    //     x = std::min(x - 1, sum.XSize() - 1);
    //     y = std::min(y - 1, sum.YSize() - 1);
    //     return sum(x, y);
    // }

    fn lookupInt(self: Self, x: i32, y: i32) f32 {
        // Return zero at lower boundaries
        if (0 == x or 0 == y) {
            return 0.0;
        }

        const d = self.dim;

        // Reindex (x,y) and return actual stored value
        const xx = @min(x - 1, d[0] - 1);
        const yy = @min(y - 1, d[1] - 1);

        return self.buffer[index(xx, yy, d[0])];
    }

    inline fn index(x: i32, y: i32, w: i32) u32 {
        return @intCast(y * w + x);
    }
};
