const core = @import("core");
const image = core.image;
const scn = core.scn;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;
const Pack4f = math.Pack4f;
const spectrum = base.spectrum;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Blur = struct {
    radius: i32,

    weights: []f32,

    pub fn init(alloc: Allocator, sigma: f32) !Blur {
        const radius: i32 = @intFromFloat(@ceil(2.0 * sigma));

        const width = 2 * radius + 1;
        const area = width * width;

        const sigma2 = sigma * sigma;

        var weights = try alloc.alloc(f32, @intCast(area));

        const begin = -radius;
        const end = radius;

        var w: u32 = 0;

        var sum: f32 = 0.0;

        var y = begin;
        while (y <= end) : (y += 1) {
            var x = begin;
            while (x <= end) : (x += 1) {
                const fx: f32 = @floatFromInt(x);
                const fy: f32 = @floatFromInt(y);

                const p = (fx * fx + fy * fy) / (2.0 * sigma2);

                const g = @exp(-p);

                weights[w] = g;

                sum += g;
                w += 1;
            }
        }

        // normalize
        for (weights) |*g| {
            g.* /= sum;
        }

        return Blur{ .radius = radius, .weights = weights };
    }

    pub fn deinit(self: *Blur, alloc: Allocator) void {
        alloc.free(self.weights);
    }

    pub fn process(self: Blur, target: *image.Float4, source: core.tx.Texture, scene: *const scn.Scene, begin: u32, end: u32) void {
        const dim = source.description(scene).dimensions;
        const dim2 = Vec2i{ dim[0], dim[1] };
        const width = dim[0];

        var y = begin;
        while (y < end) : (y += 1) {
            const iy: i32 = @intCast(y);

            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const ix: i32 = @intCast(x);

                const color = self.filter(source, dim2, ix, iy, scene);

                const srgb = spectrum.AP1tosRGB(color);

                target.set2D(ix, iy, Pack4f.init4(srgb[0], srgb[1], srgb[2], color[3]));
            }
        }
    }

    fn filter(self: Blur, source: core.tx.Texture, dim: Vec2i, px: i32, py: i32, scene: *const scn.Scene) Vec4f {
        const begin = -self.radius;
        const end = self.radius;

        var result: Vec4f = @splat(0.0);

        var w: u32 = 0;

        var y = begin;
        while (y <= end) : (y += 1) {
            var x = begin;
            while (x <= end) : (x += 1) {
                const sx = std.math.clamp(px + x, 0, dim[0] - 1);
                const sy = std.math.clamp(py + y, 0, dim[1] - 1);

                const weigth: Vec4f = @splat(self.weights[w]);

                w += 1;

                const color = source.get2D_4(sx, sy, scene);

                result += weigth * color;
            }
        }

        return result;
    }
};
