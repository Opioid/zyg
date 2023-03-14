const cam = @import("../camera/perspective.zig");
const Scene = @import("../scene/scene.zig").Scene;
const sr = @import("../scene/ray.zig");
const Ray = sr.Ray;
const RayDif = sr.RayDif;
const Renderstate = @import("../scene/renderstate.zig").Renderstate;
const Intersection = @import("../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../scene/prop/interface.zig").Stack;
const mat = @import("../scene/material/material_helper.zig");
const MaterialSample = @import("../scene/material/sample.zig").Sample;
const NullSample = @import("../scene/material/null/sample.zig").Sample;
const IoR = @import("../scene/material/sample_base.zig").IoR;
const ro = @import("../scene/ray_offset.zig");
const shp = @import("../scene/shape/intersection.zig");
const Interpolation = shp.Interpolation;
const LightTree = @import("../scene/light/light_tree.zig").Tree;
const smpl = @import("../sampler/sampler.zig");
const Sampler = smpl.Sampler;
const Filter = @import("../image/texture/texture_sampler.zig").Filter;
const surface = @import("integrator/surface/integrator.zig");
const vol = @import("integrator/volume/integrator.zig");
const VolumeResult = @import("integrator/volume/result.zig").Result;
const lt = @import("integrator/particle/lighttracer.zig");
const PhotonSettings = @import("../take/take.zig").PhotonSettings;
const PhotonMapper = @import("integrator/particle/photon/photon_mapper.zig").Mapper;
const PhotonMap = @import("integrator/particle/photon/photon_map.zig").Map;
const aov = @import("sensor/aov/aov_value.zig");

