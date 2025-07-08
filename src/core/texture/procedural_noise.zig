const ts = @import("texture_sampler.zig");
const Texture = @import("texture.zig").Texture;
const perlin = @import("noise/perlin.zig");
const worley = @import("noise/worley.zig");
const Context = @import("../scene/context.zig").Context;
const Renderstate = @import("../scene/renderstate.zig").Renderstate;
const hlp = @import("../scene/material/material_helper.zig");

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec2i = math.Vec2i;
const Vec2u = math.Vec2u;
const Vec4f = math.Vec4f;
const Vec4i = math.Vec4i;
const Vec4u = math.Vec4u;

const std = @import("std");

pub const Noise = struct {
    pub const Class = enum {
        Cellular,
        Gradient,
    };

    pub const Flags = packed struct {
        absolute: bool,
        invert: bool,
    };

    class: Class,

    flags: Flags,

    levels: u32,

    attenuation: f32,
    ratio: f32,
    transition: f32,

    scale: Vec4f,
    period: Vec4f,

    const Self = @This();

    pub fn evaluate1(self: Self, rs: Renderstate, offset: Vec4f, mode: Texture.Mode) f32 {
        const is_cellular = .Cellular == self.class;
        const att = self.attenuation;

        var weight: f32 = 0.0;
        var amplitude: f32 = 1.0;

        var value: f32 = 0.0;

        if (.ObjectPos == mode.tex_coord) {
            var scale = self.scale;

            const uvw = rs.trafo.worldToObjectPoint(rs.p - offset);

            for (0..self.levels) |_| {
                const local_weight = std.math.pow(f32, amplitude, att);

                const local = if (is_cellular) worley.worley3D_1(uvw * scale, 1.0) else perlin.perlin3D_1(uvw * scale);

                value += local * local_weight;

                weight += local_weight;
                amplitude *= 0.5;
                scale *= @splat(2.0);
            }
        } else {
            var scale: Vec2f = .{ self.scale[0], self.scale[1] };
            var perdiod: Vec2f = .{ self.period[0], self.period[1] };

            const uv_offset = Vec2f{ offset[0], offset[1] };
            const uv = (if (.Triplanar == mode.tex_coord) rs.triplanarSt() else rs.uv()) - uv_offset;

            for (0..self.levels) |_| {
                const local_weight = std.math.pow(f32, amplitude, att);

                const local = if (is_cellular) worley.worley2D_1(uv * scale, 1.0) else perlin.perlin2D_1(uv * scale, perdiod);

                value += local * local_weight;

                weight += local_weight;
                amplitude *= 0.5;
                scale *= @splat(2.0);
                perdiod *= @splat(2.0);
            }
        }

        value /= weight;

        const unsigned = if (is_cellular) value else (if (self.flags.absolute) @abs(value) else (value + 1.0) * 0.5);

        const a = self.ratio - self.transition;
        const b = self.ratio + self.transition;

        const result = math.saturate((unsigned - a) / (b - a));
        //  const result = math.smoothstep(remapped_noise);

        return if (self.flags.invert) (1.0 - result) else result;
    }

    pub fn evaluateNormalmap(self: Self, rs: Renderstate, mode: Texture.Mode, context: Context) Vec2f {
        if (.ObjectPos == mode.tex_coord) {
            const dpdx, const dpdy = context.approximateDpDxy(rs);

            const center = self.evaluate1(rs, @splat(0.0), mode);
            const left = self.evaluate1(rs, dpdx, mode);
            const bottom = self.evaluate1(rs, dpdy, mode);

            const nx = left - center;
            const ny = bottom - center;

            const n = math.normalize3(.{ nx, ny, math.length3(dpdx + dpdy), 0.0 });

            return .{ n[0], n[1] };
        } else {
            const dd = @abs(context.screenspaceDifferentials(rs, mode.tex_coord));

            const shift_x = dd[0] + dd[2];
            const shift_y = dd[1] + dd[3];

            const center = self.evaluate1(rs, @splat(0.0), mode);
            const left = self.evaluate1(rs, Vec4f{ shift_x, 0.0, 0.0, 0.0 }, mode);
            const top = self.evaluate1(rs, Vec4f{ 0.0, shift_y, 0.0, 0.0 }, mode);

            const nx = left - center;
            const ny = top - center;

            const n = math.normalize3(.{ nx, ny, math.length2(.{ shift_x, shift_y }), 0.0 });

            return .{ n[0], n[1] };
        }
    }

    pub fn evaluate3(self: Self, rs: Renderstate, mode: Texture.Mode) Vec4f {
        const noise = self.evaluate1(rs, @splat(0.0), mode);

        return @splat(noise);
    }
};
