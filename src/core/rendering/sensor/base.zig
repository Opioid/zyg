const Tonemapper = @import("tonemapper.zig").Tonemapper;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const Allocator = @import("std").mem.Allocator;

pub const Base = struct {
    dimensions: Vec2i = @splat(2, @as(i32, 0)),

    max: f32,

    tonemapper: Tonemapper = Tonemapper.init(.Linear, 0.0),

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

    pub fn diluteErrorEstimate(self: *Base, threads: *Threads) void {
        _ = threads.runRange(self, diluteErrorEstimateRange, 0, @intCast(u32, self.dimensions[1]), 0);
    }

    fn diluteErrorEstimateRange(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;

        const self = @intToPtr(*Base, context);

        const d = self.dimensions;

        var y = @intCast(i32, begin);
        while (y < end) : (y += 1) {
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

    pub fn clamp(self: Base, color: Vec4f) Vec4f {
        const mc = math.maxComponent3(color);

        if (mc > self.max) {
            const r = self.max / mc;
            const s = @splat(4, r) * color;
            return .{ s[0], s[1], s[2], color[3] };
        }

        return color;
    }
};