const base = @import("base");
const math = base.math;
const Vec2b = math.Vec2b;
const Vec2i = math.Vec2i;
const Vec2ul = math.Vec2ul;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Worker = struct {
    camera: *cam.Perspective align(64) = undefined,
    scene: *Scene = undefined,

    rng: RNG = undefined,

    interface_stack: InterfaceStack = undefined,

    lights: Scene.Lights = undefined,

    sampler: Sampler = undefined,

    surface_integrator: surface.Integrator = undefined,
    volume_integrator: vol.Integrator = undefined,
    lighttracer: lt.Lighttracer = undefined,

    aov: aov.Value = undefined,

    photon_mapper: PhotonMapper = .{},
    photon_map: *PhotonMap = undefined,

    photon: Vec4f = undefined,

    pub fn deinit(self: *Worker, alloc: Allocator) void {
        self.photon_mapper.deinit(alloc);
    }

    pub fn configure(
        self: *Worker,
        alloc: Allocator,
        camera: *cam.Perspective,
        scene: *Scene,
        samplers: smpl.Factory,
        surfaces: surface.Factory,
        volumes: vol.Factory,
        lighttracers: lt.Factory,
        aovs: aov.Factory,
        photon_settings: PhotonSettings,
        photon_map: *PhotonMap,
    ) !void {
        self.camera = camera;
        self.scene = scene;

        const rng = &self.rng;

        self.sampler = samplers.create(rng);

        self.surface_integrator = surfaces.create(rng);
        self.volume_integrator = volumes.create();
        self.lighttracer = lighttracers.create(rng);

        self.aov = aovs.create();

        const max_bounces = if (photon_settings.num_photons > 0) photon_settings.max_bounces else 0;
        try self.photon_mapper.configure(alloc, .{
            .max_bounces = max_bounces,
            .full_light_path = photon_settings.full_light_path,
        }, rng);

        self.photon_map = photon_map;
    }

    // Running variance calculation inspired by
    // https://www.johndcook.com/blog/standard_deviation/

    pub fn render(
        self: *Worker,
        frame: u32,
        tile: Vec4i,
        iteration: u32,
        num_samples: u32,
        num_expected_samples: u32,
        num_photon_samples: u32,
        em_threshold: f32,
    ) void {
        var camera = self.camera;
        const sensor = &camera.sensor;

        const scene = self.scene;
        var rng = &self.rng;

        const step = @floatToInt(u32, @ceil(@sqrt(@intToFloat(f32, num_expected_samples))));

        const r = camera.resolution;
        //const a = @intCast(u32, r[0]) * @intCast(u32, r[1]);
        //const o = @as(u64, iteration) * a;
        const so = iteration / num_expected_samples;

        _ = em_threshold;

        var ss: u32 = 0;
        while (ss < num_samples) {
            const s_end = @min(ss + step, num_samples);

            const y_back = tile[3];
            var y: i32 = tile[1];
            var yy: u32 = 0;
            while (y <= y_back) : (y += 1) {
                const x_back = tile[2];
                var x: i32 = tile[0];
                var xx: u32 = 0;
                const pixel_n = @intCast(u32, y * r[0]);
                while (x <= x_back) : (x += 1) {
                    const pixel_id = pixel_n + @intCast(u32, x);

                    const sample_index = @as(u64, pixel_id) * @as(u64, num_expected_samples) + @as(u64, iteration + ss);
                    const tsi = @truncate(u32, sample_index);
                    const seed = @truncate(u32, sample_index >> 32) + so;

                    rng.start(0, sample_index);
                    self.sampler.startPixel(tsi, seed);
                    self.surface_integrator.startPixel(tsi, seed + 1);

                    self.photon = @splat(4, @as(f32, 0.0));

                    const pixel = Vec2i{ x, y };

                    // var old_m = old_ms[c];
                    // var old_s = old_ss[c];

                    // var new_m: Vec4f = undefined;
                    // var new_s: f32 = undefined;

                    var s = ss;
                    while (s < s_end) : (s += 1) {
                        self.aov.clear();

                        var sample = self.sampler.cameraSample(pixel);
                        var ray = camera.generateRay(&sample, frame, scene);

                        const color = self.li(&ray, s < num_photon_samples, camera.interface_stack);

                        var photon = self.photon;
                        if (photon[3] > 0.0) {
                            photon /= @splat(4, photon[3]);
                            photon[3] = 0.0;
                        }

                        const clamped = sensor.addSample(sample, color + photon, self.aov);
                        _ = clamped;
                        // const value = clamped.last;

                        // new_m = clamped.mean;
                        // new_s = old_s + math.hmax3((value - old_m) * (value - new_m));

                        // // set up for next iteration
                        // old_m = new_m;
                        // old_s = new_s;
                    }

                    xx += 1;
                }

                yy += 1;
            }

            ss += step;
        }

        // const yy_back = tile[3];
        // var yy: i32 = tile[1];
        // while (yy <= yy_back) : (yy += 4) {
        //     const xx_back = tile[2];
        //     var xx: i32 = tile[0];
        //     while (xx <= xx_back) : (xx += 4) {
        //         var old_ms = [_]Vec4f{.{ 0.0, 0.0, 0.0, 0.0 }} ** 16;
        //         var old_ss = [_]f32{0.0} ** 16;
        //         var ems = [_]f32{0.0} ** 16;
        //         var cell_ems: [4]f32 = undefined;

        //         var ss: u32 = 0;
        //         while (ss < num_samples) {
        //             var cc: u32 = 0;

        //             const s_end = @min(ss + step, num_samples);
        //             const y_back = @min(yy + 3, yy_back);
        //             var y = yy;
        //             while (y <= y_back) : (y += 1) {
        //                 const pixel_n = @intCast(u32, y * r[0]);

        //                 const x_back = @min(xx + 3, xx_back);
        //                 var x = xx;
        //                 while (x <= x_back) : (x += 1) {
        //                     const c = cc;
        //                     cc += 1;

        //                     if (ss >= num_samples / 2) {
        //                         if (ems[c] < em_threshold) continue;
        //                     } else if (ss >= num_samples / 4) {
        //                         const cx = (x - xx) >> 1;
        //                         const cy = (y - yy) >> 1;
        //                         const cid = @intCast(u32, (cy << 1) | cx);

        //                         if (cell_ems[cid] < em_threshold) continue;
        //                     }

        //                     const pixel_id = pixel_n + @intCast(u32, x);

        //                     const sample_index = @as(u64, pixel_id) * @as(u64, num_expected_samples) + @as(u64, iteration + ss);
        //                     const tsi = @truncate(u32, sample_index);
        //                     const seed = @truncate(u32, sample_index >> 32) + so;

        //                     rng.start(0, sample_index);
        //                     self.sampler.startPixel(tsi, seed);
        //                     self.surface_integrator.startPixel(tsi, seed + 1);

        //                     self.photon = @splat(4, @as(f32, 0.0));

        //                     const pixel = Vec2i{ x, y };

        //                     var old_m = old_ms[c];
        //                     var old_s = old_ss[c];

        //                     var new_m: Vec4f = undefined;
        //                     var new_s: f32 = undefined;

        //                     var s = ss;
        //                     while (s < s_end) : (s += 1) {
        //                         self.aov.clear();

        //                         var sample = self.sampler.cameraSample(pixel);
        //                         var ray = camera.generateRay(&sample, frame, scene);

        //                         const color = self.li(&ray, s < num_photon_samples, camera.interface_stack);

        //                         var photon = self.photon;
        //                         if (photon[3] > 0.0) {
        //                             photon /= @splat(4, photon[3]);
        //                             photon[3] = 0.0;
        //                         }

        //                         const clamped = sensor.addSample(sample, color + photon, self.aov);
        //                         const value = clamped.last;

        //                         new_m = clamped.mean;
        //                         new_s = old_s + math.hmax3((value - old_m) * (value - new_m));

        //                         // set up for next iteration
        //                         old_m = new_m;
        //                         old_s = new_s;
        //                     }

        //                     old_ms[c] = old_m;
        //                     old_ss[c] = old_s;

        //                     const variance = new_s * new_m[3];
        //                     const mam = math.hmax3(new_m);

        //                     // c0
        //                     //   const em = @sqrt(variance) / std.math.max(mam, 0.0001);

        //                     // csw
        //                     //  const em = @sqrt(variance / std.math.max(mam, 0.0001));

        //                     //  const em = @sqrt(variance) / (if (mam < 1.0) std.math.max(@sqrt(mam), 0.0001) else mam);
        //                     const em = if (mam < 1.0) @sqrt(variance / std.math.max(mam, 0.0001)) else @sqrt(variance) / mam;

        //                     // cg
        //                     // const em = std.math.pow(f32, variance, 0.16);

        //                     // cw
        //                     // const em = std.math.pow(f32, variance / std.math.max(mam, 1.0), 0.16);

        //                     ems[c] = em;
        //                 }
        //             }

        //             inline for (&cell_ems, 0..) |*c, i| {
        //                 const id = ((i >> 1) << 2) + (i << 1);
        //                 const em0 = std.math.max(ems[id + 0], ems[id + 1]);
        //                 const em1 = std.math.max(ems[id + 4], ems[id + 5]);
        //                 c.* = std.math.max(em0, em1);
        //             }

        //             const em0 = std.math.max(cell_ems[0], cell_ems[1]);
        //             const em1 = std.math.max(cell_ems[2], cell_ems[3]);
        //             const max_em = std.math.max(em0, em1);

        //             if (0.0 == max_em or (ss >= step * 4 and max_em < em_threshold)) {
        //                 break;
        //             }

        //             ss += step;
        //         }
        //     }
        // }
    }

    pub fn particles(self: *Worker, frame: u32, offset: u64, range: Vec2ul) void {
        const camera = self.camera;

        var rng = &self.rng;
        rng.start(0, offset);
        const seed = rng.randomUint();
        self.lighttracer.startPixel(@truncate(u32, range[0]), seed);

        var i = range[0];
        while (i < range[1]) : (i += 1) {
            self.lighttracer.li(frame, self, &camera.interface_stack);
        }
    }

    pub fn bakePhotons(self: *Worker, begin: u32, end: u32, frame: u32, iteration: u32) u32 {
        return self.photon_mapper.bake(self.photon_map, begin, end, frame, iteration, self);
    }

    pub fn photonLi(self: *const Worker, isec: Intersection, sample: *const MaterialSample) Vec4f {
        return self.photon_map.li(isec, sample, self.scene);
    }

    pub fn addPhoton(self: *Worker, photon: Vec4f) void {
        self.photon += Vec4f{ photon[0], photon[1], photon[2], 1.0 };
    }

    pub fn commonAOV(
        self: *Worker,
        throughput: Vec4f,
        ray: Ray,
        isec: Intersection,
        mat_sample: *const MaterialSample,
        primary_ray: bool,
    ) void {
        if (primary_ray and self.aov.activeClass(.Albedo) and mat_sample.canEvaluate()) {
            self.aov.insert3(.Albedo, throughput * mat_sample.aovAlbedo());
        }

        if (ray.depth > 0) {
            return;
        }

        if (self.aov.activeClass(.ShadingNormal)) {
            self.aov.insert3(.ShadingNormal, mat_sample.super().shadingNormal());
        }

        if (self.aov.activeClass(.Depth)) {
            self.aov.insert1(.Depth, ray.ray.maxT());
        }

        if (self.aov.activeClass(.MaterialId)) {
            self.aov.insert1(
                .MaterialId,
                @intToFloat(f32, 1 + self.scene.propMaterialId(isec.prop, isec.geo.part)),
            );
        }
    }

    fn li(self: *Worker, ray: *Ray, gather_photons: bool, interface_stack: InterfaceStack) Vec4f {
        var isec = Intersection{};
        if (self.intersectAndResolveMask(ray, null, &isec)) {
            return self.surface_integrator.li(ray, &isec, gather_photons, self, &interface_stack);
        }

        return @splat(4, @as(f32, 0.0));
    }

    pub fn transmitted(self: *Worker, ray: *Ray, wo: Vec4f, isec: Intersection, filter: ?Filter) ?Vec4f {
        if (self.subsurfaceVisibility(ray, wo, isec, filter)) |a| {
            if (self.transmittance(ray.*, filter)) |b| {
                return a * b;
            }
        }

        return null;
    }

    pub fn volume(self: *Worker, ray: *Ray, throughput: Vec4f, isec: *Intersection, filter: ?Filter, sampler: *Sampler) VolumeResult {
        return self.volume_integrator.integrate(ray, throughput, isec, filter, sampler, self);
    }

    fn transmittance(self: *Worker, ray: Ray, filter: ?Filter) ?Vec4f {
        if (!self.scene.has_volumes) {
            return @splat(4, @as(f32, 1.0));
        }

        var stack: InterfaceStack = undefined;
        stack.copy(&self.interface_stack);

        // This is the typical SSS case:
        // A medium is on the stack but we already considered it during shadow calculation,
        // ignoring the IoR. Therefore remove the medium from the stack.
        if (!stack.straight(self.scene)) {
            stack.pop();
        }

        const ray_max_t = ray.ray.maxT();
        var tray = ray;

        var isec: Intersection = undefined;

        var w = @splat(4, @as(f32, 1.0));

        while (true) {
            const hit = self.scene.intersectVolume(&tray, &isec);

            if (!stack.empty()) {
                if (self.volume_integrator.transmittance(tray, stack.top(), filter, self)) |tr| {
                    w *= tr;
                } else {
                    return null;
                }
            }

            if (!hit) {
                break;
            }

            if (isec.sameHemisphere(tray.ray.direction)) {
                _ = stack.remove(isec);
            } else {
                stack.push(isec);
            }

            const ray_min_t = ro.offsetF(tray.ray.maxT());
            if (ray_min_t > ray_max_t) {
                break;
            }

            tray.ray.setMinMaxT(ray_min_t, ray_max_t);
        }

        return w;
    }

    pub fn correctVolumeInterfaceStack(self: *Worker, a: Vec4f, b: Vec4f, time: u64) void {
        var isec: Intersection = undefined;

        const axis = b - a;
        const ray_max_t = math.length3(axis);

        var ray = Ray.init(a, axis / @splat(4, ray_max_t), 0.0, ray_max_t, 0, 0.0, time);

        while (true) {
            const hit = self.scene.intersectVolume(&ray, &isec);

            if (!hit) {
                break;
            }

            if (isec.sameHemisphere(ray.ray.direction)) {
                _ = self.interface_stack.remove(isec);
            } else {
                self.interface_stack.push(isec);
            }

            const ray_min_t = ro.offsetF(ray.ray.maxT());
            if (ray_min_t > ray_max_t) {
                break;
            }

            ray.ray.setMinMaxT(ray_min_t, ray_max_t);
        }
    }

    fn subsurfaceVisibility(self: *Worker, ray: *Ray, wo: Vec4f, isec: Intersection, filter: ?Filter) ?Vec4f {
        const material = isec.material(self.scene);

        if (isec.subsurface and material.ior() > 1.0) {
            const ray_max_t = ray.ray.maxT();
            var nisec: Intersection = .{};

            var hit: bool = false;
            if (material.denseSSSOptimization()) {
                hit = self.intersectPropShadow(isec.prop, ray, &nisec.geo);
            } else {
                ray.ray.setMaxT(std.math.min(ro.offsetF(self.scene.propAabbIntersectP(isec.prop, ray.*) orelse ray_max_t), ray_max_t));
                hit = self.scene.intersectShadow(ray, &nisec);
            }

            if (hit) {
                const sss_min_t = ray.ray.minT();
                const sss_max_t = ray.ray.maxT();
                ray.ray.setMinMaxT(ro.offsetF(ray.ray.maxT()), ray_max_t);
                if (self.scene.visibility(ray.*, filter)) |tv| {
                    ray.ray.setMinMaxT(sss_min_t, sss_max_t);
                    if (self.volume_integrator.transmittance(ray.*, self.interface_stack.top(), filter, self)) |tr| {
                        ray.ray.setMinMaxT(ro.offsetF(ray.ray.maxT()), ray_max_t);
                        const wi = ray.ray.direction;
                        const vbh = material.super().border(wi, nisec.geo.n);
                        const nsc = mat.nonSymmetryCompensation(wo, wi, nisec.geo.geo_n, nisec.geo.n);

                        return @splat(4, vbh * nsc) * tv * tr;
                    }
                }

                return null;
            }
        }

        return self.scene.visibility(ray.*, filter);
    }

    pub fn intersectProp(self: *Worker, entity: u32, ray: *Ray, ipo: Interpolation, isec: *shp.Intersection) bool {
        return self.scene.prop(entity).intersect(entity, ray, self.scene, ipo, isec);
    }

    pub fn intersectPropShadow(self: *Worker, entity: u32, ray: *Ray, isec: *shp.Intersection) bool {
        return self.scene.prop(entity).intersectShadow(entity, ray, self.scene, isec);
    }

    pub fn intersectAndResolveMask(self: *Worker, ray: *Ray, filter: ?Filter, isec: *Intersection) bool {
        if (!self.scene.intersect(ray, .All, isec)) {
            return false;
        }

        var o = isec.opacity(filter, self.scene);

        while (o < 1.0) {
            if (o > 0.0 and o > self.rng.randomFloat()) {
                return true;
            }

            // Slide along ray until opaque surface is found
            ray.ray.setMinMaxT(ro.offsetF(ray.ray.maxT()), ro.Ray_max_t);
            if (!self.scene.intersect(ray, .All, isec)) {
                return false;
            }

            o = isec.opacity(filter, self.scene);
        }

        return true;
    }

    pub fn resetInterfaceStack(self: *Worker, stack: *const InterfaceStack) void {
        self.interface_stack.copy(stack);
    }

    pub fn iorOutside(self: *const Worker, wo: Vec4f, isec: Intersection) f32 {
        if (isec.sameHemisphere(wo)) {
            return self.interface_stack.topIor(self.scene);
        }

        return self.interface_stack.peekIor(isec, self.scene);
    }

    pub fn interfaceChange(self: *Worker, dir: Vec4f, isec: *Intersection) void {
        const leave = isec.sameHemisphere(dir);
        if (leave) {
            _ = self.interface_stack.remove(isec.*);
        } else if (self.interface_stack.straight(self.scene) or isec.material(self.scene).ior() > 1.0) {
            isec.volume_entry = isec.geo.p;
            self.interface_stack.push(isec.*);
        }
    }

    pub fn interfaceChangeIor(self: *Worker, dir: Vec4f, isec: Intersection) IoR {
        const inter_ior = isec.material(self.scene).ior();

        const leave = isec.sameHemisphere(dir);
        if (leave) {
            const ior = IoR{ .eta_t = self.interface_stack.peekIor(isec, self.scene), .eta_i = inter_ior };
            _ = self.interface_stack.remove(isec);
            return ior;
        }

        const ior = IoR{ .eta_t = inter_ior, .eta_i = self.interface_stack.topIor(self.scene) };

        if (self.interface_stack.straight(self.scene) or inter_ior > 1.0) {
            self.interface_stack.push(isec);
        }

        return ior;
    }

    pub fn sampleMaterial(
        self: *const Worker,
        ray: Ray,
        wo: Vec4f,
        wo1: Vec4f,
        isec: Intersection,
        filter: ?Filter,
        alpha: f32,
        avoid_caustics: bool,
        straight_border: bool,
    ) MaterialSample {
        const material = isec.material(self.scene);

        const wi = ray.ray.direction;

        if (!isec.subsurface and straight_border and material.ior() > 1.0 and isec.sameHemisphere(wi)) {
            const geo_n = isec.geo.geo_n;
            const n = isec.geo.n;

            const vbh = material.super().border(wi, n);
            const nsc = mat.nonSymmetryCompensation(wo1, wi, geo_n, n);
            const factor = nsc * vbh;

            return .{ .Null = NullSample.initFactor(wo, geo_n, n, alpha, factor) };
        }

        return isec.sample(wo, ray, filter, avoid_caustics, self);
    }

    pub fn randomLightSpatial(
        self: *Worker,
        p: Vec4f,
        n: Vec4f,
        total_sphere: bool,
        random: f32,
        split: bool,
    ) []Scene.LightPick {
        return self.scene.randomLightSpatial(p, n, total_sphere, random, split, &self.lights);
    }

    pub fn absoluteTime(self: *const Worker, frame: u32, frame_delta: f32) u64 {
        return self.camera.absoluteTime(frame, frame_delta);
    }

    pub fn screenspaceDifferential(self: *const Worker, rs: Renderstate) Vec4f {
        const rd = self.camera.calculateRayDifferential(rs.p, rs.time, self.scene);

        const ds = self.scene.propShape(rs.prop).differentialSurface(rs.primitive);

        const dpdu_w = rs.trafo.objectToWorldVector(ds.dpdu);
        const dpdv_w = rs.trafo.objectToWorldVector(ds.dpdv);

        return calculateScreenspaceDifferential(rs.p, rs.geo_n, rd, dpdu_w, dpdv_w);
    }

    // https://blog.yiningkarlli.com/2018/10/bidirectional-mipmap.html
    fn calculateScreenspaceDifferential(p: Vec4f, n: Vec4f, rd: RayDif, dpdu: Vec4f, dpdv: Vec4f) Vec4f {
        // Compute offset-ray isec points with tangent plane
        const d = math.dot3(n, p);

        const tx = -(math.dot3(n, rd.x_origin) - d) / math.dot3(n, rd.x_direction);
        const ty = -(math.dot3(n, rd.y_origin) - d) / math.dot3(n, rd.y_direction);

        const px = rd.x_origin + @splat(4, tx) * rd.x_direction;
        const py = rd.y_origin + @splat(4, ty) * rd.y_direction;

        // Compute uv offsets at offset-ray isec points
        // Choose two dimensions to use for ray offset computations
        const dim = if (@fabs(n[0]) > @fabs(n[1]) and @fabs(n[0]) > @fabs(n[2])) Vec2b{
            1,
            2,
        } else if (@fabs(n[1]) > @fabs(n[2])) Vec2b{
            0,
            2,
        } else Vec2b{
            0,
            1,
        };

        // Initialize A, bx, and by matrices for offset computation
        const a: [2][2]f32 = .{ .{ dpdu[dim[0]], dpdv[dim[0]] }, .{ dpdu[dim[1]], dpdv[dim[1]] } };

        const bx = Vec2f{ px[dim[0]] - p[dim[0]], px[dim[1]] - p[dim[1]] };
        const by = Vec2f{ py[dim[0]] - p[dim[0]], py[dim[1]] - p[dim[1]] };

        const det = a[0][0] * a[1][1] - a[0][1] * a[1][0];

        if (@fabs(det) < 1.0e-10) {
            return @splat(4, @as(f32, 0.0));
        }

        const dudx = (a[1][1] * bx[0] - a[0][1] * bx[1]) / det;
        const dvdx = (a[0][0] * bx[1] - a[1][0] * bx[0]) / det;

        const dudy = (a[1][1] * by[0] - a[0][1] * by[1]) / det;
        const dvdy = (a[0][0] * by[1] - a[1][0] * by[0]) / det;

        return .{ dudx, dvdx, dudy, dvdy };
    }
};
