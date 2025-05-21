const Texture = @import("texture.zig").Texture;
const ts = @import("texture_sampler.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Context = @import("../../scene//context.zig").Context;
const Renderstate = @import("../../scene/renderstate.zig").Renderstate;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Mul = struct {
    a: Texture,
    b: Texture,

    pub fn evaluate1(self: Mul, rs: Renderstate, sampler: *Sampler, context: Context) f32 {
        const a = ts.sample2D_1(self.a, rs, sampler, context);
        const b = ts.sample2D_1(self.b, rs, sampler, context);

        return a * b;
    }

    pub fn evaluate2(self: Mul, rs: Renderstate, sampler: *Sampler, context: Context) Vec2f {
        const a = ts.sample2D_2(self.a, rs, sampler, context);
        const b = ts.sample2D_2(self.b, rs, sampler, context);

        return a * b;
    }

    pub fn evaluate3(self: Mul, rs: Renderstate, sampler: *Sampler, context: Context) Vec4f {
        const a = ts.sample2D_3(self.a, rs, sampler, context);
        const b = ts.sample2D_3(self.b, rs, sampler, context);

        return a * b;
    }
};
