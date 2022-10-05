const img = @import("../../image/image.zig");
const tx = @import("../../image/texture/provider.zig");
const Texture = tx.Texture;
const Resources = @import("../../resource/manager.zig").Manager;
const Shaper = @import("../../rendering/shaper.zig").Shaper;

const PngWriter = @import("../../image/encoding/png/writer.zig").Writer;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Generator = struct {
    pub const Result = struct {
        normal: Texture,
        mask: Texture,
    };

    pub fn generate(alloc: Allocator, resources: *Resources) !Result {
        const flakes_size: f32 = 0.04;
        const flakes_radius = flakes_size / 2.0;

        var shaper = try Shaper.init(alloc, .{ 1024, 1024 });
        defer shaper.deinit(alloc);

        shaper.clear(.{ 0.0, 0.0, 1.0, 0.0 });

        var rng = RNG.init(0, 0);

        const num_flakes = 64;

        var i: u32 = 0;
        while (i < num_flakes) : (i += 1) {
            const uv = math.hammersley(i, num_flakes, 0);

            const st = Vec2f{ rng.randomFloat(), rng.randomFloat() };
            var n = math.smpl.hemisphereUniform(st);
            n = math.normalize3(math.lerp4(n, .{ 0.0, 0.0, 1.0, 0.0 }, 0.6));
            n[3] = 1.0;

            //   shaper.drawCircle(n, uv, flakes_radius);

            shaper.drawAperture(n, uv, 6, flakes_radius, 0.0, 0.0);
        }

        var normal_view = try img.Float3.init(alloc, img.Description.init2D(shaper.dimensions));
        defer normal_view.deinit(alloc);
        shaper.resolve(img.Float3, &normal_view);
        try PngWriter.writeFloat3Normal(alloc, normal_view);

        var normal_image = try img.Byte2.init(alloc, img.Description.init2D(shaper.dimensions));
        errdefer normal_image.deinit(alloc);
        shaper.resolve(img.Byte2, &normal_image);
        const normal_id = try resources.images.store(alloc, 0xFFFFFFFF, .{ .Byte2 = normal_image });
        const normal = try tx.Provider.createTexture(normal_id, .Normal, @splat(2, @as(f32, 4.0)), resources);

        var mask_image = try img.Byte1.init(alloc, img.Description.init2D(shaper.dimensions));
        errdefer mask_image.deinit(alloc);
        shaper.resolve(img.Byte1, &mask_image);
        const mask_id = try resources.images.store(alloc, 0xFFFFFFFF, .{ .Byte1 = mask_image });
        const mask = try tx.Provider.createTexture(mask_id, .Opacity, @splat(2, @as(f32, 4.0)), resources);

        return Result{ .normal = normal, .mask = mask };
    }
};
