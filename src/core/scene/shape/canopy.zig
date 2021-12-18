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

pub const Canopy = struct {
    const Eps = -0.0005;

    pub fn intersect(ray: *Ray, trafo: Transformation, isec: *Intersection) bool {
        if (ray.maxT() < scn.Ray_max_t or math.dot3(ray.direction, trafo.rotation.r[2]) < Eps) {
            return false;
        }

        const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(ray.direction));

        const disk = hemisphereToDiskEquidistant(xyz);
        isec.uv = Vec2f{
            0.5 * disk[0] + 0.5,
            0.5 * disk[1] + 0.5,
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
        trafo: Transformation,
        sampler: *Sampler,
        rng: *RNG,
        sampler_d: usize,
    ) SampleTo {
        const uv = sampler.sample2D(rng, sampler_d);
        const dir = math.smpl.orientedHemisphereUniform(uv, trafo.rotation.r[0], trafo.rotation.r[1], trafo.rotation.r[2]);
        const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(dir));
        const disk = hemisphereToDiskEquidistant(xyz);

        const uvw = Vec4f{
            0.5 * disk[0] + 0.5,
            0.5 * disk[1] + 0.5,
            0.0,
            0.0,
        };

        return SampleTo.init(dir, @splat(4, @as(f32, 0.0)), uvw, 1.0 / (2.0 * std.math.pi), scn.Ray_max_t);
    }

    pub fn sampleToUv(uv: Vec2f, trafo: Transformation) ?SampleTo {
        const disk = Vec2f{ 2.0 * uv[0] - 1.0, 2.0 * uv[1] - 1.0 };
        const z = math.dot2(disk, disk);
        if (z > 1.0) {
            return null;
        }

        const dir = diskToHemisphereEquidistant(disk);

        return SampleTo.init(
            trafo.rotation.transformVector(dir),
            @splat(4, @as(f32, 0.0)),
            .{ uv[0], uv[1], 0.0, 0.0 },
            1.0 / (2.0 * std.math.pi),
            scn.Ray_max_t,
        );
    }

    pub fn uvWeight(uv: Vec2f) f32 {
        const disk = Vec2f{ 2.0 * uv[0] - 1.0, 2.0 * uv[1] - 1.0 };
        const z = math.dot2(disk, disk);
        if (z > 1.0) {
            return 0.0;
        }

        return 1.0;
    }

    fn hemisphereToDiskEquidistant(dir: Vec4f) Vec2f {
        // cartesian to spherical
        const colatitude = std.math.acos(dir[2]);

        const longitude = std.math.atan2(f32, -dir[1], dir[0]);

        const r = colatitude * (math.pi_inv * 2.0);

        const sin_lon = @sin(longitude);
        const cos_lon = @cos(longitude);

        return .{ r * cos_lon, r * sin_lon };
    }

    pub fn diskToHemisphereEquidistant(uv: Vec2f) Vec4f {
        const longitude = std.math.atan2(f32, -uv[1], uv[0]);

        const r = @sqrt(uv[0] * uv[0] + uv[1] * uv[1]);

        // Equidistant projection
        const colatitude = r * (std.math.pi / 2.0);

        // Equal-area projection
        // float colatitude = /*2.f **/ std::asin(r);

        // Stereographic projection
        // float colatitude = 2.f * std::atan(r);

        // spherical to cartesian
        const sin_col = @sin(colatitude);
        const cos_col = @cos(colatitude);

        const sin_lon = @sin(longitude);
        const cos_lon = @cos(longitude);

        return .{ sin_col * cos_lon, sin_col * sin_lon, cos_col };
    }
};