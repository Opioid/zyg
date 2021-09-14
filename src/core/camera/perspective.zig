const Sensor = @import("../rendering/sensor/sensor.zig").Sensor;
const prp = @import("../scene/prop/prop.zig");
const Sample = @import("../sampler/camera_sample.zig").CameraSample;
const Scene = @import("../scene/scene.zig").Scene;
const scn = @import("../scene/constants.zig");
const Ray = @import("../scene/ray.zig").Ray;
const math = @import("base").math;

const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Perspective = struct {
    entity: u32 = prp.Null,

    resolution: Vec2i = Vec2i.init1(0),
    crop: Vec4i = Vec4i.init1(0),

    sensor: Sensor = undefined,

    fov: f32 = 0.0,

    left_top: Vec4f = @splat(4, @as(f32, 0.0)),
    d_x: Vec4f = @splat(4, @as(f32, 0.0)),
    d_y: Vec4f = @splat(4, @as(f32, 0.0)),

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
        self.crop.v[2] = std.math.min(resolution.v[0], crop.v[2]);
        self.crop.v[3] = std.math.min(resolution.v[1], crop.v[3]);
    }

    pub fn setSensor(self: *Perspective, sensor: Sensor) void {
        self.sensor = sensor;
    }

    pub fn update(self: *Perspective) void {
        const fr = self.resolution.toVec2f();
        const ratio = fr.v[1] / fr.v[0];

        const z = 1.0 / std.math.tan(0.5 * self.fov);

        const left_top = Vec4f{ -1.0, ratio, z, 0.0 };
        const right_top = Vec4f{ 1.0, ratio, z, 0.0 };
        const left_bottom = Vec4f{ -1.0, -ratio, z, 0.0 };

        self.left_top = left_top;
        self.d_x = (right_top - left_top) / @splat(4, fr.v[0]);
        self.d_y = (left_bottom - left_top) / @splat(4, fr.v[1]);
    }

    pub fn generateRay(self: *const Perspective, sample: Sample, scene: Scene) ?Ray {
        const coordinates = sample.pixel.toVec2f().add(sample.pixel_uv);

        const direction = self.left_top + self.d_x * @splat(4, coordinates.v[0]) + self.d_y * @splat(4, coordinates.v[1]);
        const origin = @splat(4, @as(f32, 0.0));

        const trafo = scene.propTransformationAt(self.entity);

        const origin_w = trafo.objectToWorldPoint(origin);
        const direction_w = trafo.objectToWorldVector(math.normalize3(direction));

        return Ray.init(origin_w, direction_w, 0.0, scn.Ray_max_t);
    }
};
