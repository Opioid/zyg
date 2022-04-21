const Transformation = @import("../composed_transformation.zig").ComposedTransformation;
const Intersection = @import("intersection.zig").Intersection;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const scn = @import("../constants.zig");

const base = @import("base");
const RNG = base.rnd.Generator;
const math = base.math;
const AABB = math.AABB;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;
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

        // This is nonsense
        isec.p = @splat(4, @as(f32, scn.Ray_max_t)) * ray.direction;
        const n = -ray.direction;
        isec.geo_n = n;
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
    ) SampleTo {
        const uv = sampler.sample2D(rng);

        var dir: Vec4f = undefined;
        var pdf_: f32 = undefined;

        if (total_sphere) {
            dir = math.smpl.sphereUniform(uv);
            pdf_ = 1.0 / (4.0 * std.math.pi);
        } else {
            const xy = math.orthonormalBasis3(n);
            dir = math.smpl.orientedHemisphereUniform(uv, xy[0], xy[1], n);
            pdf_ = 1.0 / (2.0 * std.math.pi);
        }

        const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(dir));
        const uvw = Vec4f{
            std.math.atan2(f32, xyz[0], xyz[2]) * (math.pi_inv * 0.5) + 0.5,
            std.math.acos(xyz[1]) * math.pi_inv,
            0.0,
            0.0,
        };

        return SampleTo.init(dir, @splat(4, @as(f32, 0.0)), uvw, pdf_, scn.Ray_max_t);
    }

    pub fn sampleToUv(uv: Vec2f, trafo: Transformation) SampleTo {
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

    pub fn sampleFrom(
        trafo: Transformation,
        sampler: *Sampler,
        rng: *RNG,
        uv: Vec2f,
        importance_uv: Vec2f,
        bounds: AABB,
    ) ?SampleFrom {
        const phi = (uv[0] - 0.5) * (2.0 * std.math.pi);
        const theta = uv[1] * std.math.pi;

        const sin_phi = @sin(phi);
        const cos_phi = @cos(phi);

        const sin_theta = @sin(theta);
        const cos_theta = @cos(theta);

        const ls = Vec4f{ sin_phi * sin_theta, cos_theta, cos_phi * sin_theta, 0.0 };
        const ws = -trafo.rotation.transformVector(ls);
        const tb = math.orthonormalBasis3(ws);

        const r0 = sampler.sample2D(rng);
        const dir = math.smpl.orientedHemisphereCosine(r0, tb[0], tb[1], ws);

        const bounds_radius = math.length3(bounds.halfsize());

        const tb2 = math.orthonormalBasis3(dir);

        //   const rotation = Mat3x3.init3(tb[0], tb[1], ws);
        const rotation = Mat3x3.init3(tb2[0], tb2[1], dir);

        const ls_bounds = bounds.transform(Mat4x4.initMat3x3(rotation).affineInverted());

        const pe = ls_bounds.extent();

        const shuv = importance_uv - @splat(2, @as(f32, 0.5));
        const receiver_rect = Vec4f{ shuv[0], shuv[1], 0.0, 0.0 } * pe;
        const photon_rect = rotation.transformVector(receiver_rect);
        const pli = (bounds.position() + photon_rect) - @splat(4, bounds_radius) * dir;

        return SampleFrom.init(
            pli,
            ws,
            dir,
            .{ uv[0], uv[1], 0.0, 0.0 },
            importance_uv,
            //    1.0 / ((4.0 * std.math.pi) * (sin_theta * pe[0] * pe[1])),
            1.0 / ((4.0 * std.math.pi * sin_theta * pe[0] * pe[1])),
        );
    }

    pub fn pdf(total_sphere: bool) f32 {
        if (total_sphere) {
            return 1.0 / (4.0 * std.math.pi);
        }

        return 1.0 / (2.0 * std.math.pi);
    }

    pub fn pdfUv(isec: Intersection) f32 {
        // sin_theta because of the uv weight
        const sin_theta = @sin(isec.uv[1] * std.math.pi);

        if (0.0 == sin_theta) {
            return 0.0;
        }

        return 1.0 / ((4.0 * std.math.pi) * sin_theta);
    }
};
