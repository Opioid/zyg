const cam = @import("../camera/perspective.zig");
const Scene = @import("scene.zig").Scene;
const scn = @import("constants.zig");
const ro = @import("ray_offset.zig");
const Ray = @import("ray.zig").Ray;
const MaterialSample = @import("material/sample.zig").Sample;
const NullSample = @import("material/null/sample.zig").Sample;
const mat = @import("material/material_helper.zig");
const InterfaceStack = @import("prop/interface.zig").Stack;
const NodeStack = @import("shape/node_stack.zig").NodeStack;
const Intersection = @import("prop/intersection.zig").Intersection;
const Interpolation = @import("shape/intersection.zig").Interpolation;
const Filter = @import("../image/texture/sampler.zig").Filter;
const Sampler = @import("../sampler/sampler.zig").Sampler;
const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const Distribution1D = math.Distribution1D;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Worker = struct {
    pub const Lights = [4]Distribution1D.Discrete;

    camera: *cam.Perspective = undefined,
    scene: *Scene = undefined,

    rng: RNG = undefined,

    interface_stack: InterfaceStack,
    interface_stack_temp: InterfaceStack,

    node_stack: NodeStack = undefined,

    lights: Lights = undefined,

    pub fn init(alloc: *Allocator) !Worker {
        return Worker{
            .interface_stack = try InterfaceStack.init(alloc),
            .interface_stack_temp = try InterfaceStack.init(alloc),
        };
    }

    pub fn deinit(self: *Worker, alloc: *Allocator) void {
        self.interface_stack_temp.deinit(alloc);
        self.interface_stack.deinit(alloc);
    }

    pub fn configure(self: *Worker, camera: *cam.Perspective, scene: *Scene) void {
        self.camera = camera;
        self.scene = scene;
    }

    pub fn intersect(self: *Worker, ray: *Ray, ipo: Interpolation, isec: *Intersection) bool {
        return self.scene.intersect(ray, self, ipo, isec);
    }

    pub fn visibility(self: *Worker, ray: Ray, filter: ?Filter) ?Vec4f {
        return self.scene.visibility(ray, filter, self);
    }

    pub fn intersectAndResolveMask(self: *Worker, ray: *Ray, filter: ?Filter, isec: *Intersection) bool {
        if (!self.intersect(ray, .All, isec)) {
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
            if (!self.intersect(ray, .All, isec)) {
                ray.ray.setMinT(start_min_t);
                return false;
            }

            o = isec.opacity(filter, self.*);
        }

        ray.ray.setMinT(start_min_t);
        return true;
    }

    pub fn resetInterfaceStack(self: *Worker, stack: InterfaceStack) void {
        stack.copy(&self.interface_stack);
    }

    pub fn iorOutside(self: Worker, wo: Vec4f, isec: Intersection) f32 {
        if (isec.sameHemisphere(wo)) {
            return self.interface_stack.topIor(self);
        }

        return self.interface_stack.peekIor(isec, self);
    }

    pub fn interfaceChange(self: *Worker, dir: Vec4f, isec: Intersection) void {
        const leave = isec.sameHemisphere(dir);
        if (leave) {
            _ = self.interface_stack.remove(isec);
        } else if (self.interface_stack.straight(self.*) or isec.material(self.*).ior() > 1.0) {
            self.interface_stack.push(isec);
        }
    }

    pub fn sampleMaterial(
        self: *Worker,
        ray: Ray,
        wo: Vec4f,
        wo1: Vec4f,
        isec: Intersection,
        filter: ?Filter,
        alpha: f32,
        avoid_caustics: bool,
        straight_border: bool,
    ) MaterialSample {
        const material = isec.material(self.*);

        const wi = ray.ray.direction;

        if (!isec.subsurface and straight_border and material.ior() > 1.0 and isec.sameHemisphere(wi)) {
            const geo_n = isec.geo.geo_n;
            const n = isec.geo.n;

            const vbh = material.super().border(wi, n);
            const nsc = mat.nonSymmetryCompensation(wi, wo1, geo_n, n);
            const factor = nsc * vbh;

            return .{ .Null = NullSample.initFactor(wo, geo_n, n, alpha, factor) };
        }

        _ = alpha;
        return isec.sample(wo, ray, filter, avoid_caustics, self);
    }
};
