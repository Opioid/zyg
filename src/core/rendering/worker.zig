const View = @import("../take/take.zig").View;
const Scene = @import("../scene/scene.zig").Scene;
const Ray = @import("../scene/ray.zig").Ray;
const Intersection = @import("../scene/prop/intersection.zig").Intersection;
const Sampler = @import("../sampler/sampler.zig").Sampler;
const Scene_worker = @import("../scene/worker.zig").Worker;

const srfc = @import("integrator/surface/integrator.zig");

usingnamespace @import("base");
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;

pub const Worker = struct {
    worker: Scene_worker,

    sampler: Sampler,

    surface: srfc.Integrator,

    pub fn configure(self: *Worker, view: *View, scene: *Scene) void {
        self.worker.configure(view, scene);
    }

    pub fn render(self: *Worker) void {
        var camera = &self.worker.view.camera;

        const scene = self.worker.scene;

        self.worker.rng.start(0, 0);

        const dim = camera.resolution;

        self.worker.rng.start(0, 0);

        var y: i32 = 0;
        while (y < dim.v[1]) : (y += 1) {
            var x: i32 = 0;
            while (x < dim.v[0]) : (x += 1) {
                const num_samples = 16;

                var s: u32 = 0;
                while (s < num_samples) : (s += 1) {
                    const sample = self.sampler.sample(&self.worker.rng, Vec2i.init2(x, y));

                    if (camera.generateRay(sample, scene.*)) |*ray| {
                        const color = self.li(ray);
                        camera.sensor.addSample(sample, color, Vec2i.init1(0));
                    } else {
                        camera.sensor.addSample(sample, Vec4f.init1(0.0), Vec2i.init1(0));
                    }
                }
            }
        }
    }

    pub fn li(self: *Worker, ray: *Ray) Vec4f {
        var isec = Intersection{};

        if (self.worker.intersect(ray, &isec)) {
            return self.surface.li(ray, &isec, self);
        }

        return Vec4f.init1(0.0);
    }
};
