const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Distribution1D = struct {
    pub const Discrete = struct {
        offset: u32,
        pdf: f32,
    };

    pub const Continuous = struct {
        offset: f32,
        pdf: f32,
    };

    integral: f32 = -1.0,
    lut_range: f32 = 0.0,

    size: u32 = 0,
    lut_size: u32 = 0,

    cdf: [*]f32 = undefined,
    lut: [*]u32 = undefined,

    const Self = @This();

    pub fn configure(self: *Self, alloc: Allocator, data: []const f32, lut_bucket_size: u32) !void {
        try self.precomputePdfCdf(alloc, data);

        var lut_size = @as(u32, @intCast(if (0 == lut_bucket_size) data.len / 16 else data.len / lut_bucket_size));
        lut_size = @min(@max(lut_size, 1), self.size);

        try self.initLut(alloc, lut_size);
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        if (self.size > 0) {
            alloc.free(self.lut[0..self.lut_size]);
            alloc.free(self.cdf[0..self.size]);
        }
    }

    pub fn sample(self: Self, r: f32) u32 {
        const bucket = self.map(r);
        const begin = self.lut[bucket];
        return search(self.cdf, begin, self.size - 1, r) - 1;
    }

    pub fn sampleDiscrete(self: Self, r: f32) Discrete {
        const offset = self.sample(r);

        return .{ .offset = offset, .pdf = self.cdf[offset + 1] - self.cdf[offset] };
    }

    pub fn sampleContinuous(self: Self, r: f32) Continuous {
        const offset = self.sample(r);

        const c = self.cdf[offset + 1];
        const v = c - self.cdf[offset];

        if (0.0 == v) {
            return .{ .offset = 0.0, .pdf = 0.0 };
        }

        const t = (c - r) / v;
        const result = (@as(f32, @floatFromInt(offset)) + t) / @as(f32, @floatFromInt(self.size - 1));
        return .{ .offset = result, .pdf = v };
    }

    pub fn pdfI(self: Self, index: u32) f32 {
        return self.cdf[index + 1] - self.cdf[index];
    }

    pub fn pdfF(self: Self, u: f32) f32 {
        const len = self.size;
        const o = @min(@as(u32, @intFromFloat(u * @as(f32, @floatFromInt(len - 1)))), len - 2);

        return self.cdf[o + 1] - self.cdf[o];
    }

    fn precomputePdfCdf(self: *Self, alloc: Allocator, data: []const f32) !void {
        var integral: f32 = 0.0;
        for (data) |d| {
            integral += d;
        }

        if (0.0 == integral) {
            if (0.0 != self.integral) {
                self.cdf = (try alloc.realloc(self.cdf[0..self.size], 2)).ptr;
                self.size = 2;

                self.cdf[0] = 1.0;
                self.cdf[1] = 1.0;
                self.integral = 0.0;
            }

            return;
        }

        if (self.size != data.len + 1) {
            self.cdf = (try alloc.realloc(self.cdf[0..self.size], data.len + 1)).ptr;
            self.size = @intCast(data.len + 1);
        }

        const ii = 1.0 / integral;

        var p: f32 = 0.0;
        self.cdf[0] = 0.0;

        for (data[0 .. data.len - 1], self.cdf[1..data.len]) |d, *cdf| {
            const c = @mulAdd(f32, d, ii, p);
            cdf.* = c;
            p = c;
        }

        self.cdf[data.len] = 1.0;
        self.integral = integral;
    }

    fn initLut(self: *Self, alloc: Allocator, lut_size: u32) !void {
        const padded_lut_size = lut_size + 1;

        if (padded_lut_size != self.lut_size) {
            self.lut = (try alloc.realloc(self.lut[0..self.lut_size], padded_lut_size)).ptr;
            self.lut_size = padded_lut_size;
            self.lut_range = @floatFromInt(lut_size);
        }

        self.lut[0] = 1;

        var border: u32 = 0;
        for (self.cdf[1..self.size], 1..) |cdf, i| {
            const mapped = self.map(cdf);
            if (mapped > border) {
                const last: u32 = @intCast(i);

                for (self.lut[border + 1 .. mapped + 1]) |*lut| {
                    lut.* = last;
                }

                border = mapped;
            }
        }
    }

    fn map(self: Self, s: f32) u32 {
        return @intFromFloat(s * self.lut_range);
    }

    fn search(buffer: [*]const f32, begin: u32, end: u32, key: f32) u32 {
        for (buffer[begin..end], begin..) |b, i| {
            if (b >= key) {
                return @intCast(i);
            }
        }

        return end;
    }
};
