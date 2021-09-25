const cam = @import("../camera/perspective.zig");
const Scene = @import("scene.zig").Scene;
const scn = @import("constants.zig");
const ro = @import("ray_offset.zig");
const Ray = @import("ray.zig").Ray;
const NodeStack = @import("shape/node_stack.zig").NodeStack;
const Intersection = @import("prop/intersection.zig").Intersection;
const Filter = @import("../image/texture/sampler.zig").Filter;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const Distribution1D = math.Distribution1D;
const RNG = base.rnd.Generator;

pub const Worker = struct {
    pub const Lights = [4]Distribution1D.Discrete;

    camera: *cam.Perspective = undefined,
    scene: *Scene = undefined,

    rng: RNG,

    node_stack: NodeStack = .{},

    lights: Lights,

    pub fn configure(self: *Worker, camera: *cam.Perspective, scene: *Scene) void {
        self.camera = camera;
        self.scene = scene;
    }

    pub fn intersect(self: *Worker, ray: *Ray, isec: *Intersection) bool {
        return self.scene.intersect(ray, self, isec);
    }

    pub fn visibility(self: *Worker, ray: Ray, filter: ?Filter) ?Vec4f {
        return self.scene.visibility(ray, filter, self);
    }

    pub fn intersectAndResolveMask(self: *Worker, ray: *Ray, filter: ?Filter, isec: *Intersection) bool {
        if (!self.intersect(ray, isec)) {
            return false;
        }

        return self.resolveMask(ray, filter, isec);
    }

    fn resolveMask(self: *Worker, ray: *Ray, filter: ?Filter, isec: *Intersection) bool {
        const start_min_t = ray.ray.minT();

        var o = isec.opacity(filter, self.*);

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

            o = isec.opacity(filter, self.*);
        }

        ray.ray.setMinT(start_min_t);
        return true;
    }
};
