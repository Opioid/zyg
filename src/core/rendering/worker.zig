const cam = @import("../camera/perspective.zig");
const Scene = @import("../scene/scene.zig").Scene;
const Ray = @import("../scene/ray.zig").Ray;
const Intersection = @import("../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../scene/prop/interface.zig").Stack;
const mat = @import("../scene/material/material_helper.zig");
const ro = @import("../scene/ray_offset.zig");
const smpl = @import("../sampler/sampler.zig");
const Sampler = smpl.Sampler;
const SceneWorker = @import("../scene/worker.zig").Worker;
const Filter = @import("../image/texture/sampler.zig").Filter;
const surface = @import("integrator/surface/integrator.zig");
const vol = @import("integrator/volume/integrator.zig");
const VolumeResult = @import("integrator/volume/result.zig").Result;
const lt = @import("integrator/particle/lighttracer.zig");

const math = @import("base").math;
const Vec2i = math.Vec2i;
const Vec2ul = math.Vec2ul;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;

pub const Worker = struct {
    super: SceneWorker = undefined,

    sampler: Sampler = undefined,

    surface_integrator: surface.Integrator = undefined,
    volume_integrator: vol.Integrator = undefined,
    lighttracer: lt.Lighttracer = undefined,

    pub fn init(alloc: *Allocator) !Worker {
        return Worker{ .super = try SceneWorker.init(alloc) };
    }

    pub fn deinit(self: *Worker, alloc: *Allocator) void {
        self.lighttracer.deinit(alloc);
        self.volume_integrator.deinit(alloc);
        self.surface_integrator.deinit(alloc);
        self.sampler.deinit(alloc);
        self.super.deinit(alloc);
    }

    pub fn configure(
        self: *Worker,
        alloc: *Allocator,
        camera: *cam.Perspective,
        scene: *Scene,
        num_samples_per_pixel: u32,
        samplers: smpl.Factory,
        surfaces: surface.Factory,
        volumes: vol.Factory,
        lighttracers: lt.Factory,
    ) !void {
        self.super.configure(camera, scene);

        self.sampler = try samplers.create(alloc, 1, 2, num_samples_per_pixel);

        self.surface_integrator = try surfaces.create(alloc, num_samples_per_pixel);
        self.volume_integrator = try volumes.create(alloc, num_samples_per_pixel);
        self.lighttracer = try lighttracers.create(alloc);
    }

    pub fn render(self: *Worker, frame: u32, tile: Vec4i, num_samples: u32) void {
        var camera = self.super.camera;
        const sensor = &camera.sensor;
        const scene = self.super.scene;

        const offset = @splat(2, @as(i32, 0));

        var crop = camera.crop;
        crop[2] -= crop[0] + 1;
        crop[3] -= crop[1] + 1;
        crop[0] += offset[0];
        crop[1] += offset[1];

        const xy = offset + Vec2i{ tile[0], tile[1] };
        const zw = offset + Vec2i{ tile[2], tile[3] };
        const view_tile = Vec4i{ xy[0], xy[1], zw[0], zw[1] };

        var isolated_bounds = sensor.isolatedTile(view_tile);
        isolated_bounds[2] -= isolated_bounds[0];
        isolated_bounds[3] -= isolated_bounds[1];

        const fr = sensor.filterRadiusInt();

        const r = camera.resolution + @splat(2, 2 * fr);

        const o0 = 0; //uint64_t(iteration) * @intCast(u64, r.v[0] * r.v[1]);

        const y_back = tile[3];
        var y: i32 = tile[1];
        while (y <= y_back) : (y += 1) {
            const o1 = @intCast(u64, (y + fr) * r[0]) + o0;
            const x_back = tile[2];
            var x: i32 = tile[0];
            while (x <= x_back) : (x += 1) {
                self.super.rng.start(0, o1 + @intCast(u64, x + fr));

                self.sampler.startPixel();
                self.surface_integrator.startPixel();

                const pixel = Vec2i{ x, y };

                var s: u32 = 0;
                while (s < num_samples) : (s += 1) {
                    const sample = self.sampler.cameraSample(&self.super.rng, pixel);

                    if (camera.generateRay(sample, frame, scene.*)) |*ray| {
                        const color = self.li(ray, camera.interface_stack);
                        sensor.addSample(sample, color, offset, isolated_bounds, crop);
                    } else {
                        sensor.addSample(sample, @splat(4, @as(f32, 0.0)), offset, isolated_bounds, crop);
                    }
                }
            }
        }
    }

    pub fn particles(self: *Worker, frame: u32, offset: u64, range: Vec2ul) void {
        var camera = self.super.camera;

        self.super.rng.start(0, offset + range[0]);
        self.lighttracer.startPixel();

        var i = range[0];
        while (i < range[1]) : (i += 1) {
            self.lighttracer.li(frame, self, camera.interface_stack);
        }
    }

    fn li(self: *Worker, ray: *Ray, interface_stack: InterfaceStack) Vec4f {
        var isec = Intersection{};
        if (self.super.intersectAndResolveMask(ray, null, &isec)) {
            return self.surface_integrator.li(ray, &isec, self, interface_stack);
        }

        return @splat(4, @as(f32, 0.0));
    }

    pub fn transmitted(
        self: *Worker,
        ray: *Ray,
        wo: Vec4f,
        isec: Intersection,
        filter: ?Filter,
    ) ?Vec4f {
        if (self.subsurfaceVisibility(ray, wo, isec, filter)) |a| {
            if (self.transmittance(ray.*, filter)) |b| {
                return a * b;
            }
        }

        return null;
    }

    pub fn volume(self: *Worker, ray: *Ray, isec: *Intersection, filter: ?Filter) VolumeResult {
        return self.volume_integrator.integrate(ray, isec, filter, self);
    }

    fn transmittance(self: *Worker, ray: Ray, filter: ?Filter) ?Vec4f {
        if (!self.super.scene.has_volumes) {
            return @splat(4, @as(f32, 1.0));
        }

        self.super.interface_stack.copy(&self.super.interface_stack_temp);

        // This is the typical SSS case:
        // A medium is on the stack but we already considered it during shadow calculation,
        // ignoring the IoR. Therefore remove the medium from the stack.
        if (!self.super.interface_stack.straight(self.super)) {
            self.super.interface_stack.pop();
        }

        const ray_max_t = ray.ray.maxT();
        var tray = ray;

        var isec: Intersection = undefined;

        var w = @splat(4, @as(f32, 1.0));

        while (true) {
            const hit = self.super.scene.intersectVolume(&tray, &self.super, &isec);

            if (!self.super.interface_stack.empty()) {
                if (self.volume_integrator.transmittance(tray, filter, &self.super)) |tr| {
                    w *= tr;
                } else {
                    return null;
                }
            }

            if (!hit) {
                break;
            }

            if (isec.sameHemisphere(tray.ray.direction)) {
                _ = self.super.interface_stack.remove(isec);
            } else {
                self.super.interface_stack.push(isec);
            }

            tray.ray.setMinT(ro.offsetF(tray.ray.maxT()));
            tray.ray.setMaxT(ray_max_t);

            if (tray.ray.minT() > tray.ray.maxT()) {
                break;
            }
        }

        self.super.interface_stack.swap(&self.super.interface_stack_temp);

        return w;
    }

    fn subsurfaceVisibility(
        self: *Worker,
        ray: *Ray,
        wo: Vec4f,
        isec: Intersection,
        filter: ?Filter,
    ) ?Vec4f {
        const material = isec.material(self.super);

        if (isec.subsurface and material.ior() > 1.0) {
            const ray_max_t = ray.ray.maxT();

            var nisec: Intersection = .{};
            if (self.super.intersectShadow(ray, &nisec)) {
                if (self.volume_integrator.transmittance(ray.*, filter, &self.super)) |tr| {
                    ray.ray.setMinT(ro.offsetF(ray.ray.maxT()));
                    ray.ray.setMaxT(ray_max_t);

                    if (self.super.scene.visibility(ray.*, filter, &self.super)) |tv| {
                        const wi = ray.ray.direction;
                        const vbh = material.super().border(wi, nisec.geo.n);
                        const nsc = mat.nonSymmetryCompensation(wi, wo, nisec.geo.geo_n, nisec.geo.n);

                        return @splat(4, vbh * nsc) * tv * tr;
                    }
                }

                return null;
            }
        }

        return self.super.visibility(ray.*, filter);
    }
};
