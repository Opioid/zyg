const cam = @import("../camera/perspective.zig");
const Scene = @import("../scene/scene.zig").Scene;
const Ray = @import("../scene/ray.zig").Ray;
const Intersection = @import("../scene/prop/intersection.zig").Intersection;
const smpl = @import("../sampler/sampler.zig");
const Sampler = smpl.Sampler;
const Scene_worker = @import("../scene/worker.zig").Worker;

const surface = @import("integrator/surface/integrator.zig");

usingnamespace @import("base");
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const Allocator = @import("std").mem.Allocator;

pub const Worker = struct {
    worker: Scene_worker,

    sampler: Sampler,

    surface_integrator: surface.Integrator,

    pub fn deinit(self: *Worker, alloc: *Allocator) void {
        self.surface_integrator.deinit(alloc);
        self.sampler.deinit(alloc);
    }

    pub fn configure(
        self: *Worker,
        alloc: *Allocator,
        camera: *cam.Perspective,
        scene: *Scene,
        num_samples_per_pixel: u32,
        samplers: smpl.Factory,
        surfaces: surface.Factory,
    ) !void {
        self.worker.configure(camera, scene);

        self.sampler = try samplers.create(alloc, 1, 1, num_samples_per_pixel);

        self.surface_integrator = try surfaces.create(alloc, num_samples_per_pixel);
    }

    pub fn render(self: *Worker, tile: Vec4i, num_samples: u32) void {
        var camera = self.worker.camera;
        const sensor = &camera.sensor;
        const scene = self.worker.scene;

        const offset = Vec2i.init1(0);

        var crop = camera.crop;
        crop.v[2] -= crop.v[0] + 1;
        crop.v[3] -= crop.v[1] + 1;
        crop.v[0] += offset.v[0];
        crop.v[1] += offset.v[1];

        const view_tile = Vec4i.init2_2(offset.add(tile.xy()), offset.add(tile.zw()));

        var isolated_bounds = sensor.isolatedTile(view_tile);
        isolated_bounds.v[2] -= isolated_bounds.v[0];
        isolated_bounds.v[3] -= isolated_bounds.v[1];

        const fr = sensor.filterRadiusInt();

        const r = camera.resolution.addScalar(2 * fr);

        const o0 = 0; //uint64_t(iteration) * @intCast(u64, r.v[0] * r.v[1]);

        const y_back = tile.v[3];
        var y: i32 = tile.v[1];
        while (y <= y_back) : (y += 1) {
            const o1 = @intCast(u64, (y + fr) * r.v[0]) + o0;
            const x_back = tile.v[2];
            var x: i32 = tile.v[0];
            while (x <= x_back) : (x += 1) {
                self.worker.rng.start(0, o1 + @intCast(u64, x + fr));

                self.sampler.startPixel();
                self.surface_integrator.startPixel();

                const pixel = Vec2i.init2(x, y);

                var s: u32 = 0;
                while (s < num_samples) : (s += 1) {
                    const sample = self.sampler.sample(&self.worker.rng, pixel);

                    if (camera.generateRay(sample, scene.*)) |*ray| {
                        const color = self.li(ray);
                        sensor.addSample(sample, color, offset, isolated_bounds, crop);
                    } else {
                        sensor.addSample(sample, Vec4f.init1(0.0), offset, isolated_bounds, crop);
                    }
                }
            }
        }
    }

    fn li(self: *Worker, ray: *Ray) Vec4f {
        var isec = Intersection{};

        if (self.worker.intersect(ray, &isec)) {
            return self.surface_integrator.li(ray, &isec, self);
        }

        return Vec4f.init1(0.0);
    }
};
