const log = @import("../log.zig");
const Model = @import("sky_model.zig").Model;
const SkyMaterial = @import("sky_material.zig").Material;
const Prop = @import("../scene/prop/prop.zig").Prop;
const Scene = @import("../scene/scene.zig").Scene;
const Shape = @import("../scene/shape/shape.zig").Shape;
const Canopy = @import("../scene/shape/canopy.zig").Canopy;
const Trafo = @import("../scene/composed_transformation.zig").ComposedTransformation;
const Texture = @import("../texture/texture.zig").Texture;
const ts = @import("../texture/texture_sampler.zig");
const img = @import("../image/image.zig");
const Image = img.Image;
const ExrReader = @import("../image/encoding/exr/exr_reader.zig").Reader;
const ExrWriter = @import("../image/encoding/exr/exr_writer.zig").Writer;
const Filesystem = @import("../file/system.zig").System;

const base = @import("base");
const json = base.json;
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;
const Vec4f = math.Vec4f;
const Mat3x3 = math.Mat3x3;
const Transformation = math.Transformation;
const Threads = base.thread.Pool;
const RNG = base.rnd.Generator;

const std = @import("std");
const Allocator = std.mem.Allocator;
const Base64 = std.base64.url_safe_no_pad;

pub const Sky = struct {
    sun: u32 = Prop.Null,
    sky: u32 = Prop.Null,

    visibility: f32 = 100.0,
    albedo: f32 = 0.25,

    sun_rotation: Mat3x3 = Mat3x3.init9(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0),

    pub const Radius = @tan(@as(f32, @floatCast(Model.AngularRadius)));

    pub const BakeDimensions = Vec2i{ 1024, 1024 };
    pub const BakeDimensionsSun: u32 = 1024;

    const Self = @This();

    pub fn configure(self: *Self, alloc: Allocator, scene: *Scene) !void {
        if (Prop.Null != self.sun) {
            return;
        }

        var sun_mat = try SkyMaterial.initSun(alloc);
        sun_mat.commit();
        const sun_mat_id = try scene.createMaterial(alloc, .{ .Sky = sun_mat });
        const sun_prop = try scene.createPropShape(alloc, @intFromEnum(Scene.ShapeID.DistantSphere), &.{sun_mat_id}, true, false);

        const sky_image = try scene.createImage(alloc, .{ .Float3 = img.Float3.initEmpty() });
        const emission_map = Texture.initImage(.Float3, sky_image, Texture.DefaultClampMode, @splat(1.0));
        var sky_mat = SkyMaterial.initSky(emission_map);
        sky_mat.commit();
        const sky_mat_id = try scene.createMaterial(alloc, .{ .Sky = sky_mat });
        const sky_prop = try scene.createPropShape(alloc, @intFromEnum(Scene.ShapeID.Canopy), &.{sky_mat_id}, true, false);

        self.sky = sky_prop;
        self.sun = sun_prop;

        const trafo = Transformation{
            .position = @splat(0.0),
            .scale = @splat(1.0),
            .rotation = math.quaternion.initRotationX(math.degreesToRadians(90.0)),
        };

        scene.prop_space.setWorldTransformation(sky_prop, trafo);

        try scene.createLight(alloc, sun_prop);
        try scene.createLight(alloc, sky_prop);
    }

    pub fn setParameters(self: *Self, value: std.json.Value) void {
        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "sun", entry.key_ptr.*)) {
                const angles = json.readVec4f3Member(entry.value_ptr.*, "rotation", @splat(0.0));
                self.sun_rotation = json.createRotationMatrix(angles);
            } else if (std.mem.eql(u8, "turbidity", entry.key_ptr.*)) {
                self.visibility = Model.turbidityToVisibility(json.readFloat(f32, entry.value_ptr.*));
            } else if (std.mem.eql(u8, "visibility", entry.key_ptr.*)) {
                self.visibility = json.readFloat(f32, entry.value_ptr.*);
            } else if (std.mem.eql(u8, "albedo", entry.key_ptr.*)) {
                self.albedo = json.readFloat(f32, entry.value_ptr.*);
            }
        }
    }

    pub fn compile(
        self: *Self,
        alloc: Allocator,
        time: u64,
        scene: *Scene,
        threads: *Threads,
        fs: *Filesystem,
    ) !void {
        if (Prop.Null == self.sun) {
            return;
        }

        const e = scene.prop(self.sun);
        scene.propSetVisibility(self.sky, e.visibleInCamera(), e.visibleInReflection(), false);

        // HACK: artificially set sun radius to zero if under horizon to get an early out during light sampling...
        const under_horizon = self.sun_rotation.r[2][1] > Model.AngularRadius;

        const scale: Vec4f = if (under_horizon) @splat(0.0) else Vec4f{ Radius, Radius, Radius, 1.0 };

        if (scene.prop_space.hasAnimatedFrames(self.sun)) {
            self.sun_rotation = scene.prop_space.transformationAt(self.sun, time, scene.frame_start).rotation;
            scene.prop_space.setFramesScale(self.sun, scale, scene.num_interpolation_frames);
        } else {
            const trafo = Transformation{
                .position = @splat(0.0),
                .scale = scale,
                .rotation = math.quaternion.initFromMat3x3(self.sun_rotation),
            };

            scene.prop_space.setWorldTransformation(self.sun, trafo);
        }

        var hasher = std.hash.Fnv1a_128.init();
        hasher.update(std.mem.asBytes(&self.visibility));
        hasher.update(std.mem.asBytes(&self.albedo));
        hasher.update(std.mem.asBytes(&self.sun_rotation));

        var hb64: [22]u8 = undefined;
        _ = Base64.Encoder.encode(&hb64, std.mem.asBytes(&hasher.final()));

        var buf0: [48]u8 = undefined;
        const sky_filename = try std.fmt.bufPrint(&buf0, "../cache/sky_{s}.exr", .{hb64});

        var buf1: [48]u8 = undefined;
        const sun_filename = try std.fmt.bufPrint(&buf1, "../cache/sun_{s}.exr", .{hb64});

        {
            var stream = fs.readStream(alloc, sky_filename) catch {
                return self.bakeSky(alloc, scene, threads, fs, sky_filename, sun_filename);
            };

            defer stream.deinit();

            const cached_image = try ExrReader.read(alloc, stream, .XYZ, false);

            var image = scene.imagePtr(scene.propMaterial(self.sky, 0).Sky.emission_map.data.image.id);
            image.deinit(alloc);
            image.* = cached_image;
        }

        {
            var stream = fs.readStream(alloc, sun_filename) catch {
                return self.bakeSky(alloc, scene, threads, fs, sky_filename, sun_filename);
            };

            defer stream.deinit();

            var cached_image = try ExrReader.read(alloc, stream, .XYZ, false);
            defer cached_image.deinit(alloc);

            scene.propMaterial(self.sun, 0).Sky.setSunRadiance(self.sun_rotation, cached_image.Float3);
        }
    }

    fn bakeSky(
        self: *Self,
        alloc: Allocator,
        scene: *Scene,
        threads: *Threads,
        fs: *Filesystem,
        sky_filename: []u8,
        sun_filename: []u8,
    ) !void {
        var image = &scene.imagePtr(scene.propMaterial(self.sky, 0).Sky.emission_map.data.image.id).Float3;

        try image.resize(alloc, img.Description.init2D(BakeDimensions));

        const sun_direction = self.sun_rotation.r[2];
        var model = Model.init(alloc, sun_direction, self.visibility, self.albedo, fs) catch {
            var y: i32 = 0;
            while (y < BakeDimensions[1]) : (y += 1) {
                var x: i32 = 0;
                while (x < BakeDimensions[0]) : (x += 1) {
                    image.set2D(x, y, math.Pack3f.init1(0.0));
                }
            }

            scene.propMaterial(self.sun, 0).Sky.setSunRadianceZero();

            log.err("Could not initialize sky model", .{});
            return;
        };
        defer model.deinit();

        var sun_image = try img.Float3.init(alloc, img.Description.init2D(.{ BakeDimensionsSun, 1 }));
        defer sun_image.deinit(alloc);

        const n: f32 = @floatFromInt(BakeDimensionsSun - 1);

        var rng = RNG.init(0, 0);

        for (sun_image.pixels, 0..) |*s, i| {
            const v = @as(f32, @floatFromInt(i)) / n;
            var wi = sunWi(self.sun_rotation, v);
            wi[1] = math.max(wi[1], 0.0);

            s.* = math.vec4fTo3f(model.evaluateSun(wi, &rng));
        }

        scene.propMaterial(self.sun, 0).Sky.setSunRadiance(self.sun_rotation, sun_image);

        var context = SkyContext{
            .model = &model,
            .shape = scene.propShape(self.sky),
            .image = image,
            .trafo = scene.prop_space.transformationAtMaybeStatic(self.sky, 0, 0, true),
        };

        threads.runParallel(&context, SkyContext.bakeSky, 0);

        const ew = ExrWriter{ .half = false };

        var file_buffer: [4096]u8 = undefined;

        {
            var file = try std.fs.cwd().createFile(sky_filename, .{});
            defer file.close();

            var writer = file.writer(&file_buffer);

            try ew.write(
                alloc,
                &writer.interface,
                .{ .Float3 = image.* },
                .{ 0, 0, BakeDimensions[0], BakeDimensions[1] },
                .Color,
                threads,
            );
        }

        {
            var file = try std.fs.cwd().createFile(sun_filename, .{});
            defer file.close();

            var writer = file.writer(&file_buffer);

            try ew.write(
                alloc,
                &writer.interface,
                .{ .Float3 = sun_image },
                .{ 0, 0, BakeDimensionsSun, 1 },
                .Color,
                threads,
            );
        }
    }

    pub fn sunWi(rotation: Mat3x3, v: f32) Vec4f {
        const y = (2.0 * v) - 1.0;

        const ls = Vec4f{ 0.0, y * Radius, 0.0, 0.0 };
        const ws = rotation.transformVector(ls);

        return math.normalize3(ws - rotation.r[2]);
    }
};

