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

        pub fn sample(
            self: *const Intersector,
            wo: Vec4f,
            sampler: *Sampler,
            caustics: CausticsResolve,
            worker: *const Worker,
        ) mat.Sample {
            const m = self.hit.material(worker.scene);
            const p = self.hit.p;
            const b = self.hit.b;

            var rs: Renderstate = undefined;
            rs.trafo = self.hit.trafo;
            rs.p = .{ p[0], p[1], p[2], worker.iorOutside(wo, self.hit) };
            rs.t = self.hit.t;
            rs.b = .{ b[0], b[1], b[2], self.wavelength };

            if (m.twoSided() and !self.hit.sameHemisphere(wo)) {
                rs.geo_n = -self.hit.geo_n;
                rs.n = -self.hit.n;
            } else {
                rs.geo_n = self.hit.geo_n;
                rs.n = self.hit.n;
            }

            rs.ray_p = self.ray.origin;

            rs.uv = self.hit.uv();
            rs.prop = self.hit.prop;
            rs.part = self.hit.part;
            rs.primitive = self.hit.primitive;
            rs.depth = self.depth;
            rs.time = self.time;
            rs.subsurface = self.hit.subsurface();
            rs.caustics = caustics;

            return m.sample(wo, rs, sampler, worker);
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

    const Self = @This();

    pub fn init(ray: Ray, time: u64) Vertex {
        return .{
            .isec = .{
                .ray = ray,
                .depth = 0,
                .wavelength = 0.0,
                .time = time,
                .hit = undefined,
            },
            .state = .{},
        };
    }
};

pub const RayDif = struct {
    x_origin: Vec4f,
    x_direction: Vec4f,
    y_origin: Vec4f,
    y_direction: Vec4f,
};
