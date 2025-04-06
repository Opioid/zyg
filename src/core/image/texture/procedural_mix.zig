const Texture = @import("texture.zig").Texture;
const ts = @import("texture_sampler.zig");
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Renderstate = @import("../../scene/renderstate.zig").Renderstate;
const Worker = @import("../../rendering/worker.zig").Worker;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub const Mix = struct {
    a: Texture,
    b: Texture,
    t: Texture,

    pub fn evaluate1(self: Mix, rs: Renderstate, key: ts.Key, sampler: *Sampler, worker: *const Worker) f32 {
        const weight = ts.sample2D_1(key, self.t, rs, sampler, worker);

        const r = sampler.sample1D();

        return if (weight < r)
            ts.sample2D_1(key, self.a, rs, sampler, worker)
        else
            ts.sample2D_1(key, self.b, rs, sampler, worker);
    }

    pub fn evaluate2(self: Mix, rs: Renderstate, key: ts.Key, sampler: *Sampler, worker: *const Worker) Vec2f {
        const weight = ts.sample2D_1(key, self.t, rs, sampler, worker);

        const r = sampler.sample1D();

        return if (weight < r)
            ts.sample2D_2(key, self.a, rs, sampler, worker)
        else
            ts.sample2D_2(key, self.b, rs, sampler, worker);
    }

    pub fn evaluate3(self: Mix, rs: Renderstate, key: ts.Key, sampler: *Sampler, worker: *const Worker) Vec4f {
        const weight = ts.sample2D_1(key, self.t, rs, sampler, worker);

        const r = sampler.sample1D();

        return if (weight < r)
            ts.sample2D_3(key, self.a, rs, sampler, worker)
        else
            ts.sample2D_3(key, self.b, rs, sampler, worker);
    }
};
