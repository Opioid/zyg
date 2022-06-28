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
        try self.precompute1DPdfCdf(alloc, data);

        var lut_size = @intCast(u32, if (0 == lut_bucket_size) data.len / 16 else data.len / lut_bucket_size);
        lut_size = std.math.min(std.math.max(lut_size, 1), self.size);

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
        const it = search(self.cdf, begin, self.size - 1, r);

        return if (0 == it) 0 else it - 1;
    }

    pub fn sampleDiscrete(self: Self, r: f32) Discrete {
        const offset = self.sample(r);

        return .{ .offset = offset, .pdf = self.cdf[offset + 1] - self.cdf[offset] };
    }

    pub fn sampleContinous(self: Self, r: f32) Continuous {
        const offset = self.sample(r);

        const c = self.cdf[offset + 1];
        const v = c - self.cdf[offset];

        if (0.0 == v) {
            return .{ .offset = 0.0, .pdf = 0.0 };
        }

        const t = (c - r) / v;
        const result = (@intToFloat(f32, offset) + t) / @intToFloat(f32, self.size - 1);
        return .{ .offset = result, .pdf = v };
    }

    pub fn pdfI(self: Self, index: u32) f32 {
        return self.cdf[index + 1] - self.cdf[index];
    }

    pub fn pdfF(self: Self, u: f32) f32 {
        const len = self.size;
        const o = std.math.min(@floatToInt(u32, u * @intToFloat(f32, len - 1)), len - 2);

        return self.cdf[o + 1] - self.cdf[o];
    }

    fn precompute1DPdfCdf(self: *Self, alloc: Allocator, data: []const f32) !void {
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
            self.size = @intCast(u32, data.len + 1);
        }

        const ii = 1.0 / integral;

        self.cdf[0] = 0.0;
        var i: usize = 1;
        while (i < data.len) : (i += 1) {
            self.cdf[i] = @mulAdd(f32, data[i - 1], ii, self.cdf[i - 1]);
        }
        self.cdf[data.len] = 1.0;
        self.integral = integral;
    }

    fn initLut(self: *Self, alloc: Allocator, lut_size: u32) !void {
        const padded_lut_size = lut_size + 1;

        if (padded_lut_size != self.lut_size) {
            self.lut = (try alloc.realloc(self.lut[0..self.lut_size], padded_lut_size)).ptr;
            self.lut_size = padded_lut_size;
            self.lut_range = @intToFloat(f32, lut_size);
        }

        self.lut[0] = 0;

        var border: u32 = 0;
        var last: u32 = 0;

        const len = self.size;
        var i: u32 = 1;
        while (i < len) : (i += 1) {
            const mapped = self.map(self.cdf[i]);
            if (mapped > border) {
                last = i;

                var j = border + 1;
                while (j <= mapped) : (j += 1) {
                    self.lut[j] = last;
                }

                border = mapped;
            }
        }
    }

    fn map(self: Self, s: f32) u32 {
        return @floatToInt(u32, s * self.lut_range);
    }

    pub fn staticSampleDiscrete(comptime N: u32, data: [N]f32, integral: f32, n: u32, r: f32) Distribution1D.Discrete {
        const ii = 1.0 / integral;

        var cdf: [N + 1]f32 = undefined;

        cdf[0] = 0.0;
        var i: u32 = 1;
        while (i < N) : (i += 1) {
            cdf[i] = @mulAdd(f32, data[i - 1], ii, cdf[i - 1]);
        }
        cdf[N] = 1.0;

        const it = search(&cdf, 0, n, r);
        const offset = if (0 != it) it - 1 else 0;

        return .{ .offset = offset, .pdf = cdf[offset + 1] - cdf[offset] };
    }

    pub fn staticPdf(comptime N: u32, data: [N]f32, integral: f32, index: u32) f32 {
        const ii = 1.0 / integral;

        var cdf: [N + 1]f32 = undefined;

        cdf[0] = 0.0;
        var i: u32 = 1;
        while (i < N) : (i += 1) {
            cdf[i] = @mulAdd(f32, data[i - 1], ii, cdf[i - 1]);
        }
        cdf[N] = 1.0;

        return cdf[index + 1] - cdf[index];
    }
};

pub fn Distribution1DN(comptime N: u32) type {
    return struct {
        integral: f32 = -1.0,

        cdf: [N + 1]f32 = undefined,

        const Self = @This();

        const Num_samples = N;

        pub fn configure(self: *Self, data: [N]f32) void {
            var integral: f32 = 0.0;
            for (data) |d| {
                integral += d;
            }

            const ii = 1.0 / integral;

            self.cdf[0] = 0.0;
            var i: usize = 1;
            while (i < data.len) : (i += 1) {
                self.cdf[i] = @mulAdd(f32, data[i - 1], ii, self.cdf[i - 1]);
            }
            self.cdf[data.len] = 1.0;
            self.integral = integral;
        }

        pub fn sampleContinous(self: Self, r: f32) Distribution1D.Continuous {
            const offset = self.sample(r);

            const c = self.cdf[offset + 1];
            const v = c - self.cdf[offset];

            if (0.0 == v) {
                return .{ .offset = 0.0, .pdf = 0.0 };
            }

            const t = (c - r) / v;
            const result = (@intToFloat(f32, offset) + t) / @intToFloat(f32, N);
            return .{ .offset = result, .pdf = v };
        }

        fn sample(self: Self, r: f32) u32 {
            const it = search(&self.cdf, 0, N, r);
            return if (0 == it) 0 else it - 1;
        }
    };
}

fn search(buffer: [*]const f32, begin: u32, end: u32, key: f32) u32 {
    for (buffer[begin..end]) |b, i| {
        if (b >= key) {
            return begin + @intCast(u32, i);
        }
    }

    return end;
}
