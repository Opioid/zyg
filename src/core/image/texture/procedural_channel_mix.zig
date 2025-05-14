const Texture = @import("texture.zig").Texture;
const ts = @import("texture_sampler.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Context = @import("../../scene/context.zig").Context;
const Renderstate = @import("../../scene/renderstate.zig").Renderstate;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const ChannelMix = struct {
    source: Texture,

    channels: [3]Vec4f,

    pub fn evaluate1(self: ChannelMix, rs: Renderstate, key: ts.Key, sampler: *Sampler, context: Context) f32 {
        const c = ts.sample2D_3(key, self.source, rs, sampler, context);

        return math.dot3(c, self.channels[0]);
    }

    pub fn evaluate2(self: ChannelMix, rs: Renderstate, key: ts.Key, sampler: *Sampler, context: Context) Vec2f {
        const c = ts.sample2D_3(key, self.source, rs, sampler, context);

        return .{
            math.dot3(c, self.channels[0]),
            math.dot3(c, self.channels[1]),
        };
    }

    pub fn evaluate3(self: ChannelMix, rs: Renderstate, key: ts.Key, sampler: *Sampler, context: Context) Vec4f {
        const c = ts.sample2D_3(key, self.source, rs, sampler, context);

        return .{
            math.dot3(c, self.channels[0]),
            math.dot3(c, self.channels[1]),
            math.dot3(c, self.channels[2]),
            0.0,
        };
    }
};
