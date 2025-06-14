const Texture = @import("texture.zig").Texture;
const ts = @import("texture_sampler.zig");
const Sampler = @import("../sampler/sampler.zig").Sampler;
const Renderstate = @import("../scene/renderstate.zig").Renderstate;
const Context = @import("../scene/context.zig").Context;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Mix = struct {
    a: Texture,
    b: Texture,
    t: Texture,

    pub fn evaluate1(self: Mix, rs: Renderstate, sampler: *Sampler, context: Context) f32 {
        const weight = ts.sample2D_1(self.t, rs, sampler, context);

        const r = sampler.sample1D();

        return if (weight < r)
            ts.sample2D_1(self.a, rs, sampler, context)
        else
            ts.sample2D_1(self.b, rs, sampler, context);
    }

    pub fn evaluate2(self: Mix, rs: Renderstate, sampler: *Sampler, context: Context) Vec2f {
        const weight = ts.sample2D_1(self.t, rs, sampler, context);

        const r = sampler.sample1D();

        return if (weight < r)
            ts.sample2D_2(self.a, rs, sampler, context)
        else
            ts.sample2D_2(self.b, rs, sampler, context);
    }

    pub fn evaluate3(self: Mix, rs: Renderstate, sampler: *Sampler, context: Context) Vec4f {
        const weight = ts.sample2D_1(self.t, rs, sampler, context);

        const r = sampler.sample1D();

        return if (weight < r)
            ts.sample2D_3(self.a, rs, sampler, context)
        else
            ts.sample2D_3(self.b, rs, sampler, context);
    }
};
