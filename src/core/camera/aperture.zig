const Texture = @import("../texture/texture.zig").Texture;
const Scene = @import("../scene/scene.zig").Scene;

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
        const d = texture.dimensions(scene);

        const width: u32 = @intCast(d[0]);
        const height: u32 = @intCast(d[1]);

        const conditionals = try self.distribution.allocate(alloc, height);

        var weights = try alloc.alloc(f32, height);
        defer alloc.free(weights);

        var y: u32 = 0;
        while (y < height) : (y += 1) {
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const weight = texture.image2D_1(@intCast(x), @intCast(y), scene);
                weights[x] = weight;
            }

            try conditionals[y].configure(alloc, weights, 0);
        }

        try self.distribution.configure(alloc);
    }

    pub fn sample(self: Aperture, uv: Vec2f) Vec2f {
        const s = if (self.distribution.marginal.size > 0)
            @as(Vec2f, @splat(2.0)) * self.distribution.sampleContinuous(uv).uv - @as(Vec2f, @splat(1.0))
        else
            math.smpl.diskConcentric(uv);

        return s * @as(Vec2f, @splat(self.radius));
    }
};
