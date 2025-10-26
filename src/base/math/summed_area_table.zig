const vec2 = @import("vector2.zig");
const Vec2i = vec2.Vec2i;
const Vec2f = vec2.Vec2f;
const Bounds2f = @import("bounds.zig").Bounds2f;
const math = @import("util.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

// Like the PBRT summed area table but padded with zero's as the first row/column
pub const SummedAreaTable = struct {
    dim: Vec2i,
    buffer: [*]f32,

    const Self = @This();

    pub fn init(alloc: Allocator, dim: Vec2i, data: [*]f32) !Self {
        const len: usize = @intCast((dim[0] + 1) * (dim[1] + 1));

        var buffer = (try alloc.alloc(f32, len)).ptr;

        const w = dim[0] + 1;
        const h = dim[1] + 1;

        var x: i32 = 0;
        while (x < w) : (x += 1) {
            buffer[@intCast(x)] = 0.0;
        }

        var y: i32 = 0;
        while (y < h) : (y += 1) {
            buffer[index(0, y, w)] = 0.0;
        }

        buffer[index(1, 1, w)] = data[0];

        // Compute sums along first row and column
        x = 2;
        while (x < w) : (x += 1) {
            buffer[index(x, 1, w)] = data[index(x - 1, 0, w - 1)] + buffer[index(x - 1, 1, w)];
        }

        y = 2;
        while (y < h) : (y += 1) {
            buffer[index(1, y, w)] = data[index(0, y - 1, w - 1)] + buffer[index(1, y - 1, w)];
        }

        // Compute sums for the remainder of the entries
        y = 2;
        while (y < h) : (y += 1) {
            x = 2;
            while (x < w) : (x += 1) {
                buffer[index(x, y, w)] = data[index(x - 1, y - 1, w - 1)] + buffer[index(x - 1, y, w)] + buffer[index(x, y - 1, w)] - buffer[index(x - 1, y - 1, w)];
            }
        }

        return .{ .dim = dim, .buffer = buffer };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        const d = self.dim;
        const len: usize = @intCast((d[0] + 1) * (d[1] + 1));
        if (len > 0) {
            alloc.free(self.buffer[0..len]);
        }
    }

    pub fn integral(self: Self, extent: Bounds2f) f32 {
        const d = self.dim;
        const w = d[0] + 1;
        const fd: Vec2f = @floatFromInt(d);

        const ax = extent.bounds[0][0] * fd[0];
        const ay = extent.bounds[0][1] * fd[1];
        const bx = extent.bounds[1][0] * fd[0];
        const by = extent.bounds[1][1] * fd[1];

        const ax0: i32 = @intFromFloat(ax);
        const ay0: i32 = @intFromFloat(ay);
        const bx0: i32 = @intFromFloat(bx);
        const by0: i32 = @intFromFloat(by);

        const axx0 = @min(ax0, d[0]);
        const ayy0 = @min(ay0, d[1]);
        const axx1 = @min(ax0 + 1, d[0]);
        const ayy1 = @min(ay0 + 1, d[1]);

        const bxx0 = @min(bx0, d[0]);
        const byy0 = @min(by0, d[1]);
        const bxx1 = @min(bx0 + 1, d[0]);
        const byy1 = @min(by0 + 1, d[1]);

        const adx = ax - @as(f32, @floatFromInt(ax0));
        const ady = ay - @as(f32, @floatFromInt(ay0));
        const bdx = bx - @as(f32, @floatFromInt(bx0));
        const bdy = by - @as(f32, @floatFromInt(by0));

        const s =
            (self.lookup(bxx0, bxx1, byy0, byy1, bdx, bdy, w) -
                self.lookup(axx0, axx1, byy0, byy1, adx, bdy, w)) +
            (self.lookup(axx0, axx1, ayy0, ayy1, adx, ady, w) -
                self.lookup(bxx0, bxx1, ayy0, ayy1, bdx, ady, w));

        const area = fd[0] * fd[1];
        return math.max(s / area, 0.0);
    }

    pub fn lookup(self: Self, xx0: i32, xx1: i32, yy0: i32, yy1: i32, dx: f32, dy: f32, w: i32) f32 {
        const v00 = self.buffer[index(xx0, yy0, w)];
        const v10 = self.buffer[index(xx1, yy0, w)];
        const v01 = self.buffer[index(xx0, yy1, w)];
        const v11 = self.buffer[index(xx1, yy1, w)];

        return (1.0 - dx) * (1.0 - dy) * v00 + (1.0 - dx) * dy * v01 + dx * (1.0 - dy) * v10 + dx * dy * v11;
    }

    inline fn index(x: i32, y: i32, w: i32) u32 {
        return @intCast(y * w + x);
    }
};

pub const EvaluatorX = struct {
    sat: SummedAreaTable,
    ay0: i32,
    by0: i32,
    lookup_b: f32,
    lookup_c: f32,
    ady: f32,
    bdy: f32,
    integral_area: f32,

    pub fn init(sat: SummedAreaTable, extent: Bounds2f, integral: f32) EvaluatorX {
        const d = sat.dim;
        const w = d[0] + 1;
        const fd: Vec2f = @floatFromInt(d);

        const ax = extent.bounds[0][0] * fd[0];
        const ay = extent.bounds[0][1] * fd[1];
        const by = extent.bounds[1][1] * fd[1];

        const ax0: i32 = @intFromFloat(ax);
        const ay0: i32 = @intFromFloat(ay);
        const by0: i32 = @intFromFloat(by);

        const axx0 = @min(ax0, d[0]);
        const ayy0 = @min(ay0, d[1]);
        const axx1 = @min(ax0 + 1, d[0]);
        const ayy1 = @min(ay0 + 1, d[1]);

        const byy0 = @min(by0, d[1]);
        const byy1 = @min(by0 + 1, d[1]);

        const adx = ax - @as(f32, @floatFromInt(ax0));
        const ady = ay - @as(f32, @floatFromInt(ay0));
        const bdy = by - @as(f32, @floatFromInt(by0));

        const area = fd[0] * fd[1];

        return .{
            .sat = sat,
            .ay0 = ay0,
            .by0 = by0,
            .lookup_b = sat.lookup(axx0, axx1, byy0, byy1, adx, bdy, w),
            .lookup_c = sat.lookup(axx0, axx1, ayy0, ayy1, adx, ady, w),
            .ady = ady,
            .bdy = bdy,
            .integral_area = integral * area,
        };
    }

    pub fn eval(self: EvaluatorX, x: f32) f32 {
        const d = self.sat.dim;
        const w = d[0] + 1;

        const bx = x * @as(f32, @floatFromInt(d[0]));

        const ay0 = self.ay0;
        const bx0: i32 = @intFromFloat(bx);
        const by0 = self.by0;

        const ayy0 = @min(ay0, d[1]);
        const ayy1 = @min(ay0 + 1, d[1]);

        const bxx0 = @min(bx0, d[0]);
        const byy0 = @min(by0, d[1]);
        const bxx1 = @min(bx0 + 1, d[0]);
        const byy1 = @min(by0 + 1, d[1]);

        const ady = self.ady;
        const bdx = bx - @as(f32, @floatFromInt(bx0));
        const bdy = self.bdy;

        const lookup_a = self.sat.lookup(bxx0, bxx1, byy0, byy1, bdx, bdy, w);
        const lookup_b = self.lookup_b;
        const lookup_c = self.lookup_c;
        const lookup_d = self.sat.lookup(bxx0, bxx1, ayy0, ayy1, bdx, ady, w);

        const s = (lookup_a - lookup_b) + (lookup_c - lookup_d);

        return math.max(s / self.integral_area, 0.0);
    }
};

pub const EvaluatorY = struct {
    sat: SummedAreaTable,
    ax0: i32,
    bx0: i32,
    lookup_c: f32,
    lookup_d: f32,
    adx: f32,
    bdx: f32,
    integral_area: f32,

    pub fn init(sat: SummedAreaTable, extent: Bounds2f, integral: f32) EvaluatorY {
        const d = sat.dim;
        const w = d[0] + 1;
        const fd: Vec2f = @floatFromInt(d);

        const ax = extent.bounds[0][0] * fd[0];
        const ay = extent.bounds[0][1] * fd[1];
        const bx = extent.bounds[1][0] * fd[0];

        const ax0: i32 = @intFromFloat(ax);
        const ay0: i32 = @intFromFloat(ay);
        const bx0: i32 = @intFromFloat(bx);

        const axx0 = @min(ax0, d[0]);
        const ayy0 = @min(ay0, d[1]);
        const axx1 = @min(ax0 + 1, d[0]);
        const ayy1 = @min(ay0 + 1, d[1]);

        const bxx0 = @min(bx0, d[0]);
        const bxx1 = @min(bx0 + 1, d[0]);

        const adx = ax - @as(f32, @floatFromInt(ax0));
        const ady = ay - @as(f32, @floatFromInt(ay0));
        const bdx = bx - @as(f32, @floatFromInt(bx0));

        const area = fd[0] * fd[1];

        return .{
            .sat = sat,
            .ax0 = ax0,
            .bx0 = bx0,
            .lookup_c = sat.lookup(axx0, axx1, ayy0, ayy1, adx, ady, w),
            .lookup_d = sat.lookup(bxx0, bxx1, ayy0, ayy1, bdx, ady, w),
            .adx = adx,
            .bdx = bdx,
            .integral_area = integral * area,
        };
    }

    pub fn eval(self: EvaluatorY, y: f32) f32 {
        const d = self.sat.dim;
        const w = d[0] + 1;

        const by = y * @as(f32, @floatFromInt(d[1]));

        const ax0 = self.ax0;
        const bx0 = self.bx0;
        const by0: i32 = @intFromFloat(by);

        const axx0 = @min(ax0, d[0]);
        const axx1 = @min(ax0 + 1, d[0]);

        const bxx0 = @min(bx0, d[0]);
        const byy0 = @min(by0, d[1]);
        const bxx1 = @min(bx0 + 1, d[0]);
        const byy1 = @min(by0 + 1, d[1]);

        const adx = self.adx;
        const bdx = self.bdx;
        const bdy = by - @as(f32, @floatFromInt(by0));

        const lookup_a = self.sat.lookup(bxx0, bxx1, byy0, byy1, bdx, bdy, w);
        const lookup_b = self.sat.lookup(axx0, axx1, byy0, byy1, adx, bdy, w);
        const lookup_c = self.lookup_c;
        const lookup_d = self.lookup_d;

        const s = (lookup_a - lookup_b) + (lookup_c - lookup_d);

        return math.max(s / self.integral_area, 0.0);
    }
};
