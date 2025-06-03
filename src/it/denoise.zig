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
    radius_r: i32,
    radius_d: i32,

    sigma_r: f32,

    sigma_d: f32,
    norm_d: f32,

    weights_r: []f32,
    weights_d: []f32,

    const Self = @This();

    pub fn init(alloc: Allocator, sigma_r: f32, sigma_d: f32) !Self {
        const radius_r: i32 = @intFromFloat(@ceil(3.0 * sigma_r));

        const width_r = 2 * radius_r + 1;
        const area_r = width_r * width_r;

        var weights_r = try alloc.alloc(f32, @intCast(area_r));

        {
            const sigma2 = sigma_r * sigma_r;

            const begin = -radius_r;
            const end = radius_r;

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

                    weights_r[w] = g;

                    sum += g;
                    w += 1;
                }
            }

            // normalize
            for (weights_r) |*g| {
                g.* /= sum;
            }
        }

        const radius_d: i32 = @intFromFloat(@ceil(3.0 * sigma_d));

        const width_d = 2 * radius_d + 1;
        const area_d = width_d * width_d;

        var weights_d = try alloc.alloc(f32, @intCast(area_d));

        var norm_d: f32 = undefined;

        {
            const sigma2 = sigma_d * sigma_d;

            const begin = -radius_d;
            const end = radius_d;

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

                    weights_d[w] = g;

                    sum += g;
                    w += 1;
                }
            }

            // normalize
            // for (weights_d) |*g| {
            //     g.* /= sum;
            // }

            // for (weights_d) |g| {
            //     std.debug.print("{}\n", .{g});
            // }

            norm_d = 1.0 / sum;
        }

        return Self{
            .radius_r = radius_r,
            .radius_d = radius_d,
            .sigma_r = sigma_r,
            .sigma_d = sigma_d,
            .norm_d = norm_d,
            .weights_r = weights_r,
            .weights_d = weights_d,
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.weights_r);
        alloc.free(self.weights_d);
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
        const dim = source.dimensions(scene);
        const dim2 = Vec2i{ dim[0], dim[1] };
        const width = dim[0];

        var y = begin;
        while (y < end) : (y += 1) {
            const iy: i32 = @intCast(y);

            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const ix: i32 = @intCast(x);

                const color = self.filter(source, normal, albedo, depth, dim2, ix, iy, scene);

                // _ = depth;
                // const color = self.alternativeFilter(source, normal, albedo, dim2, ix, iy, scene);

                const srgb = spectrum.AP1tosRGB(color);

                target.set2D(ix, iy, Pack4f.init4(srgb[0], srgb[1], srgb[2], 1.0));
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
        const begin = -self.radius_r;
        const end = self.radius_r;

        const ref_color = source.image2D_3(px, py, scene);
        const ref_n = normal.image2D_3(px, py, scene);
        const ref_albedo = albedo.image2D_3(px, py, scene);
        const ref_depth = depth.image2D_1(px, py, scene);

        const noise_estimate = estimateNoise(source, dim, px, py, scene);

        // const ref_l = std.math.pow(f32, math.hmax3(ref_color), 1.0 / 2.2);

        const depth_dx = math.max(1.0 / 512.0, math.min(@abs(depth.image2D_1(@min(px + 1, dim[0]), py, scene) - ref_depth), @abs(depth.image2D_1(@max(px - 1, 0), py, scene) - ref_depth)));
        const depth_dy = math.max(1.0 / 512.0, math.min(@abs(depth.image2D_1(px, @min(py + 1, dim[1]), scene) - ref_depth), @abs(depth.image2D_1(px, @max(py - 1, 0), scene) - ref_depth)));

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

                const weigth: Vec4f = @splat(self.weights_r[w]);

                w += 1;

                const f_depth = depth.image2D_1(sx, sy, scene);

                const depth_dist = @abs(ref_depth - f_depth);
                //  const expected_depth_dist = @sqrt(@abs(fx * depth_dx) + @abs(fy * depth_dy));
                //   const expected_depth_dist = math.length2(.{ fx * depth_dx, fy * depth_dy });
                const expected_depth_dist = fx * depth_dx + fy * depth_dy;

                const f_n = normal.image2D_3(sx, sy, scene);
                const f_albedo = albedo.image2D_3(sx, sy, scene);

                const dot_n = math.saturate(math.dot3(ref_n, f_n));

                const dist_albedo = math.min(math.distance3(ref_albedo, f_albedo), 1.0);

                var dd: f32 = if (depth_dist > expected_depth_dist) expected_depth_dist / depth_dist else 1.0;
                dd = 1.0;

                const strength = @as(Vec4f, @splat(dd * (dot_n * dot_n) * (1.0 - dist_albedo) * noise_estimate));

                const color = math.lerp(ref_color, source.image2D_3(sx, sy, scene), strength);

                // const color = strength; //math.lerp(ref_color, source.image2D_3(sx, sy, scene), strength);

                result += weigth * color;
            }
        }

        return result;
    }

    fn alternativeFilter(
        self: Self,
        source: Texture,
        normal: Texture,
        albedo: Texture,
        dim: Vec2i,
        px: i32,
        py: i32,
        scene: *const scn.Scene,
    ) Vec4f {
        const begin = -self.radius_d;
        const end = self.radius_d;

        //   const ref_color = source.get2D_4(px, py, scene);

        const expected_color = self.filter_d(source, dim, px, py, scene);

        const expected_l = std.math.pow(f32, math.hmax3(expected_color), 1.0 / 2.2);

        _ = normal;
        _ = albedo;
        // const ref_n = normal.image2D_3(px, py, scene);
        // const ref_albedo = albedo.image2D_3(px, py, scene);

        var result: Vec4f = @splat(0.0);

        var w: u32 = 0;

        var sum: f32 = 0.0;

        var y = begin;
        while (y <= end) : (y += 1) {
            var x = begin;

            while (x <= end) : (x += 1) {
                const sx = std.math.clamp(px + x, 0, dim[0] - 1);
                const sy = std.math.clamp(py + y, 0, dim[1] - 1);

                const f_color = source.get2D_4(sx, sy, scene);

                const c = self.weights_d[w];
                //   const c: f32 = 1.0;

                //    std.debug.print("{}\n", .{c});

                const weigth_d: Vec4f = @splat(c);

                const f_l = std.math.pow(f32, math.hmax3(f_color), 1.0 / 2.2);

                // const f_l: f32 = 10.0;

                // const d_l = expected_l - f_l;
                //  const range = 1.0 - math.min(@sqrt(@abs(d_l)), 1.0); // gauss(expected_l, f_l, self.sigma_r);

                const range = gauss(expected_l, f_l, self.sigma_r);

                //   const range: f32 = if (0 == x and 0 == y) 1.0 else 0.0001;

                //   std.debug.print("{} {} {}\n", .{ expected_l, f_l, range });

                sum += c * range;

                result += f_color * weigth_d * @as(Vec4f, @splat(range));

                // const weigth_r: Vec4f = @splat(self.weights_r[w]);

                w += 1;

                // const f_n = normal.image2D_3(sx, sy, scene);
                // const f_albedo = albedo.image2D_3(sx, sy, scene);

                // const dot_n = math.max(math.dot3(ref_n, f_n), 0.0);

                // const dist_albedo = math.min(math.distance3(ref_albedo, f_albedo), 1.0);

                // const strength = @as(Vec4f, @splat(dot_n * (1.0 - dist_albedo)));

                // const color = math.lerp(ref_color, source.get2D_4(sx, sy, scene), strength);

                // result += weigth_r * color;

            }
        }

        return result / @as(Vec4f, @splat(sum));
    }

    fn gauss(a: f32, b: f32, sigma: f32) f32 {
        const d = a - b;
        const p = (d * d) / (2.0 * (sigma * sigma));

        const g = @exp(-p);

        return g;
    }

    fn filter_d(
        self: Self,
        source: Texture,
        dim: Vec2i,
        px: i32,
        py: i32,
        scene: *const scn.Scene,
    ) Vec4f {
        const begin = -self.radius_d;
        const end = self.radius_d;

        var result: Vec4f = @splat(0.0);

        var w: u32 = 0;

        var y = begin;
        while (y <= end) : (y += 1) {
            var x = begin;
            while (x <= end) : (x += 1) {
                const sx = std.math.clamp(px + x, 0, dim[0] - 1);
                const sy = std.math.clamp(py + y, 0, dim[1] - 1);

                const weigth: Vec4f = @splat(self.weights_d[w]);

                w += 1;

                const color = source.get2D_4(sx, sy, scene);

                result += weigth * color;
            }
        }

        return result * @as(Vec4f, @splat(self.norm_d));
    }

    fn estimateNoise(
        //self: Self,
        source: Texture,
        dim: Vec2i,
        px: i32,
        py: i32,
        scene: *const scn.Scene,
    ) f32 {
        const Radius: i32 = 1;

        const begin = -Radius;
        const end = Radius;

        // const ref_color = source.image2D_3(px, py, scene);
        // const ref_l = std.math.pow(f32, math.hmax3(ref_color), 1.0 / 2.2);

        var sum: f32 = 0.0;

        var y = begin;
        while (y <= end) : (y += 1) {
            var x = begin;

            while (x <= end) : (x += 1) {
                const sx = std.math.clamp(px + x, 0, dim[0] - 1);
                const sy = std.math.clamp(py + y, 0, dim[1] - 1);

                const color = source.image2D_3(sx, sy, scene);
                const l = std.math.pow(f32, math.hmax3(color), 1.0 / 2.2);

                sum += l;
            }
        }

        const width = 2 * Radius + 1;
        const norm: f32 = 1.0 / (@as(f32, @floatFromInt(width * width)));

        const mean = sum * norm;

        var dif_sum: f32 = 0.0;

        y = begin;
        while (y <= end) : (y += 1) {
            var x = begin;

            while (x <= end) : (x += 1) {
                const sx = std.math.clamp(px + x, 0, dim[0] - 1);
                const sy = std.math.clamp(py + y, 0, dim[1] - 1);

                const color = source.image2D_3(sx, sy, scene);
                const l = std.math.pow(f32, math.hmax3(color), 1.0 / 2.2);

                const dif = (l - mean);

                dif_sum += dif * dif;
            }
        }

        // const before = norm * dif_sum;
        // const after = @sqrt(before / (if (ma > 0.0) ma else 1.0));

        // std.debug.print("{} {}\n", .{ before, after });

        const std_dev = @sqrt(norm * dif_sum);

        const coef = if (mean > 0.0) std_dev / mean else 0.0;

        return math.min(coef * 20.0 * math.min(mean, 1.0), 1.0);
    }
};
