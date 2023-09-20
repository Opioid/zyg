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

        pub fn evaluateRadiance(
            self: *const Intersector,
            wo: Vec4f,
            sampler: *Sampler,
            scene: *const Scene,
            pure_emissive: *bool,
        ) ?Vec4f {
            const m = self.hit.material(scene);

            const volume = self.hit.event;

            pure_emissive.* = m.pureEmissive() or .Absorb == volume;

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
        treat_as_singular: bool = true,
        is_translucent: bool = false,
        split_photon: bool = false,
        direct: bool = true,
        from_subsurface: bool = false,
        started_specular: bool = false,
    };

    isec: Intersector,

    state: State,
    bxdf_pdf: f32,

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

    pub fn sample(
        self: *const Self,
        wo: Vec4f,
        sampler: *Sampler,
        caustics: CausticsResolve,
        worker: *const Worker,
    ) mat.Sample {
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
    const Num_vertices = 2;

    buffer: [2 * Num_vertices]Vertex = undefined,

    current_id: u32 = undefined,
    current_end: u32 = undefined,
    next_id: u32 = undefined,
    next_end: u32 = undefined,

    pub fn empty(self: Pool) bool {
        return self.current_id == self.current_end;
    }

    pub fn start(self: *Pool, vertex: Vertex) void {
        self.buffer[0] = vertex;
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

pub const RayDif = struct {
    x_origin: Vec4f,
    x_direction: Vec4f,
    y_origin: Vec4f,
    y_direction: Vec4f,
};
