const Intersection = @import("shape/intersection.zig").Intersection;
const Scene = @import("scene.zig").Scene;
const InterfaceStack = @import("prop/interface.zig").Stack;
const Sampler = @import("../sampler/sampler.zig").Sampler;
const rst = @import("renderstate.zig");
const Renderstate = rst.Renderstate;
const CausticsResolve = rst.CausticsResolve;
const Worker = @import("../rendering/worker.zig").Worker;
const mat = @import("material/material.zig");
const IoR = @import("material/sample_base.zig").IoR;

const math = @import("base").math;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

pub const Vertex = struct {
    pub const Probe = struct {
        ray: Ray,

        depth: u32,
        wavelength: f32,
        time: u64,

        pub fn init(ray: Ray, time: u64) Probe {
            return .{
                .ray = ray,
                .depth = 0,
                .wavelength = 0.0,
                .time = time,
            };
        }

        pub fn clone(self: *const Probe, ray: Ray) Probe {
            return .{
                .ray = ray,
                .depth = self.depth,
                .wavelength = self.wavelength,
                .time = self.time,
            };
        }
    };

    pub const State = packed struct {
        primary_ray: bool = true,
        direct: bool = true,
        transparent: bool = true,
        treat_as_singular: bool = true,
        is_translucent: bool = false,
        from_subsurface: bool = false,
        started_specular: bool = false,
    };

    probe: Probe,

    state: State,
    bxdf_pdf: f32,
    split_weight: f32,
    path_count: u32,

    throughput: Vec4f,
    throughput_old: Vec4f,
    origin: Vec4f,
    geo_n: Vec4f,

    interfaces: InterfaceStack,

    const Self = @This();

    pub fn init(ray: Ray, time: u64, interfaces: *const InterfaceStack) Vertex {
        return .{
            .probe = .{
                .ray = ray,
                .depth = 0,
                .wavelength = 0.0,
                .time = time,
            },
            .state = .{},
            .bxdf_pdf = 0.0,
            .split_weight = 1.0,
            .path_count = 1,
            .throughput = @splat(1.0),
            .throughput_old = @splat(1.0),
            .origin = ray.origin,
            .geo_n = @splat(0.0),
            .interfaces = interfaces.clone(),
        };
    }

    inline fn iorOutside(self: *const Self, isec: *const Intersection, wo: Vec4f, scene: *const Scene) f32 {
        if (isec.sameHemisphere(wo)) {
            return self.interfaces.topIor(scene);
        }

        return self.interfaces.peekIor(isec, scene);
    }

    pub fn interfaceChange(self: *Self, isec: *const Intersection, dir: Vec4f, sampler: *Sampler, scene: *const Scene) void {
        const leave = isec.sameHemisphere(dir);
        if (leave) {
            self.interfaces.remove(isec);
        } else {
            const cc = isec.material(scene).collisionCoefficients2D(isec.uv(), sampler, scene);
            self.interfaces.push(isec, cc);
        }
    }

    pub fn interfaceChangeIor(self: *Self, isec: *const Intersection, dir: Vec4f, sampler: *Sampler, scene: *const Scene) IoR {
        const inter_ior = isec.material(scene).ior();

        const leave = isec.sameHemisphere(dir);
        if (leave) {
            const ior = IoR{ .eta_t = self.interfaces.peekIor(isec, scene), .eta_i = inter_ior };
            self.interfaces.remove(isec);
            return ior;
        }

        const ior = IoR{ .eta_t = inter_ior, .eta_i = self.interfaces.topIor(scene) };

        const cc = isec.material(scene).collisionCoefficients2D(isec.uv(), sampler, scene);
        self.interfaces.push(isec, cc);

        return ior;
    }

    pub fn sample(
        self: *const Self,
        isec: *const Intersection,
        sampler: *Sampler,
        caustics: CausticsResolve,
        worker: *const Worker,
    ) mat.Sample {
        const wo = -self.probe.ray.direction;

        const m = isec.material(worker.scene);

        var rs: Renderstate = undefined;
        rs.trafo = isec.trafo;
        rs.p = isec.p;
        rs.t = isec.t;
        rs.b = isec.b;

        if (m.twoSided() and !isec.sameHemisphere(wo)) {
            rs.geo_n = -isec.geo_n;
            rs.n = -isec.n;
        } else {
            rs.geo_n = isec.geo_n;
            rs.n = isec.n;
        }

        rs.origin = self.origin;
        rs.uv = isec.uv();
        rs.ior = self.iorOutside(isec, wo, worker.scene);
        rs.wavelength = self.probe.wavelength;
        rs.time = self.probe.time;
        rs.prop = isec.prop;
        rs.part = isec.part;
        rs.primitive = isec.primitive;
        rs.depth = self.probe.depth;
        rs.subsurface = isec.subsurface();
        rs.caustics = caustics;

        return m.sample(wo, rs, sampler, worker);
    }
};

pub const Pool = struct {
    const Num_vertices = 4;

    buffer: [2 * Num_vertices]Vertex = undefined,
    terminated: u32 = undefined,

    current_id: u32 = undefined,
    current_start: u32 = undefined,
    current_end: u32 = undefined,
    next_start: u32 = undefined,
    next_end: u32 = undefined,

    alpha: f32 = undefined,

    pub fn start(self: *Pool, vertex: Vertex) void {
        self.buffer[0] = vertex;
        self.current_id = Num_vertices;
        self.current_start = Num_vertices;
        self.current_end = Num_vertices;
        self.next_start = 0;
        self.next_end = 1;
        self.alpha = 0.0;
    }

    pub fn iterate(self: *Pool) bool {
        const old_end = self.current_end;
        var i = self.current_start;
        while (i < old_end) : (i += 1) {
            const mask = @as(u32, 1) << @as(u5, @truncate(i));
            if (0 != (self.terminated & mask)) {
                const v = &self.buffer[i];
                if (v.state.transparent) {
                    self.alpha += math.max((1.0 - math.average3(v.throughput)) * v.split_weight, 0.0);
                } else {
                    self.alpha += v.split_weight;
                }
            }
        }

        const current_start = self.next_start;
        const current_end = self.next_end;

        self.current_id = current_start;
        self.current_start = current_start;
        self.current_end = current_end;

        const next_start: u32 = if (Num_vertices == current_start) 0 else Num_vertices;
        self.next_start = next_start;
        self.next_end = next_start;

        return current_start < current_end;
    }

    pub fn consume(self: *Pool) ?*Vertex {
        const id = self.current_id;
        self.current_id += 1;

        if (id < self.current_end) {
            const mask = @as(u32, 1) << @as(u5, @truncate(id));
            self.terminated |= mask;

            return &self.buffer[id];
        }

        return null;
    }

    pub fn new(self: *Pool) *Vertex {
        const mask = @as(u32, 1) << @as(u5, @truncate(self.current_id - 1));
        self.terminated &= ~mask;

        const end = self.next_end;
        self.next_end += 1;

        return &self.buffer[end];
    }
};

pub const RayDif = struct {
    x_origin: Vec4f,
    x_direction: Vec4f,
    y_origin: Vec4f,
    y_direction: Vec4f,
};
