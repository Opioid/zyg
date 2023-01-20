const Ray = @import("ray.zig").Ray;
const Scene = @import("scene.zig").Scene;
const Intersection = @import("prop/intersection.zig").Intersection;
const InterfaceStack = @import("prop/interface.zig").Stack;
const IoR = @import("material/sample_base.zig").IoR;

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
        self.path_count = 1;
        self.bxdf_pdf = 0.0;
        self.state = .{};
    }

    pub fn iorOutside(self: *const Vertex, wo: Vec4f, isec: Intersection, scene: *const Scene) f32 {
        if (isec.sameHemisphere(wo)) {
            return self.interface_stack.topIor(scene);
        }

        return self.interface_stack.peekIor(isec, scene);
    }

    pub fn interfaceChange(self: *Vertex, dir: Vec4f, isec: Intersection, scene: *const Scene) void {
        const leave = isec.sameHemisphere(dir);
        if (leave) {
            _ = self.interface_stack.remove(isec);
        } else if (self.interface_stack.straight(scene) or isec.material(scene).ior() > 1.0) {
            self.interface_stack.push(isec);
        }
    }

    pub fn interfaceChangeIor(self: *Vertex, dir: Vec4f, isec: Intersection, scene: *const Scene) IoR {
        const inter_ior = isec.material(scene).ior();

        const leave = isec.sameHemisphere(dir);
        if (leave) {
            const ior = IoR{ .eta_t = self.interface_stack.peekIor(isec, scene), .eta_i = inter_ior };
            _ = self.interface_stack.remove(isec);
            return ior;
        }

        const ior = IoR{ .eta_t = inter_ior, .eta_i = self.interface_stack.topIor(scene) };

        if (self.interface_stack.straight(scene) or inter_ior > 1.0) {
            self.interface_stack.push(isec);
        }

        return ior;
    }
};

pub const Pool = struct {
    const Num_vertices = 2;

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
