const Camera = @import("../camera/camera.zig").Camera;
const Sensor = @import("../rendering/sensor/sensor.zig").Sensor;
const Scene = @import("../scene/scene.zig").Scene;
const vt = @import("../scene/vertex.zig");
const Vertex = vt.Vertex;
const RayDif = vt.RayDif;
const Renderstate = @import("../scene/renderstate.zig").Renderstate;
const Probe = @import("../scene/shape/probe.zig").Probe;
const Material = @import("../scene/material/material.zig").Material;
const MaterialSample = @import("../scene/material/material_sample.zig").Sample;
const hlp = @import("../scene/material/material_helper.zig");
const ro = @import("../scene/ray_offset.zig");
const int = @import("../scene/shape/intersection.zig");
const Fragment = int.Fragment;
const Volume = int.Volume;
const DifferentialSurface = int.DifferentialSurface;
const Texture = @import("../image/texture/texture.zig").Texture;
const ts = @import("../image/texture/texture_sampler.zig");
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
const Mat3x3 = math.Mat3x3;
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
    camera: *Camera = undefined,
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

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.photon_mapper.deinit(alloc);
    }

    pub fn configure(
        self: *Self,
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

    pub fn render(
        self: *Self,
        frame: u32,
        tile: Vec4i,
        iteration: u32,
        num_samples: u32,
        num_expected_samples: u32,
    ) void {
        const camera = self.camera;
        const layer = self.layer;
        const sensor = self.sensor;
        const scene = self.scene;
        var rng = &self.rng;

        var crop = camera.super().crop;
        crop[2] -= crop[0] + 1;
        crop[3] -= crop[1] + 1;

        var isolated_bounds = sensor.isolatedTile(tile);
        isolated_bounds[2] -= isolated_bounds[0];
        isolated_bounds[3] -= isolated_bounds[1];

        const fr = sensor.filter_radius_int;
        const r = camera.super().resolution + @as(Vec2i, @splat(2 * fr));
        const a = @as(u32, @intCast(r[0])) * @as(u32, @intCast(r[1]));
        const o = @as(u64, iteration) * a;
        const so = iteration / num_expected_samples;

        const y_back = tile[3];
        var y: i32 = tile[1];
        while (y <= y_back) : (y += 1) {
            const pixel_n: u32 = @intCast((y + fr) * r[0]);

            const x_back = tile[2];
            var x: i32 = tile[0];
            while (x <= x_back) : (x += 1) {
                const pixel_id = pixel_n + @as(u32, @intCast(x + fr));

                rng.start(0, @as(u64, pixel_id) + o);

                const sample_index = @as(u64, pixel_id) * @as(u64, num_expected_samples) + @as(u64, iteration);
                const tsi: u32 = @truncate(sample_index);
                const seed = @as(u32, @truncate(sample_index >> 32)) + so;

                self.samplers[0].startPixel(tsi, seed);

                const pixel = Vec2i{ x, y };

                var s: u32 = 0;
                while (s < num_samples) : (s += 1) {
                    self.aov.clear();

                    const sample = sensor.cameraSample(pixel, &self.samplers[0]);
                    const vertex = camera.generateVertex(sample, layer, frame, scene);

                    const ivalue = self.surface_integrator.li(vertex, self);

                    sensor.addSample(layer, sample, ivalue, self.aov, crop, isolated_bounds);

                    self.samplers[0].incrementSample();
                }
            }
        }
    }

    pub fn particles(self: *Self, frame: u32, offset: u64, range: Vec2ul) void {
        var rng = &self.rng;
        rng.start(0, offset);

        const tsi: u32 = @truncate(range[0]);
        const seed: u32 = @truncate(range[0] >> 32);
        self.samplers[0].startPixel(tsi, seed);

        for (range[0]..range[1]) |_| {
            self.lighttracer.li(frame, self);

            self.samplers[0].incrementSample();
        }
    }

    pub fn bakePhotons(self: *Self, begin: u32, end: u32, frame: u32, iteration: u32) u32 {
        if (self.photon_map) |pm| {
            return self.photon_mapper.bake(pm, begin, end, frame, iteration, self);
        }

        return 0;
    }

    pub fn photonLi(self: *const Self, frag: *const Fragment, sample: *const MaterialSample, sampler: *Sampler) Vec4f {
        if (self.photon_map) |pm| {
            return pm.li(frag, sample, sampler, self);
        }

        return @splat(0.0);
    }

    pub inline fn pickSampler(self: *Self, bounce: u32) *Sampler {
        if (bounce < 3) {
            return &self.samplers[0];
        }

        return &self.samplers[1];
    }

    pub fn commonAOV(self: *Self, vertex: *const Vertex, frag: *const Fragment, mat_sample: *const MaterialSample) void {
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

    pub fn visibility(self: *const Self, probe: Probe, sampler: *Sampler, tr: *Vec4f) bool {
        return self.scene.visibility(probe, sampler, self, tr);
    }

    pub fn nextEvent(self: *Self, vertex: *Vertex, frag: *Fragment, sampler: *Sampler) void {
        if (!vertex.mediums.empty()) {
            VolumeIntegrator.integrate(vertex, frag, sampler, self);
            return;
        }

        const origin = vertex.probe.ray.origin;

        _ = self.intersectAndResolveMask(&vertex.probe, frag, sampler);

        const dif_t = math.distance3(origin, vertex.probe.ray.origin);
        vertex.probe.ray.origin = origin;
        vertex.probe.ray.max_t += dif_t;

        self.scene.scatter(&vertex.probe, frag, &vertex.throughput, sampler, self);
    }

    pub fn emission(self: *const Self, vertex: *const Vertex, frag: *Fragment, split_threshold: f32, sampler: *Sampler) Vec4f {
        return self.scene.unoccluding_bvh.emission(vertex, frag, split_threshold, sampler, self);
    }

    pub fn propTransmittance(
        self: *const Self,
        ray: Ray,
        material: *const Material,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        tr: *Vec4f,
    ) bool {
        const cc = material.collisionCoefficients();
        return VolumeIntegrator.propTransmittance(ray, material, cc, entity, depth, sampler, self, tr);
    }

    pub fn propScatter(
        self: *const Self,
        ray: Ray,
        throughput: Vec4f,
        material: *const Material,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
    ) Volume {
        const cc = material.collisionCoefficients();
        return VolumeIntegrator.propScatter(ray, throughput, material, cc, entity, depth, sampler, self);
    }

    pub fn propIntersect(self: *const Self, entity: u32, probe: Probe, frag: *Fragment) bool {
        if (self.scene.prop(entity).intersect(entity, probe, &frag.isec, self.scene, &self.scene.prop_space)) {
            frag.prop = entity;
            return true;
        }

        return false;
    }

    pub fn propInterpolateFragment(self: *const Self, entity: u32, probe: Probe, frag: *Fragment) void {
        self.scene.propShape(entity).fragment(probe.ray, frag);
    }

    pub fn intersectAndResolveMask(self: *const Self, probe: *Probe, frag: *Fragment, sampler: *Sampler) bool {
        while (true) {
            if (!self.scene.intersect(probe, frag)) {
                return false;
            }

            const o = frag.opacity(sampler, self);
            if (1.0 == o or (o > 0.0 and o > sampler.sample1D())) {
                break;
            }

            // Offset ray until opaque surface is found
            probe.ray.origin = frag.offsetP(probe.ray.direction);
            probe.ray.max_t = ro.RayMaxT;
        }

        return true;
    }

    pub fn sampleProcedural2D_1(self: *const Self, key: ts.Key, texture: Texture, rs: Renderstate, sampler: *Sampler) f32 {
        return self.scene.procedural.sample2D_1(key, texture, rs, sampler, self);
    }

    pub fn sampleProcedural2D_2(self: *const Self, key: ts.Key, texture: Texture, rs: Renderstate, sampler: *Sampler) Vec2f {
        return self.scene.procedural.sample2D_2(key, texture, rs, sampler, self);
    }

    pub fn sampleProcedural2D_3(self: *const Self, key: ts.Key, texture: Texture, rs: Renderstate, sampler: *Sampler) Vec4f {
        return self.scene.procedural.sample2D_3(key, texture, rs, sampler, self);
    }

    pub fn absoluteTime(self: *const Self, frame: u32, frame_delta: f32) u64 {
        return self.camera.super().absoluteTime(frame, frame_delta);
    }

    pub fn screenspaceDifferential(self: *const Self, rs: Renderstate, texcoord: Texture.TexCoordMode) Vec4f {
        const rd = self.camera.calculateRayDifferential(self.layer, rs.p, rs.time, self.scene);

        const ds: DifferentialSurface =
            if (.UV0 == texcoord)
                self.scene.propShape(rs.prop).surfaceDifferential(rs.primitive, rs.trafo)
            else
                hlp.triplanarDifferential(rs.geo_n, rs.trafo);

        return calculateScreenspaceDifferential(rs.p, rs.geo_n, rd, ds.dpdu, ds.dpdv);
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

    // Adapted from PBRT
    // https://github.com/mmp/pbrt-v4/blob/f140d7cba5dc7b941f9346d6b7d1476a05c28c37/src/pbrt/cameras.h#L155
    pub fn approximateDpDxy(self: *const Self, rs: Renderstate) [2]Vec4f {
        const Origin: Vec4f = comptime @splat(0.0);
        const Z: Vec4f = comptime .{ 0.0, 0.0, 1.0, 0.0 };

        const min_pos_differential_x: Vec4f = @splat(0.0);
        const min_pos_differential_y: Vec4f = @splat(0.0);

        const min_dir_differential_x, const min_dir_differential_y = self.camera.minDirDifferential(self.layer);

        const trafo = self.scene.propTransformationAt(self.camera.super().entity, rs.time);

        const p_o = trafo.worldToObjectPoint(rs.p);
        const n_o = trafo.worldToObjectNormal(rs.geo_n);

        const down_z_from_camera = Mat3x3.initRotationAlign(math.normalize3(p_o), Z);
        const p_down_z = down_z_from_camera.transformVector(p_o);
        const n_down_z = down_z_from_camera.transformVector(n_o);
        const d = n_down_z[2] * p_down_z[2];

        const x_ray = Ray.init(Origin + min_pos_differential_x, Z + min_dir_differential_x, 0.0, 1.0);
        const tx = -(math.dot3(n_down_z, x_ray.origin) - d) / math.dot3(n_down_z, x_ray.direction);

        const y_ray = Ray.init(Origin + min_pos_differential_y, Z + min_dir_differential_y, 0.0, 1.0);
        const ty = -(math.dot3(n_down_z, y_ray.origin) - d) / math.dot3(n_down_z, y_ray.direction);

        const px = x_ray.point(tx);
        const py = y_ray.point(ty);

        const dpdx = trafo.objectToWorldVector(down_z_from_camera.transformVectorTransposed(px - p_down_z));
        const dpdy = trafo.objectToWorldVector(down_z_from_camera.transformVectorTransposed(py - p_down_z));

        return .{
            dpdx,
            dpdy,
        };
    }
};
