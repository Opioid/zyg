const Trafo = @import("../composed_transformation.zig").ComposedTransformation;

const math = @import("base").math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Bounds2f = math.Bounds2f;

const std = @import("std");

pub const Portal = struct {
    pub const WorldSample = struct {
        dir: Vec4f,
        weight: f32,
    };

    pub fn imageToWorld(uv: Vec2f, trafo: Trafo) WorldSample {
        const ab = @as(Vec2f, @splat(-std.math.pi * 0.5)) + (uv * @as(Vec2f, @splat(std.math.pi)));
        const xy = @tan(ab);
        const w = math.normalize3(.{ xy[0], xy[1], 1.0, 0.0 });

        const weight = math.pow2(std.math.pi) * (1.0 - math.pow2(w[0])) * (1.0 - math.pow2(w[1])) / w[2];

        return .{ .dir = trafo.objectToWorldNormal(w), .weight = weight };
    }

    pub fn worldToImage(dir: Vec4f, trafo: Trafo) ?Vec2f {
        const w = trafo.worldToObjectNormal(dir);
        if (w[2] <= 0.0) {
            return null;
        }

        const ab = Vec2f{
            std.math.atan2(w[0], w[2]),
            std.math.atan2(w[1], w[2]),
        };

        return math.clamp2((ab + @as(Vec2f, @splat(std.math.pi / 2.0))) / @as(Vec2f, @splat(std.math.pi)), @splat(0.0), @splat(1.0));
    }

    pub const ImageSample = struct {
        uv: Vec2f,
        weight: f32,
    };

    pub fn worldToImageWeighted(dir: Vec4f, trafo: Trafo) ?ImageSample {
        const w = trafo.worldToObjectNormal(dir);
        if (w[2] <= 0.0) {
            return null;
        }

        const alpha = std.math.atan2(w[0], w[2]);
        const beta = std.math.atan2(w[1], w[2]);

        const weight = math.pow2(std.math.pi) * (1.0 - math.pow2(w[0])) * (1.0 - math.pow2(w[1])) / w[2];

        return ImageSample{
            .uv = .{
                math.clamp((alpha + std.math.pi / 2.0) / std.math.pi, 0.0, 1.0),
                math.clamp((beta + std.math.pi / 2.0) / std.math.pi, 0.0, 1.0),
            },
            .weight = weight,
        };
    }

    pub fn imageBounds(p: Vec4f, trafo: Trafo) ?Bounds2f {
        const a = trafo.rotation.r[0] * @as(Vec4f, @splat(trafo.rotation.r[0][3]));
        const b = trafo.rotation.r[1] * @as(Vec4f, @splat(trafo.rotation.r[1][3]));
        const ab = a + b;
        const o = p - trafo.position;

        const corners: [2]Vec4f = .{
            @as(Vec4f, @splat(0.5)) * ab + o,
            @as(Vec4f, @splat(-0.5)) * ab + o,
        };

        const p0 = worldToImage(math.normalize3(corners[0]), trafo) orelse return null;
        const p1 = worldToImage(math.normalize3(corners[1]), trafo) orelse return null;

        return Bounds2f.init(math.min2(p0, p1), math.max2(p0, p1));
    }
};
