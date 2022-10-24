const cam = @import("../camera/perspective.zig");
const Scene = @import("scene.zig").Scene;
const scn = @import("constants.zig");
const ro = @import("ray_offset.zig");
const sr = @import("ray.zig");
const Ray = sr.Ray;
const RayDif = sr.RayDif;
const Renderstate = @import("renderstate.zig").Renderstate;
const MaterialSample = @import("material/sample.zig").Sample;
const IoR = @import("material/sample_base.zig").IoR;
const NullSample = @import("material/null/sample.zig").Sample;
const mat = @import("material/material_helper.zig");
const InterfaceStack = @import("prop/interface.zig").Stack;
const Intersection = @import("prop/intersection.zig").Intersection;
const shp = @import("shape/intersection.zig");
const Interpolation = shp.Interpolation;
const LightTree = @import("light/tree.zig").Tree;
const Filter = @import("../image/texture/sampler.zig").Filter;
const Sampler = @import("../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2b = math.Vec2b;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Distribution1D = math.Distribution1D;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Worker = struct {
    pub const Lights = LightTree.Lights;

    camera: *cam.Perspective = undefined,
    scene: *Scene = undefined,

    rng: RNG = undefined,

    interface_stack: InterfaceStack = undefined,

    lights: Lights = undefined,

    pub fn configure(self: *Worker, camera: *cam.Perspective, scene: *Scene) void {
        self.camera = camera;
        self.scene = scene;
    }

    pub fn intersect(self: *Worker, ray: *Ray, ipo: Interpolation, isec: *Intersection) bool {
        return self.scene.intersect(ray, self, ipo, isec);
    }

    pub fn intersectProp(self: *Worker, entity: u32, ray: *Ray, ipo: Interpolation, isec: *shp.Intersection) bool {
        return self.scene.prop(entity).intersect(entity, ray, self, ipo, isec);
    }

    pub fn intersectShadow(self: *Worker, ray: *Ray, isec: *Intersection) bool {
        return self.scene.intersectShadow(ray, self, isec);
    }

    pub fn visibility(self: *Worker, ray: Ray, filter: ?Filter, sampler: *Sampler) ?Vec4f {
        return self.scene.visibility(ray, filter, sampler, self);
    }

    pub fn intersectAndResolveMask(self: *Worker, ray: *Ray, filter: ?Filter, sampler: *Sampler, isec: *Intersection) bool {
        if (!self.intersect(ray, .All, isec)) {
            return false;
        }

        return self.resolveMask(ray, filter, sampler, isec);
    }

    fn resolveMask(self: *Worker, ray: *Ray, filter: ?Filter, sampler: *Sampler, isec: *Intersection) bool {
        const start_min_t = ray.ray.minT();

        var o = isec.opacity(filter, sampler, self.scene.*);

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

            o = isec.opacity(filter, sampler, self.scene.*);
        }

        ray.ray.setMinT(start_min_t);
        return true;
    }

    pub fn resetInterfaceStack(self: *Worker, stack: InterfaceStack) void {
        self.interface_stack.copy(stack);
    }

    pub fn iorOutside(self: Worker, wo: Vec4f, isec: Intersection) f32 {
        if (isec.sameHemisphere(wo)) {
            return self.interface_stack.topIor(self.scene.*);
        }

        return self.interface_stack.peekIor(isec, self.scene.*);
    }

    pub fn interfaceChange(self: *Worker, dir: Vec4f, isec: Intersection) void {
        const leave = isec.sameHemisphere(dir);
        if (leave) {
            _ = self.interface_stack.remove(isec);
        } else if (self.interface_stack.straight(self.scene.*) or isec.material(self.scene.*).ior() > 1.0) {
            self.interface_stack.push(isec);
        }
    }

    pub fn interfaceChangeIor(self: *Worker, dir: Vec4f, isec: Intersection) IoR {
        const inter_ior = isec.material(self.scene.*).ior();

        const leave = isec.sameHemisphere(dir);
        if (leave) {
            const ior = IoR{ .eta_t = self.interface_stack.peekIor(isec, self.scene.*), .eta_i = inter_ior };
            _ = self.interface_stack.remove(isec);
            return ior;
        }

        const ior = IoR{ .eta_t = inter_ior, .eta_i = self.interface_stack.topIor(self.scene.*) };

        if (self.interface_stack.straight(self.scene.*) or inter_ior > 1.0) {
            self.interface_stack.push(isec);
        }

        return ior;
    }

    pub fn sampleMaterial(
        self: Worker,
        ray: Ray,
        wo: Vec4f,
        wo1: Vec4f,
        isec: Intersection,
        filter: ?Filter,
        sampler: *Sampler,
        alpha: f32,
        avoid_caustics: bool,
        straight_border: bool,
    ) MaterialSample {
        const material = isec.material(self.scene.*);

        const wi = ray.ray.direction;

        if (!isec.subsurface and straight_border and material.ior() > 1.0 and isec.sameHemisphere(wi)) {
            const geo_n = isec.geo.geo_n;
            const n = isec.geo.n;

            const vbh = material.super().border(wi, n);
            const nsc = mat.nonSymmetryCompensation(wo1, wi, geo_n, n);
            const factor = nsc * vbh;

            return .{ .Null = NullSample.initFactor(wo, geo_n, n, alpha, factor) };
        }

        return isec.sample(wo, ray, filter, sampler, avoid_caustics, self);
    }

    pub fn randomLightSpatial(
        self: *Worker,
        p: Vec4f,
        n: Vec4f,
        total_sphere: bool,
        random: f32,
        split: bool,
    ) []Scene.LightPick {
        return self.scene.randomLightSpatial(p, n, total_sphere, random, split, &self.lights);
    }

    pub fn absoluteTime(self: Worker, frame: u32, frame_delta: f32) u64 {
        return self.camera.absoluteTime(frame, frame_delta);
    }

    pub fn screenspaceDifferential(self: Worker, rs: Renderstate) Vec4f {
        const rd = self.camera.calculateRayDifferential(rs.p, rs.time, self.scene.*);

        const ds = self.scene.propShape(rs.prop).differentialSurface(rs.primitive);

        const dpdu_w = rs.trafo.objectToWorldVector(ds.dpdu);
        const dpdv_w = rs.trafo.objectToWorldVector(ds.dpdv);

        return calculateScreenspaceDifferential(rs.p, rs.geo_n, rd, dpdu_w, dpdv_w);
    }

    // https://blog.yiningkarlli.com/2018/10/bidirectional-mipmap.html
    fn calculateScreenspaceDifferential(p: Vec4f, n: Vec4f, rd: RayDif, dpdu: Vec4f, dpdv: Vec4f) Vec4f {
        // Compute offset-ray isec points with tangent plane
        const d = math.dot3(n, p);

        const tx = -(math.dot3(n, rd.x_origin) - d) / math.dot3(n, rd.x_direction);
        const ty = -(math.dot3(n, rd.y_origin) - d) / math.dot3(n, rd.y_direction);

        const px = rd.x_origin + @splat(4, tx) * rd.x_direction;
        const py = rd.y_origin + @splat(4, ty) * rd.y_direction;

        // Compute uv offsets at offset-ray isec points
        // Choose two dimensions to use for ray offset computations
        const dim = if (@fabs(n[0]) > @fabs(n[1]) and @fabs(n[0]) > @fabs(n[2])) Vec2b{
            1,
            2,
        } else if (@fabs(n[1]) > @fabs(n[2])) Vec2b{
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

        if (@fabs(det) < 1.0e-10) {
            return @splat(4, @as(f32, 0.0));
        }

        const dudx = (a[1][1] * bx[0] - a[0][1] * bx[1]) / det;
        const dvdx = (a[0][0] * bx[1] - a[1][0] * bx[0]) / det;

        const dudy = (a[1][1] * by[0] - a[0][1] * by[1]) / det;
        const dvdy = (a[0][0] * by[1] - a[1][0] * by[0]) / det;

        return .{ dudx, dvdx, dudy, dvdy };
    }
};
