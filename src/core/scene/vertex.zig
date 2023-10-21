const Intersection = @import("shape/intersection.zig").Intersection;
const Sampler = @import("../sampler/sampler.zig").Sampler;
const rst = @import("renderstate.zig");
const Renderstate = rst.Renderstate;
const CausticsResolve = rst.CausticsResolve;
const Scene = @import("scene.zig").Scene;
const Worker = @import("../rendering/worker.zig").Worker;
const mat = @import("material/material.zig");

const math = @import("base").math;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

pub const Vertex = struct {
    pub const State = packed struct {
        primary_ray: bool = true,
        direct: bool = true,
        transparent: bool = true,
        treat_as_singular: bool = true,
        is_translucent: bool = false,
        from_subsurface: bool = false,
        started_specular: bool = false,
    };

    ray: Ray,

    depth: u32,
    wavelength: f32,
    time: u64,
    state: State,

    isec: Intersection,

    const Self = @This();

    pub fn init(
        origin: Vec4f,
        direction: Vec4f,
        min_t: f32,
        max_t: f32,
        depth: u32,
        wavelength: f32,
        time: u64,
        isec: Intersection,
    ) Vertex {
        return .{
            .ray = Ray.init(origin, direction, min_t, max_t),
            .depth = depth,
            .wavelength = wavelength,
            .time = time,
            .state = .{},
            .isec = isec,
        };
    }

    pub fn initRay(ray: Ray, vertex: *const Self) Vertex {
        return .{
            .ray = ray,
            .depth = vertex.depth,
            .wavelength = 0.0,
            .time = vertex.time,
            .state = .{},
            .isec = vertex.isec,
        };
    }

    pub fn sample(self: *const Self, sampler: *Sampler, caustics: CausticsResolve, worker: *const Worker) mat.Sample {
        const wo = -self.ray.direction;

        const m = self.isec.material(worker.scene);
        const p = self.isec.p;
        const b = self.isec.b;

        var rs: Renderstate = undefined;
        rs.trafo = self.isec.trafo;
        rs.p = .{ p[0], p[1], p[2], worker.iorOutside(wo, self.isec) };
        rs.t = self.isec.t;
        rs.b = .{ b[0], b[1], b[2], self.wavelength };

        if (m.twoSided() and !self.isec.sameHemisphere(wo)) {
            rs.geo_n = -self.isec.geo_n;
            rs.n = -self.isec.n;
        } else {
            rs.geo_n = self.isec.geo_n;
            rs.n = self.isec.n;
        }

        rs.ray_p = self.ray.origin;

        rs.uv = self.isec.uv();
        rs.prop = self.isec.prop;
        rs.part = self.isec.part;
        rs.primitive = self.isec.primitive;
        rs.depth = self.depth;
        rs.time = self.time;
        rs.subsurface = self.isec.subsurface();
        rs.caustics = caustics;

        return m.sample(wo, rs, sampler, worker);
    }

    pub fn evaluateRadiance(
        self: *const Self,
        wo: Vec4f,
        sampler: *Sampler,
        scene: *const Scene,
        pure_emissive: *bool,
    ) ?Vec4f {
        const m = self.isec.material(scene);

        const volume = self.isec.event;

        pure_emissive.* = m.pureEmissive() or .Absorb == volume;

        if (.Absorb == volume) {
            return self.isec.vol_li;
        }

        if (!m.emissive() or (!m.twoSided() and !self.isec.sameHemisphere(wo)) or .Scatter == volume) {
            return null;
        }

        return m.evaluateRadiance(
            self.ray.origin,
            wo,
            self.isec.geo_n,
            self.isec.uvw,
            self.isec.trafo,
            self.isec.prop,
            self.isec.part,
            sampler,
            scene,
        );
    }
};

pub const RayDif = struct {
    x_origin: Vec4f,
    x_direction: Vec4f,
    y_origin: Vec4f,
    y_direction: Vec4f,
};
