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
    pub const Intersector = struct {
        ray: Ray,

        depth: u32,
        wavelength: f32,
        time: u64,

        hit: Intersection,

        pub fn init(ray: Ray, time: u64) Intersector {
            return .{
                .ray = ray,
                .depth = 0,
                .wavelength = 0.0,
                .time = time,
                .hit = undefined,
            };
        }

        pub fn initFrom(ray: Ray, isec: *const Intersector) Intersector {
            return .{
                .ray = ray,
                .depth = isec.depth,
                .wavelength = isec.wavelength,
                .time = isec.time,
                .hit = isec.hit,
            };
        }

        pub fn evaluateRadiance(self: *const Intersector, wo: Vec4f, sampler: *Sampler, scene: *const Scene) ?Vec4f {
            const m = self.hit.material(scene);

            const volume = self.hit.event;

            if (.Absorb == volume) {
                return self.hit.vol_li;
            }

            if (!m.emissive() or (!m.twoSided() and !self.hit.sameHemisphere(wo)) or .Scatter == volume) {
                return null;
            }

            return m.evaluateRadiance(
                self.ray.origin,
                wo,
                self.hit.geo_n,
                self.hit.uvw,
                self.hit.trafo,
                self.hit.prop,
                self.hit.part,
                sampler,
                scene,
            );
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

    isec: Intersector,

    state: State,
    bxdf_pdf: f32,
    split_weight: f32,
    path_count: u32,

    throughput: Vec4f,
    throughput_old: Vec4f,
    geo_n: Vec4f,

    interfaces: InterfaceStack,

    const Self = @This();

    pub fn init(ray: Ray, time: u64, interfaces: *const InterfaceStack) Vertex {
        var tmp: InterfaceStack = .{};
        tmp.copy(interfaces);

        return .{
            .isec = .{
                .ray = ray,
                .depth = 0,
                .wavelength = 0.0,
                .time = time,
                .hit = undefined,
            },
            .state = .{},
            .bxdf_pdf = 0.0,
            .split_weight = 1.0,
            .path_count = 1,
            .throughput = @splat(1.0),
            .throughput_old = @splat(1.0),
            .geo_n = @splat(0.0),
            .interfaces = tmp,
        };
    }

    inline fn iorOutside(self: *const Self, wo: Vec4f, scene: *const Scene) f32 {
        if (self.isec.hit.sameHemisphere(wo)) {
            return self.interfaces.topIor(scene);
        }

        return self.interfaces.peekIor(self.isec.hit, scene);
    }

    pub fn interfaceChange(self: *Self, dir: Vec4f, sampler: *Sampler, scene: *const Scene) void {
        const leave = self.isec.hit.sameHemisphere(dir);
        if (leave) {
            _ = self.interfaces.remove(self.isec.hit);
        } else {
            const material = self.isec.hit.material(scene);
            const cc = material.collisionCoefficients2D(self.isec.hit.uv(), sampler, scene);
            self.interfaces.push(self.isec.hit, cc);
        }
    }

    pub fn interfaceChangeIor(self: *Self, dir: Vec4f, sampler: *Sampler, scene: *const Scene) IoR {
        const inter_ior = self.isec.hit.material(scene).ior();

        const leave = self.isec.hit.sameHemisphere(dir);
        if (leave) {
            const ior = IoR{ .eta_t = self.interfaces.peekIor(self.isec.hit, scene), .eta_i = inter_ior };
            _ = self.interfaces.remove(self.isec.hit);
            return ior;
        }

        const ior = IoR{ .eta_t = inter_ior, .eta_i = self.interfaces.topIor(scene) };

        const cc = self.isec.hit.material(scene).collisionCoefficients2D(self.isec.hit.uv(), sampler, scene);
        self.interfaces.push(self.isec.hit, cc);

        return ior;
    }

    pub fn sample(self: *const Self, sampler: *Sampler, caustics: CausticsResolve, worker: *const Worker) mat.Sample {
        const wo = -self.isec.ray.direction;

        const m = self.isec.hit.material(worker.scene);
        const p = self.isec.hit.p;
        const b = self.isec.hit.b;

        var rs: Renderstate = undefined;
        rs.trafo = self.isec.hit.trafo;
        rs.p = .{ p[0], p[1], p[2], self.iorOutside(wo, worker.scene) };
        rs.t = self.isec.hit.t;
        rs.b = .{ b[0], b[1], b[2], self.isec.wavelength };

        if (m.twoSided() and !self.isec.hit.sameHemisphere(wo)) {
            rs.geo_n = -self.isec.hit.geo_n;
            rs.n = -self.isec.hit.n;
        } else {
            rs.geo_n = self.isec.hit.geo_n;
            rs.n = self.isec.hit.n;
        }

        rs.ray_p = self.isec.ray.origin;

        rs.uv = self.isec.hit.uv();
        rs.prop = self.isec.hit.prop;
        rs.part = self.isec.hit.part;
        rs.primitive = self.isec.hit.primitive;
        rs.depth = self.isec.depth;
        rs.time = self.isec.time;
        rs.subsurface = self.isec.hit.subsurface();
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
    next_id: u32 = undefined,
    next_end: u32 = undefined,

    alpha: f32 = undefined,

    pub fn start(self: *Pool, vertex: Vertex) void {
        self.buffer[0] = vertex;
        self.current_id = Num_vertices;
        self.current_start = Num_vertices;
        self.current_end = Num_vertices;
        self.next_id = 0;
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

        const current_id = self.next_id;
        const current_end = self.next_end;

        self.current_id = current_id;
        self.current_start = current_id;
        self.current_end = current_end;

        const next_id: u32 = if (Num_vertices == self.next_id) 0 else Num_vertices;
        self.next_id = next_id;
        self.next_end = next_id;

        return current_id < current_end;
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
