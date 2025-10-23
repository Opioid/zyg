const SummedAreaTable = @import("summed_area_table.zig").SummedAreaTable;
const Continuous = @import("distribution_2d.zig").Distribution2D.Continuous;
const vec2 = @import("vector2.zig");
const Vec2i = vec2.Vec2i;
const Vec2f = vec2.Vec2f;
const Bounds2f = @import("bounds.zig").Bounds2f;
const util = @import("util.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const WindowedDistribution2D = struct {
    sat: SummedAreaTable,

    func: []f32,

    const Self = @This();

    pub fn init(alloc: Allocator, dim: Vec2i, data: []f32) !Self {
        return .{ .sat = try .init(alloc, dim, data.ptr), .func = data };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.func);
        self.sat.deinit(alloc);
    }

    const CDFX = struct {
        b: Bounds2f,
        sat: SummedAreaTable,
        int: f32,

        pub fn eval(self: CDFX, x: f32) f32 {
            var bx = self.b;
            bx.bounds[1][0] = x;
            return self.sat.integral(bx) / self.int;
        }
    };

    const CDFY = struct {
        b: Bounds2f,
        sat: SummedAreaTable,
        int: f32,

        pub fn eval(self: CDFY, y: f32) f32 {
            var by = self.b;
            by.bounds[1][1] = y;
            return self.sat.integral(by) / self.int;
        }
    };

    pub fn sampleContinuous(self: Self, r2: Vec2f, b: Bounds2f) Continuous {
        const int = self.sat.integral(b);
        if (0.0 == int) {
            return .{ .uv = undefined, .pdf = 0.0 };
        }

        const cdfx = CDFX{ .b = b, .sat = self.sat, .int = int };

        var p: Vec2f = undefined;
        p[0] = sampleBisection(cdfx, r2[0], b.bounds[0][0], b.bounds[1][0], self.sat.dim[0]);

        const nx: f32 = @floatFromInt(self.sat.dim[0]);
        var bcond = Bounds2f.init(
            .{ @floor(p[0] * nx) / nx, b.bounds[0][1] },
            .{ @ceil(p[0] * nx) / nx, b.bounds[1][1] },
        );

        if (bcond.bounds[0][0] == bcond.bounds[1][0]) {
            bcond.bounds[1][0] += 1.0 / nx;
        }

        const cond_int = self.sat.integral(bcond);
        if (0.0 == cond_int) {
            return .{ .uv = undefined, .pdf = 0.0 };
        }

        const cdfy = CDFY{ .b = bcond, .sat = self.sat, .int = cond_int };

        p[1] = sampleBisection(cdfy, r2[1], b.bounds[0][1], b.bounds[1][1], self.sat.dim[1]);

        return .{ .uv = p, .pdf = self.eval(p) / int };
    }

    pub fn pdf(self: Self, p: Vec2f, b: Bounds2f) f32 {
        const int = self.sat.integral(b);
        if (0.0 == int) {
            return 0.0;
        }

        return self.eval(p) / int;
    }

    fn sampleBisection(cdf: anytype, u: f32, imin: f32, imax: f32, n: i32) f32 {
        const nf: f32 = @floatFromInt(n);

        var min = imin;
        var max = imax;
        while (@ceil(nf * max) - @floor(nf * min) > 1.0) {
            const mid = (min + max) / 2.0;
            if (cdf.eval(mid) > u) {
                max = mid;
            } else {
                min = mid;
            }
        }

        const pmin = cdf.eval(min);
        const pmax = cdf.eval(max);

        const t = (u - pmin) / (pmax - pmin);
        return util.clamp(util.lerp(min, max, t), min, max);
    }

    fn eval(self: Self, uv: Vec2f) f32 {
        const d = self.sat.dim;
        const w: u32 = @intCast(d[0]);

        const x: u32 = @intFromFloat(uv[0] * @as(f32, @floatFromInt(d[0])));
        const cx = @min(x, w - 1);

        const y: u32 = @intFromFloat(uv[1] * @as(f32, @floatFromInt(d[1])));
        const cy = @min(y, @as(u32, @intCast(d[1] - 1)));

        return self.func[cy * w + cx];
    }
};
