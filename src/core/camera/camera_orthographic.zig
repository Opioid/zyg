const Base = @import("camera_base.zig").Base;
const cs = @import("camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const Scene = @import("../scene/scene.zig").Scene;
const vt = @import("../scene/vertex.zig");
const Vertex = vt.Vertex;
const RayDif = vt.RayDif;
const ro = @import("../scene/ray_offset.zig");

const base = @import("base");
const json = base.json;
const math = base.math;
const Ray = math.Ray;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Orthographic = struct {
    super: Base = .{},

    left_top: Vec4f = undefined,
    d_x: Vec4f = undefined,
    d_y: Vec4f = undefined,

    size: f32 = 1.0,

    const Self = @This();

    pub fn update(self: *Self) void {
        const size_x = 0.5 * self.size;

        const fr: Vec2f = @floatFromInt(self.super.resolution);
        const ratio = fr[1] / fr[0];

        const size_y = size_x * ratio;

        const left_top = Vec4f{ -size_x, size_y, 0.0, 0.0 };
        const right_top = Vec4f{ size_x, size_y, 0.0, 0.0 };
        const left_bottom = Vec4f{ -size_x, -size_y, 0.0, 0.0 };

        const d_x = (right_top - left_top) / @as(Vec4f, @splat(fr[0]));
        const d_y = (left_bottom - left_top) / @as(Vec4f, @splat(fr[1]));

        self.left_top = left_top;
        self.d_x = d_x;
        self.d_y = d_y;
    }

    pub fn generateVertex(self: *const Self, sample: Sample, frame: u32, scene: *const Scene) Vertex {
        const center = @as(Vec2f, @floatFromInt(sample.pixel)) + @as(Vec2f, @splat(0.5));
        const coordinates = center + sample.filter_uv;

        const origin = self.left_top + self.d_x * @as(Vec4f, @splat(coordinates[0])) + self.d_y * @as(Vec4f, @splat(coordinates[1]));
        const direction = Vec4f{ 0.0, 0.0, 1.0, 0.0 };

        const time = self.super.absoluteTime(frame, sample.time);
        const trafo = scene.propTransformationAt(self.super.entity, time);

        const origin_w = trafo.objectToWorldPoint(origin);
        const direction_w = trafo.objectToWorldVector(math.normalize3(direction));

        return Vertex.init(Ray.init(origin_w, direction_w, 0.0, ro.RayMaxT), time);
    }

    pub fn calculateRayDifferential(self: *const Self, p: Vec4f, time: u64, scene: *const Scene) RayDif {
        const trafo = scene.propTransformationAt(self.super.entity, time);

        const n = trafo.rotation.r[2];
        const d = math.dot3(n, trafo.position);
        const hit_t = -(math.dot3(n, p) - d);

        const p_w = p + @as(Vec4f, @splat(hit_t)) * n;

        const dir_w = math.normalize3(p - p_w);

        const d_x_w = trafo.objectToWorldVector(self.d_x);
        const d_y_w = trafo.objectToWorldVector(self.d_y);

        const ss: Vec4f = @splat(self.super.sample_spacing);

        return .{
            .x_origin = p_w + ss * d_x_w,
            .x_direction = dir_w,
            .y_origin = p_w + ss * d_y_w,
            .y_direction = dir_w,
        };
    }

    pub fn minDirDifferential(self: *const Self) [2]Vec4f {
        const d_x = self.d_x;
        const d_y = self.d_y;

        const ss: Vec4f = @splat(self.super.sample_spacing);

        return .{ ss * d_x, ss * d_y };
    }

    pub fn setParameters(self: *Self, value: std.json.Value) void {
        self.size = json.readFloatMember(value, "size", self.size);
    }
};
