const cam = @import("../camera/perspective.zig");
const Scene = @import("../scene/scene.zig").Scene;
const vt = @import("../scene/vertex.zig");
const Vertex = vt.Vertex;
const RayDif = vt.RayDif;
const rst = @import("../scene/renderstate.zig");
const Renderstate = rst.Renderstate;
const CausticsResolve = rst.CausticsResolve;
const Trafo = @import("../scene/composed_transformation.zig").ComposedTransformation;
const InterfaceStack = @import("../scene/prop/interface.zig").Stack;
const mat = @import("../scene/material/sample_helper.zig");
const Material = @import("../scene/material/material.zig").Material;
const MaterialSample = @import("../scene/material/sample.zig").Sample;
const NullSample = @import("../scene/material/null/null_sample.zig").Sample;
const IoR = @import("../scene/material/sample_base.zig").IoR;
const ro = @import("../scene/ray_offset.zig");
const shp = @import("../scene/shape/intersection.zig");
const Intersection = shp.Intersection;
const Interpolation = shp.Interpolation;
const Volume = shp.Volume;
const LightTree = @import("../scene/light/light_tree.zig").Tree;
const smpl = @import("../sampler/sampler.zig");
const Sampler = smpl.Sampler;
const surface = @import("integrator/surface/integrator.zig");
const vlhlp = @import("integrator/volume/tracking_multi.zig").Multi;
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
    pub const Tile_dimensions = 16;
    const Tile_area = Tile_dimensions * Tile_dimensions;
    const Tile_cells = 4 + 16 + 64;

    camera: *cam.Perspective align(64) = undefined,
    scene: *Scene = undefined,

    rng: RNG = undefined,

    interface_stack: InterfaceStack = undefined,

    lights: Scene.Lights = undefined,

    samplers: [2]Sampler = undefined,

    surface_integrator: surface.Integrator = undefined,
    lighttracer: lt.Lighttracer = undefined,

    aov: aov.Value = undefined,

    old_ms: [Tile_area]Vec4f = undefined,
    old_ss: [Tile_area]f32 = undefined,
    qms: [Tile_area]f32 = undefined,
    cell_qms: [Tile_cells]f32 = undefined,
    cell_qms_work: [Tile_cells]f32 = undefined,

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
        lighttracers: lt.Factory,
        aovs: aov.Factory,
        photon_settings: PhotonSettings,
        photon_map: *PhotonMap,
    ) !void {
        self.camera = camera;
        self.scene = scene;

        const rng = &self.rng;

        self.samplers[0] = samplers.create(rng);
        self.samplers[1] = .{ .Random = .{ .rng = rng } };

        self.surface_integrator = surfaces.create();
        self.lighttracer = lighttracers.create();

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
        qm_threshold: f32,
    ) void {
        var camera = self.camera;
        const sensor = &camera.sensor;

        const scene = self.scene;
        var rng = &self.rng;

        const step = @min(16, num_samples);

        const r = camera.resolution;
        const so = iteration / num_expected_samples;

        //
        // 0 16 / 1 = 16
        // 1 16 / 2 = 8
        // 2 16 / 4 = 4
        // 3 16 / 8 = 2
        // 4 16 / 16 = 1

        @memset(&self.old_ms, @as(Vec4f, @splat(0.0)));
        @memset(&self.old_ss, 0.0);

        var tile_qm_work: f32 = undefined;

        var ss: u32 = 0;
        while (ss < num_samples) {
            @memcpy(&self.cell_qms, &self.cell_qms_work);
            @memset(&self.cell_qms_work, 0.0);
            const tile_qm = tile_qm_work;
            tile_qm_work = 0.0;

            const s_end = @min(ss + step, num_samples);

            const y_back = tile[3];
            var y: i32 = tile[1];
            var yy: u32 = 0;
            while (y <= y_back) : (y += 1) {
                const x_back = tile[2];
                var x: i32 = tile[0];
                var xx: u32 = 0;
                const pixel_n: u32 = @intCast(y * r[0]);
                while (x <= x_back) : (x += 1) {
                    const ii = yy * Tile_dimensions + xx;
                    const pp = Vec2i{ @intCast(xx), @intCast(yy) };
                    xx += 1;

                    const c1 = 0 + coordToZorder(pp >> @as(@Vector(2, u5), @splat(3)));
                    const c2 = 4 + coordToZorder(pp >> @as(@Vector(2, u5), @splat(2)));
                    const c3 = 20 + coordToZorder(pp >> @as(@Vector(2, u5), @splat(1)));

                    if (ss >= 1024) {
                        if (self.qms[ii] < qm_threshold) {
                            continue;
                        }
                    } else if (ss >= 512) {
                        if (self.cell_qms[c3] < qm_threshold) {
                            continue;
                        }
                    } else if (ss >= 256) {
                        if (self.cell_qms[c2] < qm_threshold) {
                            continue;
                        }
                    } else if (ss >= 128) {
                        if (self.cell_qms[c1] < qm_threshold) {
                            continue;
                        }
                    } else if (ss >= 64) {
                        if (tile_qm < qm_threshold) {
                            continue;
                        }
                    }

                    const pixel_id = pixel_n + @as(u32, @intCast(x));

                    const sample_index = @as(u64, pixel_id) * @as(u64, num_expected_samples) + @as(u64, iteration + ss);
                    const tsi: u32 = @truncate(sample_index);
                    const seed = @as(u32, @truncate(sample_index >> 32)) + so;

                    rng.start(0, sample_index);
                    self.samplers[0].startPixel(tsi, seed);

                    self.photon = @splat(0.0);

                    const pixel = Vec2i{ x, y };

                    var old_m = self.old_ms[ii];
                    var old_s = self.old_ss[ii];

                    var new_m: Vec4f = undefined;
                    var new_s: f32 = undefined;

                    for (ss..s_end) |s| {
                        self.aov.clear();

                        var sample = self.samplers[0].cameraSample(pixel);
                        var vertex = camera.generateVertex(&sample, frame, scene);

                        self.resetInterfaceStack(&camera.interface_stack);
                        const color = self.surface_integrator.li(&vertex, s < num_photon_samples, self);

                        var photon = self.photon;
                        if (photon[3] > 0.0) {
                            photon /= @splat(photon[3]);
                            photon[3] = 0.0;
                        }

                        const clamped = sensor.addSample(sample, color + photon, self.aov);
                        const value = clamped.last;

                        new_m = clamped.mean;
                        new_s = old_s + math.hmax3((value - old_m) * (value - new_m));

                        // set up for next iteration
                        old_m = new_m;
                        old_s = new_s;

                        self.samplers[0].incrementSample();
                    }

                    self.old_ms[ii] = old_m;
                    self.old_ss[ii] = old_s;

                    const variance = new_s * new_m[3];
                    const mam = math.max(math.hmax3(new_m), 0.0001);

                    //const qm = if (mam < 1.0) @sqrt(variance / mam) else std.math.pow(f32, variance, 1.0 / 2.4) / mam;

                    const qm = if (mam < 1.0) std.math.pow(f32, variance / mam, 1.0 / 2.4) else @log(math.max(variance, 1.0)) / mam;

                    self.qms[ii] = qm;
                    tile_qm_work = math.max(tile_qm_work, qm);
                    self.cell_qms_work[c1] = math.max(self.cell_qms_work[c1], qm);
                    self.cell_qms_work[c2] = math.max(self.cell_qms_work[c2], qm);
                    self.cell_qms_work[c3] = math.max(self.cell_qms_work[c3], qm);
                }

                yy += 1;
            }

            if (0.0 == tile_qm_work) {
                break;
            }

            ss += step;
        }
    }

    // https://fgiesen.wordpress.com/2009/12/13/decoding-morton-codes/

    // "Insert" a 0 bit after each of the 16 low bits of x
    fn part1By1(v: u32) u32 {
        var x = v & 0x0000ffff; // x = ---- ---- ---- ---- fedc ba98 7654 3210
        x = (x ^ (x << 8)) & 0x00ff00ff; // x = ---- ---- fedc ba98 ---- ---- 7654 3210
        x = (x ^ (x << 4)) & 0x0f0f0f0f; // x = ---- fedc ---- ba98 ---- 7654 ---- 3210
        x = (x ^ (x << 2)) & 0x33333333; // x = --fe --dc --ba --98 --76 --54 --32 --10
        x = (x ^ (x << 1)) & 0x55555555; // x = -f-e -d-c -b-a -9-8 -7-6 -5-4 -3-2 -1-0
        return x;
    }

    // Inverse of Part1By1 - "delete" all odd-indexed bits
    fn compact1By1(v: u32) u32 {
        var x = v & 0x55555555; // x = -f-e -d-c -b-a -9-8 -7-6 -5-4 -3-2 -1-0
        x = (x ^ (x >> 1)) & 0x33333333; // x = --fe --dc --ba --98 --76 --54 --32 --10
        x = (x ^ (x >> 2)) & 0x0f0f0f0f; // x = ---- fedc ---- ba98 ---- 7654 ---- 3210
        x = (x ^ (x >> 4)) & 0x00ff00ff; // x = ---- ---- fedc ba98 ---- ---- 7654 3210
        x = (x ^ (x >> 8)) & 0x0000ffff; // x = ---- ---- ---- ---- fedc ba98 7654 3210
        return x;
    }

    fn coordToZorder(v: Vec2i) u32 {
        return (part1By1(@as(u32, @intCast(v[1]))) << 1) + part1By1(@as(u32, @intCast(v[0])));
    }

    fn zorderToCoord(z: u32) Vec2i {
        return .{ @as(i32, @intCast(compact1By1(z >> 0))), @as(i32, @intCast(compact1By1(z >> 1))) };
    }

    pub fn particles(self: *Worker, frame: u32, offset: u64, range: Vec2ul) void {
        const camera = self.camera;

        var rng = &self.rng;
        rng.start(0, offset);

        const tsi = @as(u32, @truncate(range[0]));
        const seed = @as(u32, @truncate(range[0] >> 32));
        self.samplers[0].startPixel(tsi, seed);

        for (range[0]..range[1]) |_| {
            self.lighttracer.li(frame, self, &camera.interface_stack);

            self.samplers[0].incrementSample();
        }
    }

    pub fn bakePhotons(self: *Worker, begin: u32, end: u32, frame: u32, iteration: u32) u32 {
        return self.photon_mapper.bake(self.photon_map, begin, end, frame, iteration, self);
    }

    pub fn photonLi(self: *const Worker, isec: Intersection, sample: *const MaterialSample, sampler: *Sampler) Vec4f {
        return self.photon_map.li(isec, sample, sampler, self.scene);
    }

    pub fn addPhoton(self: *Worker, photon: Vec4f) void {
        self.photon += Vec4f{ photon[0], photon[1], photon[2], 1.0 };
    }

    pub inline fn pickSampler(self: *Worker, bounce: u32) *Sampler {
        if (bounce < 3) {
            return &self.samplers[0];
        }

        return &self.samplers[1];
    }

    pub fn commonAOV(
        self: *Worker,
        throughput: Vec4f,
        vertex: Vertex,
        isec: Intersection,
        mat_sample: *const MaterialSample,
    ) void {
        const primary_ray = vertex.state.primary_ray;

        if (primary_ray and self.aov.activeClass(.Albedo) and mat_sample.canEvaluate()) {
            self.aov.insert3(.Albedo, throughput * mat_sample.aovAlbedo());
        }

        if (vertex.depth > 0) {
            return;
        }

        if (self.aov.activeClass(.GeometricNormal)) {
            self.aov.insert3(.GeometricNormal, mat_sample.super().geometricNormal());
        }

        if (self.aov.activeClass(.ShadingNormal)) {
            self.aov.insert3(.ShadingNormal, mat_sample.super().shadingNormal());
        }

        if (self.aov.activeClass(.Depth)) {
            self.aov.insert1(.Depth, vertex.ray.maxT());
        }

        if (self.aov.activeClass(.MaterialId)) {
            self.aov.insert1(
                .MaterialId,
                @as(f32, @floatFromInt(1 + self.scene.propMaterialId(isec.prop, isec.part))),
            );
        }
    }

    pub fn visibility(self: *Worker, vertex: *Vertex, isec: Intersection, sampler: *Sampler) ?Vec4f {
        const material = isec.material(self.scene);

        if (isec.subsurface() and !self.interface_stack.empty() and material.denseSSSOptimization()) {
            const ray_max_t = vertex.ray.maxT();
            const prop = isec.prop;

            var nisec: Intersection = undefined;
            const hit = self.scene.prop(prop).intersectSSS(prop, vertex, self.scene, &nisec);

            if (hit) {
                const sss_min_t = vertex.ray.minT();
                const sss_max_t = vertex.ray.maxT();
                vertex.ray.setMinMaxT(ro.offsetF(sss_max_t), ray_max_t);
                if (self.scene.visibility(vertex.*, sampler, self)) |tv| {
                    vertex.ray.setMinMaxT(sss_min_t, sss_max_t);
                    const interface = self.interface_stack.top();
                    const cc = interface.cc;
                    const tray = if (material.heterogeneousVolume()) nisec.trafo.worldToObjectRay(vertex.ray) else vertex.ray;
                    if (vlhlp.propTransmittance(tray, material, cc, prop, vertex.depth, sampler, self)) |tr| {
                        const wi = vertex.ray.direction;
                        const n = nisec.n;
                        const vbh = material.super().border(wi, n);
                        const nsc = subsurfaceNonSymmetryCompensation(wi, nisec.geo_n, n);

                        return @as(Vec4f, @splat(vbh * nsc)) * tv * tr;
                    }
                }

                return null;
            }
        }

        return self.scene.visibility(vertex.*, sampler, self);
    }

    pub fn nextEvent(self: *Worker, vertex: *Vertex, throughput: Vec4f, isec: *Intersection, sampler: *Sampler) bool {
        while (!self.interface_stack.empty()) {
            if (vlhlp.integrate(vertex, throughput, isec, sampler, self)) {
                return true;
            }

            self.interface_stack.pop();
        }

        const origin = vertex.ray.origin;

        const hit = self.intersectAndResolveMask(vertex, sampler, isec);

        const dif_t = math.distance3(origin, vertex.ray.origin);
        vertex.ray.origin = origin;
        vertex.ray.setMaxT(dif_t + vertex.ray.maxT());

        const volume_hit = self.scene.scatter(vertex, throughput, sampler, self, isec);

        return hit or volume_hit;
    }

    pub fn propTransmittance(
        self: *Worker,
        ray: math.Ray,
        material: *const Material,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
    ) ?Vec4f {
        const cc = material.super().cc;
        return vlhlp.propTransmittance(ray, material, cc, entity, depth, sampler, self);
    }

    pub fn propScatter(
        self: *Worker,
        ray: math.Ray,
        throughput: Vec4f,
        material: *const Material,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
    ) Volume {
        const cc = material.super().cc;
        return vlhlp.propScatter(ray, throughput, material, cc, entity, depth, sampler, self);
    }

    pub fn propIntersect(self: *Worker, entity: u32, vertex: *Vertex, ipo: Interpolation, isec: *Intersection) bool {
        return self.scene.prop(entity).intersect(entity, vertex, self.scene, ipo, isec);
    }

    pub fn intersectAndResolveMask(self: *Worker, vertex: *Vertex, sampler: *Sampler, isec: *Intersection) bool {
        while (true) {
            if (!self.scene.intersect(vertex, .All, isec)) {
                return false;
            }

            const o = isec.opacity(sampler, self.scene);
            if (1.0 == o or (o > 0.0 and o > sampler.sample1D())) {
                break;
            }

            // Offset ray until opaque surface is found
            vertex.ray.origin = isec.offsetP(vertex.ray.direction);
            vertex.ray.setMaxT(ro.Ray_max_t);
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

    pub fn interfaceChange(self: *Worker, dir: Vec4f, isec: Intersection, sampler: *Sampler) void {
        const leave = isec.sameHemisphere(dir);
        if (leave) {
            _ = self.interface_stack.remove(isec);
        } else {
            const material = isec.material(self.scene);
            const cc = material.collisionCoefficients2D(isec.uv(), sampler, self.scene);
            self.interface_stack.push(isec, cc);
        }
    }

    pub fn interfaceChangeIor(self: *Worker, dir: Vec4f, isec: Intersection, sampler: *Sampler) IoR {
        const inter_ior = isec.material(self.scene).ior();

        const leave = isec.sameHemisphere(dir);
        if (leave) {
            const ior = IoR{ .eta_t = self.interface_stack.peekIor(isec, self.scene), .eta_i = inter_ior };
            _ = self.interface_stack.remove(isec);
            return ior;
        }

        const ior = IoR{ .eta_t = inter_ior, .eta_i = self.interface_stack.topIor(self.scene) };

        const cc = isec.material(self.scene).collisionCoefficients2D(isec.uv(), sampler, self.scene);
        self.interface_stack.push(isec, cc);

        return ior;
    }

    pub fn sampleMaterial(
        self: *const Worker,
        vertex: Vertex,
        isec: Intersection,
        sampler: *Sampler,
        alpha: f32,
        caustics: CausticsResolve,
    ) MaterialSample {
        const wo = -vertex.ray.direction;
        const material = isec.material(self.scene);
        const straight_border = vertex.state.from_subsurface;

        if (!isec.subsurface() and straight_border and material.denseSSSOptimization() and !isec.sameHemisphere(wo)) {
            const geo_n = isec.geo_n;
            const n = isec.n;

            const vbh = material.super().border(wo, n);
            const nsc = subsurfaceNonSymmetryCompensation(wo, geo_n, n);
            const factor = nsc * vbh;

            return .{ .Null = NullSample.init(wo, geo_n, n, factor, alpha) };
        }

        return isec.sample(wo, vertex, sampler, caustics, self);
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

    inline fn subsurfaceNonSymmetryCompensation(wo: Vec4f, geo_n: Vec4f, n: Vec4f) f32 {
        return @fabs(math.dot3(wo, n)) / mat.clampAbsDot(wo, geo_n);
    }

    // https://blog.yiningkarlli.com/2018/10/bidirectional-mipmap.html
    fn calculateScreenspaceDifferential(p: Vec4f, n: Vec4f, rd: RayDif, dpdu: Vec4f, dpdv: Vec4f) Vec4f {
        // Compute offset-ray isec points with tangent plane
        const d = math.dot3(n, p);

        const tx = -(math.dot3(n, rd.x_origin) - d) / math.dot3(n, rd.x_direction);
        const ty = -(math.dot3(n, rd.y_origin) - d) / math.dot3(n, rd.y_direction);

        const px = rd.x_origin + @as(Vec4f, @splat(tx)) * rd.x_direction;
        const py = rd.y_origin + @as(Vec4f, @splat(ty)) * rd.y_direction;

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
            return @splat(0.0);
        }

        const dudx = (a[1][1] * bx[0] - a[0][1] * bx[1]) / det;
        const dvdx = (a[0][0] * bx[1] - a[1][0] * bx[0]) / det;

        const dudy = (a[1][1] * by[0] - a[0][1] * by[1]) / det;
        const dvdy = (a[0][0] * by[1] - a[1][0] * by[0]) / det;

        return .{ dudx, dvdx, dudy, dvdy };
    }
};
