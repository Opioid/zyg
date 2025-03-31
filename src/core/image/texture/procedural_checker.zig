const TextureAddress = @import("texture_sampler.zig").Address;
const Renderstate = @import("../../scene/renderstate.zig").Renderstate;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;
const json = base.json;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Checker = struct {
    color_a: Pack3f,
    color_b: Pack3f,
    scale: f32,

    pub fn init(value: std.json.Value) Checker {
        var checker = Checker{
            .color_a = Pack3f.init1(0.0),
            .color_b = Pack3f.init1(0.0),
            .scale = 1.0,
        };

        var citer = value.object.iterator();
        while (citer.next()) |cn| {
            if (std.mem.eql(u8, "scale", cn.key_ptr.*)) {
                checker.scale = json.readFloat(f32, cn.value_ptr.*);
            } else if (std.mem.eql(u8, "colors", cn.key_ptr.*)) {
                checker.color_a = math.vec4fTo3f(json.readColor(cn.value_ptr.array.items[0]));
                checker.color_b = math.vec4fTo3f(json.readColor(cn.value_ptr.array.items[1]));
            }
        }

        return checker;
    }

    // https://www.iquilezles.org/www/articles/checkerfiltering/checkerfiltering.htm

    pub fn evaluate(self: Checker, rs: Renderstate, address: TextureAddress) Vec4f {
        const scale: Vec2f = @splat(self.scale);

        const t = checkersGrad(
            scale * address.address2(rs.uv()),
            scale * rs.ddx,
            scale * rs.ddy,
        );

        return math.lerp(math.vec3fTo4f(self.color_a), math.vec3fTo4f(self.color_b), @as(Vec4f, @splat(t)));
    }

    fn checkersGrad(uv: Vec2f, ddx: Vec2f, ddy: Vec2f) f32 {
        // filter kernel
        const w = math.max2(@abs(ddx), @abs(ddy)) + @as(Vec2f, @splat(0.0001));

        // analytical integral (box filter)
        const i = (tri(uv + @as(Vec2f, @splat(0.5)) * w) - tri(uv - @as(Vec2f, @splat(0.5)) * w)) / w;

        // xor pattern
        return 0.5 - 0.5 * i[0] * i[1];
    }

    // triangular signal
    fn tri(x: Vec2f) Vec2f {
        const hx = math.frac(x[0] * 0.5) - 0.5;
        const hy = math.frac(x[1] * 0.5) - 0.5;
        return .{ 1.0 - 2.0 * @abs(hx), 1.0 - 2.0 * @abs(hy) };
    }
};
