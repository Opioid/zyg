const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Vertex = @import("../vertex.zig").Vertex;
const Renderstate = @import("../renderstate.zig").Renderstate;
const int = @import("intersection.zig");
const Intersection = int.Intersection;
const Fragment = int.Fragment;
const Sampler = @import("../../sampler/sampler.zig").Sampler;
const smpl = @import("sample.zig");
const SampleTo = smpl.To;
const SampleFrom = smpl.From;
const ShapeSampler = @import("shape_sampler.zig").Sampler;
const Context = @import("../context.zig").Context;
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
    const UseEquiAngularSampling = true;

    pub fn intersect(ray: Ray, trafo: Trafo, isec: *Intersection) bool {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t >= ray.min_t and ray.max_t >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const l = math.dot3(k, k);
            const radius = 0.5 * trafo.scaleX();

            if (l <= radius * radius) {
                const t = trafo.rotation.r[0];
                const b = trafo.rotation.r[1];

                const sk = k / @as(Vec4f, @splat(radius));
                isec.u = -math.dot3(t, sk);
                isec.v = -math.dot3(b, sk);

                isec.t = hit_t;
                isec.primitive = 0;
                isec.prototype = Intersection.Null;
                isec.trafo = trafo;
                return true;
            }
        }

        return false;
    }

    pub fn intersectOpacity(ray: Ray, trafo: Trafo, entity: u32, sampler: *Sampler, scene: *const Scene, isec: *Intersection) bool {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t >= ray.min_t and ray.max_t >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const l = math.dot3(k, k);
            const radius = 0.5 * trafo.scaleX();

            if (l <= radius * radius) {
                const t = trafo.rotation.r[0];
                const b = trafo.rotation.r[1];

                const sk = k / @as(Vec4f, @splat(radius));
                const u = -math.dot3(t, sk);
                const v = -math.dot3(b, sk);

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
        }

        return false;
    }

    pub fn fragment(ray: Ray, frag: *Fragment) void {
        const u = frag.isec.u;
        const v = frag.isec.v;

        const n = frag.isec.trafo.rotation.r[2];
        const t = -frag.isec.trafo.rotation.r[0];
        const b = -frag.isec.trafo.rotation.r[1];

        frag.p = ray.point(frag.isec.t);
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

        if (hit_t >= ray.min_t and ray.max_t >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const l = math.dot3(k, k);
            const radius = 0.5 * trafo.scaleX();

            if (l <= radius * radius) {
                return true;
            }
        }

        return false;
    }

    pub fn visibility(ray: Ray, trafo: Trafo, entity: u32, sampler: *Sampler, context: Context, tr: *Vec4f) bool {
        const normal = trafo.rotation.r[2];
        const d = math.dot3(normal, trafo.position);
        const denom = -math.dot3(normal, ray.direction);
        const numer = math.dot3(normal, ray.origin) - d;
        const hit_t = numer / denom;

        if (hit_t >= ray.min_t and ray.max_t >= hit_t) {
            const p = ray.point(hit_t);
            const k = p - trafo.position;
            const l = math.dot3(k, k);
            const radius = 0.5 * trafo.scaleX();

            if (l <= radius * radius) {
                const t = trafo.rotation.r[0];
                const b = trafo.rotation.r[1];

                const sk = k / @as(Vec4f, @splat(radius));

                const uv = Vec2f{
                    0.5 * (1.0 - math.dot3(t, sk)),
                    0.5 * (1.0 - math.dot3(b, sk)),
                };

                var rs: Renderstate = undefined;
                rs.geo_n = normal;
                rs.uvw = .{ uv[0], uv[1], 0.0, 0.0 };

                return context.scene.propMaterial(entity, 0).visibility(ray.direction, rs, sampler, context, tr);
            }
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

    const DiskSamplerData = struct {
        xd: Vec4f,
        yd: Vec4f,

        pub fn init(p: Vec4f) DiskSamplerData {
            const td = Vec4f{ p[1], -p[0], 0.0, 0.0 };

            const xd = if (td[0] == 0.0 and td[1] == 0.0 and td[2] == 0.0) Vec4f{ 1.0, 0.0, 0.0, 0.0 } else math.normalize3(td);

            return .{
                .xd = xd,
                .yd = .{ -xd[1], xd[0], 0.0, 0.0 },
            };
        }
    };

    const EquiAngularSampling = struct {
        offset: f32,
        min_t: f32,
        max_t: f32,
        scale: f32,
        scale_sqr: f32,
        angle_min: f32,
        angle_extent: f32,

        const Self = @This();

        pub fn init(source: Vec4f, origin: Vec4f, direction: Vec4f, min_t: f32, max_t: f32) Self {
            const offset = math.dot3(direction, source - origin) / math.squaredLength3(direction);
            const scale_sqr = math.squaredLength3((origin + @as(Vec4f, @splat(offset)) * direction) - source);
            const scale = @sqrt(scale_sqr);

            const inv_scale = if (0.0 == scale) 0.0 else 1.0 / scale;
            const angle_min = std.math.atan((min_t - offset) * inv_scale);
            const angle_max = std.math.atan((max_t - offset) * inv_scale);
            const angle_extent = angle_max - angle_min;

            return .{
                .offset = offset,
                .min_t = min_t,
                .max_t = max_t,
                .scale = scale,
                .scale_sqr = scale_sqr,
                .angle_min = angle_min,
                .angle_extent = angle_extent,
            };
        }

        pub fn sample(self: Self, u: f32, t: *f32) f32 {
            const lt = self.scale * @tan(self.angle_min + u * self.angle_extent);
            const p = self.scale / (self.angle_extent * (self.scale_sqr + lt * lt));
            t.* = math.clamp(lt + self.offset, self.min_t, self.max_t);
            return p;
        }

        pub fn pdf(self: Self, t: f32) f32 {
            if (self.min_t <= t and t < self.max_t) {
                const lt = t - self.offset;
                return self.scale / (self.angle_extent * (self.scale_sqr + lt * lt));
            } else {
                return 0.0;
            }
        }

        pub fn pdfAndSample(self: Self, t: f32, u: *f32) f32 {
            const lt = t - self.offset;
            u.* = math.saturate((std.math.atan(lt / self.scale) - self.angle_min) / self.angle_extent);
            return self.scale / (self.angle_extent * (self.scale_sqr + lt * lt));
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

        const radius = 0.5 * trafo.scaleX();

        if (UseEquiAngularSampling) {
            const lp = trafo.worldToFramePoint(p);

            const dsd = DiskSamplerData.init(lp);

            const eas0 = EquiAngularSampling.init(lp, @splat(0.0), dsd.yd, -radius, radius);
            if (0.0 == eas0.angle_extent) {
                return buffer[0..0];
            }

            var current_sample: u32 = 0;
            for (0..num_samples) |_| {
                const r2 = sampler.sample2D();
                const xy = math.smpl.diskConcentric(r2);

                var u = xy[0];
                var pdf_ = @sqrt(1.0 - u * u) / (0.25 * std.math.pi);
                u = (u + 1.0) * 0.5;

                var y_coord: f32 = undefined;
                pdf_ *= eas0.sample(u, &y_coord);

                const x_chord = @sqrt(radius * radius - y_coord * y_coord);
                if (0.0 == x_chord) {
                    continue;
                }

                const eas1 = EquiAngularSampling.init(lp, @as(Vec4f, @splat(y_coord)) * dsd.yd, dsd.xd, -x_chord, x_chord);
                if (0.0 == eas1.angle_extent) {
                    continue;
                }

                var x_coord: f32 = undefined;
                pdf_ *= eas1.sample(sampler.sample1D(), &x_coord);

                const l_direction = @as(Vec4f, @splat(x_coord)) * dsd.xd + @as(Vec4f, @splat(y_coord)) * dsd.yd - lp;
                const axis = trafo.objectToWorldNormal(l_direction);
                const ws = p + axis;

                var wn = trafo.rotation.r[2];

                if (two_sided and math.dot3(wn, ws - p) > 0.0) {
                    wn = -wn;
                }

                const sl = math.squaredLength3(axis);
                const dir = axis / @as(Vec4f, @splat(@sqrt(sl)));
                const c = -math.dot3(wn, dir);

                if (c < math.safe.DotMin or (math.dot3(dir, n) <= 0.0 and !total_sphere)) {
                    continue;
                }

                const v = (xy[1] + 1.0) * 0.5;
                buffer[current_sample] = SampleTo.init(ws, wn, dir, .{ u, v, 0.0, 0.0 }, (nsf * pdf_ * sl) / c);
                current_sample += 1;
            }

            return buffer[0..current_sample];
        } else {
            var current_sample: u32 = 0;
            for (0..num_samples) |_| {
                const r2 = sampler.sample2D();
                const xy = math.smpl.diskConcentric(r2);

                const ls = Vec4f{ xy[0], xy[1], 0.0, 0.0 };
                const ws = trafo.position + @as(Vec4f, @splat(radius)) * trafo.objectToWorldNormal(ls);
                var wn = trafo.rotation.r[2];

                if (two_sided and math.dot3(wn, ws - p) > 0.0) {
                    wn = -wn;
                }

                const axis = ws - p;
                const sl = math.squaredLength3(axis);
                const t = @sqrt(sl);
                const dir = axis / @as(Vec4f, @splat(t));
                const c = -math.dot3(wn, dir);

                if (c < math.safe.DotMin) {
                    continue;
                }

                const area = std.math.pi * (radius * radius);

                buffer[current_sample] = SampleTo.init(ws, wn, dir, @splat(0.0), (nsf * sl) / (c * area));
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

        const radius = 0.5 * trafo.scaleX();
        const area = std.math.pi * (radius * radius);

        var current_sample: u32 = 0;

        for (0..num_samples) |_| {
            const r2 = sampler.sample2D();
            const rs = shape_sampler.impl.sample(.{ r2[0], r2[1], 0.0, 0.0 });
            if (0.0 == rs.pdf()) {
                continue;
            }

            const uv = Vec2f{ rs.uvw[0], rs.uvw[1] };

            const uv2 = @as(Vec2f, @splat(-2.0)) * uv + @as(Vec2f, @splat(1.0));
            const ls = Vec4f{ uv2[0], uv2[1], 0.0, 0.0 };

            const k = @as(Vec4f, @splat(radius)) * trafo.objectToWorldNormal(ls);
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
        uv: Vec2f,
        importance_uv: Vec2f,
        cos_a: f32,
        two_sided: bool,
        sampler: *Sampler,
        from_image: bool,
    ) ?SampleFrom {
        var ls: Vec4f = undefined;

        if (from_image) {
            const xy = @as(Vec2f, @splat(-2.0)) * uv + @as(Vec2f, @splat(1.0));
            if (math.squaredLength2(xy) > 1.0) {
                return null;
            }

            ls = Vec4f{ xy[0], xy[1], 0.0, 0.0 };
        } else {
            const xy = math.smpl.diskConcentric(uv);
            ls = Vec4f{ xy[0], xy[1], 0.0, 0.0 };
        }

        const radius = 0.5 * trafo.scaleX();
        const ws = trafo.position + @as(Vec4f, @splat(radius)) * trafo.objectToWorldNormal(ls);

        const area = @as(f32, if (two_sided) 2.0 * std.math.pi else std.math.pi) * (radius * radius);

        var wn = trafo.rotation.r[2];
        const frame: Frame = .{ .x = trafo.rotation.r[0], .y = trafo.rotation.r[1], .z = wn };

        var dir_l: Vec4f = undefined;
        var pdf_: f32 = undefined;

        if (cos_a < math.safe.DotMin) {
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

        const uvw = Vec4f{ uv[0], uv[1], 0.0, 0.0 };

        return SampleFrom.init(ro.offsetRay(ws, wn), wn, dir, uvw, importance_uv, trafo, pdf_);
    }

    pub fn pdf(dir: Vec4f, p: Vec4f, frag: *const Fragment, split_threshold: f32, shape_sampler: *const ShapeSampler) f32 {
        const c = @abs(math.dot3(frag.isec.trafo.rotation.r[2], dir));

        const num_samples = shape_sampler.numSamples(split_threshold);
        const nsf: f32 = @floatFromInt(num_samples);

        const radius = 0.5 * frag.isec.trafo.scaleX();

        const sl = math.squaredDistance3(p, frag.p);

        if (UseEquiAngularSampling) {
            const lp = frag.isec.trafo.worldToFramePoint(p);

            const dsd = DiskSamplerData.init(lp);

            const eas0 = EquiAngularSampling.init(lp, @splat(0.0), dsd.yd, -radius, radius);

            const l_point = frag.isec.trafo.worldToFramePoint(frag.p);

            const y_coord = math.dot3(l_point, dsd.yd);

            var u: f32 = undefined;
            const eas_pdf = eas0.pdfAndSample(y_coord, &u);
            u = u * 2.0 - 1.0;
            var pdf_ = @sqrt(1.0 - u * u) / (0.25 * std.math.pi);

            pdf_ *= eas_pdf;

            const x_chord = @sqrt(radius * radius - y_coord * y_coord);
            const eas1 = EquiAngularSampling.init(lp, @as(Vec4f, @splat(y_coord)) * dsd.yd, dsd.xd, -x_chord, x_chord);
            const x_coord = math.dot3(l_point, dsd.xd);
            pdf_ *= eas1.pdf(x_coord);

            const result_pdf = (nsf * pdf_ * sl) / c;

            return result_pdf;
        } else {
            const area = std.math.pi * (radius * radius);

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

        const radius = 0.5 * frag.isec.trafo.scaleX();
        const area = std.math.pi * (radius * radius);

        const sl = math.squaredDistance3(p, frag.p);

        const num_samples = shape_sampler.numSamples(split_threshold);
        const material_pdf = shape_sampler.impl.pdf(frag.uvw) * @as(f32, @floatFromInt(num_samples));

        return (material_pdf * sl) / (c * area);
    }
};
