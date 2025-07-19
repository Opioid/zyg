const Texture = @import("texture.zig").Texture;
const ts = @import("texture_sampler.zig");
const Sampler = @import("../sampler/sampler.zig").Sampler;
const Context = @import("../scene/context.zig").Context;
const Renderstate = @import("../scene/renderstate.zig").Renderstate;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const ChannelMix = struct {
    source: Texture,

    channels: [3]Vec4f,

    pub fn evaluate1(self: ChannelMix, rs: Renderstate, sampler: *Sampler, context: Context) f32 {
        const c = ts.sample2D_3(self.source, rs, sampler, context);

        return math.clamp(math.dot3(c, self.channels[0]), 0.0, 1.0);
    }

    pub fn evaluate2(self: ChannelMix, rs: Renderstate, sampler: *Sampler, context: Context) Vec2f {
        const c = ts.sample2D_3(self.source, rs, sampler, context);

        return math.clamp2(.{
            math.dot3(c, self.channels[0]),
            math.dot3(c, self.channels[1]),
        }, @splat(0.0), @splat(1.0));
    }

    pub fn evaluate3(self: ChannelMix, rs: Renderstate, sampler: *Sampler, context: Context) Vec4f {
        const c = ts.sample2D_3(self.source, rs, sampler, context);

        return math.clamp4(.{
            math.dot3(c, self.channels[0]),
            math.dot3(c, self.channels[1]),
            math.dot3(c, self.channels[2]),
            0.0,
        }, @splat(0.0), @splat(1.0));
    }
};
