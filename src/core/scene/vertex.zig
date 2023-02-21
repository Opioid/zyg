const Ray = @import("ray.zig").Ray;
const Scene = @import("scene.zig").Scene;
const Renderstate = @import("renderstate.zig").Renderstate;
const ro = @import("ray_offset.zig");
const Intersection = @import("prop/intersection.zig").Intersection;
const InterfaceStack = @import("prop/interface.zig").Stack;
const IoR = @import("material/sample_base.zig").IoR;
const mat = @import("material/material.zig");
const Filter = @import("../image/texture/texture_sampler.zig").Filter;
const Worker = @import("../rendering/worker.zig").Worker;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

pub const Vertex = struct {
    const PathState = packed struct {
        primary_ray: bool = true,
        treat_as_singular: bool = true,
        is_translucent: bool = false,
        split_photon: bool = false,
        direct: bool = true,
        from_subsurface: bool = false,
    };

    ray: Ray,

    isec: Intersection,

    interface_stack: InterfaceStack,

    throughput: Vec4f,
    geo_n: Vec4f,
    wo1: Vec4f,
    volume_entry: Vec4f,

    path_count: u32,
    bxdf_pdf: f32,

    state: PathState,

    pub fn start(self: *Vertex, ray: Ray, isec: Intersection, stack: *const InterfaceStack) void {
        self.ray = ray;
        self.isec = isec;
        self.interface_stack.copy(stack);
        self.throughput = @splat(4, @as(f32, 1.0));
        self.geo_n = @splat(4, @as(f32, 0.0));
        self.wo1 = @splat(4, @as(f32, 0.0));
        self.volume_entry = @splat(4, @as(f32, 0.0));
        self.path_count = 1;
        self.bxdf_pdf = 0.0;
        self.state = .{};
    }

    pub fn iorOutside(self: *const Vertex, wo: Vec4f, scene: *const Scene) f32 {
        if (self.isec.sameHemisphere(wo)) {
            return self.interface_stack.topIor(scene);
        }

        return self.interface_stack.peekIor(self.isec, scene);
    }

    pub fn interfaceChange(self: *Vertex, dir: Vec4f, scene: *const Scene) void {
        const leave = self.isec.sameHemisphere(dir);
        if (leave) {
            _ = self.interface_stack.remove(self.isec);
        } else if (self.interface_stack.straight(scene) or self.isec.material(scene).ior() > 1.0) {
            self.volume_entry = self.isec.geo.p;
            self.interface_stack.push(self.isec);
        }
    }

    pub fn interfaceChangeIor(self: *Vertex, dir: Vec4f, scene: *const Scene) IoR {
        const inter_ior = self.isec.material(scene).ior();

        const leave = self.isec.sameHemisphere(dir);
        if (leave) {
            const ior = IoR{ .eta_t = self.interface_stack.peekIor(self.isec, scene), .eta_i = inter_ior };
            _ = self.interface_stack.remove(self.isec);
            return ior;
        }

        const ior = IoR{ .eta_t = inter_ior, .eta_i = self.interface_stack.topIor(scene) };

        if (self.interface_stack.straight(scene) or inter_ior > 1.0) {
            self.interface_stack.push(self.isec);
        }

        return ior;
    }

    pub fn correctVolumeInterfaceStack(self: *Vertex, scene: *const Scene) void {
        var isec: Intersection = undefined;

        const axis = self.isec.geo.p - self.volume_entry;
        const ray_max_t = math.length3(axis);

        var ray = Ray.init(self.volume_entry, axis / @splat(4, ray_max_t), 0.0, ray_max_t, 0, 0.0, self.ray.time);

        while (true) {
            const hit = scene.intersectVolume(&ray, &isec);

            if (!hit) {
                break;
            }

            if (isec.sameHemisphere(ray.ray.direction)) {
                _ = self.interface_stack.remove(isec);
            } else {
                self.interface_stack.push(isec);
            }

            const ray_min_t = ro.offsetF(ray.ray.maxT());
            if (ray_min_t > ray_max_t) {
                break;
            }

            ray.ray.setMinMaxT(ray_min_t, ray_max_t);
        }
    }

    pub fn sample(self: *const Vertex, wo: Vec4f, filter: ?Filter, avoid_caustics: bool, worker: *const Worker) mat.Sample {
        const m = self.isec.material(worker.scene);
        const p = self.isec.geo.p;
        const b = self.isec.geo.b;

        var rs: Renderstate = undefined;
        rs.trafo = self.isec.geo.trafo;
        rs.p = .{ p[0], p[1], p[2], self.iorOutside(wo, worker.scene) };
        rs.t = self.isec.geo.t;
        rs.b = .{ b[0], b[1], b[2], self.ray.wavelength };

        if (m.twoSided() and !self.isec.sameHemisphere(wo)) {
            rs.geo_n = -self.isec.geo.geo_n;
            rs.n = -self.isec.geo.n;
        } else {
            rs.geo_n = self.isec.geo.geo_n;
            rs.n = self.isec.geo.n;
        }

        rs.ray_p = self.ray.ray.origin;
        rs.uv = self.isec.geo.uv;
        rs.prop = self.isec.prop;
        rs.part = self.isec.geo.part;
        rs.primitive = self.isec.geo.primitive;
        rs.depth = self.ray.depth;
        rs.time = self.ray.time;
        rs.filter = filter;
        rs.subsurface = self.isec.subsurface;
        rs.avoid_caustics = avoid_caustics;

        return m.sample(wo, rs, worker);
    }
};

pub const Pool = struct {
    const Num_vertices = 4;

    buffer: [2 * Num_vertices]Vertex,

    current_id: u32 = undefined,
    current_end: u32 = undefined,
    next_id: u32 = undefined,
    next_end: u32 = undefined,

    pub fn empty(self: Pool) bool {
        return self.current_id == self.current_end;
    }

    pub fn start(self: *Pool, ray: Ray, isec: Intersection, stack: *const InterfaceStack) void {
        self.buffer[0].start(ray, isec, stack);
        self.current_id = 0;
        self.current_end = 1;
        self.next_id = Num_vertices;
        self.next_end = Num_vertices;
    }

    pub fn consume(self: *Pool) []Vertex {
        const id = self.current_id;
        const end = self.current_end;
        self.current_id = end;
        return self.buffer[id..end];
    }

    pub fn push(self: *Pool, vertex: Vertex) void {
        self.buffer[self.next_end] = vertex;
        self.next_end += 1;
    }

    pub fn cycle(self: *Pool) void {
        self.current_id = self.next_id;
        self.current_end = self.next_end;

        const next_id: u32 = if (Num_vertices == self.next_id) 0 else Num_vertices;
        self.next_id = next_id;
        self.next_end = next_id;
    }
};
