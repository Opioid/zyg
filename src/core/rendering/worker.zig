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
const TileStackN = @import("tile_queue.zig").TileStackN;
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
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Worker = struct {
    pub const Tile_dimensions = 16;
    const Tile_area = Tile_dimensions * Tile_dimensions;
    const Tile_cells = 4 + 16 + 64;

    const TileStack = TileStackN(Tile_area);

    camera: *cam.Perspective align(64) = undefined,
    scene: *Scene = undefined,

    rng: RNG = undefined,

    interface_stack: InterfaceStack = undefined,

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
        target_tile: Vec4i,
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

        var old_ms: [Tile_area]Vec4f = undefined;
        var old_ss: [Tile_area]f32 = undefined;

        @memset(&old_ms, @as(Vec4f, @splat(0.0)));
        @memset(&old_ss, 0.0);

        var tile_stacks: [2]TileStack = undefined;

        var stack_a = &tile_stacks[0];
        var stack_b = &tile_stacks[1];

        stack_a.clear();
        stack_a.push(target_tile);

        var ss: u32 = 0;
        while (ss < num_samples) {
            const s_end = @min(ss + step, num_samples);

            stack_b.clear();

            while (stack_a.pop()) |tile| {
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

                        const sample_index = @as(u64, pixel_id) * @as(u64, num_expected_samples) + @as(u64, iteration + ss);
                        const tsi: u32 = @truncate(sample_index);
                        const seed = @as(u32, @truncate(sample_index >> 32)) + so;

                        rng.start(0, sample_index);
                        self.samplers[0].startPixel(tsi, seed);

                        self.photon = @splat(0.0);

                        const pixel = Vec2i{ x, y };

                        var old_m = old_ms[ii];
                        var old_s = old_ss[ii];

                        for (ss..s_end) |s| {
                            self.aov.clear();

                            const sample = sensor.cameraSample(pixel, &self.samplers[0]);
                            var vertex = camera.generateVertex(sample, frame, scene);

                            self.resetInterfaceStack(&camera.interface_stack);
                            const color = self.surface_integrator.li(&vertex, s < num_photon_samples, self);

                            var photon = self.photon;
                            if (photon[3] > 0.0) {
                                photon /= @splat(photon[3]);
                                photon[3] = 0.0;
                            }

                            const clamped = sensor.addSample(sample, color + photon, self.aov);
                            const value = clamped.last;
                            const new_m = clamped.mean;

                            old_s += math.hmax3((value - old_m) * (value - new_m));
                            old_m = new_m;

                            self.samplers[0].incrementSample();
                        }

                        old_ms[ii] = old_m;
                        old_ss[ii] = old_s;

                        const variance = old_s * old_m[3];
                        const mam = math.max(math.hmax3(old_m), 0.0001);

                        const qm = if (mam < 1.0) std.math.pow(f32, variance / mam, 1.0 / 2.4) else @log(math.max(variance, 1.0)) / mam;

                        tile_qm = math.max(tile_qm, qm);
                    }

                    yy += 1;
                }

                if (tile_qm > qm_threshold or (tile_qm > 0.0 and ss < 64)) {
                    if (ss == 128) {
                        stack_b.pushQuartet(tile, Tile_dimensions / 2 - 1);
                    } else if (ss == 256) {
                        stack_b.pushQuartet(tile, Tile_dimensions / 4 - 1);
                    } else if (ss == 512) {
                        stack_b.pushQuartet(tile, Tile_dimensions / 8 - 1);
                    } else if (ss == 1024) {
                        stack_b.pushQuartet(tile, Tile_dimensions / 16 - 1);
                    } else {
                        stack_b.push(tile);
                    }
                }
            }

            if (stack_b.empty()) {
                break;
            }

            ss += step;

            std.mem.swap(TileStack, stack_a, stack_b);
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
        vertex: *const Vertex,
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
                @as(f32, @floatFromInt(1 + self.scene.propMaterialId(vertex.isec.prop, vertex.isec.part))),
            );
        }
    }

    pub fn visibility(self: *Worker, vertex: *Vertex, sampler: *Sampler) ?Vec4f {
        const material = vertex.isec.material(self.scene);

        if (vertex.isec.subsurface() and !self.interface_stack.empty() and material.denseSSSOptimization()) {
            const ray_max_t = vertex.ray.maxT();
            const prop = vertex.isec.prop;

            const hit = self.scene.prop(prop).intersectSSS(prop, vertex, self.scene);

            if (hit) {
                const sss_min_t = vertex.ray.minT();
                const sss_max_t = vertex.ray.maxT();
                vertex.ray.setMinMaxT(ro.offsetF(sss_max_t), ray_max_t);
                if (self.scene.visibility(vertex, sampler, self)) |tv| {
                    vertex.ray.setMinMaxT(sss_min_t, sss_max_t);
                    const interface = self.interface_stack.top();
                    const cc = interface.cc;
                    const tray = if (material.heterogeneousVolume()) vertex.isec.trafo.worldToObjectRay(vertex.ray) else vertex.ray;
                    if (vlhlp.propTransmittance(tray, material, cc, prop, vertex.depth, sampler, self)) |tr| {
                        const wi = vertex.ray.direction;
                        const n = vertex.isec.n;
                        const vbh = material.border(wi, n);
                        const nsc: Vec4f = @splat(subsurfaceNonSymmetryCompensation(wi, vertex.isec.geo_n, n));

                        return (vbh * nsc) * (tv * tr);
                    }
                }

                return null;
            }
        }

        return self.scene.visibility(vertex, sampler, self);
    }

    pub fn nextEvent(self: *Worker, vertex: *Vertex, throughput: Vec4f, sampler: *Sampler) bool {
        var sss_throughput: Vec4f = @splat(1.0);

        while (!self.interface_stack.empty()) {
            if (vlhlp.integrate(vertex, throughput * sss_throughput, sampler, self)) {
                if (.Pass == vertex.isec.event) {
                    const wo = -vertex.ray.direction;
                    const material = vertex.isec.material(self.scene);
                    const straight_border = vertex.state.from_subsurface and material.denseSSSOptimization();

                    if (!vertex.isec.subsurface() and straight_border and !vertex.isec.sameHemisphere(wo)) {
                        const geo_n = vertex.isec.geo_n;
                        const n = vertex.isec.n;

                        const vbh = material.border(wo, n);
                        const nsc: Vec4f = @splat(subsurfaceNonSymmetryCompensation(wo, geo_n, n));
                        const weight = nsc * vbh;

                        sss_throughput *= vertex.isec.vol_tr * weight;
                        vertex.ray.setMinMaxT(vertex.isec.offsetT(vertex.ray.maxT()), ro.Ray_max_t);
                        vertex.depth += 1;
                        sampler.incrementPadding();

                        self.interface_stack.pop();
                        continue;
                    }
                }

                return true;
            }

            self.interface_stack.pop();
        }

        const origin = vertex.ray.origin;

        const hit = self.intersectAndResolveMask(vertex, sampler);

        const dif_t = math.distance3(origin, vertex.ray.origin);
        vertex.ray.origin = origin;
        vertex.ray.setMaxT(dif_t + vertex.ray.maxT());

        const volume_hit = self.scene.scatter(vertex, throughput * sss_throughput, sampler, self);

        vertex.isec.vol_tr *= sss_throughput;

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

    pub fn propIntersect(self: *Worker, entity: u32, vertex: *Vertex, ipo: Interpolation) bool {
        return self.scene.prop(entity).intersect(entity, vertex, self.scene, ipo);
    }

    pub fn intersectAndResolveMask(self: *Worker, vertex: *Vertex, sampler: *Sampler) bool {
        while (true) {
            if (!self.scene.intersect(vertex, .All)) {
                return false;
            }

            const o = vertex.isec.opacity(sampler, self.scene);
            if (1.0 == o or (o > 0.0 and o > sampler.sample1D())) {
                break;
            }

            // Offset ray until opaque surface is found
            vertex.ray.origin = vertex.isec.offsetP(vertex.ray.direction);
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
