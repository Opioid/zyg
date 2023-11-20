const cam = @import("../camera/perspective.zig");
const Sensor = @import("../rendering/sensor/sensor.zig").Sensor;
const Scene = @import("../scene/scene.zig").Scene;
const vt = @import("../scene/vertex.zig");
const Vertex = vt.Vertex;
const Probe = vt.Vertex.Probe;
const RayDif = vt.RayDif;
const rst = @import("../scene/renderstate.zig");
const Renderstate = rst.Renderstate;
const CausticsResolve = rst.CausticsResolve;
const Trafo = @import("../scene/composed_transformation.zig").ComposedTransformation;
const InterfaceStack = @import("../scene/prop/interface.zig").Stack;
const mat = @import("../scene/material/sample_helper.zig");
const Material = @import("../scene/material/material.zig").Material;
const MaterialSample = @import("../scene/material/sample.zig").Sample;
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
const Ray = math.Ray;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Worker = struct {
    camera: *cam.Perspective = undefined,
    sensor: *Sensor = undefined,
    scene: *Scene = undefined,

    rng: RNG = undefined,

    samplers: [2]Sampler = undefined,

    surface_integrator: surface.Integrator = undefined,
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
        sensor: *Sensor,
        scene: *Scene,
        samplers: smpl.Factory,
        surfaces: surface.Factory,
        lighttracers: lt.Factory,
        aovs: aov.Factory,
        photon_settings: PhotonSettings,
        photon_map: *PhotonMap,
    ) !void {
        self.sensor = sensor;
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

    pub fn render(
        self: *Worker,
        frame: u32,
        tile: Vec4i,
        iteration: u32,
        num_samples: u32,
        num_expected_samples: u32,
    ) void {
        const camera = self.camera;
        const sensor = self.sensor;
        const scene = self.scene;
        var rng = &self.rng;

        var crop = camera.crop;
        crop[2] -= crop[0] + 1;
        crop[3] -= crop[1] + 1;

        var isolated_bounds = sensor.isolatedTile(tile);
        isolated_bounds[2] -= isolated_bounds[0];
        isolated_bounds[3] -= isolated_bounds[1];

        const fr = sensor.filter_radius_int;
        const r = camera.resolution + @as(Vec2i, @splat(2 * fr));
        const a = @as(u32, @intCast(r[0])) * @as(u32, @intCast(r[1]));
        const o = @as(u64, iteration) * a;
        const so = iteration / num_expected_samples;

        const y_back = tile[3];
        var y: i32 = tile[1];
        while (y <= y_back) : (y += 1) {
            const pixel_n = @as(u32, @intCast((y + fr) * r[0]));

            const x_back = tile[2];
            var x: i32 = tile[0];
            while (x <= x_back) : (x += 1) {
                const pixel_id = pixel_n + @as(u32, @intCast(x + fr));

                rng.start(0, @as(u64, pixel_id) + o);

                const sample_index = @as(u64, pixel_id) * @as(u64, num_expected_samples) + @as(u64, iteration);
                const tsi = @as(u32, @truncate(sample_index));
                const seed = @as(u32, @truncate(sample_index >> 32)) + so;

                self.samplers[0].startPixel(tsi, seed);

                self.photon = @splat(0.0);

                const pixel = Vec2i{ x, y };

                var s: u32 = 0;
                while (s < num_samples) : (s += 1) {
                    self.aov.clear();

                    const sample = sensor.cameraSample(pixel, &self.samplers[0]);
                    const vertex = camera.generateVertex(sample, frame, scene);

                    const color = self.surface_integrator.li(vertex, self);

                    var photon = self.photon;
                    if (photon[3] > 0.0) {
                        photon /= @as(Vec4f, @splat(photon[3]));
                        photon[3] = 0.0;
                    }

                    sensor.addSample(sample, color + photon, self.aov, crop, isolated_bounds);

                    self.samplers[0].incrementSample();
                }
            }
        }
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

    pub fn photonLi(self: *const Worker, isec: *const Intersection, sample: *const MaterialSample, sampler: *Sampler) Vec4f {
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

    pub fn commonAOV(self: *Worker, vertex: *const Vertex, isec: *const Intersection, mat_sample: *const MaterialSample) void {
        const primary_ray = vertex.state.primary_ray;

        if (primary_ray and self.aov.activeClass(.Albedo) and mat_sample.canEvaluate()) {
            self.aov.insert3(.Albedo, vertex.throughput * mat_sample.aovAlbedo());
        }

        if (vertex.probe.depth > 0) {
            return;
        }

        if (self.aov.activeClass(.GeometricNormal)) {
            self.aov.insert3(.GeometricNormal, mat_sample.super().geometricNormal());
        }

        if (self.aov.activeClass(.ShadingNormal)) {
            self.aov.insert3(.ShadingNormal, mat_sample.super().shadingNormal());
        }

        if (self.aov.activeClass(.Depth)) {
            self.aov.insert1(.Depth, vertex.probe.ray.maxT());
        }

        if (self.aov.activeClass(.MaterialId)) {
            self.aov.insert1(
                .MaterialId,
                @floatFromInt(1 + self.scene.propMaterialId(isec.prop, isec.part)),
            );
        }
    }

    pub fn visibility(
        self: *Worker,
        probe: *Probe,
        isec: *const Intersection,
        interfaces: *const InterfaceStack,
        sampler: *Sampler,
    ) ?Vec4f {
        const material = isec.material(self.scene);

        if (isec.subsurface() and !interfaces.empty() and material.denseSSSOptimization()) {
            const ray_max_t = probe.ray.maxT();
            const prop = isec.prop;

            var sss_isec: Intersection = undefined;
            const hit = self.scene.prop(prop).intersectSSS(prop, probe, &sss_isec, self.scene);

            if (hit) {
                const sss_min_t = probe.ray.minT();
                const sss_max_t = probe.ray.maxT();
                probe.ray.setMinMaxT(ro.offsetF(sss_max_t), ray_max_t);
                if (self.scene.visibility(probe, sampler, self)) |tv| {
                    probe.ray.setMinMaxT(sss_min_t, sss_max_t);
                    const cc = interfaces.topCC();
                    const tray = if (material.heterogeneousVolume()) sss_isec.trafo.worldToObjectRay(probe.ray) else probe.ray;
                    if (vlhlp.propTransmittance(tray, material, cc, prop, probe.depth, sampler, self)) |tr| {
                        const wi = probe.ray.direction;
                        const n = sss_isec.n;
                        const vbh = material.border(wi, n);
                        const nsc: Vec4f = @splat(subsurfaceNonSymmetryCompensation(wi, sss_isec.geo_n, n));

                        return (vbh * nsc) * (tv * tr);
                    }
                }

                return null;
            }
        }

        return self.scene.visibility(probe, sampler, self);
    }

    pub fn nextEvent(self: *Worker, comptime Particle: bool, vertex: *Vertex, isec: *Intersection, sampler: *Sampler) bool {
        while (!vertex.interfaces.empty()) {
            if (vlhlp.integrate(vertex, isec, sampler, self)) {
                vertex.throughput *= isec.vol_tr;

                if (.Pass == isec.event) {
                    const wo = -vertex.probe.ray.direction;
                    const material = isec.material(self.scene);
                    const straight_border = vertex.state.from_subsurface and material.denseSSSOptimization();

                    if (straight_border and !isec.sameHemisphere(wo)) {
                        const geo_n = isec.geo_n;
                        const n = isec.n;

                        const vbh = material.border(wo, n);
                        const nsc: Vec4f = @splat(subsurfaceNonSymmetryCompensation(wo, geo_n, n));
                        const weight = nsc * vbh;

                        vertex.throughput *= weight;

                        vertex.probe.ray.origin = isec.offsetP(vertex.probe.ray.direction);
                        vertex.probe.ray.setMaxT(ro.Ray_max_t);
                        vertex.probe.depth += 1;

                        sampler.incrementPadding();

                        if (Particle) {
                            const ior_t = vertex.interfaces.surroundingIor(self.scene);
                            const eta = material.ior() / ior_t;
                            vertex.throughput *= @splat(eta * eta);
                        }

                        vertex.interfaces.pop();
                        continue;
                    }
                }

                return true;
            }

            vertex.interfaces.pop();
        }

        const origin = vertex.probe.ray.origin;

        const hit = self.intersectAndResolveMask(&vertex.probe, isec, sampler);

        const dif_t = math.distance3(origin, vertex.probe.ray.origin);
        vertex.probe.ray.origin = origin;
        vertex.probe.ray.setMaxT(dif_t + vertex.probe.ray.maxT());

        const volume_hit = self.scene.scatter(&vertex.probe, isec, vertex.throughput, sampler, self);
        vertex.throughput *= isec.vol_tr;

        return hit or volume_hit;
    }

    pub fn propTransmittance(
        self: *Worker,
        ray: Ray,
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
        ray: Ray,
        throughput: Vec4f,
        material: *const Material,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
    ) Volume {
        const cc = material.super().cc;
        return vlhlp.propScatter(ray, throughput, material, cc, entity, depth, sampler, self);
    }

    pub fn propIntersect(self: *Worker, entity: u32, probe: *Probe, isec: *Intersection, ipo: Interpolation) bool {
        if (self.scene.prop(entity).intersect(entity, probe, isec, self.scene, ipo)) {
            isec.prop = entity;
            return true;
        }

        return false;
    }

    pub fn intersectAndResolveMask(self: *Worker, probe: *Probe, isec: *Intersection, sampler: *Sampler) bool {
        while (true) {
            if (!self.scene.intersect(probe, isec, .All)) {
                return false;
            }

            const o = isec.opacity(sampler, self.scene);
            if (1.0 == o or (o > 0.0 and o > sampler.sample1D())) {
                break;
            }

            // Offset ray until opaque surface is found
            probe.ray.origin = isec.offsetP(probe.ray.direction);
            probe.ray.setMaxT(ro.Ray_max_t);
        }

        return true;
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
        return @abs(math.dot3(wo, n)) / mat.clampAbsDot(wo, geo_n);
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
        const dim = if (@abs(n[0]) > @abs(n[1]) and @abs(n[0]) > @abs(n[2])) Vec2b{
            1,
            2,
        } else if (@abs(n[1]) > @abs(n[2])) Vec2b{
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

        if (@abs(det) < 1.0e-10) {
            return @splat(0.0);
        }

        const dudx = (a[1][1] * bx[0] - a[0][1] * bx[1]) / det;
        const dvdx = (a[0][0] * bx[1] - a[1][0] * bx[0]) / det;

        const dudy = (a[1][1] * by[0] - a[0][1] * by[1]) / det;
        const dvdy = (a[0][0] * by[1] - a[1][0] * by[0]) / det;

        return .{ dudx, dvdx, dudy, dvdy };
    }
};
