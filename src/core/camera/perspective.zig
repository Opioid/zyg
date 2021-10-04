const Sensor = @import("../rendering/sensor/sensor.zig").Sensor;
const prp = @import("../scene/prop/prop.zig");
const Sample = @import("../sampler/camera_sample.zig").CameraSample;
const Scene = @import("../scene/scene.zig").Scene;
const Worker = @import("../scene/worker.zig").Worker;
const scn = @import("../scene/constants.zig");
const Ray = @import("../scene/ray.zig").Ray;
const Intersection = @import("../scene/prop/intersection.zig").Intersection;

const base = @import("base");
const json = base.json;
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Perspective = struct {
    const Focus = struct {
        point: Vec4f = undefined,
        distance: f32 = undefined,
        use_point: bool = false,
    };

    const Default_frame_time = scn.Units_per_second / 60;

    entity: u32 = prp.Null,

    resolution: Vec2i = Vec2i{ 0, 0 },
    crop: Vec4i = Vec4i.init1(0),

    sensor: Sensor = undefined,

    left_top: Vec4f = @splat(4, @as(f32, 0.0)),
    d_x: Vec4f = @splat(4, @as(f32, 0.0)),
    d_y: Vec4f = @splat(4, @as(f32, 0.0)),

    fov: f32 = 0.0,
    lens_radius: f32 = 0.0,
    focus_distance: f32 = 0.0,

    focus: Focus = .{},

    frame_step: u64 = Default_frame_time,
    frame_duration: u64 = Default_frame_time,

    pub fn deinit(self: *Perspective, alloc: *Allocator) void {
        self.sensor.deinit(alloc);
    }

    pub fn sensorDimensions(self: Perspective) Vec2i {
        return self.resolution;
    }

    pub fn setResolution(self: *Perspective, resolution: Vec2i, crop: Vec4i) void {
        self.resolution = resolution;

        self.crop.v[0] = std.math.max(0, crop.v[0]);
        self.crop.v[1] = std.math.max(0, crop.v[1]);
        self.crop.v[2] = std.math.min(resolution[0], crop.v[2]);
        self.crop.v[3] = std.math.min(resolution[1], crop.v[3]);
    }

    pub fn setSensor(self: *Perspective, sensor: Sensor) void {
        self.sensor = sensor;
    }

    pub fn update(self: *Perspective, time: u64, worker: *Worker) void {
        const fr = math.vec2iTo2f(self.resolution);
        const ratio = fr[1] / fr[0];

        const z = 1.0 / std.math.tan(0.5 * self.fov);

        const left_top = Vec4f{ -1.0, ratio, z, 0.0 };
        const right_top = Vec4f{ 1.0, ratio, z, 0.0 };
        const left_bottom = Vec4f{ -1.0, -ratio, z, 0.0 };

        self.left_top = left_top;
        self.d_x = (right_top - left_top) / @splat(4, fr[0]);
        self.d_y = (left_bottom - left_top) / @splat(4, fr[1]);

        self.updateFocus(time, worker);
    }

    pub fn generateRay(self: Perspective, sample: Sample, scene: Scene) ?Ray {
        const coordinates = math.vec2iTo2f(sample.pixel) + sample.pixel_uv;

        var direction = self.left_top + self.d_x * @splat(4, coordinates[0]) + self.d_y * @splat(4, coordinates[1]);
        var origin: Vec4f = undefined;

        if (self.lens_radius > 0.0) {
            const lens = math.smpl.diskConcentric(sample.lens_uv) * @splat(2, self.lens_radius);

            origin = Vec4f{ lens[0], lens[1], 0.0, 0.0 };

            const t = @splat(4, self.focus_distance / direction[2]);
            const focus = t * direction;
            direction = focus - origin;
        } else {
            origin = @splat(4, @as(f32, 0.0));
        }

        const time: u64 = 0;

        const trafo = scene.propTransformationAt(self.entity, time);

        const origin_w = trafo.objectToWorldPoint(origin);
        const direction_w = trafo.objectToWorldVector(math.normalize3(direction));

        return Ray.init(origin_w, direction_w, 0.0, scn.Ray_max_t, time);
    }

    pub fn setParameters(self: *Perspective, value: std.json.Value) void {
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
                self.lens_radius = json.readFloatMember(entry.value_ptr.*, "radius", 0.0);
            } else if (std.mem.eql(u8, "focus", entry.key_ptr.*)) {
                self.setFocus(loadFocus(entry.value_ptr.*));
            }
        }

        self.frame_duration = if (motion_blur) self.frame_step else 0;
    }

    fn setFocus(self: *Perspective, focus: Focus) void {
        self.focus = focus;
        self.focus.point[0] *= @intToFloat(f32, self.resolution[0]);
        self.focus.point[1] *= @intToFloat(f32, self.resolution[1]);
        self.focus_distance = focus.distance;
    }

    fn updateFocus(self: *Perspective, time: u64, worker: *Worker) void {
        if (self.focus.use_point and self.lens_radius > 0.0) {
            const direction = math.normalize3(
                self.left_top + self.d_x * @splat(4, self.focus.point[0]) + self.d_y * @splat(4, self.focus.point[1]),
            );

            const trafo = worker.scene.propTransformationAt(self.entity, time);

            var ray = Ray.init(
                trafo.position,
                trafo.objectToWorldVector(direction),
                0.0,
                scn.Ray_max_t,
                time,
            );

            var isec = Intersection{};
            if (worker.intersect(&ray, &isec)) {
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
