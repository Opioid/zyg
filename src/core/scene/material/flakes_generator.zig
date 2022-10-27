const img = @import("../../image/image.zig");
const tx = @import("../../image/texture/texture_provider.zig");
const Texture = tx.Texture;
const Resources = @import("../../resource/manager.zig").Manager;
const Shaper = @import("../../rendering/shaper.zig").Shaper;
const ggx = @import("ggx.zig");
const Frame = @import("sample_base.zig").Frame;
const Substitute = @import("substitute/sample.zig").Sample;

const PngWriter = @import("../../image/encoding/png/png_writer.zig").Writer;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Generator = struct {
    pub const Result = struct {
        normal: Texture,
        mask: Texture,
    };

    pub fn generate(
        alloc: Allocator,
        flakes_size: f32,
        flakes_coverage: f32,
        flakes_roughness: f32,
        resources: *Resources,
    ) !Result {
        const texture_scale: f32 = 8.0;
        const adjusted_scale = texture_scale * flakes_size;
        const flakes_radius = adjusted_scale / 2.0;
        const num_flakes = @floatToInt(u32, @ceil(flakes_coverage / (adjusted_scale * adjusted_scale)));

        var shaper = try Shaper.init(alloc, @splat(2, @as(u32, 2048)));
        defer shaper.deinit(alloc);

        shaper.clear(.{ 0.0, 0.0, 1.0, 0.0 });

        // var rng = RNG.init(0, 0);

        // var i: u32 = 0;
        // while (i < num_flakes) : (i += 1) {
        //     const uv = math.hammersley(i, num_flakes, 0);

        //     const st = Vec2f{ rng.randomFloat(), rng.randomFloat() };
        //     var n = math.smpl.hemisphereUniform(st);
        //     n = math.normalize3(math.lerp4(n, .{ 0.0, 0.0, 1.0, 0.0 }, 0.75));
        //     n[3] = 1.0;

        //     //   shaper.drawCircle(n, uv, flakes_radius);

        //     shaper.drawAperture(n, uv, 6, flakes_radius, 0.0, (2.0 * std.math.pi) * rng.randomFloat());
        // }

        {
            const r = ggx.clampRoughness(flakes_roughness);
            const alpha = r * r;
            const dist = alpha - Substitute.flakesA2cone(alpha);

            var context = Context{
                .shaper = &shaper,
                .num_flakes = num_flakes,
                .flakes_radius = flakes_radius,
                .flakes_alpha = dist,
            };

            resources.threads.waitAsync();
            _ = resources.threads.runRange(&context, Context.render, 0, num_flakes, 0);
        }

        // var normal_view = try img.Float3.init(alloc, img.Description.init2D(shaper.dimensions));
        // defer normal_view.deinit(alloc);
        // shaper.resolve(img.Float3, &normal_view);
        // try PngWriter.writeFloat3Normal(alloc, normal_view);

        var normal_image = try img.Byte2.init(alloc, img.Description.init2D(shaper.dimensions));
        errdefer normal_image.deinit(alloc);
        shaper.resolve(img.Byte2, &normal_image);
        const normal_id = try resources.images.store(alloc, 0xFFFFFFFF, .{ .Byte2 = normal_image });
        const normal = try tx.Provider.createTexture(normal_id, .Normal, @splat(2, texture_scale), resources);

        var mask_image = try img.Byte1.init(alloc, img.Description.init2D(shaper.dimensions));
        errdefer mask_image.deinit(alloc);
        shaper.resolve(img.Byte1, &mask_image);
        const mask_id = try resources.images.store(alloc, 0xFFFFFFFF, .{ .Byte1 = mask_image });
        const mask = try tx.Provider.createTexture(mask_id, .Opacity, @splat(2, texture_scale), resources);

        return Result{ .normal = normal, .mask = mask };
    }
};

const Context = struct {
    shaper: *Shaper,
    num_flakes: u32,
    flakes_radius: f32,
    flakes_alpha: f32,

    pub fn render(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;
        const self = @intToPtr(*Context, context);

        var shaper = self.shaper;

        const num_flakes = self.num_flakes;
        const radius = self.flakes_radius;
        const alpha = @splat(2, self.flakes_alpha);

        const frame = Frame{
            .t = .{ 1.0, 0.0, 0.0, 0.0 },
            .b = .{ 0.0, 1.0, 0.0, 0.0 },
            .n = .{ 0.0, 0.0, 1.0, 0.0 },
        };

        const wo = frame.n;

        var i = begin;
        while (i < end) : (i += 1) {
            var rng = RNG.init(0, i);

            const uv = math.hammersley(i, num_flakes, 0);

            const xi = Vec2f{ rng.randomFloat(), rng.randomFloat() };
            var n_dot_h: f32 = undefined;
            const m = ggx.Aniso.sample(wo, alpha, xi, frame, &n_dot_h);
            const n = Vec4f{ m[0], m[1], m[2], 1.0 };

            shaper.drawCircle(n, uv, radius);
            // shaper.drawAperture(n, uv, 6, radius, 0.0, (2.0 * std.math.pi) * rng.randomFloat());
            // shaper.drawDisk(n, uv, n, radius);
        }
    }
};
