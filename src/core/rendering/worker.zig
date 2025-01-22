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
const MediumStack = @import("../scene/prop/medium.zig").Stack;
const TileStackN = @import("tile_queue.zig").TileStackN;
const Material = @import("../scene/material/material.zig").Material;
const MaterialSample = @import("../scene/material/material_sample.zig").Sample;
const IoR = @import("../scene/material/sample_base.zig").IoR;
const ro = @import("../scene/ray_offset.zig");
const shp = @import("../scene/shape/intersection.zig");
const Fragment = shp.Fragment;
const Volume = shp.Volume;
const LightTree = @import("../scene/light/light_tree.zig").Tree;
const smpl = @import("../sampler/sampler.zig");
const Sampler = smpl.Sampler;
const surface = @import("integrator/surface/integrator.zig");
const VolumeIntegrator = @import("integrator/volume/volume_integrator.zig").Integrator;
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
    pub const Tile_dimensions = 16;
    const Tile_area = Tile_dimensions * Tile_dimensions;

    const TileStack = TileStackN(Tile_area);

    const Step = 16;

    camera: *cam.Perspective = undefined,
    sensor: *Sensor = undefined,

    scene: *Scene = undefined,

    surface_integrator: *surface.Integrator = undefined,
    lighttracer: *lt.Lighttracer = undefined,

    rng: RNG = undefined,

    samplers: [2]Sampler = undefined,

    aov: aov.Value = undefined,

    photon_mapper: PhotonMapper = .{},
    photon_map: ?*PhotonMap = null,

    layer: u32 = undefined,

    pub fn deinit(self: *Worker, alloc: Allocator) void {
        self.photon_mapper.deinit(alloc);
    }

    pub fn configure(
        self: *Worker,
        alloc: Allocator,
        sensor: *Sensor,
        scene: *Scene,
        surface_integrator: *surface.Integrator,
        lighttracer: *lt.Lighttracer,
        samplers: smpl.Factory,
        aovs: aov.Factory,
        photon_settings: PhotonSettings,
        photon_map: ?*PhotonMap,
    ) !void {
        self.sensor = sensor;
        self.scene = scene;

        self.surface_integrator = surface_integrator;
        self.lighttracer = lighttracer;

        const rng = &self.rng;

        self.samplers[0] = samplers.create(rng);
        self.samplers[1] = .{ .Random = .{ .rng = rng } };

        self.aov = aovs.create();

        const max_bounces = if (photon_settings.num_photons > 0) photon_settings.max_bounces else 0;
        try self.photon_mapper.configure(alloc, .{
            .max_bounces = max_bounces,
            .full_light_path = photon_settings.full_light_path,
        }, rng);

        self.photon_map = photon_map;
    }

    fn curve(value: Vec4f) Vec4f {
        const p = Vec4f{
            std.math.pow(f32, value[0], 1.0 / 2.2),
            std.math.pow(f32, value[1], 1.0 / 2.2),
            std.math.pow(f32, value[2], 1.0 / 2.2),
            0.0,
        };

        return p;
    }

    // Running variance calculation as described in
    // https://www.johndcook.com/blog/standard_deviation/

    pub fn render(
        self: *Worker,
        frame: u32,
        target_tile: Vec4i,
        iteration: u32,
        num_samples: u32,
        num_expected_samples: u32,
        qm_threshold: f32,
    ) void {
        const camera = self.camera;
        const layer = self.layer;
        const sensor = self.sensor;
        const scene = self.scene;
        const r = camera.resolution;
        const so = iteration / num_expected_samples;
        const offset = Vec2i{ target_tile[0], target_tile[1] };

        // Those values are only used for variance estimation
        // Exposure and tonemapping is not done here
        const ef: Vec4f = @splat(sensor.tonemapper.exposure_factor);
        const wp: f32 = 1.0;
        const qm_threshold_squared = qm_threshold * qm_threshold;

        var rng = &self.rng;

        var old_mm = [_]Vec4f{@splat(0)} ** Tile_area;
        var old_ss = [_]Vec4f{@splat(0)} ** Tile_area;

        var tile_stacks: [2]TileStack = undefined;

        var stack_a = &tile_stacks[0];
        var stack_b = &tile_stacks[1];

        stack_a.clear();
        stack_a.push(target_tile, offset);

        var s_start: u32 = 0;
        while (s_start < num_samples) {
            const s_end = @min(s_start + Step, num_samples);

            stack_b.clear();

            while (stack_a.pop(offset)) |tile| {
                const y_back = tile[3];
                var y = tile[1];
                var yy = @rem(y, Tile_dimensions);

                var tile_qm: f32 = 0.0;

                while (y <= y_back) : (y += 1) {
                    const x_back = tile[2];
                    var x = tile[0];
                    var xx = @rem(x, Tile_dimensions);
                    const pixel_n: u32 = @intCast(y * r[0]);

                    while (x <= x_back) : (x += 1) {
                        const ii: u32 = @intCast(yy * Tile_dimensions + xx);
                        xx += 1;

                        const pixel_id = pixel_n + @as(u32, @intCast(x));

                        const sample_index = @as(u64, pixel_id) * @as(u64, num_expected_samples) + @as(u64, iteration + s_start);
                        const tsi: u32 = @truncate(sample_index);
                        const seed = @as(u32, @truncate(sample_index >> 32)) + so;

                        rng.start(0, sample_index);
                        self.samplers[0].startPixel(tsi, seed);

                        const pixel = Vec2i{ x, y };

                        var old_m = old_mm[ii];
                        var old_s = old_ss[ii];

                        for (s_start..s_end) |cs| {
                            self.aov.clear();

                            const sample = sensor.cameraSample(pixel, &self.samplers[0]);
                            const vertex = camera.generateVertex(sample, layer, frame, scene);

                            const ivalue = self.surface_integrator.li(vertex, self);

                            // The weightd value is what was added to the pixel
                            const weighted = sensor.addSample(layer, sample, ivalue, self.aov);

                            // This clipped value is what we use for the noise estimate
                            const value = math.min4(@abs(ef * weighted), @splat(wp));

                            const new_m = old_m + (value - old_m) / @as(Vec4f, @splat(@floatFromInt(cs + 1)));

                            old_s += (value - old_m) * (value - new_m);
                            old_m = new_m;

                            self.samplers[0].incrementSample();
                        }

                        old_mm[ii] = old_m;
                        old_ss[ii] = old_s;

                        const variance = old_s / @as(Vec4f, @splat(@floatFromInt(s_end - 1)));

                        const std_dev = @sqrt(variance);

                        const mapped_value = curve(old_m);
                        const mapped_lower = curve(math.max4(old_m - std_dev, @splat(0.0)));
                        const mapped_upper = curve(old_m + std_dev);

                        const qm = math.max(math.hmax3(mapped_value - mapped_lower), math.hmax3(mapped_upper - mapped_value));

                        tile_qm = math.max(tile_qm, qm);
                    }

                    yy += 1;
                }

                var terminates = true;

                const target_samples: u32 = @intFromFloat(@ceil(tile_qm / qm_threshold_squared));

                if (target_samples > s_end or (tile_qm > 0.0 and s_end < 64)) {
                    if (s_end == 128) {
                        stack_b.pushQuartet(tile, offset, Tile_dimensions / 2 - 1);
                    } else if (s_end == 256) {
                        stack_b.pushQuartet(tile, offset, Tile_dimensions / 4 - 1);
                    } else if (s_end == 512) {
                        stack_b.pushQuartet(tile, offset, Tile_dimensions / 8 - 1);
                    } else if (s_end == 1024) {
                        stack_b.pushQuartet(tile, offset, Tile_dimensions / 16 - 1);
                    } else {
                        stack_b.push(tile, offset);
                    }

                    terminates = s_end == num_samples;
                }

                if (terminates) {
                    sensor.writeTileNoise(layer, tile, tile_qm);
                }
            }

            if (stack_b.empty()) {
                break;
            }

            s_start += Step;

            std.mem.swap(TileStack, stack_a, stack_b);
        }
    }

    pub fn particles(self: *Worker, frame: u32, offset: u64, range: Vec2ul) void {
        const camera = self.camera;

        var rng = &self.rng;
        rng.start(0, offset);

        const tsi: u32 = @truncate(range[0]);
        const seed: u32 = @truncate(range[0] >> 32);
        self.samplers[0].startPixel(tsi, seed);

        for (range[0]..range[1]) |_| {
            self.lighttracer.li(frame, self, &camera.mediums);

            self.samplers[0].incrementSample();
        }
    }

    pub fn bakePhotons(self: *Worker, begin: u32, end: u32, frame: u32, iteration: u32) u32 {
        if (self.photon_map) |pm| {
            return self.photon_mapper.bake(pm, begin, end, frame, iteration, self);
        }

        return 0;
    }

    pub fn photonLi(self: *const Worker, frag: *const Fragment, sample: *const MaterialSample, sampler: *Sampler) Vec4f {
        if (self.photon_map) |pm| {
            return pm.li(frag, sample, sampler, self.scene);
        }

        return @splat(0.0);
    }

    pub inline fn pickSampler(self: *Worker, bounce: u32) *Sampler {
        if (bounce < 3) {
            return &self.samplers[0];
        }

        return &self.samplers[1];
    }

    pub fn commonAOV(self: *Worker, vertex: *const Vertex, frag: *const Fragment, mat_sample: *const MaterialSample) void {
        const primary_ray = vertex.state.primary_ray;

        if (primary_ray and self.aov.activeClass(.Albedo) and mat_sample.canEvaluate()) {
            self.aov.insert3(.Albedo, vertex.throughput * mat_sample.aovAlbedo());
        }

        if (vertex.probe.depth.surface > 0) {
            return;
        }

        if (self.aov.activeClass(.GeometricNormal)) {
            self.aov.insert3(.GeometricNormal, mat_sample.super().geometricNormal());
        }

        if (self.aov.activeClass(.ShadingNormal)) {
            self.aov.insert3(.ShadingNormal, mat_sample.super().shadingNormal());
        }

        if (self.aov.activeClass(.Depth)) {
            self.aov.insert1(.Depth, vertex.probe.ray.max_t);
        }

        if (self.aov.activeClass(.MaterialId)) {
            self.aov.insert1(
                .MaterialId,
                @floatFromInt(1 + self.scene.propMaterialId(frag.prop, frag.part)),
            );
        }
    }

    pub fn visibility(self: *Worker, probe: *Probe, sampler: *Sampler, tr: *Vec4f) bool {
        return self.scene.visibility(probe, sampler, self, tr);
    }

    pub fn nextEvent(self: *Worker, vertex: *Vertex, frag: *Fragment, sampler: *Sampler) bool {
        if (!vertex.mediums.empty()) {
            return VolumeIntegrator.integrate(vertex, frag, sampler, self);
        }

        const origin = vertex.probe.ray.origin;

        const hit = self.intersectAndResolveMask(&vertex.probe, frag, sampler);

        const dif_t = math.distance3(origin, vertex.probe.ray.origin);
        vertex.probe.ray.origin = origin;
        vertex.probe.ray.max_t += dif_t;

        const volume_hit = self.scene.scatter(&vertex.probe, frag, &vertex.throughput, sampler, self);

        return hit or volume_hit;
    }

    pub fn propTransmittance(
        self: *Worker,
        ray: Ray,
        material: *const Material,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        tr: *Vec4f,
    ) bool {
        const cc = material.super().cc;
        return VolumeIntegrator.propTransmittance(ray, material, cc, entity, depth, sampler, self, tr);
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
        return VolumeIntegrator.propScatter(ray, throughput, material, cc, entity, depth, sampler, self);
    }

    pub fn propIntersect(self: *Worker, entity: u32, probe: *Probe, frag: *Fragment, override_visibility: bool) bool {
        if (self.scene.prop(entity).intersect(entity, probe, frag, override_visibility, self.scene)) {
            frag.prop = entity;
            return true;
        }

        return false;
    }

    pub fn propInterpolateFragment(self: *Worker, entity: u32, probe: *const Probe, frag: *Fragment) void {
        self.scene.prop(entity).fragment(probe, frag, self.scene);
    }

    pub fn intersectAndResolveMask(self: *Worker, probe: *Probe, frag: *Fragment, sampler: *Sampler) bool {
        while (true) {
            if (!self.scene.intersect(probe, frag)) {
                return false;
            }

            const o = frag.opacity(sampler, self.scene);
            if (1.0 == o or (o > 0.0 and o > sampler.sample1D())) {
                break;
            }

            // Offset ray until opaque surface is found
            probe.ray.origin = frag.offsetP(probe.ray.direction);
            probe.ray.max_t = ro.Ray_max_t;
        }

        return true;
    }

    pub fn absoluteTime(self: *const Worker, frame: u32, frame_delta: f32) u64 {
        return self.camera.absoluteTime(frame, frame_delta);
    }

    pub fn screenspaceDifferential(self: *const Worker, rs: Renderstate) Vec4f {
        const rd = self.camera.calculateRayDifferential(self.layer, rs.p, rs.time, self.scene);

        const ds = self.scene.propShape(rs.prop).differentialSurface(rs.primitive);

        const dpdu_w = rs.trafo.objectToWorldVector(ds.dpdu);
        const dpdv_w = rs.trafo.objectToWorldVector(ds.dpdv);

        return calculateScreenspaceDifferential(rs.p, rs.geo_n, rd, dpdu_w, dpdv_w);
    }

    // https://blog.yiningkarlli.com/2018/10/bidirectional-mipmap.html
    fn calculateScreenspaceDifferential(p: Vec4f, n: Vec4f, rd: RayDif, dpdu: Vec4f, dpdv: Vec4f) Vec4f {
        // Compute offset-ray frag points with tangent plane
        const d = math.dot3(n, p);

        const tx = -(math.dot3(n, rd.x_origin) - d) / math.dot3(n, rd.x_direction);
        const ty = -(math.dot3(n, rd.y_origin) - d) / math.dot3(n, rd.y_direction);

        const px = rd.x_origin + @as(Vec4f, @splat(tx)) * rd.x_direction;
        const py = rd.y_origin + @as(Vec4f, @splat(ty)) * rd.y_direction;

        // Compute uv offsets at offset-ray frag points
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
