const Texture = @import("texture.zig").Texture;
const ts = @import("texture_sampler.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Renderstate = @import("../../scene/renderstate.zig").Renderstate;
const Scene = @import("../../scene/scene.zig").Scene;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const DetailNormal = struct {
    base: Texture,
    detail: Texture,

    // Based on a technique described here
    // https://blog.selfshadow.com/publications/blending-in-detail/

    pub fn evaluate(self: DetailNormal, rs: Renderstate, key: ts.Key, sampler: *Sampler, scene: *const Scene) Vec2f {
        const n1 = reconstructNormal(self.base, rs, key, sampler, scene);
        const n2 = reconstructNormal(self.detail, rs, key, sampler, scene);

        // Construct a basis
        const xy = math.orthonormalBasis3(n1);

        // Rotate n2 via the basis
        const r = @as(Vec4f, @splat(n2[0])) * xy[0] + @as(Vec4f, @splat(n2[1])) * xy[1] + @as(Vec4f, @splat(n2[2])) * n1;

        return .{ r[0], r[1] };
    }

    fn reconstructNormal(map: Texture, rs: Renderstate, key: ts.Key, sampler: *Sampler, scene: *const Scene) Vec4f {
        const nm = ts.sample2D_2(key, map, rs, sampler, scene);
        const nmz = @sqrt(math.max(1.0 - math.dot2(nm, nm), 0.01));
        return math.normalize3(.{ nm[0], nm[1], nmz, 0.0 });
    }
};
