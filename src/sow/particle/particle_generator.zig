const Project = @import("../project.zig").Project;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;
const smpl = math.smpl;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Particles = struct {
    radius: f32,

    position_samples: [][]Pack3f,

    pub fn deinit(self: *Particles, alloc: Allocator) void {
        for (self.position_samples) |ps| {
            alloc.free(ps);
        }

        alloc.free(self.position_samples);
    }
};

pub const Generator = struct {
    pub fn generate(alloc: Allocator, project: Project, particles: *Particles) !void {
        const num_particles = project.particles.num_particles;

        const position_samples = try alloc.alloc([]Pack3f, project.particles.num_frames);

        for (position_samples) |*ps| {
            ps.* = try alloc.alloc(Pack3f, num_particles);
        }

        var velocities = try alloc.alloc(Pack3f, num_particles);

        var rng = RNG.init(0, 0);

        const radius: Vec4f = @splat(0.01);
        const velocity: Vec4f = @splat(2.0);

        for (0..num_particles) |i| {
            const uv = Vec2f{ rng.randomFloat(), rng.randomFloat() };

            const s = smpl.sphereUniform(uv);

            const p = s * radius;

            position_samples[0][i] = math.vec4fTo3f(p);
            velocities[i] = math.vec4fTo3f((s * velocity));
        }

        for (1..project.particles.num_frames) |f| {
            simulate(1.0 / 120.0, position_samples[f], position_samples[f - 1], velocities);
        }

        particles.radius = project.particles.radius;
        particles.position_samples = position_samples;
    }

    fn simulate(step: f32, result: []Pack3f, positions: []const Pack3f, velocities: []Pack3f) void {
        const gravity = Vec4f{ 0.0, -9.8, 0.0, 0.0 };
        const drag: Vec4f = @splat(1.0);

        const stepv: Vec4f = @splat(step);

        for (result, positions, velocities) |*r, p, *v| {
            var pos = math.vec3fTo4f(p);
            var vel = math.vec3fTo4f(v.*);

            pos += stepv * vel;
            vel += stepv * (drag * -math.normalize3(vel) + gravity);

            r.* = math.vec4fTo3f(pos);
            v.* = math.vec4fTo3f(vel);
        }
    }
};
