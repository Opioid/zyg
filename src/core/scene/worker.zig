const View = @import("../take/take.zig").View;
const Scene = @import("scene.zig").Scene;
const Ray = @import("ray.zig").Ray;
const Intersection = @import("prop/intersection.zig").Intersection;

const base = @import("base");
const RNG = base.rnd.Generator;

pub const Worker = struct {
    view: *View = undefined,
    scene: *Scene = undefined,

    rng: RNG,

    pub fn configure(self: *Worker, view: *View, scene: *Scene) void {
        self.view = view;
        self.scene = scene;
    }

    pub fn intersect(self: Worker, ray: *Ray, isec: *Intersection) bool {
        return self.scene.intersect(ray, isec);
    }
};
