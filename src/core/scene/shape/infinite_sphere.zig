const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const Scene = @import("../scene.zig").Scene;
const ro = @import("../ray_offset.zig");

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Frame = math.Frame;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;
const Ray = math.Ray;

const std = @import("std");

pub const InfiniteSphere = struct {
    pub fn intersect(ray: Ray) Intersection {
        var hpoint = Intersection{};

        if (ray.maxT() >= ro.Ray_max_t) {
            hpoint.t = ro.Ray_max_t;
            hpoint.primitive = 0;
        }

        return hpoint;
    }

    pub fn fragment(ray: Ray, frag: *Fragment) void {
        const xyz = math.normalize3(frag.trafo.rotation.transformVectorTransposed(ray.direction));

        frag.uvw = .{
            std.math.atan2(xyz[0], xyz[2]) * (math.pi_inv * 0.5) + 0.5,
            std.math.acos(xyz[1]) * math.pi_inv,
            0.0,
            0.0,
        };

        // This is nonsense
        const dir = Vec4f{ ray.direction[0], ray.direction[1], ray.direction[2], 0.0 };
        frag.p = @as(Vec4f, @splat(ro.Ray_max_t)) * dir;
        const n = -dir;
        frag.geo_n = n;
        frag.t = frag.trafo.rotation.r[0];
        frag.b = frag.trafo.rotation.r[1];
        frag.n = n;
        frag.part = 0;
    }

    pub fn sampleTo(n: Vec4f, trafo: Trafo, total_sphere: bool, sampler: *Sampler, buffer: *Scene.SamplesTo) []SampleTo {
        const uv = sampler.sample2D();

        var dir: Vec4f = undefined;
        var pdf_: f32 = undefined;

        if (total_sphere) {
            dir = math.smpl.sphereUniform(uv);
            pdf_ = 1.0 / (4.0 * std.math.pi);
        } else {
            const dir_l = math.smpl.hemisphereUniform(uv);
            const frame = Frame.init(n);
            dir = frame.frameToWorld(dir_l);

            if (math.dot3(dir, n) <= 0.0) {
                return buffer[0..0];
            }

            pdf_ = 1.0 / (2.0 * std.math.pi);
        }

        const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(dir));
        const uvw = Vec4f{
            std.math.atan2(xyz[0], xyz[2]) * (math.pi_inv * 0.5) + 0.5,
            std.math.acos(xyz[1]) * math.pi_inv,
            0.0,
            0.0,
        };

        buffer[0] = SampleTo.init(
            @as(Vec4f, @splat(ro.Ray_max_t)) * dir,
            -dir,
            dir,
            uvw,
            pdf_,
        );
        return buffer[0..1];
    }

    pub fn sampleToUv(uv: Vec2f, trafo: Trafo) SampleTo {
        const phi = (uv[0] - 0.5) * (2.0 * std.math.pi);
        const theta = uv[1] * std.math.pi;

        const sin_phi = @sin(phi);
        const cos_phi = @cos(phi);

        const sin_theta = @sin(theta);
        const cos_theta = @cos(theta);

        const ldir = Vec4f{ sin_phi * sin_theta, cos_theta, cos_phi * sin_theta, 0.0 };
        const dir = trafo.rotation.transformVector(ldir);

        return SampleTo.init(
            @as(Vec4f, @splat(ro.Ray_max_t)) * dir,
            -dir,
            dir,
            .{ uv[0], uv[1], 0.0, 0.0 },
            1.0 / ((4.0 * std.math.pi) * sin_theta),
        );
    }

    pub fn sampleFrom(trafo: Trafo, uv: Vec2f, importance_uv: Vec2f, bounds: AABB, from_image: bool) ?SampleFrom {
        const phi = (uv[0] - 0.5) * (2.0 * std.math.pi);
        const theta = uv[1] * std.math.pi;

        const sin_phi = @sin(phi);
        const cos_phi = @cos(phi);

        const sin_theta = @sin(theta);
        const cos_theta = @cos(theta);

        const ls = Vec4f{ sin_phi * sin_theta, cos_theta, cos_phi * sin_theta, 0.0 };
        const dir = -trafo.rotation.transformVector(ls);
        const tb = math.orthonormalBasis3(dir);

        const rotation = Mat3x3.init3(tb[0], tb[1], dir);

        const ls_bounds = bounds.transformTransposed(rotation);
        const ls_extent = ls_bounds.extent();
        const ls_rect = (importance_uv - @as(Vec2f, @splat(0.5))) * Vec2f{ ls_extent[0], ls_extent[1] };
        const photon_rect = rotation.transformVector(.{ ls_rect[0], ls_rect[1], 0.0, 0.0 });

        const offset = @as(Vec4f, @splat(ls_extent[2])) * dir;
        const p = ls_bounds.position() - offset + photon_rect;

        var ipdf = (4.0 * std.math.pi) * ls_extent[0] * ls_extent[1];
        if (from_image) {
            ipdf *= sin_theta;
        }

        return SampleFrom.init(
            p,
            dir,
            dir,
            .{ uv[0], uv[1], 0.0, 0.0 },
            importance_uv,
            trafo,
            1.0 / ipdf,
        );
    }

    pub fn pdf(total_sphere: bool) f32 {
        if (total_sphere) {
            return 1.0 / (4.0 * std.math.pi);
        }

        return 1.0 / (2.0 * std.math.pi);
    }

    pub fn pdfUv(frag: *const Fragment) f32 {
        // sin_theta because of the uv weight
        const sin_theta = @sin(frag.uvw[1] * std.math.pi);

        if (0.0 == sin_theta) {
            return 0.0;
        }

        return 1.0 / ((4.0 * std.math.pi) * sin_theta);
    }
};
