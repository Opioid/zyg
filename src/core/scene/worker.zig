const cam = @import("../camera/perspective.zig");
const Scene = @import("scene.zig").Scene;
const Ray = @import("ray.zig").Ray;
const Intersection = @import("prop/intersection.zig").Intersection;

const base = @import("base");
const RNG = base.rnd.Generator;

pub const Worker = struct {
    camera: *cam.Perspective = undefined,
    scene: *Scene = undefined,

    rng: RNG,

    pub fn configure(self: *Worker, camera: *cam.Perspective, scene: *Scene) void {
        self.camera = camera;
        self.scene = scene;
    }

    pub fn intersect(self: Worker, ray: *Ray, isec: *Intersection) bool {
        return self.scene.intersect(ray, isec);
    }

    pub fn intersectP(self: Worker, ray: *const Ray) bool {
        return self.scene.intersectP(ray);
    }
};
