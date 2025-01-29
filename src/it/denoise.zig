const core = @import("core");
const Texture = core.tx.Texture;
const image = core.image;
const scn = core.scn;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Pack4f = math.Pack4f;
const spectrum = base.spectrum;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Denoise = struct {
    radius: i32,

    weights: []f32,

    const Self = @This();

    pub fn init(alloc: Allocator, sigma: f32) !Self {
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

        return Self{ .radius = radius, .weights = weights };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.weights);
    }

    pub fn process(
        self: Self,
        target: *image.Float4,
        source: Texture,
        normal: Texture,
        albedo: Texture,
        depth: Texture,
        scene: *const scn.Scene,
        begin: u32,
        end: u32,
    ) void {
        const dim = source.description(scene).dimensions;
        const dim2 = Vec2i{ dim[0], dim[1] };
        const width = dim[0];

        var y = begin;
        while (y < end) : (y += 1) {
            const iy: i32 = @intCast(y);

            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const ix: i32 = @intCast(x);

                const color = self.filter(source, normal, albedo, depth, dim2, ix, iy, scene);

                const srgb = spectrum.AP1tosRGB(color);

                target.set2D(ix, iy, Pack4f.init4(srgb[0], srgb[1], srgb[2], color[3]));
            }
        }
    }

    fn filter(
        self: Self,
        source: Texture,
        normal: Texture,
        albedo: Texture,
        depth: Texture,
        dim: Vec2i,
        px: i32,
        py: i32,
        scene: *const scn.Scene,
    ) Vec4f {
        const begin = -self.radius;
        const end = self.radius;

        const ref_color = source.get2D_4(px, py, scene);
        const ref_n = normal.get2D_3(px, py, scene);
        const ref_albedo = albedo.get2D_3(px, py, scene);
        const ref_depth = depth.get2D_1(px, py, scene);

        const depth_dx = math.max(1.0 / 512.0, math.min(@abs(depth.get2D_1(@min(px + 1, dim[0]), py, scene) - ref_depth), @abs(depth.get2D_1(@max(px - 1, 0), py, scene) - ref_depth)));
        const depth_dy = math.max(1.0 / 512.0, math.min(@abs(depth.get2D_1(px, @min(py + 1, dim[1]), scene) - ref_depth), @abs(depth.get2D_1(px, @max(py - 1, 0), scene) - ref_depth)));

        var result: Vec4f = @splat(0.0);

        var w: u32 = 0;

        var y = begin;
        while (y <= end) : (y += 1) {
            const fy: f32 = @floatFromInt(@abs(y));

            var x = begin;

            while (x <= end) : (x += 1) {
                const fx: f32 = @floatFromInt(@abs(x));

                const sx = std.math.clamp(px + x, 0, dim[0] - 1);
                const sy = std.math.clamp(py + y, 0, dim[1] - 1);

                const weigth: Vec4f = @splat(self.weights[w]);

                w += 1;

                const f_depth = depth.get2D_1(sx, sy, scene);

                const depth_dist = @abs(ref_depth - f_depth);
                //  const expected_depth_dist = @sqrt(@abs(fx * depth_dx) + @abs(fy * depth_dy));
                //   const expected_depth_dist = math.length2(.{ fx * depth_dx, fy * depth_dy });
                const expected_depth_dist = fx * depth_dx + fy * depth_dy;

                const f_n = normal.get2D_3(sx, sy, scene);
                const f_albedo = albedo.get2D_3(sx, sy, scene);

                const dot_n = math.max(math.dot3(ref_n, f_n), 0.0);

                const dist_albedo = math.min(math.distance3(ref_albedo, f_albedo), 1.0);

                const dd: f32 = if (depth_dist > expected_depth_dist) expected_depth_dist / depth_dist else 1.0;

                const color = math.lerp(ref_color, source.get2D_4(sx, sy, scene), @as(Vec4f, @splat(dd * dot_n * (1.0 - dist_albedo))));

                result += weigth * color;
            }
        }

        return result;
    }
};
