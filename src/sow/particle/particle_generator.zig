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
    frames_per_second: u32,
    radius: f32,

    position_samples: [][]Pack3f,
    radius_samples: [][]f32,

    pub fn deinit(self: *Particles, alloc: Allocator) void {
        for (self.position_samples) |ps| {
            alloc.free(ps);
        }

        alloc.free(self.position_samples);

        for (self.radius_samples) |rs| {
            alloc.free(rs);
        }

        alloc.free(self.radius_samples);
    }
};

pub const Generator = struct {
    const State = struct {
        velocities: []Pack3f,
        ages: []i32,
        max_ages: []i32,

        pub fn init(alloc: Allocator, num_particles: u32) !State {
            return State{
                .velocities = try alloc.alloc(Pack3f, num_particles),
                .ages = try alloc.alloc(i32, num_particles),
                .max_ages = try alloc.alloc(i32, num_particles),
            };
        }

        pub fn deinit(state: *State, alloc: Allocator) void {
            alloc.free(state.max_ages);
            alloc.free(state.ages);
            alloc.free(state.velocities);
        }
    };

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

        const fps = 120;

        for (1..project.particles.num_frames) |f| {
            simulate(1.0 / fps, position_samples[f], position_samples[f - 1], velocities);
        }

        particles.frames_per_second = fps;
        particles.radius = project.particles.radius;
        particles.position_samples = position_samples;
        particles.radius_samples = &.{};
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

    pub fn generateSparks(alloc: Allocator, project: Project, particles: *Particles) !void {
        const num_particles = project.particles.num_particles;

        const position_samples = try alloc.alloc([]Pack3f, project.particles.num_frames);
        for (position_samples) |*ps| {
            ps.* = try alloc.alloc(Pack3f, num_particles);
        }

        const radius_samples = try alloc.alloc([]f32, project.particles.num_frames);
        for (radius_samples) |*rs| {
            rs.* = try alloc.alloc(f32, num_particles);
        }

        var state = try State.init(alloc, num_particles);
        defer state.deinit(alloc);

        var rng = RNG.init(0, 0);

        const point_radius = project.particles.radius;

        // const radius: Vec4f = @splat(0.005);
        // const velocity: Vec4f = @splat(2.0);

        const fps = 120;
        const TickDuration = 1.0 / @as(f32, @floatFromInt(fps));

        for (0..num_particles) |i| {
            position_samples[0][i] = Pack3f.init1(0.0);
            radius_samples[0][i] = 0.0;

            state.velocities[i] = Pack3f.init1(1.0);

            const max_age = 0.12;

            state.ages[i] = @intFromFloat((-rng.randomFloat() * max_age) / TickDuration);
            state.max_ages[i] = 0; // @intFromFloat(max_age / TickDuration);

            //   std.debug.print("{} {}\n", .{ state.ages[i], state.max_ages[i] });
        }

        for (1..project.particles.num_frames) |f| {
            simulateSparks(TickDuration, &rng, position_samples[f], radius_samples[f], position_samples[f - 1], &state, point_radius);
        }

        particles.frames_per_second = fps;
        particles.radius = project.particles.radius;
        particles.position_samples = position_samples;
        particles.radius_samples = radius_samples;
    }

    fn simulateSparks(
        step: f32,
        rng: *RNG,
        out_pos: []Pack3f,
        out_radius: []f32,
        in_pos: []const Pack3f,
        state: *State,
        point_radius: f32,
    ) void {
        const gravity = Vec4f{ 0.0, -9.8, 0.0, 0.0 };
        const drag: Vec4f = @splat(1.0);

        const radius: Vec4f = @splat(0.005);
        const velocity: Vec4f = @splat(2.0);

        const stepv: Vec4f = @splat(step);

        for (0..out_pos.len) |i| {
            if (state.ages[i] >= state.max_ages[i]) {
                const sphere_uv = Vec2f{ rng.randomFloat(), rng.randomFloat() };
                const sphere = smpl.sphereUniform(sphere_uv);

                const cone_uv = Vec2f{ rng.randomFloat(), rng.randomFloat() };
                const cone = smpl.coneUniform(cone_uv, 0.9);

                out_pos[i] = math.vec4fTo3f(sphere * radius);
                out_radius[i] = 0.0;

                state.velocities[i] = math.vec4fTo3f((cone * velocity));
                state.ages[i] = -2;
                state.max_ages[i] = @intFromFloat((0.08 + 0.04 * rng.randomFloat()) / step);
            } else if (state.ages[i] < 0) {
                out_pos[i] = in_pos[i];
                out_radius[i] = 0.0;
            } else {
                var pos = math.vec3fTo4f(in_pos[i]);
                var vel = math.vec3fTo4f(state.velocities[i]);

                pos += stepv * vel;
                vel += stepv * (drag * -math.normalize3(vel) + gravity);

                out_pos[i] = math.vec4fTo3f(pos);

                if (state.ages[i] >= (state.max_ages[i] - 1)) {
                    out_radius[i] = 0.0;
                } else {
                    out_radius[i] = point_radius;
                }

                state.velocities[i] = math.vec4fTo3f(vel);
            }

            state.ages[i] += 1;
        }
    }

    pub fn generateCornellRain(alloc: Allocator, project: Project, particles: *Particles) !void {
        const num_particles = project.particles.num_particles;

        const position_samples = try alloc.alloc([]Pack3f, project.particles.num_frames);
        for (position_samples) |*ps| {
            ps.* = try alloc.alloc(Pack3f, num_particles);
        }

        const radius_samples = try alloc.alloc([]f32, project.particles.num_frames);
        for (radius_samples) |*rs| {
            rs.* = try alloc.alloc(f32, num_particles);
        }

        var state = try State.init(alloc, num_particles);
        defer state.deinit(alloc);

        var rng = RNG.init(0, 0);

        const point_radius = project.particles.radius;

        const fps = 120;
        const TickDuration = 1.0 / @as(f32, @floatFromInt(fps));
        const MaxAge = 0.4;

        for (0..num_particles) |i| {
            position_samples[0][i] = Pack3f.init1(0.0);
            radius_samples[0][i] = 0.0;

            state.velocities[i] = Pack3f.init1(0.0);

            state.ages[i] = -@as(i32, @intFromFloat((rng.randomFloat() * MaxAge) / TickDuration)) - 2;
            state.max_ages[i] = 0;
        }

        for (1..project.particles.num_frames) |f| {
            simulateCornellRain(TickDuration, MaxAge, &rng, position_samples[f], radius_samples[f], position_samples[f - 1], &state, point_radius);
        }

        particles.frames_per_second = fps;
        particles.radius = project.particles.radius;
        particles.position_samples = position_samples;
        particles.radius_samples = radius_samples;
    }

    fn simulateCornellRain(
        step: f32,
        max_age: f32,
        rng: *RNG,
        out_pos: []Pack3f,
        out_radius: []f32,
        in_pos: []const Pack3f,
        state: *State,
        point_radius: f32,
    ) void {
        //  const gravity = Vec4f{ 0.0, -9.8, 0.0, 0.0 };
        const gravity = Vec4f{ 0.0, -7.0, 0.0, 0.0 };

        const extent: Vec2f = @splat(0.27);

        const stepv: Vec4f = @splat(step);

        for (0..out_pos.len) |i| {
            if (state.ages[i] >= state.max_ages[i]) {
                const rect_uv = Vec2f{ rng.randomFloat(), rng.randomFloat() };

                const rect = extent * (@as(Vec2f, @splat(2.0)) * (rect_uv - @as(Vec2f, @splat(0.5))));

                out_pos[i] = Pack3f.init3(rect[0], 0.0, rect[1]);

                out_radius[i] = 0.0;

                state.velocities[i] = Pack3f.init1(0.0);
                state.ages[i] = -2;
                state.max_ages[i] = @intFromFloat(max_age / step);
            } else if (state.ages[i] < 0) {
                out_pos[i] = in_pos[i];
                out_radius[i] = 0.0;
            } else {
                var pos = math.vec3fTo4f(in_pos[i]);
                var vel = math.vec3fTo4f(state.velocities[i]);

                pos += stepv * vel;
                vel += stepv * gravity;

                out_pos[i] = math.vec4fTo3f(pos);

                if (state.ages[i] >= (state.max_ages[i] - 1)) {
                    out_radius[i] = 0.0;
                } else {
                    out_radius[i] = point_radius;
                }

                state.velocities[i] = math.vec4fTo3f(vel);
            }

            state.ages[i] += 1;
        }
    }
};
