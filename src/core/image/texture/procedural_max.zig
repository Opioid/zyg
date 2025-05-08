const Texture = @import("texture.zig").Texture;
const ts = @import("texture_sampler.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Context = @import("../../scene/context.zig").Context;
const Renderstate = @import("../../scene/renderstate.zig").Renderstate;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Max = struct {
    a: Texture,
    b: Texture,

    pub fn evaluate1(self: Max, rs: Renderstate, key: ts.Key, sampler: *Sampler, context: Context) f32 {
        const a = ts.sample2D_1(key, self.a, rs, sampler, context);
        const b = ts.sample2D_1(key, self.b, rs, sampler, context);

        return math.max(a, b);
    }

    pub fn evaluate2(self: Max, rs: Renderstate, key: ts.Key, sampler: *Sampler, context: Context) Vec2f {
        const a = ts.sample2D_2(key, self.a, rs, sampler, context);
        const b = ts.sample2D_2(key, self.b, rs, sampler, context);

        return math.max2(a, b);
    }

    pub fn evaluate3(self: Max, rs: Renderstate, key: ts.Key, sampler: *Sampler, context: Context) Vec4f {
        const a = ts.sample2D_3(key, self.a, rs, sampler, context);
        const b = ts.sample2D_3(key, self.b, rs, sampler, context);

        return math.max4(a, b);
    }
};
