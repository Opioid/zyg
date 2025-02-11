const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const Material = @import("../material/material.zig").Material;
const Scene = @import("../scene.zig").Scene;
const ro = @import("../ray_offset.zig");

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Frame = math.Frame;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Mat3x3 = math.Mat3x3;
const Ray = math.Ray;

const std = @import("std");

pub const Canopy = struct {
    const Eps = -0.0005;

    pub fn intersect(ray: Ray, trafo: Trafo) Intersection {
        var hpoint = Intersection{};

        if (ray.max_t < ro.RayMaxT or math.dot3(ray.direction, trafo.rotation.r[2]) < Eps) {
            return hpoint;
        }

        hpoint.primitive = 0;
        hpoint.t = ro.RayMaxT;

        return hpoint;
    }

    pub fn fragment(ray: Ray, frag: *Fragment) void {
        const xyz = math.normalize3(frag.trafo.rotation.transformVectorTransposed(ray.direction));

        const disk = hemisphereToDiskEquidistant(xyz);
        frag.uvw = .{
            0.5 * disk[0] + 0.5,
            0.5 * disk[1] + 0.5,
            0.0,
            0.0,
        };

        // This is nonsense
        const dir = Vec4f{ ray.direction[0], ray.direction[1], ray.direction[2], 0.0 };
        frag.p = @as(Vec4f, @splat(ro.RayMaxT)) * dir;
        const n = -dir;
        frag.geo_n = n;
        frag.t = frag.trafo.rotation.r[0];
        frag.b = frag.trafo.rotation.r[1];
        frag.n = n;
        frag.part = 0;
    }

    pub fn sampleTo(n: Vec4f, trafo: Trafo, total_sphere: bool, sampler: *Sampler, buffer: *Scene.SamplesTo) []SampleTo {
        const uv = sampler.sample2D();

        const frame: Frame = .{ .x = trafo.rotation.r[0], .y = trafo.rotation.r[1], .z = trafo.rotation.r[2] };

        const dir_l = math.smpl.hemisphereUniform(uv);
        const dir = frame.frameToWorld(dir_l);

        if (math.dot3(dir, n) <= 0.0 and !total_sphere) {
            return buffer[0..0];
        }

        const disk = hemisphereToDiskEquidistant(dir_l);

        const uvw = Vec4f{
            0.5 * disk[0] + 0.5,
            0.5 * disk[1] + 0.5,
            0.0,
            0.0,
        };

        buffer[0] = SampleTo.init(
            @as(Vec4f, @splat(ro.RayMaxT)) * dir,
            -dir,
            dir,
            uvw,
            1.0 / (2.0 * std.math.pi),
        );

        return buffer[0..1];
    }

    pub fn sampleMaterialTo(
        n: Vec4f,
        trafo: Trafo,
        total_sphere: bool,
        material: *const Material,
        sampler: *Sampler,
        buffer: *Scene.SamplesTo,
    ) []SampleTo {
        const r2 = sampler.sample2D();
        const rs = material.radianceSample(.{ r2[0], r2[1], 0.0, 0.0 });
        if (0.0 == rs.pdf()) {
            return buffer[0..0];
        }

        const uv = Vec2f{ rs.uvw[0], rs.uvw[1] };

        const disk = Vec2f{ 2.0 * uv[0] - 1.0, 2.0 * uv[1] - 1.0 };
        const z = math.dot2(disk, disk);
        if (z > 1.0) {
            return buffer[0..0];
        }

        const dir_l = diskToHemisphereEquidistant(disk);
        const dir = trafo.rotation.transformVector(dir_l);

        if (math.dot3(dir, n) <= 0.0 and !total_sphere) {
            return buffer[0..0];
        }

        buffer[0] = SampleTo.init(
            @as(Vec4f, @splat(ro.RayMaxT)) * dir,
            -dir,
            dir,
            .{ uv[0], uv[1], 0.0, 0.0 },
            rs.pdf() / (2.0 * std.math.pi),
        );
        return buffer[0..1];
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

        const longitude = std.math.atan2(-dir[1], dir[0]);

        const r = colatitude * (math.pi_inv * 2.0);

        const sin_lon = @sin(longitude);
        const cos_lon = @cos(longitude);

        return .{ r * cos_lon, r * sin_lon };
    }

    pub fn diskToHemisphereEquidistant(uv: Vec2f) Vec4f {
        const longitude = std.math.atan2(-uv[1], uv[0]);

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
