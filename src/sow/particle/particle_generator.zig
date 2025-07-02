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
    positions: []Pack3f,
    velocities: []Pack3f,

    pub fn deinit(self: *Particles, alloc: Allocator) void {
        alloc.free(self.velocities);
        alloc.free(self.positions);
    }
};

pub const Generator = struct {
    pub fn generate(alloc: Allocator, project: Project, particles: *Particles) !void {
        const num_particles = project.particles.num_particles;

        var positions = try alloc.alloc(Pack3f, num_particles);
        var velocities = try alloc.alloc(Pack3f, num_particles);

        var rng = RNG.init(0, 0);

        const radius: Vec4f = @splat(0.1);
        const velocity: Vec4f = @splat(2.0);

        for (0..num_particles) |i| {
            const uv = Vec2f{ rng.randomFloat(), rng.randomFloat() };

            const s = smpl.sphereUniform(uv);

            const p = s * radius;

            positions[i] = math.vec4fTo3f(p);
            velocities[i] = math.vec4fTo3f(s * velocity);
        }

        particles.positions = positions;
        particles.velocities = velocities;
    }
};
