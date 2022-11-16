const Texture = @import("../../image/texture/texture.zig").Texture;
const Scene = @import("../../scene/scene.zig").Scene;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Distribution2D = math.Distribution2D;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Aperture = struct {
    radius: f32 = 0.0,

    distribution: Distribution2D = .{},

    pub fn deinit(self: *Aperture, alloc: Allocator) void {
        self.distribution.deinit(alloc);
    }

    pub fn setShape(self: *Aperture, alloc: Allocator, texture: Texture, scene: *const Scene) !void {
        const d = texture.description(scene).dimensions;

        const width = @intCast(u32, d[0]);
        const height = @intCast(u32, d[1]);

        const conditionals = try self.distribution.allocate(alloc, height);

        var weights = try alloc.alloc(f32, height);
        defer alloc.free(weights);

        var y: u32 = 0;
        while (y < height) : (y += 1) {
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const weight = texture.get2D_1(@intCast(i32, x), @intCast(i32, y), scene);
                weights[x] = weight;
            }

            try conditionals[y].configure(alloc, weights, 0);
        }

        try self.distribution.configure(alloc);
    }

    pub fn sample(self: Aperture, uv: Vec2f) Vec2f {
        const s = if (self.distribution.marginal.size > 0)
            @splat(2, @as(f32, 2.0)) * self.distribution.sampleContinuous(uv).uv - @splat(2, @as(f32, 1.0))
        else
            math.smpl.diskConcentric(uv);

        return s * @splat(2, self.radius);
    }
};
