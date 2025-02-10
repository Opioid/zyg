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
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const DistantSphere = struct {
    pub fn intersect(ray: Ray, trafo: Trafo) Intersection {
        var hpoint = Intersection{};

        const radius = trafo.scaleX();

        const n = trafo.rotation.r[2];
        const b = math.dot3(n, ray.direction);

        if (b > 0.0 or ray.max_t < ro.RayMaxT or radius <= 0.0) {
            return hpoint;
        }

        const det = (b * b) - math.dot3(n, n) + (radius * radius);

        if (det >= 0.0) {
            const k = ray.direction - n;
            const sk = k / @as(Vec4f, @splat(radius));

            const isec_t = trafo.rotation.r[0];
            const isec_b = trafo.rotation.r[1];

            hpoint.u = math.dot3(isec_t, sk);
            hpoint.v = math.dot3(isec_b, sk);

            hpoint.primitive = 0;
            hpoint.t = ro.RayMaxT;
        }

        return hpoint;
    }

    pub fn fragment(ray: Ray, frag: *Fragment) void {
        frag.p = @as(Vec4f, @splat(ro.RayMaxT)) * ray.direction;

        const n = frag.trafo.rotation.r[2];

        frag.geo_n = n;
        frag.t = frag.trafo.rotation.r[0];
        frag.b = frag.trafo.rotation.r[1];
        frag.n = n;

        frag.uvw = .{
            (frag.isec.u + 1.0) * 0.5,
            (frag.isec.v + 1.0) * 0.5,
            0.0,
            0.0,
        };

        frag.part = 0;
    }

    pub fn intersectP(ray: Ray, trafo: Trafo) bool {
        const radius = trafo.scaleX();

        const n = trafo.rotation.r[2];
        const b = math.dot3(n, ray.direction);

        if (b > 0.0 or ray.max_t < ro.RayMaxT or radius <= 0.0) {
            return false;
        }

        const det = (b * b) - math.dot3(n, n) + (radius * radius);

        return det >= 0.0;
    }

    pub fn sampleTo(n: Vec4f, trafo: Trafo, total_sphere: bool, sampler: *Sampler, buffer: *Scene.SamplesTo) []SampleTo {
        const radius = trafo.scaleX();
        if (radius <= 0.0) {
            return buffer[0..0];
        }

        const r2 = sampler.sample2D();
        const xy = math.smpl.diskConcentric(r2);

        const ls = Vec4f{ xy[0], xy[1], 0.0, 0.0 };

        const ws = @as(Vec4f, @splat(radius)) * trafo.rotation.transformVector(ls);

        const dir = math.normalize3(ws - trafo.rotation.r[2]);

        if (math.dot3(dir, n) <= 0.0 and !total_sphere) {
            return buffer[0..0];
        }

        const solid_angle = solidAngle(radius);

        buffer[0] = SampleTo.init(
            @as(Vec4f, @splat(ro.RayMaxT)) * dir,
            trafo.rotation.r[2],
            dir,
            @splat(0.0),
            1.0 / solid_angle,
        );
        return buffer[0..1];
    }

    pub fn sampleFrom(trafo: Trafo, uv: Vec2f, importance_uv: Vec2f, bounds: AABB) ?SampleFrom {
        const radius = trafo.scaleX();
        if (radius <= 0.0) {
            return null;
        }

        const xy = math.smpl.diskConcentric(uv);

        const ls = Vec4f{ xy[0], xy[1], 0.0, 0.0 };
        const ws = @as(Vec4f, @splat(radius)) * trafo.rotation.transformVector(ls);

        const dir = math.normalize3(trafo.rotation.r[2] - ws);

        const ls_bounds = bounds.transformTransposed(trafo.rotation);
        const ls_extent = ls_bounds.extent();
        const ls_rect = (importance_uv - @as(Vec2f, @splat(0.5))) * Vec2f{ ls_extent[0], ls_extent[1] };
        const photon_rect = trafo.rotation.transformVector(.{ ls_rect[0], ls_rect[1], 0.0, 0.0 });

        const offset = @as(Vec4f, @splat(ls_extent[2])) * dir;
        const p = ls_bounds.position() - offset + photon_rect;

        const solid_angle = solidAngle(radius);

        return SampleFrom.init(
            p,
            trafo.rotation.r[2],
            dir,
            .{ uv[0], uv[1], 0.0, 0.0 },
            importance_uv,
            trafo,
            1.0 / (solid_angle * ls_extent[0] * ls_extent[1]),
        );
    }

    pub fn pdf(trafo: Trafo) f32 {
        return 1.0 / solidAngle(trafo.scaleX());
    }

    pub fn solidAngle(radius: f32) f32 {
        return (2.0 * std.math.pi) * (1.0 - @sqrt(1.0 / (radius * radius + 1.0)));
    }
};