const SkyContext = struct {
    model: *const Model,
    shape: *const Shape,
    image: *img.Float3,
    trafo: Trafo,
    current: u32 = 0,

    pub fn bakeSky(context: Threads.Context, id: u32) void {
        _ = id;

        const self: *SkyContext = @ptrCast(@alignCast(context));

        var rng: RNG = undefined;

        const idf = @as(Vec2f, @splat(1.0)) / @as(Vec2f, @floatFromInt(Sky.BakeDimensions));

        while (true) {
            const y = @atomicRmw(u32, &self.current, .Add, 1, .monotonic);
            if (y >= Sky.BakeDimensions[1]) {
                return;
            }

            const v = idf[1] * (@as(f32, @floatFromInt(y)) + 0.5);

            var x: u32 = 0;
            while (x < Sky.BakeDimensions[0]) : (x += 1) {
                rng.start(0, y * Sky.BakeDimensions[0] + x);

                const u = idf[0] * (@as(f32, @floatFromInt(x)) + 0.5);
                const uv = Vec2f{ u, v };
                if (clippedCanopyMapping(self.trafo, uv, 3.5 * idf[0])) |wi| {
                    const li = self.model.evaluateSky(math.normalize3(wi), &rng);

                    self.image.set2D(@intCast(x), @intCast(y), math.vec4fTo3f(li));
                } else {
                    self.image.set2D(@intCast(x), @intCast(y), Pack3f.init1(0.0));
                }
            }
        }
    }

    fn clippedCanopyMapping(trafo: Trafo, uv: Vec2f, e: f32) ?Vec4f {
        var disk = Vec2f{ 2.0 * uv[0] - 1.0, 2.0 * uv[1] - 1.0 };

        const l = math.length2(disk);

        if (l > 1.0 + e) {
            return null;
        }

        if (l >= 1.0 - e) {
            disk /= @splat(l + e);
        }

        const dir = Canopy.diskToHemisphereEquidistant(disk);

        return trafo.rotation.transformVector(dir);
    }
};
