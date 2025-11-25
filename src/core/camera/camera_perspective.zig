const Base = @import("camera_base.zig").Base;
const cs = @import("camera_sample.zig");
const Sample = cs.CameraSample;
const SampleTo = cs.CameraSampleTo;
const Aperture = @import("aperture.zig").Aperture;
const Shaper = @import("../rendering/shaper.zig").Shaper;
const Context = @import("../scene/context.zig").Context;
const Prop = @import("../scene/prop/prop.zig").Prop;
const Scene = @import("../scene/scene.zig").Scene;
const vt = @import("../scene/vertex.zig");
const Vertex = vt.Vertex;
const RayDif = vt.RayDif;
const ro = @import("../scene/ray_offset.zig");
const Fragment = @import("../scene/shape/intersection.zig").Fragment;
const Probe = @import("../scene/shape/probe.zig").Probe;
const MediumStack = @import("../scene/prop/medium.zig").Stack;
const Resources = @import("../resource/manager.zig").Manager;
const Sampler = @import("../sampler/sampler.zig").Sampler;
const tx = @import("../texture/texture_provider.zig");
const img = @import("../image/image.zig");

const base = @import("base");
const json = base.json;
const math = base.math;
const Ray = math.Ray;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Mat3x3 = math.Mat3x3;
const rnd = base.rnd;
const Variants = base.memory.VariantMap;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Perspective = struct {
    const Focus = struct {
        point: Vec4f = undefined,
        distance: f32 = -1.0,
        use_point: bool = false,
    };

    const Stereo = struct { ipd: f32 = 0.0 };

    super: Base = .{},

    left_top: [2]Vec4f = undefined,
    d_x: [2]Vec4f = undefined,
    d_y: [2]Vec4f = undefined,
    eye_offsets: [2]Vec4f = .{ @splat(0.0), @splat(0.0) },

    fov: f32 = 0.0,
    aperture: Aperture = .{},
    focus_distance: f32 = 0.0,
    a: f32 = undefined,

    focus: Focus = .{},
    stereo: Stereo = .{},

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.aperture.deinit(alloc);
    }

    pub fn numLayers(self: Self) u32 {
        return if (self.stereo.ipd > 0.0) 2 else 1;
    }

    pub fn layerExtension(self: Self, layer: u32) []const u8 {
        if (self.stereo.ipd > 0.0) {
            return if (0 == layer) "_l" else "_r";
        }

        return "";
    }

    pub fn update(self: *Self, time: u64, scene: *const Scene) void {
        const fr: Vec2f = @floatFromInt(self.super.resolution);
        const ratio = fr[1] / fr[0];

        const z = 1.0 / @tan(0.5 * self.fov);

        const left_top = Vec4f{ -1.0, ratio, z, 0.0 };
        const right_top = Vec4f{ 1.0, ratio, z, 0.0 };
        const left_bottom = Vec4f{ -1.0, -ratio, z, 0.0 };

        const d_x = (right_top - left_top) / @as(Vec4f, @splat(fr[0]));
        const d_y = (left_bottom - left_top) / @as(Vec4f, @splat(fr[1]));

        const nlb = left_bottom / @as(Vec4f, @splat(z));
        const nrt = right_top / @as(Vec4f, @splat(z));

        self.a = @abs((nrt[0] - nlb[0]) * (nrt[1] - nlb[1]));

        self.updateFocus(left_top, d_x, d_y, time, scene);

        if (self.stereo.ipd > 0.0 and self.focus_distance > 0.0) {
            const foccus_point = Vec4f{ 0.0, 0.0, self.focus_distance, 0.0 };
            const axis_l = math.normalize3(foccus_point - self.eye_offsets[0]);
            const angle = std.math.acos(axis_l[2]);

            const rot_l = Mat3x3.initRotationY(-angle);
            self.left_top[0] = rot_l.transformVector(left_top);
            self.d_x[0] = rot_l.transformVector(d_x);
            self.d_y[0] = rot_l.transformVector(d_y);

            const rot_r = Mat3x3.initRotationY(angle);
            self.left_top[1] = rot_r.transformVector(left_top);
            self.d_x[1] = rot_r.transformVector(d_x);
            self.d_y[1] = rot_r.transformVector(d_y);
        } else {
            self.left_top[0] = left_top;
            self.d_x[0] = d_x;
            self.d_y[0] = d_y;

            self.left_top[1] = left_top;
            self.d_x[1] = d_x;
            self.d_y[1] = d_y;
        }
    }

    pub fn generateVertex(self: *const Self, sample: Sample, layer: u32, frame: u32, scene: *const Scene) Vertex {
        const coordinates = @as(Vec2f, @floatFromInt(sample.pixel)) + sample.pixel_uv;

        var direction = self.left_top[layer] + self.d_x[layer] * @as(Vec4f, @splat(coordinates[0])) + self.d_y[layer] * @as(Vec4f, @splat(coordinates[1]));
        var origin: Vec4f = undefined;

        if (self.aperture.radius > 0.0) {
            const lens = self.aperture.sample(sample.lens_uv);

            origin = Vec4f{ lens[0], lens[1], 0.0, 0.0 };

            const t: Vec4f = @splat(self.focus_distance / direction[2]);
            const focus = t * direction;
            direction = focus - origin;
        } else {
            origin = self.eye_offsets[layer];
        }

        const shutter_time = self.super.sampleShutterTime(sample.time);
        const time = self.super.absoluteTime(frame, shutter_time);
        const trafo = scene.propTransformationAt(self.super.entity, time);

        const origin_w = trafo.objectToWorldPoint(origin);
        const direction_w = trafo.objectToWorldVector(math.normalize3(direction));

        return Vertex.init(Ray.init(origin_w, direction_w, 0.0, ro.RayMaxT), time);
    }

    pub fn sampleTo(
        self: *const Self,
        layer: u32,
        bounds: Vec4i,
        time: u64,
        p: Vec4f,
        sampler: *Sampler,
        scene: *const Scene,
    ) ?SampleTo {
        const trafo = scene.propTransformationAt(self.super.entity, time);

        const po = trafo.worldToObjectPoint(p) - self.eye_offsets[layer];

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

        const left_top = self.left_top[layer];

        const pd = @as(Vec4f, @splat(left_top[2])) * (dir / @as(Vec4f, @splat(dir[2])));

        const offset = pd - left_top;

        const x = offset[0] / self.d_x[layer][0];
        const y = offset[1] / self.d_y[layer][1];

        const fx = @floor(x);
        const fy = @floor(y);

        const pixel = Vec2i{ @intFromFloat(fx), @intFromFloat(fy) };

        if (@as(u32, @bitCast(pixel[0] - bounds[0])) > @as(u32, @bitCast(bounds[2])) or
            @as(u32, @bitCast(pixel[1] - bounds[1])) > @as(u32, @bitCast(bounds[3])))
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

    pub fn calculateRayDifferential(self: *const Self, layer: u32, p: Vec4f, time: u64, scene: *const Scene) RayDif {
        const trafo = scene.propTransformationAt(self.super.entity, time);

        var p_w: Vec4f = undefined;
        if (self.stereo.ipd > 0.0) {
            p_w = trafo.objectToWorldPoint(self.eye_offsets[layer]);
        } else {
            p_w = trafo.position;
        }

        const dir_w = math.normalize3(p - p_w);

        const d_x_w = trafo.objectToWorldVector(self.d_x[layer]);
        const d_y_w = trafo.objectToWorldVector(self.d_y[layer]);

        const ss: Vec4f = @splat(self.super.sample_spacing);

        const x_dir_w = math.normalize3(@mulAdd(Vec4f, ss, d_x_w, dir_w));
        const y_dir_w = math.normalize3(@mulAdd(Vec4f, ss, d_y_w, dir_w));

        return .{
            .x_origin = p_w,
            .x_direction = x_dir_w,
            .y_origin = p_w,
            .y_direction = y_dir_w,
        };
    }

    pub fn minDirDifferential(self: *const Self, layer: u32) [2]Vec4f {
        const d_x = self.d_x[layer];
        const d_y = self.d_y[layer];

        const ss: Vec4f = @splat(self.super.sample_spacing);

        return .{ ss * d_x, ss * d_y };
    }

    pub fn setParameters(self: *Self, alloc: Allocator, value: std.json.Value, resources: *Resources) !void {
        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "fov", entry.key_ptr.*)) {
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
                    options.set(alloc, "usage", tx.Usage.Opacity) catch {};

                    const texture = try tx.Provider.loadFile(alloc, shape, options, tx.Texture.DefaultMode, @splat(1.0), resources);
                    resources.commitAsync();

                    try self.aperture.setShape(alloc, texture, resources);
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

                        const texture = try tx.Provider.createTexture(iid, .Opacity, tx.Texture.DefaultMode, @splat(1.0), resources);
                        try self.aperture.setShape(alloc, texture, resources);
                    }
                }
            } else if (std.mem.eql(u8, "stereo", entry.key_ptr.*)) {
                const ipd = json.readFloatMember(entry.value_ptr.*, "ipd", 0.062);

                self.stereo.ipd = ipd;

                self.eye_offsets[0] = .{ -0.5 * ipd, 0.0, 0.0, 0.0 };
                self.eye_offsets[1] = .{ 0.5 * ipd, 0.0, 0.0, 0.0 };
            }
        }
    }

    fn setFocus(self: *Self, focus: Focus) void {
        const resolution = self.super.resolution;

        self.focus = focus;
        self.focus.point[0] *= @floatFromInt(resolution[0]);
        self.focus.point[1] *= @floatFromInt(resolution[1]);
        self.focus_distance = focus.distance;
    }

    fn updateFocus(self: *Self, left_top: Vec4f, d_x: Vec4f, d_y: Vec4f, time: u64, scene: *const Scene) void {
        if (self.focus.use_point and (self.aperture.radius > 0.0 or self.stereo.ipd > 0.0)) {
            const direction = math.normalize3(
                left_top + d_x * @as(Vec4f, @splat(self.focus.point[0])) + d_y * @as(Vec4f, @splat(self.focus.point[1])),
            );

            const trafo = scene.propTransformationAt(self.super.entity, time);

            var probe = Probe.init(
                Ray.init(trafo.position, trafo.objectToWorldVector(direction), 0.0, ro.RayMaxT),
                time,
            );

            var rng = rnd.Generator.init(0, 0);
            var sampler = Sampler{ .Random = .{ .rng = &rng } };

            var frag: Fragment = undefined;
            if (scene.intersect(&probe, false, &sampler, &frag)) {
                self.focus_distance = probe.ray.max_t + self.focus.point[2];
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
