const Fragment = @import("shape/intersection.zig").Fragment;
const Probe = @import("shape/probe.zig").Probe;
const Scene = @import("scene.zig").Scene;
const MaterialSample = @import("material/material_sample.zig").Sample;
const MediumStack = @import("prop/medium.zig").Stack;
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
    pub const State = packed struct {
        primary_ray: bool = true,
        transparent: bool = true,
        treat_as_singular: bool = true,
        is_translucent: bool = false,
        started_specular: bool = false,
        from_shadow_catcher: bool = false,
        shadow_catcher_in_camera: bool = false,
        exit_sss: bool = false,
    };

    probe: Probe,

    state: State,
    depth: Probe.Depth,
    bxdf_pdf: f32,
    min_alpha: f32,
    split_weight: f32,
    path_count: u32,

    throughput: Vec4f,
    shadow_catcher_occluded: Vec4f,
    shadow_catcher_unoccluded: Vec4f,
    shadow_catcher_emission: Vec4f,
    origin: Vec4f,
    geo_n: Vec4f,

    mediums: MediumStack,

    const Self = @This();

    pub fn init(ray: Ray, time: u64) Vertex {
        return .{
            .probe = Probe.init(ray, time),
            .state = .{},
            .depth = .{},
            .bxdf_pdf = 0.0,
            .min_alpha = 0.0,
            .split_weight = 1.0,
            .path_count = 1,
            .throughput = @splat(1.0),
            .shadow_catcher_occluded = undefined,
            .shadow_catcher_unoccluded = undefined,
            .shadow_catcher_emission = @splat(0.0),
            .origin = ray.origin,
            .geo_n = @splat(0.0),
            .mediums = .{},
        };
    }

    inline fn iorOutside(self: *const Self, frag: *const Fragment, wo: Vec4f) f32 {
        if (frag.sameHemisphere(wo)) {
            return self.mediums.topIor();
        }

        return self.mediums.peekIor(frag);
    }

    pub fn interfaceChange(
        self: *Self,
        dir: Vec4f,
        frag: *const Fragment,
        mat_sample: *const MaterialSample,
        scene: *const Scene,
    ) void {
        const leave = frag.sameHemisphere(dir);
        if (leave) {
            self.mediums.remove(frag);
        } else {
            const material = frag.material(scene);
            const cc = material.collisionCoefficients2D(mat_sample);
            self.mediums.push(frag, cc, material.ior(), material.super().priority);
        }
    }

    pub fn interfaceChangeIor(
        self: *Self,
        dir: Vec4f,
        frag: *const Fragment,
        mat_sample: *const MaterialSample,
        scene: *const Scene,
    ) IoR {
        const inter_ior = frag.material(scene).ior();

        const leave = frag.sameHemisphere(dir);
        if (leave) {
            const ior = IoR{ .eta_t = self.mediums.peekIor(frag), .eta_i = inter_ior };
            self.mediums.remove(frag);
            return ior;
        }

        const ior = IoR{ .eta_t = inter_ior, .eta_i = self.mediums.topIor() };

        const material = frag.material(scene);
        const cc = material.collisionCoefficients2D(mat_sample);
        self.mediums.push(frag, cc, material.ior(), material.super().priority);

        return ior;
    }

    pub fn sample(
        self: *const Self,
        frag: *const Fragment,
        sampler: *Sampler,
        caustics: CausticsResolve,
        worker: *const Worker,
    ) mat.Sample {
        const wo = -self.probe.ray.direction;

        const m = frag.material(worker.scene);

        var rs: Renderstate = undefined;
        rs.trafo = frag.isec.trafo;
        rs.p = frag.p;
        rs.t = frag.t;
        rs.b = frag.b;

        if (m.twoSided() and !frag.sameHemisphere(wo)) {
            rs.geo_n = -frag.geo_n;
            rs.n = -frag.n;
        } else {
            rs.geo_n = frag.geo_n;
            rs.n = frag.n;
        }

        rs.origin = self.origin;
        rs.uvw = frag.uvw;
        rs.ior = self.iorOutside(frag, wo);
        rs.wavelength = self.probe.wavelength;
        rs.min_alpha = self.min_alpha;
        rs.time = self.probe.time;
        rs.prop = frag.prop;
        rs.part = frag.part;
        rs.primitive = frag.isec.primitive;
        rs.volume_depth = self.probe.depth.volume;
        rs.event = frag.event;
        rs.primary = self.state.primary_ray;
        rs.caustics = caustics;
        rs.highest_priority = self.mediums.highestPriority();

        return m.sample(wo, rs, sampler, worker);
    }
};

pub const Pool = struct {
    pub const NumVertices = 4;

    transparency: Vec4f,

    buffer: [2 * NumVertices]Vertex,
    terminated: u32,

    current_id: u32,
    current_start: u32,
    current_end: u32,
    next_start: u32,
    next_end: u32,

    pub fn start(self: *Pool, vertex: Vertex) void {
        self.transparency = @splat(0.0);
        self.buffer[0] = vertex;
        self.terminated = 0;
        self.current_id = NumVertices;
        self.current_start = NumVertices;
        self.current_end = NumVertices;
        self.next_start = 0;
        self.next_end = 1;
    }

    pub fn iterate(self: *Pool) bool {
        const old_end = self.current_end;
        var i = self.current_start;
        while (i < old_end) : (i += 1) {
            const mask = @as(u32, 1) << @as(u5, @truncate(i));
            if (0 != (self.terminated & mask)) {
                const v = &self.buffer[i];
                if (v.state.shadow_catcher_in_camera) {
                    const occluded = v.shadow_catcher_occluded;
                    const unoccluded = v.shadow_catcher_unoccluded;
                    const ol = occluded < unoccluded;
                    const shadow_ratio = @select(f32, ol, occluded / unoccluded, @as(Vec4f, @splat(1.0)));
                    const alpha = self.transparency[3];
                    self.transparency += shadow_ratio * v.shadow_catcher_emission * @as(Vec4f, @splat(v.split_weight));
                    self.transparency[3] = alpha + math.max((1.0 - math.average3(shadow_ratio)) * v.split_weight, 0.0);
                } else if (v.state.transparent) {
                    self.transparency[3] += math.max((1.0 - math.average3(v.throughput)) * v.split_weight, 0.0);
                } else {
                    const alpha = self.transparency[3];
                    self.transparency += v.shadow_catcher_emission * @as(Vec4f, @splat(v.split_weight));
                    self.transparency[3] = alpha + v.split_weight;
                }
            }
        }

        const current_start = self.next_start;
        const current_end = self.next_end;

        self.current_id = current_start;
        self.current_start = current_start;
        self.current_end = current_end;

        const next_start: u32 = if (NumVertices == current_start) 0 else NumVertices;
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

    pub inline fn maxSplits(v: *const Vertex, depth: u32) u32 {
        const m = NumVertices / v.path_count;
        return m - (if (v.state.primary_ray) 0 else @min(depth, m - 1));
    }
};

pub const RayDif = struct {
    x_origin: Vec4f,
    x_direction: Vec4f,
    y_origin: Vec4f,
    y_direction: Vec4f,
};
