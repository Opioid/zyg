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
const Frame = math.Frame;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const Disk = struct {
    pub fn intersect(ray: Ray, trafo: Trafo) Intersection {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        var hpoint = Intersection{};

        if (hit_t >= ray.minT() and ray.maxT() >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const l = math.dot3(k, k);
            const radius = trafo.scaleX();

            if (l <= radius * radius) {
                const t = -trafo.rotation.r[0];
                const b = -trafo.rotation.r[1];

                const sk = k / @as(Vec4f, @splat(radius));
                hpoint.u = math.dot3(t, sk);
                hpoint.v = math.dot3(b, sk);

                hpoint.t = hit_t;
                hpoint.primitive = 0;
            }
        }

        return hpoint;
    }

    pub fn fragment(ray: Ray, frag: *Fragment) void {
        const u = frag.isec.u;
        const v = frag.isec.v;

        const n = frag.trafo.rotation.r[2];
        const t = -frag.trafo.rotation.r[0];
        const b = -frag.trafo.rotation.r[1];

        frag.p = ray.point(ray.maxT());
        frag.t = t;
        frag.b = b;
        frag.n = n;
        frag.geo_n = n;
        frag.uvw = .{ 0.5 * (u + 1.0), 0.5 * (v + 1.0), 0.0, 0.0 };
        frag.part = 0;
    }

    pub fn intersectP(ray: Ray, trafo: Trafo) bool {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t >= ray.minT() and ray.maxT() >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const l = math.dot3(k, k);
            const radius = trafo.scaleX();

            if (l <= radius * radius) {
                return true;
            }
        }

        return false;
    }

    pub fn visibility(ray: Ray, trafo: Trafo, entity: u32, sampler: *Sampler, scene: *const Scene) ?Vec4f {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t >= ray.minT() and ray.maxT() >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const l = math.dot3(k, k);
            const radius = trafo.scaleX();

            if (l <= radius * radius) {
                const t = trafo.rotation.r[0];
                const b = trafo.rotation.r[1];

                const sk = k / @as(Vec4f, @splat(radius));

                const uv = Vec2f{
                    0.5 * (1.0 - math.dot3(t, sk)),
                    0.5 * (1.0 - math.dot3(b, sk)),
                };

                return scene.propMaterial(entity, 0).visibility(ray.direction, normal, uv, sampler, scene);
            }
        }

        return @as(Vec4f, @splat(1.0));
    }

    pub fn sampleTo(p: Vec4f, trafo: Trafo, two_sided: bool, sampler: *Sampler) ?SampleTo {
        const r2 = sampler.sample2D();
        const xy = math.smpl.diskConcentric(r2);

        const ls = Vec4f{ xy[0], xy[1], 0.0, 0.0 };
        const ws = trafo.position + @as(Vec4f, @splat(trafo.scaleX())) * trafo.rotation.transformVector(ls);
        var wn = trafo.rotation.r[2];

        if (two_sided and math.dot3(wn, ws - p) > 0.0) {
            wn = -wn;
        }

        const axis = ws - p;
        const sl = math.squaredLength3(axis);
        const t = @sqrt(sl);
        const dir = axis / @as(Vec4f, @splat(t));
        const c = -math.dot3(wn, dir);

        if (c < math.safe.Dot_min) {
            return null;
        }

        const radius = trafo.scaleX();
        const area = std.math.pi * (radius * radius);

        return SampleTo.init(ws, wn, dir, @splat(0.0), trafo, sl / (c * area));
    }

    pub fn sampleToUv(p: Vec4f, uv: Vec2f, trafo: Trafo, two_sided: bool) ?SampleTo {
        const uv2 = @as(Vec2f, @splat(-2.0)) * uv + @as(Vec2f, @splat(1.0));
        const ls = Vec4f{ uv2[0], uv2[1], 0.0, 0.0 };

        const radius = trafo.scaleX();
        const k = @as(Vec4f, @splat(radius)) * trafo.rotation.transformVector(ls);

        const l = math.dot3(k, k);

        if (l <= radius * radius) {
            const ws = trafo.position + k;
            var wn = trafo.rotation.r[2];

            if (two_sided and math.dot3(wn, ws - p) > 0.0) {
                wn = -wn;
            }

            const axis = ws - p;
            const sl = math.squaredLength3(axis);
            const t = @sqrt(sl);
            const dir = axis / @as(Vec4f, @splat(t));
            const c = -math.dot3(wn, dir);

            if (c < math.safe.Dot_min) {
                return null;
            }

            const area = std.math.pi * (radius * radius);

            return SampleTo.init(ws, wn, dir, .{ uv[0], uv[1], 0.0, 0.0 }, trafo, sl / (c * area));
        }

        return null;
    }

    pub fn sampleFrom(
        trafo: Trafo,
        cos_a: f32,
        two_sided: bool,
        sampler: *Sampler,
        uv: Vec2f,
        importance_uv: Vec2f,
    ) ?SampleFrom {
        const xy = math.smpl.diskConcentric(uv);
        const ls = Vec4f{ xy[0], xy[1], 0.0, 0.0 };
        const ws = trafo.position + @as(Vec4f, @splat(trafo.scaleX())) * trafo.rotation.transformVector(ls);
        const uvw = Vec4f{ uv[0], uv[1], 0.0, 0.0 };

        const radius = trafo.scaleX();
        const area = @as(f32, if (two_sided) 2.0 * std.math.pi else std.math.pi) * (radius * radius);

        var wn = trafo.rotation.r[2];
        const frame: Frame = .{ .x = trafo.rotation.r[0], .y = trafo.rotation.r[1], .z = wn };

        var dir_l: Vec4f = undefined;
        var pdf_: f32 = undefined;

        if (cos_a < math.safe.Dot_min) {
            dir_l = math.smpl.hemisphereCosine(importance_uv);
            pdf_ = 1.0 / (std.math.pi * area);
        } else {
            dir_l = math.smpl.coneCosine(importance_uv, cos_a);
            pdf_ = math.smpl.conePdfCosine(cos_a) / area;
        }

        var dir = frame.frameToWorld(dir_l);

        if (two_sided and sampler.sample1D() > 0.5) {
            wn = -wn;
            dir = -dir;
        }

        return SampleFrom.init(ro.offsetRay(ws, wn), wn, dir, uvw, importance_uv, trafo, pdf_);
    }

    pub fn pdf(dir: Vec4f, p: Vec4f, frag: *const Fragment, two_sided: bool) f32 {
        var c = -math.dot3(frag.trafo.rotation.r[2], dir);

        if (two_sided) {
            c = @abs(c);
        }

        const radius = frag.trafo.scaleX();
        const area = std.math.pi * (radius * radius);

        const sl = math.squaredDistance3(p, frag.p);
        return sl / (c * area);
    }
};
