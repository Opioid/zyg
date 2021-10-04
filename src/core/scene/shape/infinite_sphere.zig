const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const SampleTo = @import("sample.zig").To;
const scn = @import("../constants.zig");

const base = @import("base");
const RNG = base.rnd.Generator;
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const InfiniteSphere = struct {
    pub fn intersect(ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        if (ray.maxT() < scn.Ray_max_t) {
            return false;
        }

        const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(ray.direction));

        isec.uv = Vec2f{
            std.math.atan2(f32, xyz[0], xyz[2]) * (math.pi_inv * 0.5) + 0.5,
            std.math.acos(xyz[1]) * math.pi_inv,
        };

        isec.p = ray.point(scn.Ray_max_t);

        const n = -ray.direction;
        isec.geo_n = n;

        // This is nonsense
        isec.t = trafo.rotation.r[0];
        isec.b = trafo.rotation.r[1];
        isec.n = n;
        isec.part = 0;
        isec.primitive = 0;

        ray.setMaxT(scn.Ray_max_t);

        return true;
    }

    pub fn sampleTo(
        n: Vec4f,
        trafo: Transformation,
        total_sphere: bool,
        sampler: *Sampler,
        rng: *RNG,
        sampler_d: usize,
    ) SampleTo {
        const uv = sampler.sample2D(rng, sampler_d);

        var dir: Vec4f = undefined;
        var pdf: f32 = undefined;

        if (total_sphere) {
            dir = math.smpl.sphereUniform(uv);
            pdf = 1.0 / (4.0 * std.math.pi);
        } else {
            const xy = math.orthonormalBasis3(n);
            dir = math.smpl.orientedHemisphereUniform(uv, xy[0], xy[1], n);
            pdf = 1.0 / (2.0 * std.math.pi);
        }

        const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(dir));
        const uvw = Vec4f{
            std.math.atan2(f32, xyz[0], xyz[2]) * (math.pi_inv * 0.5) + 0.5,
            std.math.acos(xyz[1]) * math.pi_inv,
            0.0,
            0.0,
        };

        return SampleTo.init(dir, @splat(4, @as(f32, 0.0)), uvw, pdf, scn.Ray_max_t);
    }

    pub fn sampleToUV(uv: Vec2f, trafo: Transformation) SampleTo {
        const phi = (uv[0] - 0.5) * (2.0 * std.math.pi);
        const theta = uv[1] * std.math.pi;

        const sin_phi = @sin(phi);
        const cos_phi = @cos(phi);

        const sin_theta = @sin(theta);
        const cos_theta = @cos(theta);

        const dir = Vec4f{ sin_phi * sin_theta, cos_theta, cos_phi * sin_theta, 0.0 };

        return SampleTo.init(
            trafo.rotation.transformVector(dir),
            @splat(4, @as(f32, 0.0)),
            .{ uv[0], uv[1], 0.0, 0.0 },
            1.0 / ((4.0 * std.math.pi) * sin_theta),
            scn.Ray_max_t,
        );
    }
};