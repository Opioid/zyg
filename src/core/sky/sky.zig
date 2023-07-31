const log = @import("../log.zig");
const Model = @import("model.zig").Model;
const SkyMaterial = @import("material.zig").Material;
const Prop = @import("../scene/prop/prop.zig").Prop;
const Scene = @import("../scene/scene.zig").Scene;
const Shape = @import("../scene/shape/shape.zig").Shape;
const Canopy = @import("../scene/shape/canopy.zig").Canopy;
const ComposedTransformation = @import("../scene/composed_transformation.zig").ComposedTransformation;
const Texture = @import("../image/texture/texture.zig").Texture;
const ts = @import("../image/texture/texture_sampler.zig");
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
    albedo: f32 = 0.2,

    sun_rotation: Mat3x3 = Mat3x3.init9(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0),

    pub const Radius = @tan(@as(f32, @floatCast(Model.Angular_radius)));

    pub const Bake_dimensions = Vec2i{ 512, 512 };
    pub const Bake_dimensions_sun: u32 = 1024;

    const Self = @This();

    pub fn configure(self: *Self, alloc: Allocator, scene: *Scene) !void {
        if (Prop.Null != self.sun) {
            return;
        }

        var sun_mat = try SkyMaterial.initSun(alloc);
        sun_mat.commit();
        const sun_mat_id = try scene.createMaterial(alloc, .{ .Sky = sun_mat });
        const sun_prop = try scene.createProp(alloc, @intFromEnum(Scene.ShapeID.DistantSphere), &.{sun_mat_id});

        const sky_image = try scene.createImage(alloc, .{ .Float3 = .{} });
        const emission_map = Texture{ .type = .Float3, .image = sky_image, .scale = .{ 1.0, 1.0 } };
        var sky_mat = SkyMaterial.initSky(emission_map);
        sky_mat.commit();
        const sky_mat_id = try scene.createMaterial(alloc, .{ .Sky = sky_mat });
        const sky_prop = try scene.createProp(alloc, @intFromEnum(Scene.ShapeID.Canopy), &.{sky_mat_id});

        self.sky = sky_prop;
        self.sun = sun_prop;

        const trafo = Transformation{
            .position = @splat(0.0),
            .scale = @splat(1.0),
            .rotation = math.quaternion.initRotationX(math.degreesToRadians(90.0)),
        };

        scene.propSetWorldTransformation(sky_prop, trafo);

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
        scene.propSetVisibility(self.sky, e.visibleInCamera(), e.visibleInReflection(), e.visibleInShadow());

        const scale = Vec4f{ Radius, Radius, Radius, 1.0 };

        if (scene.propHasAnimatedFrames(self.sun)) {
            self.sun_rotation = scene.propTransformationAt(self.sun, time).rotation;
            scene.propSetFramesScale(self.sun, scale);
        } else {
            const trafo = Transformation{
                .position = @splat(0.0),
                .scale = .{ Radius, Radius, Radius, 1.0 },
                .rotation = math.quaternion.initFromMat3x3(self.sun_rotation),
            };

            scene.propSetWorldTransformation(self.sun, trafo);
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
                return try self.bakeSky(alloc, scene, threads, fs, sky_filename, sun_filename);
            };

            defer stream.deinit();

            const cached_image = try ExrReader.read(alloc, &stream, .XYZ, false);

            var image = scene.imagePtr(scene.propMaterial(self.sky, 0).Sky.emission_map.image);
            image.deinit(alloc);
            image.* = cached_image;
        }

        {
            var stream = fs.readStream(alloc, sun_filename) catch {
                return try self.bakeSky(alloc, scene, threads, fs, sky_filename, sun_filename);
            };

            defer stream.deinit();

            var cached_image = try ExrReader.read(alloc, &stream, .XYZ, false);
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
        var image = &scene.imagePtr(scene.propMaterial(self.sky, 0).Sky.emission_map.image).Float3;

        try image.resize(alloc, img.Description.init2D(Bake_dimensions));

        const sun_direction = self.sun_rotation.r[2];
        var model = Model.init(alloc, sun_direction, self.visibility, self.albedo, fs) catch {
            var y: i32 = 0;
            while (y < Bake_dimensions[1]) : (y += 1) {
                var x: i32 = 0;
                while (x < Bake_dimensions[0]) : (x += 1) {
                    image.set2D(x, y, math.Pack3f.init1(0.0));
                }
            }

            scene.propMaterial(self.sun, 0).Sky.setSunRadianceZero();

            log.err("Could not initialize sky model", .{});
            return;
        };
        defer model.deinit();

        var sun_image = try img.Float3.init(alloc, img.Description.init2D(.{ Bake_dimensions_sun, 1 }));
        defer sun_image.deinit(alloc);

        const n = @as(f32, @floatFromInt(Bake_dimensions_sun - 1));

        var rng = RNG.init(0, 0);

        for (sun_image.pixels, 0..) |*s, i| {
            const v = @as(f32, @floatFromInt(i)) / n;
            var wi = sunWi(self.sun_rotation, v);
            wi[1] = math.max(wi[1], 0.0);

            s.* = math.vec4fTo3f(model.evaluateSkyAndSun(wi, &rng));
        }

        scene.propMaterial(self.sun, 0).Sky.setSunRadiance(self.sun_rotation, sun_image);

        var context = SkyContext{
            .model = &model,
            .shape = scene.propShape(self.sky),
            .image = image,
            .trafo = scene.propTransformationAtMaybeStatic(self.sky, 0, true),
        };

        threads.runParallel(&context, SkyContext.bakeSky, 0);

        const ew = ExrWriter{ .half = false };

        {
            var file = try std.fs.cwd().createFile(sky_filename, .{});
            defer file.close();

            try ew.write(
                alloc,
                file.writer(),
                .{ .Float3 = image.* },
                .{ 0, 0, Bake_dimensions[0], Bake_dimensions[1] },
                .Color,
                threads,
            );
        }

        {
            var file = try std.fs.cwd().createFile(sun_filename, .{});
            defer file.close();

            try ew.write(
                alloc,
                file.writer(),
                .{ .Float3 = sun_image },
                .{ 0, 0, Bake_dimensions_sun, 1 },
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
    trafo: ComposedTransformation,
    current: u32 = 0,

    pub fn bakeSky(context: Threads.Context, id: u32) void {
        _ = id;

        const self = @as(*SkyContext, @ptrCast(@alignCast(context)));

        var rng = RNG{};

        const idf = @as(Vec2f, @splat(1.0)) / math.vec2iTo2f(Sky.Bake_dimensions);

        while (true) {
            const y = @atomicRmw(u32, &self.current, .Add, 1, .Monotonic);
            if (y >= Sky.Bake_dimensions[1]) {
                return;
            }

            const v = idf[1] * (@as(f32, @floatFromInt(y)) + 0.5);

            var x: u32 = 0;
            while (x < Sky.Bake_dimensions[0]) : (x += 1) {
                rng.start(0, @as(u64, @intCast(y * Sky.Bake_dimensions[0] + x)));

                const u = idf[0] * (@as(f32, @floatFromInt(x)) + 0.5);
                const uv = Vec2f{ u, v };
                const wi = clippedCanopyMapping(self.trafo, uv, 1.5 * idf[0]);

                const li = self.model.evaluateSky(math.normalize3(wi), &rng);

                self.image.set2D(@as(i32, @intCast(x)), @as(i32, @intCast(y)), math.vec4fTo3f(li));
            }
        }
    }

    fn clippedCanopyMapping(trafo: ComposedTransformation, uv: Vec2f, e: f32) Vec4f {
        var disk = Vec2f{ 2.0 * uv[0] - 1.0, 2.0 * uv[1] - 1.0 };

        const l = math.length2(disk);
        if (l >= 1.0 - e) {
            disk /= @splat(l + e);
        }

        const dir = Canopy.diskToHemisphereEquidistant(disk);

        return trafo.rotation.transformVector(dir);
    }
};
