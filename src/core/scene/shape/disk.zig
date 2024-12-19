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
const LowThreshold = @import("../../rendering/integrator/helper.zig").LightSampling.LowThreshold;

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

    pub fn visibility(ray: Ray, trafo: Trafo, entity: u32, sampler: *Sampler, scene: *const Scene, tr: *Vec4f) bool {
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

                return scene.propMaterial(entity, 0).visibility(ray.direction, normal, uv, sampler, scene, tr);
            }
        }

        return true;
    }

    pub fn sampleTo(
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        two_sided: bool,
        total_sphere: bool,
        sampler: *Sampler,
        buffer: *Scene.SamplesTo,
    ) []SampleTo {
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

        if (c < math.safe.Dot_min or (math.dot3(dir, n) <= 0.0 and !total_sphere)) {
            return buffer[0..0];
        }

        const radius = trafo.scaleX();
        const area = std.math.pi * (radius * radius);

        buffer[0] = SampleTo.init(ws, wn, dir, @splat(0.0), sl / (c * area));
        return buffer[0..1];
    }

    pub fn sampleMaterialTo(
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        two_sided: bool,
        total_sphere: bool,
        split_threshold: f32,
        material: *const Material,
        sampler: *Sampler,
        buffer: *Scene.SamplesTo,
    ) []SampleTo {
        const num_samples = if (split_threshold <= LowThreshold) 1 else material.super().emittance.num_samples;

        const nsf: f32 = @floatFromInt(num_samples);

        const radius = trafo.scaleX();
        const area = std.math.pi * (radius * radius);

        var current_sample: u32 = 0;

        for (0..num_samples) |_| {
            const r2 = sampler.sample2D();
            const rs = material.radianceSample(.{ r2[0], r2[1], 0.0, 0.0 });
            if (0.0 == rs.pdf()) {
                continue;
            }

            const uv = Vec2f{ rs.uvw[0], rs.uvw[1] };

            const uv2 = @as(Vec2f, @splat(-2.0)) * uv + @as(Vec2f, @splat(1.0));
            const ls = Vec4f{ uv2[0], uv2[1], 0.0, 0.0 };

            const k = @as(Vec4f, @splat(radius)) * trafo.rotation.transformVector(ls);
            const l = math.dot3(k, k);
            if (l > radius * radius) {
                continue;
            }

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

            if (c < math.safe.Dot_min or (math.dot3(dir, n) <= 0.0 and !total_sphere)) {
                continue;
            }

            buffer[current_sample] = SampleTo.init(
                ws,
                wn,
                dir,
                .{ uv[0], uv[1], 0.0, 0.0 },
                (nsf * rs.pdf() * sl) / (c * area),
            );
            current_sample += 1;
        }

        return buffer[0..current_sample];
    }

    pub fn uvWeight(uv: Vec2f) f32 {
        const disk = Vec2f{ 2.0 * uv[0] - 1.0, 2.0 * uv[1] - 1.0 };
        const l = math.squaredLength2(disk);
        if (l > 1.0) {
            return 0.0;
        }

        return 1.0;
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

    pub fn materialPdf(
        dir: Vec4f,
        p: Vec4f,
        frag: *const Fragment,
        two_sided: bool,
        split_threshold: f32,
        material: *const Material,
    ) f32 {
        var c = -math.dot3(frag.trafo.rotation.r[2], dir);

        if (two_sided) {
            c = @abs(c);
        }

        const radius = frag.trafo.scaleX();
        const area = std.math.pi * (radius * radius);

        const sl = math.squaredDistance3(p, frag.p);

        const num_samples = if (split_threshold <= LowThreshold) 1 else material.super().emittance.num_samples;
        const material_pdf = material.emissionPdf(frag.uvw) * @as(f32, @floatFromInt(num_samples));

        return (material_pdf * sl) / (c * area);
    }
};
