const Texture = @import("texture.zig").Texture;
const ts = @import("texture_sampler.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Renderstate = @import("../../scene/renderstate.zig").Renderstate;
const Scene = @import("../../scene/scene.zig").Scene;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Max = struct {
    a: Texture,
    b: Texture,

    pub fn evaluate1(self: Max, rs: Renderstate, key: ts.Key, sampler: *Sampler, scene: *const Scene) f32 {
        const a = ts.sample2D_1(key, self.a, rs, sampler, scene);
        const b = ts.sample2D_1(key, self.b, rs, sampler, scene);

        return math.max(a, b);
    }

    pub fn evaluate2(self: Max, rs: Renderstate, key: ts.Key, sampler: *Sampler, scene: *const Scene) Vec2f {
        const a = ts.sample2D_2(key, self.a, rs, sampler, scene);
        const b = ts.sample2D_2(key, self.b, rs, sampler, scene);

        return math.max2(a, b);
    }

    pub fn evaluate3(self: Max, rs: Renderstate, key: ts.Key, sampler: *Sampler, scene: *const Scene) Vec4f {
        const a = ts.sample2D_3(key, self.a, rs, sampler, scene);
        const b = ts.sample2D_3(key, self.b, rs, sampler, scene);

        return math.max4(a, b);
    }
};
