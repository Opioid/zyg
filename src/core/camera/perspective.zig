const cs = @import("camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const snsr = @import("../rendering/sensor/sensor.zig");
const Sensor = snsr.Sensor;
const Aperture = @import("../rendering/sensor/aperture.zig").Aperture;
const Shaper = @import("../rendering/shaper.zig").Shaper;
const Prop = @import("../scene/prop/prop.zig").Prop;
const Sampler = @import("../sampler/sampler.zig").Sampler;
const Scene = @import("../scene/scene.zig").Scene;
const vt = @import("../scene/vertex.zig");
const Vertex = vt.Vertex;
const RayDif = vt.RayDif;
const ro = @import("../scene/ray_offset.zig");
const Intersection = @import("../scene/shape/intersection.zig").Intersection;
const InterfaceStack = @import("../scene/prop/interface.zig").Stack;
const Resources = @import("../resource/manager.zig").Manager;
const tx = @import("../image/texture/texture_provider.zig");
const img = @import("../image/image.zig");

const base = @import("base");
const json = base.json;
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Variants = base.memory.VariantMap;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Perspective = struct {
    const Focus = struct {
        point: Vec4f = undefined,
        distance: f32 = undefined,
        use_point: bool = false,
    };

    const Default_frame_time = Scene.Units_per_second / 60;

    entity: u32 = Prop.Null,

    sample_spacing: f32 = undefined,

    resolution: Vec2i = Vec2i{ 0, 0 },
    crop: Vec4i = @splat(0),

    sensor: Sensor = Sensor.init(
        .{ .Opaque = .{} },
        std.math.floatMax(f32),
        2.0,
        snsr.Mitchell{ .b = 1.0 / 3.0, .c = 1.0 / 3.0 },
    ),

    left_top: Vec4f = @splat(0.0),
    d_x: Vec4f = @splat(0.0),
    d_y: Vec4f = @splat(0.0),

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

        var cc: Vec4i = @max(crop, @as(Vec4i, @splat(0)));
        cc[2] = @min(cc[2], resolution[0]);
        cc[3] = @min(cc[3], resolution[1]);
        cc[0] = @min(cc[0], cc[2]);
        cc[1] = @min(cc[1], cc[3]);
        self.crop = cc;
    }

    pub fn update(self: *Self, time: u64, scene: *const Scene) void {
        self.interface_stack.clear();

        const fr = math.vec2iTo2f(self.resolution);
        const ratio = fr[1] / fr[0];

        const z = 1.0 / @tan(0.5 * self.fov);

        const left_top = Vec4f{ -1.0, ratio, z, 0.0 };
        const right_top = Vec4f{ 1.0, ratio, z, 0.0 };
        const left_bottom = Vec4f{ -1.0, -ratio, z, 0.0 };

        self.left_top = left_top;
        self.d_x = (right_top - left_top) / @as(Vec4f, @splat(fr[0]));
        self.d_y = (left_bottom - left_top) / @as(Vec4f, @splat(fr[1]));

        const nlb = left_bottom / @as(Vec4f, @splat(z));
        const nrt = right_top / @as(Vec4f, @splat(z));

        self.a = @abs((nrt[0] - nlb[0]) * (nrt[1] - nlb[1]));

        self.updateFocus(time, scene);
    }

    pub fn generateVertex(self: *const Self, sample: Sample, frame: u32, scene: *const Scene) Vertex {
        const center = math.vec2iTo2f(sample.pixel) + @as(Vec2f, @splat(0.5));
        const coordinates = center + sample.filter_uv;

        var direction = self.left_top + self.d_x * @as(Vec4f, @splat(coordinates[0])) + self.d_y * @as(Vec4f, @splat(coordinates[1]));
        var origin: Vec4f = undefined;

        if (self.aperture.radius > 0.0) {
            const lens = self.aperture.sample(sample.lens_uv);

            origin = Vec4f{ lens[0], lens[1], 0.0, 0.0 };

            const t: Vec4f = @splat(self.focus_distance / direction[2]);
            const focus = t * direction;
            direction = focus - origin;
        } else {
            origin = @splat(0.0);
        }

        const time = self.absoluteTime(frame, sample.time);
        const trafo = scene.propTransformationAt(self.entity, time);

        const origin_w = trafo.objectToWorldPoint(origin);
        const direction_w = trafo.objectToWorldVector(math.normalize3(direction));

        return Vertex.init(origin_w, direction_w, 0.0, ro.Ray_max_t, 0, 0.0, time, undefined);
    }

    pub fn sampleTo(
        self: *const Self,
        bounds: Vec4i,
        time: u64,
        p: Vec4f,
        sampler: *Sampler,
        scene: *const Scene,
    ) ?SampleTo {
        const trafo = scene.propTransformationAt(self.entity, time);

        const po = trafo.worldToObjectPoint(p);

        var t: f32 = undefined;
        var dir: Vec4f = undefined;
        var out_dir: Vec4f = undefined;

        if (self.aperture.radius > 0.0) {
            const uv = sampler.sample2D();
            const lens = self.aperture.sample(uv);
            const origin = Vec4f{ lens[0], lens[1], 0.0, 0.0 };
            const axis = po - origin;
            const d = self.focus_distance / axis[2];

            dir = origin + @as(Vec4f, @splat(d)) * axis;
            t = math.length3(axis);
            out_dir = axis / @as(Vec4f, @splat(t));
        } else {
            t = math.length3(po);
            dir = po / @as(Vec4f, @splat(t));
            out_dir = dir;
        }

        const cos_theta = out_dir[2];
        if (cos_theta < 0.0) {
            return null;
        }

        const pd = @as(Vec4f, @splat(self.left_top[2])) * (dir / @as(Vec4f, @splat(dir[2])));

        const offset = pd - self.left_top;

        const x = offset[0] / self.d_x[0];
        const y = offset[1] / self.d_y[1];

        const fx = @floor(x);
        const fy = @floor(y);

        const pixel = Vec2i{ @as(i32, @intFromFloat(fx)), @as(i32, @intFromFloat(fy)) };

        if (@as(u32, @intCast(pixel[0] - bounds[0])) > @as(u32, @intCast(bounds[2])) or
            @as(u32, @intCast(pixel[1] - bounds[1])) > @as(u32, @intCast(bounds[3])))
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

    pub fn calculateRayDifferential(self: *const Self, p: Vec4f, time: u64, scene: *const Scene) RayDif {
        const trafo = scene.propTransformationAt(self.entity, time);

        const p_w = trafo.position;

        const dir_w = math.normalize3(p - p_w);

        const d_x_w = trafo.objectToWorldVector(self.d_x);
        const d_y_w = trafo.objectToWorldVector(self.d_y);

        const ss = self.sample_spacing;

        const x_dir_w = math.normalize3(dir_w + @as(Vec4f, @splat(ss)) * d_x_w);
        const y_dir_w = math.normalize3(dir_w + @as(Vec4f, @splat(ss)) * d_y_w);

        return .{
            .x_origin = p_w,
            .x_direction = x_dir_w,
            .y_origin = p_w,
            .y_direction = y_dir_w,
        };
    }

    pub fn absoluteTime(self: Self, frame: u32, frame_delta: f32) u64 {
        const delta = @as(f64, @floatCast(frame_delta));
        const duration = @as(f64, @floatFromInt(self.frame_duration));

        const fdi = @as(u64, @intFromFloat(@round(delta * duration)));

        return @as(u64, frame) * self.frame_step + fdi;
    }

    pub fn setParameters(self: *Self, alloc: Allocator, value: std.json.Value, scene: *const Scene, resources: *Resources) !void {
        var motion_blur = true;

        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "frame_step", entry.key_ptr.*)) {
                self.frame_step = Scene.absoluteTime(json.readFloat(f64, entry.value_ptr.*));
            } else if (std.mem.eql(u8, "frames_per_second", entry.key_ptr.*)) {
                const fps = json.readFloat(f64, entry.value_ptr.*);
                if (0.0 == fps) {
                    self.frame_step = 0;
                } else {
                    self.frame_step = @as(u64, @intFromFloat(@round(@as(f64, @floatFromInt(Scene.Units_per_second)) / fps)));
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
                    options.set(alloc, "usage", .Opacity) catch {};

                    const texture = try tx.Provider.loadFile(alloc, shape, options, @splat(1.0), resources);
                    try self.aperture.setShape(alloc, texture, scene);
                } else {
                    const blades = json.readUIntMember(entry.value_ptr.*, "blades", 0);
                    if (blades > 3) {
                        var shaper = try Shaper.init(alloc, .{ 128, 128 });
                        defer shaper.deinit(alloc);

                        const roundness = json.readFloatMember(entry.value_ptr.*, "roundness", 0.0);

                        shaper.clear(@splat(0.0));
                        shaper.drawAperture(@splat(1.0), .{ 0.5, 0.5 }, blades, 0.5, roundness, std.math.pi);

                        var image = try img.Byte1.init(alloc, img.Description.init2D(shaper.dimensions));
                        shaper.resolve(img.Byte1, &image);
                        const iid = try resources.images.store(alloc, 0xFFFFFFFF, .{ .Byte1 = image });

                        const texture = try tx.Provider.createTexture(iid, .Opacity, @splat(1.0), resources);
                        try self.aperture.setShape(alloc, texture, scene);
                    }
                }
            }
        }

        self.frame_duration = if (motion_blur) self.frame_step else 0;
    }

    fn setFocus(self: *Self, focus: Focus) void {
        self.focus = focus;
        self.focus.point[0] *= @as(f32, @floatFromInt(self.resolution[0]));
        self.focus.point[1] *= @as(f32, @floatFromInt(self.resolution[1]));
        self.focus_distance = focus.distance;
    }

    fn updateFocus(self: *Self, time: u64, scene: *const Scene) void {
        if (self.focus.use_point and self.aperture.radius > 0.0) {
            const direction = math.normalize3(
                self.left_top + self.d_x * @as(Vec4f, @splat(self.focus.point[0])) + self.d_y * @as(Vec4f, @splat(self.focus.point[1])),
            );

            const trafo = scene.propTransformationAt(self.entity, time);

            var vertex = Vertex.init(
                trafo.position,
                trafo.objectToWorldVector(direction),
                0.0,
                ro.Ray_max_t,
                0,
                0.0,
                time,
                undefined,
            );

            if (scene.intersect(&vertex, .Normal)) {
                self.focus_distance = vertex.ray.maxT() + self.focus.point[2];
            } else {
                self.focus_distance = self.focus_distance;
            }
        }
    }

    fn loadFocus(value: std.json.Value) Focus {
        var focus = Focus{};

        var iter = value.object.iterator();
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
