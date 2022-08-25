const snsr = @import("../rendering/sensor/sensor.zig");
const Sensor = snsr.Sensor;
const Aperture = @import("../rendering/sensor/aperture.zig").Aperture;
const Prop = @import("../scene/prop/prop.zig").Prop;
const cs = @import("../sampler/camera_sample.zig");
const Sampler = @import("../sampler/sampler.zig").Sampler;
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const Scene = @import("../scene/scene.zig").Scene;
const Worker = @import("../scene/worker.zig").Worker;
const scn = @import("../scene/constants.zig");
const sr = @import("../scene/ray.zig");
const Ray = sr.Ray;
const RayDif = sr.RayDif;
const Intersection = @import("../scene/prop/intersection.zig").Intersection;
const InterfaceStack = @import("../scene/prop/interface.zig").Stack;
const Resources = @import("../resource/manager.zig").Manager;
const tx = @import("../image/texture/provider.zig");

const base = @import("base");
const json = base.json;
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const RNG = base.rnd.Generator;
const Variants = base.memory.VariantMap;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Perspective = struct {
    const Focus = struct {
        point: Vec4f = undefined,
        distance: f32 = undefined,
        use_point: bool = false,
    };

    const Default_frame_time = scn.Units_per_second / 60;

    entity: u32 = Prop.Null,

    sample_spacing: f32 = undefined,

    resolution: Vec2i = Vec2i{ 0, 0 },
    crop: Vec4i = @splat(4, @as(i32, 0)),

    sensor: Sensor = .{
        .Filtered_2p0_opaque = snsr.Filtered(snsr.Opaque, 2).init(
            std.math.f32_max,
            2.0,
            snsr.Mitchell{ .b = 1.0 / 3.0, .c = 1.0 / 3.0 },
        ),
    },

    left_top: Vec4f = @splat(4, @as(f32, 0.0)),
    d_x: Vec4f = @splat(4, @as(f32, 0.0)),
    d_y: Vec4f = @splat(4, @as(f32, 0.0)),

    fov: f32 = 0.0,
    aperture: Aperture = .{},
    focus_distance: f32 = 0.0,
    a: f32 = undefined,

    focus: Focus = .{},

    interface_stack: InterfaceStack = undefined,

    frame_step: u64 = Default_frame_time,
    frame_duration: u64 = Default_frame_time,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.aperture.deinit(alloc);
        self.sensor.deinit(alloc);
    }

    pub fn sensorDimensions(self: Self) Vec2i {
        return self.resolution;
    }

    pub fn setResolution(self: *Self, resolution: Vec2i, crop: Vec4i) void {
        self.resolution = resolution;

        self.crop[0] = std.math.max(0, crop[0]);
        self.crop[1] = std.math.max(0, crop[1]);
        self.crop[2] = std.math.min(resolution[0], crop[2]);
        self.crop[3] = std.math.min(resolution[1], crop[3]);
    }

    pub fn update(self: *Self, time: u64, worker: *Worker) void {
        self.interface_stack.clear();

        const fr = math.vec2iTo2f(self.resolution);
        const ratio = fr[1] / fr[0];

        const z = 1.0 / @tan(0.5 * self.fov);

        const left_top = Vec4f{ -1.0, ratio, z, 0.0 };
        const right_top = Vec4f{ 1.0, ratio, z, 0.0 };
        const left_bottom = Vec4f{ -1.0, -ratio, z, 0.0 };

        self.left_top = left_top;
        self.d_x = (right_top - left_top) / @splat(4, fr[0]);
        self.d_y = (left_bottom - left_top) / @splat(4, fr[1]);

        const nlb = left_bottom / @splat(4, z);
        const nrt = right_top / @splat(4, z);

        self.a = @fabs((nrt[0] - nlb[0]) * (nrt[1] - nlb[1]));

        self.updateFocus(time, worker);
    }

    pub fn generateRay(self: Self, sample: Sample, frame: u32, scene: Scene) Ray {
        // const coordinates = math.vec2iTo2f(sample.pixel) + sample.pixel_uv;
        const coordinates = self.sensor.pixelToImageCoordinates(sample);

        var direction = self.left_top + self.d_x * @splat(4, coordinates[0]) + self.d_y * @splat(4, coordinates[1]);
        var origin: Vec4f = undefined;

        if (self.aperture.radius > 0.0) {
            const lens = self.aperture.sample(sample.lens_uv);

            origin = Vec4f{ lens[0], lens[1], 0.0, 0.0 };

            const t = @splat(4, self.focus_distance / direction[2]);
            const focus = t * direction;
            direction = focus - origin;
        } else {
            origin = @splat(4, @as(f32, 0.0));
        }

        const time = self.absoluteTime(frame, sample.time);
        const trafo = scene.propTransformationAt(self.entity, time);

        const origin_w = trafo.objectToWorldPoint(origin);
        const direction_w = trafo.objectToWorldVector(math.normalize3(direction));

        return Ray.init(origin_w, direction_w, 0.0, scn.Ray_max_t, 0, 0.0, time);
    }

    pub fn sampleTo(
        self: Self,
        bounds: Vec4i,
        time: u64,
        p: Vec4f,
        sampler: *Sampler,
        rng: *RNG,
        scene: Scene,
    ) ?SampleTo {
        const trafo = scene.propTransformationAt(self.entity, time);

        const po = trafo.worldToObjectPoint(p);

        var t: f32 = undefined;
        var dir: Vec4f = undefined;
        var out_dir: Vec4f = undefined;

        if (self.aperture.radius > 0.0) {
            const uv = sampler.sample2D(rng);
            const lens = self.aperture.sample(uv);
            const origin = Vec4f{ lens[0], lens[1], 0.0, 0.0 };
            const axis = po - origin;
            const d = self.focus_distance / axis[2];

            dir = origin + @splat(4, d) * axis;
            t = math.length3(axis);
            out_dir = axis / @splat(4, t);
        } else {
            t = math.length3(po);
            dir = po / @splat(4, t);
            out_dir = dir;
        }

        const cos_theta = out_dir[2];
        if (cos_theta < 0.0) {
            return null;
        }

        const pd = @splat(4, self.left_top[2]) * (dir / @splat(4, dir[2]));

        const offset = pd - self.left_top;

        const x = offset[0] / self.d_x[0];
        const y = offset[1] / self.d_y[1];

        const fx = @floor(x);
        const fy = @floor(y);

        const pixel = Vec2i{ @floatToInt(i32, fx), @floatToInt(i32, fy) };

        if (@intCast(u32, pixel[0] - bounds[0]) > @intCast(u32, bounds[2]) or
            @intCast(u32, pixel[1] - bounds[1]) > @intCast(u32, bounds[3]))
        {
            return null;
        }

        const cos_theta_2 = cos_theta * cos_theta;
        const wa = 1.0 / ((t * t) / cos_theta);
        const wb = 1.0 / (self.a * (cos_theta_2 * cos_theta_2));

        return SampleTo{
            .pixel = pixel,
            .pixel_uv = Vec2f{ x - fx, y - fy },
            .dir = trafo.objectToWorldVector(out_dir),
            .t = t,
            .pdf = wa * wb,
        };
    }

    pub fn calculateRayDifferential(self: Self, p: Vec4f, time: u64, scene: Scene) RayDif {
        const trafo = scene.propTransformationAt(self.entity, time);

        const p_w = trafo.position;

        const dir_w = math.normalize3(p - p_w);

        const d_x_w = trafo.objectToWorldVector(self.d_x);
        const d_y_w = trafo.objectToWorldVector(self.d_y);

        const ss = self.sample_spacing;

        const x_dir_w = math.normalize3(dir_w + @splat(4, ss) * d_x_w);
        const y_dir_w = math.normalize3(dir_w + @splat(4, ss) * d_y_w);

        return .{
            .x_origin = p_w,
            .x_direction = x_dir_w,
            .y_origin = p_w,
            .y_direction = y_dir_w,
        };
    }

    pub fn absoluteTime(self: Self, frame: u32, frame_delta: f32) u64 {
        const delta = @floatCast(f64, frame_delta);
        const duration = @intToFloat(f64, self.frame_duration);

        const fdi = @floatToInt(u64, @round(delta * duration));

        return @as(u64, frame) * self.frame_step + fdi;
    }

    pub fn setParameters(self: *Self, alloc: Allocator, value: std.json.Value, scene: Scene, resources: *Resources) !void {
        var motion_blur = true;

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "frame_step", entry.key_ptr.*)) {
                self.frame_step = scn.time(json.readFloat(f64, entry.value_ptr.*));
            } else if (std.mem.eql(u8, "frames_per_second", entry.key_ptr.*)) {
                const fps = json.readFloat(f64, entry.value_ptr.*);
                if (0.0 == fps) {
                    self.frame_step = 0;
                } else {
                    self.frame_step = @floatToInt(u64, @round(@intToFloat(f64, scn.Units_per_second) / fps));
                }
            } else if (std.mem.eql(u8, "motion_blur", entry.key_ptr.*)) {
                motion_blur = json.readBool(entry.value_ptr.*);
            } else if (std.mem.eql(u8, "fov", entry.key_ptr.*)) {
                const fov = json.readFloat(f32, entry.value_ptr.*);
                self.fov = math.degreesToRadians(fov);
            } else if (std.mem.eql(u8, "lens", entry.key_ptr.*)) {
                self.aperture.radius = json.readFloatMember(entry.value_ptr.*, "radius", self.aperture.radius);
            } else if (std.mem.eql(u8, "focus", entry.key_ptr.*)) {
                self.setFocus(loadFocus(entry.value_ptr.*));
            } else if (std.mem.eql(u8, "aperture", entry.key_ptr.*)) {
                self.aperture.radius = json.readFloatMember(entry.value_ptr.*, "radius", self.aperture.radius);

                const shape = json.readStringMember(entry.value_ptr.*, "shape", "");

                if (shape.len > 0) {
                    var options: Variants = .{};
                    defer options.deinit(alloc);
                    options.set(alloc, "usage", .Roughness) catch {};

                    const texture = try tx.Provider.loadFile(alloc, shape, options, @splat(2, @as(f32, 1.0)), resources);

                    try self.aperture.setShape(alloc, texture, scene);
                }
            }
        }

        self.frame_duration = if (motion_blur) self.frame_step else 0;
    }

    fn setFocus(self: *Self, focus: Focus) void {
        self.focus = focus;
        self.focus.point[0] *= @intToFloat(f32, self.resolution[0]);
        self.focus.point[1] *= @intToFloat(f32, self.resolution[1]);
        self.focus_distance = focus.distance;
    }

    fn updateFocus(self: *Self, time: u64, worker: *Worker) void {
        if (self.focus.use_point and self.aperture.radius > 0.0) {
            const direction = math.normalize3(
                self.left_top + self.d_x * @splat(4, self.focus.point[0]) + self.d_y * @splat(4, self.focus.point[1]),
            );

            const trafo = worker.scene.propTransformationAt(self.entity, time);

            var ray = Ray.init(
                trafo.position,
                trafo.objectToWorldVector(direction),
                0.0,
                scn.Ray_max_t,
                0,
                0.0,
                time,
            );

            var isec = Intersection{};
            if (worker.intersect(&ray, .Normal, &isec)) {
                self.focus_distance = ray.ray.maxT() + self.focus.point[2];
            } else {
                self.focus_distance = self.focus_distance;
            }
        }
    }

    fn loadFocus(value: std.json.Value) Focus {
        var focus = Focus{};

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "point", entry.key_ptr.*)) {
                focus.point = json.readVec4f3(entry.value_ptr.*);
                focus.use_point = true;
            } else if (std.mem.eql(u8, "distance", entry.key_ptr.*)) {
                focus.distance = json.readFloat(f32, entry.value_ptr.*);
            }
        }

        return focus;
    }
};
