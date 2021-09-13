const cam = @import("../camera/perspective.zig");
const Scene = @import("scene.zig").Scene;
const scn = @import("constants.zig");
const ro = @import("ray_offset.zig");
const Ray = @import("ray.zig").Ray;
const NodeStack = @import("shape/node_stack.zig").NodeStack;
const Intersection = @import("prop/intersection.zig").Intersection;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;

pub const Worker = struct {
    camera: *cam.Perspective = undefined,
    scene: *Scene = undefined,

    rng: RNG,

    node_stack: NodeStack = .{},

    pub fn configure(self: *Worker, camera: *cam.Perspective, scene: *Scene) void {
        self.camera = camera;
        self.scene = scene;
    }

    pub fn intersect(self: *Worker, ray: *Ray, isec: *Intersection) bool {
        return self.scene.intersect(ray, self, isec);
    }

    pub fn visibility(self: *Worker, ray: Ray, v: *Vec4f) bool {
        return self.scene.visibility(ray, self, v);
    }

    pub fn intersectAndResolveMask(self: *Worker, ray: *Ray, isec: *Intersection) bool {
        if (!self.intersect(ray, isec)) {
            return false;
        }

        return self.resolveMask(ray, isec);
    }

    fn resolveMask(self: *Worker, ray: *Ray, isec: *Intersection) bool {
        const start_min_t = ray.ray.minT();

        var o = isec.opacity(self.*);

        while (o < 1.0) // : (o = isec.opacity(self.*))
        {
            if (o > 0.0 and o > self.rng.randomFloat()) {
                ray.ray.setMinT(start_min_t);
                return true;
            }

            // Slide along ray until opaque surface is found
            ray.ray.setMinT(ro.offsetF(ray.ray.maxT()));
            ray.ray.setMaxT(scn.Ray_max_t);
            if (!self.intersect(ray, isec)) {
                ray.ray.setMinT(start_min_t);
                return false;
            }

            o = isec.opacity(self.*);
        }

        ray.ray.setMinT(start_min_t);
        return true;
    }
};
