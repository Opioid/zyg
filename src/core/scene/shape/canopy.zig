const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const ro = @import("../ray_offset.zig");

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Mat3x3 = math.Mat3x3;
const Ray = math.Ray;

const std = @import("std");

pub const Canopy = struct {
    const Eps = -0.0005;

    pub fn intersect(ray: *Ray, trafo: Trafo, isec: *Intersection) bool {
        if (ray.maxT() < ro.Ray_max_t or math.dot3(ray.direction, trafo.rotation.r[2]) < Eps) {
            return false;
        }

        const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(ray.direction));

        const disk = hemisphereToDiskEquidistant(xyz);
        isec.uv = Vec2f{
            0.5 * disk[0] + 0.5,
            0.5 * disk[1] + 0.5,
        };

        // This is nonsense
        isec.p = @as(Vec4f, @splat(ro.Ray_max_t)) * ray.direction;
        const n = -ray.direction;
        isec.geo_n = n;
        isec.t = trafo.rotation.r[0];
        isec.b = trafo.rotation.r[1];
        isec.n = n;
        isec.part = 0;
        isec.offset = 0.0;
        isec.primitive = 0;

        ray.setMaxT(ro.Ray_max_t);

        return true;
    }

    pub fn sampleTo(trafo: Trafo, sampler: *Sampler) SampleTo {
        const uv = sampler.sample2D();
        const dir = math.smpl.orientedHemisphereUniform(uv, trafo.rotation.r[0], trafo.rotation.r[1], trafo.rotation.r[2]);
        const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(dir));
        const disk = hemisphereToDiskEquidistant(xyz);

        const uvw = Vec4f{
            0.5 * disk[0] + 0.5,
            0.5 * disk[1] + 0.5,
            0.0,
            0.0,
        };

        return SampleTo.init(
            @as(Vec4f, @splat(ro.Ray_max_t)) * dir,
            -dir,
            dir,
            uvw,
            trafo,
            1.0 / (2.0 * std.math.pi),
        );
    }

    pub fn sampleToUv(uv: Vec2f, trafo: Trafo) ?SampleTo {
        const disk = Vec2f{ 2.0 * uv[0] - 1.0, 2.0 * uv[1] - 1.0 };
        const z = math.dot2(disk, disk);
        if (z > 1.0) {
            return null;
        }

        const ldir = diskToHemisphereEquidistant(disk);
        const dir = trafo.rotation.transformVector(ldir);

        return SampleTo.init(
            @as(Vec4f, @splat(ro.Ray_max_t)) * dir,
            -dir,
            dir,
            .{ uv[0], uv[1], 0.0, 0.0 },
            trafo,
            1.0 / (2.0 * std.math.pi),
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

    pub fn sampleFrom(trafo: Trafo, uv: Vec2f, importance_uv: Vec2f, bounds: AABB) ?SampleFrom {
        const disk = Vec2f{ 2.0 * uv[0] - 1.0, 2.0 * uv[1] - 1.0 };
        const z = math.dot2(disk, disk);
        if (z > 1.0) {
            return null;
        }

        const ls = diskToHemisphereEquidistant(disk);
        const dir = -trafo.rotation.transformVector(ls);
        const tb = math.orthonormalBasis3(dir);

        const rotation = Mat3x3.init3(tb[0], tb[1], dir);

        const ls_bounds = bounds.transformTransposed(rotation);
        const ls_extent = ls_bounds.extent();
        const ls_rect = (importance_uv - @as(Vec2f, @splat(0.5))) * Vec2f{ ls_extent[0], ls_extent[1] };
        const photon_rect = rotation.transformVector(.{ ls_rect[0], ls_rect[1], 0.0, 0.0 });

        const offset = @as(Vec4f, @splat(ls_extent[2])) * dir;
        const p = ls_bounds.position() - offset + photon_rect;

        return SampleFrom.init(
            p,
            dir,
            dir,
            .{ uv[0], uv[1], 0.0, 0.0 },
            importance_uv,
            trafo,
            1.0 / ((2.0 * std.math.pi) * ls_extent[0] * ls_extent[1]),
        );
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

        return .{ sin_col * cos_lon, sin_col * sin_lon, cos_col, 0.0 };
    }
};
