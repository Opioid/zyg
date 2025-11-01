const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Vertex = @import("../vertex.zig").Vertex;
const Renderstate = @import("../renderstate.zig").Renderstate;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const DifferentialSurface = int.DifferentialSurface;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const Context = @import("../context.zig").Context;
const Portal = @import("portal.zig").Portal;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const ShapeSampler = @import("shape_sampler.zig").Sampler;
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
    const UseSphericalSampling = true;

    pub fn intersect(ray: Ray, trafo: Trafo, isec: *Intersection) bool {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t >= ray.min_t and ray.max_t >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];

            const u = math.dot3(t, k) / (0.5 * trafo.scaleX());
            if (u > 1.0 or u < -1.0) {
                return false;
            }

            const b = -trafo.rotation.r[1];

            const v = math.dot3(b, k) / (0.5 * trafo.scaleY());
            if (v > 1.0 or v < -1.0) {
                return false;
            }

            isec.u = u;
            isec.v = v;
            isec.t = hit_t;
            isec.primitive = 0;
            isec.prototype = Intersection.Null;
            isec.trafo = trafo;
            return true;
        }

        return false;
    }

    pub fn intersectOpacity(ray: Ray, trafo: Trafo, entity: u32, sampler: *Sampler, scene: *const Scene, isec: *Intersection) bool {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t >= ray.min_t and ray.max_t >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];

            const u = math.dot3(t, k) / (0.5 * trafo.scaleX());
            if (u > 1.0 or u < -1.0) {
                return false;
            }

            const b = -trafo.rotation.r[1];

            const v = math.dot3(b, k) / (0.5 * trafo.scaleY());
            if (v > 1.0 or v < -1.0) {
                return false;
            }

            if (!scene.propOpacity(entity, 0, .{ 0.5 * (u + 1.0), 0.5 * (v + 1.0) }, sampler)) {
                return false;
            }

            isec.u = u;
            isec.v = v;
            isec.t = hit_t;
            isec.primitive = 0;
            isec.prototype = Intersection.Null;
            isec.trafo = trafo;
            return true;
        }

        return false;
    }

    pub fn fragment(ray: Ray, frag: *Fragment) void {
        const p = ray.point(frag.isec.t);
        const n = frag.isec.trafo.rotation.r[2];
        const t = -frag.isec.trafo.rotation.r[0];
        const b = -frag.isec.trafo.rotation.r[1];

        frag.p = p;
        frag.t = t;
        frag.b = b;
        frag.n = n;
        frag.geo_n = n;
        if (frag.isec.trafo.scaleZ() < 0.0) {
            const k = p - frag.isec.trafo.position;
            const u = math.dot3(t, k) * 2.0;
            const v = math.dot3(b, k) * 2.0;
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

            const u = math.dot3(t, k) / (0.5 * trafo.scaleX());
            if (u > 1.0 or u < -1.0) {
                return false;
            }

            const b = -trafo.rotation.r[1];

            const v = math.dot3(b, k) / (0.5 * trafo.scaleY());
            if (v > 1.0 or v < -1.0) {
                return false;
            }

            return true;
        }

        return false;
    }

    pub fn visibility(ray: Ray, trafo: Trafo, entity: u32, sampler: *Sampler, context: Context, tr: *Vec4f) bool {
        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, ray.origin) - d) / math.dot3(n, ray.direction);

        if (hit_t >= ray.min_t and ray.max_t >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const t = -trafo.rotation.r[0];

            const u = math.dot3(t, k) / (0.5 * trafo.scaleX());
            if (u > 1.0 or u < -1.0) {
                return true;
            }

            const b = -trafo.rotation.r[1];

            const v = math.dot3(b, k) / (0.5 * trafo.scaleY());
            if (v > 1.0 or v < -1.0) {
                return true;
            }

            const uv = Vec2f{ 0.5 * (u + 1.0), 0.5 * (v + 1.0) };

            var rs: Renderstate = undefined;
            rs.geo_n = n;
            rs.uvw = .{ uv[0], uv[1], 0.0, 0.0 };

            return context.scene.propMaterial(entity, 0).visibility(ray.direction, rs, sampler, context, tr);
        }

        return true;
    }

    pub fn emission(vertex: *const Vertex, frag: *Fragment, sampler: *Sampler, context: Context) Vec4f {
        if (!intersect(vertex.probe.ray, frag.isec.trafo, &frag.isec)) {
            return @splat(0.0);
        }

        fragment(vertex.probe.ray, frag);

        return vertex.evaluateRadiance(frag, sampler, context);
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
            const s = Vec4f{ -0.5 * scale[0], -0.5 * scale[1], 0.0, 0.0 };
            const ex = Vec4f{ scale[0], 0.0, 0.0, 0.0 };
            const ey = Vec4f{ 0.0, scale[1], 0.0, 0.0 };

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
            const area = scale[0] * scale[1];
            const diff_solid_angle_numer = area * @abs(lp[2]);
            const diff_solid_angle_denom = sqr_dist * @sqrt(sqr_dist);

            return if (diff_solid_angle_numer > diff_solid_angle_denom * math.safe.DotMin)
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
        shape_sampler: *const ShapeSampler,
        sampler: *Sampler,
        buffer: *Scene.SamplesTo,
    ) []SampleTo {
        const num_samples = shape_sampler.numSamples(split_threshold);
        const nsf: f32 = @floatFromInt(num_samples);

        const scale = trafo.scale();

        if (UseSphericalSampling) {
            const lp = trafo.worldToFramePoint(p);

            const squad = SphQuad.init(scale, lp);

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

                if (-math.dot3(wn, dir) < math.safe.DotMin or 0.0 == squad.S or
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
        } else {
            const area = scale[0] * scale[1];

            var current_sample: u32 = 0;
            for (0..num_samples) |_| {
                const uv = sampler.sample2D();

                const uv2 = @as(Vec2f, @splat(-1.0)) * uv + @as(Vec2f, @splat(0.5));
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

                if (c < math.safe.DotMin or (math.dot3(dir, n) <= 0.0 and !total_sphere)) {
                    continue;
                }

                buffer[current_sample] = SampleTo.init(
                    ws,
                    wn,
                    dir,
                    .{ uv[0], uv[1], 0.0, 0.0 },
                    (nsf * sl) / (c * area),
                );
                current_sample += 1;
            }

            return buffer[0..current_sample];
        }
    }

    pub fn sampleMaterialTo(
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        two_sided: bool,
        total_sphere: bool,
        split_threshold: f32,
        shape_sampler: *const ShapeSampler,
        sampler: *Sampler,
        buffer: *Scene.SamplesTo,
    ) []SampleTo {
        const num_samples = shape_sampler.numSamples(split_threshold);
        const nsf: f32 = @floatFromInt(num_samples);

        const scale = trafo.scale();
        const area = scale[0] * scale[1];

        var current_sample: u32 = 0;
        for (0..num_samples) |_| {
            const r2 = sampler.sample2D();
            const rs = shape_sampler.impl.sample(.{ r2[0], r2[1], 0.0, 0.0 });
            if (0.0 == rs.pdf()) {
                continue;
            }

            const uv = Vec2f{ rs.uvw[0], rs.uvw[1] };
            const uv2 = @as(Vec2f, @splat(-1.0)) * uv + @as(Vec2f, @splat(0.5));
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

            if (c < math.safe.DotMin or (math.dot3(dir, n) <= 0.0 and !total_sphere)) {
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

    pub fn samplePortalTo(
        p: Vec4f,
        n: Vec4f,
        trafo: Trafo,
        time: u64,
        total_sphere: bool,
        split_threshold: f32,
        shape_sampler: *const ShapeSampler,
        sampler: *Sampler,
        scene: *const Scene,
        buffer: *Scene.SamplesTo,
    ) []SampleTo {
        const bounds = Portal.imageBounds(p, trafo) orelse return buffer[0..0];

        const num_samples = shape_sampler.numSamples(split_threshold);
        const nsf: f32 = @floatFromInt(num_samples);

        var current_sample: u32 = 0;
        for (0..num_samples) |_| {
            const r2 = sampler.sample2D();
            const rs = shape_sampler.impl.Portal.sample(bounds, r2);
            if (0.0 == rs.pdf()) {
                continue;
            }

            const uv = Vec2f{ rs.uvw[0], rs.uvw[1] };
            const ps = Portal.imageToWorld(uv, trafo);
            const dir = -ps.dir;

            if ((math.dot3(dir, n) <= 0.0 and !total_sphere) or 0.0 == ps.weight) {
                continue;
            }

            const wn = trafo.rotation.r[2];

            const d = math.dot3(wn, trafo.position);
            const hit_t = -(math.dot3(wn, p) - d) / math.dot3(wn, dir);

            const ws = p + @as(Vec4f, @splat(hit_t)) * dir;

            const uvw = shape_sampler.impl.Portal.portalUvw(dir, time, scene);

            buffer[current_sample] = SampleTo.init(
                ws,
                wn,
                dir,
                uvw,
                (nsf * rs.pdf()) / ps.weight,
            );
            current_sample += 1;
        }

        return buffer[0..current_sample];
    }

    pub fn sampleFrom(
        trafo: Trafo,
        uv: Vec2f,
        importance_uv: Vec2f,
        time: u64,
        two_sided: bool,
        shape_sampler: *const ShapeSampler,
        sampler: *Sampler,
        scene: *const Scene,
    ) SampleFrom {
        const uv2 = @as(Vec2f, @splat(-1.0)) * uv + @as(Vec2f, @splat(0.5));
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
        const area = @as(f32, if (two_sided) 4.0 else 1.0) * (scale[0] * scale[1]);

        const uvw = shape_sampler.impl.portalUvw(.{ uv[0], uv[1], 0.0, 0.0 }, -dir, time, scene);

        return SampleFrom.init(
            ro.offsetRay(ws, wn),
            wn,
            dir,
            uvw,
            importance_uv,
            trafo,
            1.0 / (std.math.pi * area),
        );
    }

    pub fn pdf(dir: Vec4f, p: Vec4f, frag: *const Fragment, split_threshold: f32, shape_sampler: *const ShapeSampler) f32 {
        const num_samples = shape_sampler.numSamples(split_threshold);
        const nsf: f32 = @floatFromInt(num_samples);

        const scale = frag.isec.trafo.scale();

        if (UseSphericalSampling) {
            const lp = frag.isec.trafo.worldToFramePoint(p);

            const squad = SphQuad.init(scale, lp);

            return nsf * squad.pdf(scale);
        } else {
            const c = @abs(math.dot3(frag.isec.trafo.rotation.r[2], dir));

            const area = scale[0] * scale[1];

            const sl = math.squaredDistance3(p, frag.p);

            return (nsf * sl) / (c * area);
        }
    }

    pub fn materialPdf(
        dir: Vec4f,
        p: Vec4f,
        frag: *const Fragment,
        split_threshold: f32,
        shape_sampler: *const ShapeSampler,
    ) f32 {
        const c = @abs(math.dot3(frag.isec.trafo.rotation.r[2], dir));

        const scale = frag.isec.trafo.scale();
        const area = scale[0] * scale[1];

        const sl = math.squaredDistance3(p, frag.p);

        const num_samples = shape_sampler.numSamples(split_threshold);
        const material_pdf = shape_sampler.impl.pdf(frag.uvw) * @as(f32, @floatFromInt(num_samples));

        return (material_pdf * sl) / (c * area);
    }

    pub fn portalPdf(
        dir: Vec4f,
        p: Vec4f,
        frag: *const Fragment,
        split_threshold: f32,
        shape_sampler: *const ShapeSampler,
    ) f32 {
        const ps = Portal.worldToImageWeighted(-dir, frag.isec.trafo) orelse return 0.0;

        const ppdf = shape_sampler.impl.Portal.pdf(p, ps.uv, frag.isec.trafo);

        const num_samples = shape_sampler.numSamples(split_threshold);

        return (ppdf * @as(f32, @floatFromInt(num_samples))) / ps.weight;
    }

    pub fn surfaceDifferentials(trafo: Trafo) DifferentialSurface {
        if (trafo.scaleZ() < 0.0) {
            return .{ .dpdu = -trafo.rotation.r[0], .dpdv = -trafo.rotation.r[1] };
        } else {
            return .{
                .dpdu = @as(Vec4f, @splat(-trafo.scaleX())) * trafo.rotation.r[0],
                .dpdv = @as(Vec4f, @splat(-trafo.scaleY())) * trafo.rotation.r[1],
            };
        }
    }
};
