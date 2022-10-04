const img = @import("../image/image.zig");

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;
const Pack4f = math.Pack4f;
const Vec4f = math.Vec4f;
const enc = base.encoding;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Shaper = struct {
    dimensions: Vec2i,

    pixels: []Pack4f = &.{},

    const Sub_samples = 4;

    const Self = Shaper;

    pub fn init(alloc: Allocator, dimensions: Vec2i) !Self {
        const len = @intCast(usize, dimensions[0] * dimensions[1]);
        return Self{
            .dimensions = dimensions,
            .pixels = try alloc.alloc(Pack4f, len),
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.pixels);
    }

    pub fn resolve(self: Self, comptime T: type, image: *T) void {
        const dim = self.dimensions;
        const len = @minimum(@intCast(usize, dim[0] * dim[1]), image.description.numPixels());

        const source = self.pixels;

        if (img.Byte1 == T) {
            var i: usize = 0;
            while (i < len) : (i += 1) {
                const p = source[i];
                image.pixels[i] = enc.floatToUnorm(std.math.clamp(p.v[3], 0.0, 1.0));
            }
        } else if (img.Float3 == T) {
            var i: usize = 0;
            while (i < len) : (i += 1) {
                const p = source[i];
                image.pixels[i] = Pack3f.init3(p.v[0], p.v[1], p.v[2]);
            }
        }
    }

    pub fn clear(self: *Self) void {
        for (self.pixels) |*p| {
            p.* = Pack4f.init1(0.0);
        }
    }

    const Circle = struct {
        radius2: f32,
    };

    const Aperture = struct {
        blades: u32,
        radius: f32,
        roundness: f32,
        rotation: f32,
    };

    const ApertureN = struct {
        pub const Plane = struct {
            n: Vec2f,
            d: f32,
        };

        blades: u32,
        radius: f32,
        roundness: f32,
        planes: [8]Plane = undefined,

        pub fn init(blades: u32, r: f32, roundness: f32, rot: f32) ApertureN {
            var aperture = ApertureN{
                .blades = blades,
                .radius = r,
                .roundness = roundness,
            };

            const delta = (2.0 * std.math.pi) / @intToFloat(f32, blades);

            var b = Vec2f{ @sin(rot), @cos(rot) };

            var i: u32 = 0;
            while (i < blades) : (i += 1) {
                const angle = @intToFloat(f32, i + 1) * delta + rot;
                const c = Vec2f{ @sin(angle), @cos(angle) };

                const cb = c - b;
                const n = math.normalize2(.{ cb[1], -cb[0] });
                const d = math.dot2(n, b);

                aperture.planes[i] = .{ .n = n, .d = d };

                b = c;
            }

            return aperture;
        }
    };

    const Shape = union(enum) {
        Circle: Circle,
        Aperture: Aperture,
        ApertureN: ApertureN,
    };

    pub fn drawCircle(self: *Self, p: Vec2f, r: f32) void {
        const circle = Shape{ .Circle = .{ .radius2 = r * r } };
        self.drawShape(p, circle);
    }

    pub fn drawAperture(self: *Self, p: Vec2f, n: u32, r: f32, roundness: f32, rot: f32) void {
        if (n <= 8) {
            const aperture = Shape{ .ApertureN = ApertureN.init(n, r, roundness, rot) };
            self.drawShape(p, aperture);
        } else {
            const aperture = Shape{ .Aperture = .{
                .blades = n,
                .radius = r,
                .roundness = roundness,
                .rotation = rot,
            } };
            self.drawShape(p, aperture);
        }
    }

    fn drawShape(self: *Self, p: Vec2f, shape: Shape) void {
        const dim = self.dimensions;
        const end_x = @intToFloat(f32, dim[0]);
        const end_y = @intToFloat(f32, dim[1]);
        const ss = 1.0 / @intToFloat(f32, Sub_samples);
        const ssx = ss / end_x;
        const ssy = ss / end_y;
        const so = 0.5 * ss;
        const ss2 = 1.0 / @intToFloat(f32, Sub_samples * Sub_samples);

        var y: i32 = 0;
        while (y < dim[1]) : (y += 1) {
            var x: i32 = 0;
            while (x < dim[0]) : (x += 1) {
                var w: f32 = 0.0;

                var v = (@intToFloat(f32, y) + so) / end_y;

                var sy: i32 = 0;
                while (sy < Sub_samples) : (sy += 1) {
                    var u = (@intToFloat(f32, x) + so) / end_x;

                    var sx: i32 = 0;
                    while (sx < Sub_samples) : (sx += 1) {
                        if (intersect(u, v, p, shape) or
                            intersect(u - 1.0, v, p, shape) or
                            intersect(u, v - 1.0, p, shape) or
                            intersect(u - 1.0, v - 1.0, p, shape) or
                            intersect(u + 1.0, v, p, shape) or
                            intersect(u, v + 1.0, p, shape) or
                            intersect(u + 1.0, v + 1.0, p, shape) or
                            intersect(u - 1.0, v + 1.0, p, shape) or
                            intersect(u + 1.0, v - 1.0, p, shape))
                        {
                            w += ss2;
                        }

                        u += ssx;
                    }

                    v += ssy;
                }

                if (w > 0.0) {
                    self.pixels[@intCast(usize, y * dim[0] + x)] = Pack4f.init1(w);
                }
            }
        }
    }

    fn intersect(u: f32, v: f32, p: Vec2f, shape: Shape) bool {
        const uv = Vec2f{ u, v };
        const center = uv - p;

        switch (shape) {
            .Circle => |s| {
                const d2 = math.dot2(center, center);
                return d2 <= s.radius2;
            },
            .Aperture => |s| {
                const radius = s.radius;
                const lc = math.length2(center);

                if (lc > radius) {
                    return false;
                }

                const blades = s.blades;
                const delta = (2.0 * std.math.pi) / @intToFloat(f32, blades);

                const rot = s.rotation;
                var b = Vec2f{ @sin(rot), @cos(rot) };

                var mt: f32 = 0.0;
                var i: u32 = 0;
                while (i < blades) : (i += 1) {
                    const angle = @intToFloat(f32, i + 1) * delta + rot;
                    const c = Vec2f{ @sin(angle), @cos(angle) };

                    const cb = c - b;
                    const n = math.normalize2(.{ cb[1], -cb[0] });
                    const d = math.dot2(n, b);
                    const t = math.dot2(n, center) / d;
                    mt = std.math.max(mt, t);

                    b = c;
                }

                return math.lerp(mt, lc, s.roundness) <= radius;
            },
            .ApertureN => |s| {
                const radius = s.radius;
                const lc = math.length2(center);

                if (lc > radius) {
                    return false;
                }

                var mt: f32 = 0.0;
                for (s.planes[0..s.blades]) |b| {
                    const t = math.dot2(b.n, center) / b.d;
                    mt = std.math.max(mt, t);
                }

                return math.lerp(mt, lc, s.roundness) <= radius;
            },
        }
    }
};
