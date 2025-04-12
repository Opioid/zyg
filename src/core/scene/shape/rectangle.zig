const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Vertex = @import("../vertex.zig").Vertex;
const Renderstate = @import("../renderstate.zig").Renderstate;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const DifferentialSurface = int.DifferentialSurface;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Worker = @import("../../rendering/worker.zig").Worker;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const Material = @import("../material/material.zig").Material;
const Scene = @import("../scene.zig").Scene;
const ro = @import("../ray_offset.zig");

const base = @import("base");
const math = base.math;
const Frame = math.Frame;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");

pub const Rectangle = struct {
    pub fn intersect(ray: Ray, trafo: Trafo) Intersection {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        var hpoint = Intersection{};

        if (hit_t >= ray.min_t and ray.max_t >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];

            const u = math.dot3(t, k) / trafo.scaleX();
            if (u > 1.0 or u < -1.0) {
                return hpoint;
            }

            const b = -trafo.rotation.r[1];

            const v = math.dot3(b, k) / trafo.scaleY();
            if (v > 1.0 or v < -1.0) {
                return hpoint;
            }

            hpoint.u = u;
            hpoint.v = v;
            hpoint.t = hit_t;
            hpoint.primitive = 0;
        }

        return hpoint;
    }

    pub fn fragment(ray: Ray, frag: *Fragment) void {
        const p = ray.point(frag.isec.t);
        const n = frag.trafo.rotation.r[2];
        const t = -frag.trafo.rotation.r[0];
        const b = -frag.trafo.rotation.r[1];

        frag.p = p;
        frag.t = t;
        frag.b = b;
        frag.n = n;
        frag.geo_n = n;
        if (frag.trafo.scaleZ() < 0.0) {
            const k = p - frag.trafo.position;
            const u = math.dot3(t, k);
            const v = math.dot3(b, k);
            frag.uvw = .{ 0.5 * (u + 1.0), 0.5 * (v + 1.0), 0.0, 0.0 };
        } else {
            const u = frag.isec.u;
            const v = frag.isec.v;
            frag.uvw = .{ 0.5 * (u + 1.0), 0.5 * (v + 1.0), 0.0, 0.0 };
        }
        frag.part = 0;
    }

    pub fn intersectP(ray: Ray, trafo: Trafo) bool {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t >= ray.min_t and ray.max_t >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];

            const u = math.dot3(t, k) / trafo.scaleX();
            if (u > 1.0 or u < -1.0) {
                return false;
            }

            const b = -trafo.rotation.r[1];

            const v = math.dot3(b, k) / trafo.scaleY();
            if (v > 1.0 or v < -1.0) {
                return false;
            }

            return true;
        }

        return false;
    }

    pub fn visibility(ray: Ray, trafo: Trafo, entity: u32, sampler: *Sampler, worker: *const Worker, tr: *Vec4f) bool {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t >= ray.min_t and ray.max_t >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];

            const u = math.dot3(t, k) / trafo.scaleX();
            if (u > 1.0 or u < -1.0) {
                return true;
            }

            const b = -trafo.rotation.r[1];

            const v = math.dot3(b, k) / trafo.scaleY();
            if (v > 1.0 or v < -1.0) {
                return true;
            }

            const uv = Vec2f{ 0.5 * (u + 1.0), 0.5 * (v + 1.0) };

            var rs: Renderstate = undefined;
            rs.geo_n = n;
            rs.uvw = .{ uv[0], uv[1], 0.0, 0.0 };

            return worker.scene.propMaterial(entity, 0).visibility(ray.direction, rs, sampler, worker, tr);
        }

        return true;
    }

    pub fn emission(vertex: *const Vertex, frag: *Fragment, split_threshold: f32, sampler: *Sampler, worker: *const Worker) Vec4f {
        const hit = intersect(vertex.probe.ray, frag.trafo);
        if (Intersection.Null == hit.primitive) {
            return @splat(0.0);
        }

        frag.isec = hit;

        fragment(vertex.probe.ray, frag);

        const p = vertex.origin;
        const wo = -vertex.probe.ray.direction;

        const energy = frag.evaluateRadiance(p, wo, sampler, worker) orelse return @splat(0.0);

        const weight: Vec4f = @splat(worker.scene.lightPdf(vertex, frag, split_threshold));

        return energy * weight;
    }

    // C. Ureña & M. Fajardo & A. King / An Area-Preserving Parametrization for Spherical Rectangles
    const SphQuad = struct {
        o: Vec4f,
        x: Vec4f,
        y: Vec4f,
        z: Vec4f,
        z0: f32,
        x0: f32,
        y0: f32,
        x1: f32,
        y1: f32,
        b0: f32,
        b1: f32,
        k: f32,
        S: f32,

        pub fn init(scale: Vec4f, o: Vec4f) SphQuad {
            const s = Vec4f{ -scale[0], -scale[1], 0.0, 0.0 };
            const ex = Vec4f{ 2.0 * scale[0], 0.0, 0.0, 0.0 };
            const ey = Vec4f{ 0.0, 2.0 * scale[1], 0.0, 0.0 };

            var squad: SphQuad = undefined;

            squad.o = o;
            const exl = math.length3(ex);
            const eyl = math.length3(ey);
            // compute local reference system ’R’
            squad.x = ex / @as(Vec4f, @splat(exl));
            squad.y = ey / @as(Vec4f, @splat(eyl));
            squad.z = math.cross3(squad.x, squad.y);
            // compute rectangle coords in local reference system
            const d = s - o;
            squad.z0 = math.dot3(d, squad.z);
            // flip ’z’ to make it point against ’Q’
            if (squad.z0 > 0.0) {
                squad.z = -squad.z;
                squad.z0 = -squad.z0;
            }
            squad.x0 = math.dot3(d, squad.x);
            squad.y0 = math.dot3(d, squad.y);
            squad.x1 = squad.x0 + exl;
            squad.y1 = squad.y0 + eyl;
            // create vectors to four vertices
            const v00 = Vec4f{ squad.x0, squad.y0, squad.z0, 0.0 };
            const v01 = Vec4f{ squad.x0, squad.y1, squad.z0, 0.0 };
            const v10 = Vec4f{ squad.x1, squad.y0, squad.z0, 0.0 };
            const v11 = Vec4f{ squad.x1, squad.y1, squad.z0, 0.0 };
            // compute normals to edges
            const n0 = math.normalize3(math.cross3(v00, v10));
            const n1 = math.normalize3(math.cross3(v10, v11));
            const n2 = math.normalize3(math.cross3(v11, v01));
            const n3 = math.normalize3(math.cross3(v01, v00));

            // compute internal angles (gamma_i)
            const g0 = std.math.acos(-math.dot3(n0, n1));
            const g1 = std.math.acos(-math.dot3(n1, n2));
            const g2 = std.math.acos(-math.dot3(n2, n3));
            const g3 = std.math.acos(-math.dot3(n3, n0));
            // compute predefined constants
            squad.b0 = n0[2];
            squad.b1 = n2[2];
            squad.k = 2.0 * std.math.pi - g2 - g3;
            // compute solid angle from internal angles
            squad.S = g0 + g1 - squad.k;

            return squad;
        }

        pub fn sample(squad: SphQuad, uv: Vec2f) Vec4f {
            // 1. compute ’cu’
            const au = uv[0] * squad.S + squad.k;
            const b0 = squad.b0;
            const fu = (@cos(au) * b0 - squad.b1) / @sin(au);
            var cu = 1.0 / @sqrt(fu * fu + b0 * b0) * @as(f32, (if (fu > 0.0) 1.0 else -1.0));
            cu = std.math.clamp(cu, -1.0, 1.0); // avoid NaNs
            // 2. compute ’xu’
            const z0 = squad.z0;
            var xu = -(cu * z0) / @sqrt(1 - cu * cu);
            xu = std.math.clamp(xu, squad.x0, squad.x1); // avoid Infs
            // 3. compute ’yv’
            const d = @sqrt(xu * xu + z0 * z0);
            const y0 = squad.y0;
            const h0 = y0 / @sqrt(d * d + y0 * y0);
            const y1 = squad.y1;
            const h1 = y1 / @sqrt(d * d + y1 * y1);
            const hv = h0 + uv[1] * (h1 - h0);
            const hv2 = hv * hv;
            const eps: f32 = comptime @bitCast(@as(u32, 0x35800000));
            const yv = if (hv2 < 1 - eps) ((hv * d) / @sqrt(1 - hv2)) else squad.y1;
            // 4. transform (xu,yv,z0) to world coords
            return squad.o + @as(Vec4f, @splat(xu)) * squad.x + @as(Vec4f, @splat(yv)) * squad.y + @as(Vec4f, @splat(squad.z0)) * squad.z;
        }

        pub fn pdf(squad: SphQuad, scale: Vec4f) f32 {
            const lp = squad.o;
            const sqr_dist = math.squaredLength3(lp);
            const area = 4.0 * scale[0] * scale[1];
            const diff_solid_angle_numer = area * @abs(lp[2]);
            const diff_solid_angle_denom = sqr_dist * @sqrt(sqr_dist);

            return if (diff_solid_angle_numer > diff_solid_angle_denom * math.safe.Dot_min)
                (1.0 / squad.S)
            else
                (diff_solid_angle_denom / diff_solid_angle_numer);
        }
    };

    pub fn sampleTo(
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
        const lp = trafo.worldToFramePoint(p);
        const scale = trafo.scale();

        const squad = SphQuad.init(scale, lp);

        const num_samples = material.numSamples(split_threshold);
        const nsf: f32 = @floatFromInt(num_samples);

        const sample_pdf = nsf * squad.pdf(scale);

        var current_sample: u32 = 0;
        for (0..num_samples) |_| {
            const uv = sampler.sample2D();

            const ls = squad.sample(uv);
            const ws = trafo.frameToWorldPoint(ls);
            const dir = math.normalize3(ws - p);

            var wn = trafo.rotation.r[2];
            if (two_sided and math.dot3(wn, dir) > 0.0) {
                wn = -wn;
            }

            if (-math.dot3(wn, dir) < math.safe.Dot_min or 0.0 == squad.S or
                (math.dot3(dir, n) <= 0.0 and !total_sphere))
            {
                continue;
            }

            buffer[current_sample] = SampleTo.init(
                ws,
                wn,
                dir,
                .{ uv[0], uv[1], 0.0, 0.0 },
                sample_pdf,
            );
            current_sample += 1;
        }

        return buffer[0..current_sample];
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
        const num_samples = material.numSamples(split_threshold);
        const nsf: f32 = @floatFromInt(num_samples);

        const scale = trafo.scale();
        const area = 4.0 * scale[0] * scale[1];

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
            const ws = trafo.objectToWorldPoint(ls);
            const axis = ws - p;

            var wn = trafo.rotation.r[2];

            if (two_sided and math.dot3(wn, axis) > 0.0) {
                wn = -wn;
            }

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

    pub fn sampleFrom(trafo: Trafo, two_sided: bool, sampler: *Sampler, uv: Vec2f, importance_uv: Vec2f) SampleFrom {
        const uv2 = @as(Vec2f, @splat(-2.0)) * uv + @as(Vec2f, @splat(1.0));
        const ls = Vec4f{ uv2[0], uv2[1], 0.0, 0.0 };
        const ws = trafo.objectToWorldPoint(ls);

        var wn = trafo.rotation.r[2];
        const frame: Frame = .{ .x = trafo.rotation.r[0], .y = trafo.rotation.r[1], .z = wn };

        const dir_l = math.smpl.hemisphereCosine(importance_uv);
        var dir = frame.frameToWorld(dir_l);

        if (two_sided and sampler.sample1D() > 0.5) {
            wn = -wn;
            dir = -dir;
        }

        const scale = trafo.scale();
        const area = @as(f32, if (two_sided) 8.0 else 4.0) * (scale[0] * scale[1]);

        return SampleFrom.init(
            ro.offsetRay(ws, wn),
            wn,
            dir,
            .{ uv[0], uv[1], 0.0, 0.0 },
            importance_uv,
            trafo,
            1.0 / (std.math.pi * area),
        );
    }

    pub fn pdf(p: Vec4f, trafo: Trafo, split_threshold: f32, material: *const Material) f32 {
        const lp = trafo.worldToFramePoint(p);

        const scale = trafo.scale();
        const squad = SphQuad.init(scale, lp);

        const num_samples = material.numSamples(split_threshold);
        return @as(f32, @floatFromInt(num_samples)) * squad.pdf(scale);
    }

    pub fn materialPdf(dir: Vec4f, p: Vec4f, frag: *const Fragment, split_threshold: f32, material: *const Material) f32 {
        const c = @abs(math.dot3(frag.trafo.rotation.r[2], dir));

        const scale = frag.trafo.scale();
        const area = 4.0 * (scale[0] * scale[1]);

        const sl = math.squaredDistance3(p, frag.p);

        const num_samples = material.numSamples(split_threshold);
        const material_pdf = material.emissionPdf(frag.uvw) * @as(f32, @floatFromInt(num_samples));

        return (material_pdf * sl) / (c * area);
    }

    pub fn surfaceDifferential(trafo: Trafo) DifferentialSurface {
        if (trafo.scaleZ() < 0.0) {
            return .{ .dpdu = .{ -2.0 / trafo.scaleX(), 0.0, 0.0, 0.0 }, .dpdv = .{ 0.0, -2.0 / trafo.scaleY(), 0.0, 0.0 } };
        } else {
            return .{ .dpdu = .{ -2.0, 0.0, 0.0, 0.0 }, .dpdv = .{ 0.0, -2.0, 0.0, 0.0 } };
        }
    }
};
