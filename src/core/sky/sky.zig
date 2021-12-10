const Model = @import("model.zig").Model;
const Prop = @import("../scene/prop/prop.zig").Prop;
const Scene = @import("../scene/scene.zig").Scene;
const Shape = @import("../scene/shape/shape.zig").Shape;
const Canopy = @import("../scene/shape/canopy.zig").Canopy;
const Worker = @import("../scene/worker.zig").Worker;
const ComposedTransformation = @import("../scene/composed_transformation.zig").ComposedTransformation;
const img = @import("../image/image.zig");
const Image = img.Image;
const PngWriter = @import("../image/encoding/png/writer.zig").Writer;

const base = @import("base");
const json = base.json;
const math = base.math;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const Mat3x3 = math.Mat3x3;
const Transformation = math.Transformation;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Sky = struct {
    prop: u32,

    sky: u32 = Prop.Null,
    sun: u32 = Prop.Null,

    sky_image: u32 = Prop.Null,

    sun_rotation: Mat3x3 = Mat3x3.init9(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0),

    visibility: f32 = 100.0,

    implicit_rotation: bool = true,

    const Radius = std.math.tan(@as(f32, Model.Angular_radius));

    pub const Bake_dimensions = Vec2i{ 256, 256 };

    const Self = @This();

    pub fn init() !Sky {
        return Sky{ .model = try Model.init() };
    }

    pub fn configure(self: *Self, sky: u32, sun: u32, sky_image: u32, scene: *Scene) void {
        self.sky = sky;
        self.sun = sun;
        self.sky_image = sky_image;

        const trafo = Transformation{
            .position = @splat(4, @as(f32, 0.0)),
            .scale = @splat(4, @as(f32, 1.0)),
            .rotation = math.quaternion.initRotationX(math.degreesToRadians(90.0)),
        };

        scene.propSetWorldTransformation(sky, trafo);
    }

    pub fn setParameters(self: *Self, value: std.json.Value, scene: *Scene) void {
        self.implicit_rotation = true;

        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "sun", entry.key_ptr.*)) {
                const angles = json.readVec4f3Member(entry.value_ptr.*, "rotation", @splat(4, @as(f32, 0.0)));
                self.sun_rotation = json.createRotationMatrix(angles);
                self.implicit_rotation = false;
            } else if (std.mem.eql(u8, "turbidity", entry.key_ptr.*)) {
                self.visibility = Model.turbidityToVisibility(json.readFloat(f32, entry.value_ptr.*));
            } else if (std.mem.eql(u8, "visibility", entry.key_ptr.*)) {
                self.visibility = json.readFloat(f32, entry.value_ptr.*);
            }
        }

        self.privateUpadate(scene);
    }

    pub fn sunDirection(self: Self) Vec4f {
        return self.sun_rotation.r[2];
    }

    pub fn compile(
        self: *Self,
        alloc: *Allocator,
        time: u64,
        scene: *Scene,
        threads: *Threads,
    ) void {
        const e = scene.prop(self.prop);

        scene.propSetVisibility(self.sky, e.visibleInCamera(), e.visibleInReflection(), e.visibleInShadow());
        scene.propSetVisibility(self.sun, e.visibleInCamera(), e.visibleInReflection(), e.visibleInShadow());

        if (self.implicit_rotation) {
            self.sun_rotation = scene.propTransformationAt(self.prop, time).rotation;
            self.privateUpadate(scene);
        }

        var model = Model.init(alloc, self.sunDirection(), self.visibility) catch {
            std.debug.print("Could not initialize sky model\n", .{});
            return;
        };
        defer model.deinit();

        scene.propMaterialRef(self.sun, 0).Sky.setSunRadiance(model);

        var context = SkyContext{
            .model = &model,
            .shape = scene.propShapeRef(self.sky),
            .image = scene.imageRef(self.sky_image),
            .trafo = scene.propTransformationAtMaybeStatic(self.sky, 0, true),
        };

        _ = threads.runRange(&context, SkyContext.bakeSky, 0, @intCast(u32, Bake_dimensions[1]));

        PngWriter.writeFloat3Scaled(alloc, context.image.Float3, 0.02) catch {};
    }

    pub fn sunWi(self: Self, v: f32) Vec4f {
        const y = (2.0 * v) - 1.0;

        const ls = Vec4f{ 0.0, y * Radius, 0.0, 0.0 };
        const ws = self.sun_rotation.transformVector(ls);

        return math.normalize3(ws - self.sun_rotation.r[2]);
    }

    pub fn sunV(self: Self, wi: Vec4f) f32 {
        const k = wi - self.sun_rotation.r[2];

        const c = math.dot3(self.sun_rotation.r[1], k) / Radius;

        return std.math.max((c + 1.0) * 0.5, 0.0);
    }

    fn privateUpadate(self: *Self, scene: *Scene) void {
        const trafo = Transformation{
            .position = @splat(4, @as(f32, 0.0)),
            .scale = .{ Radius, Radius, Radius, 1.0 },
            .rotation = math.quaternion.initFromMat3x3(self.sun_rotation),
        };

        scene.propSetWorldTransformation(self.sun, trafo);
    }
};

const SkyContext = struct {
    model: *const Model,
    shape: *const Shape,
    image: *Image,
    trafo: ComposedTransformation,

    pub fn bakeSky(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;

        const self = @intToPtr(*SkyContext, context);

        const idf = @splat(2, @as(f32, 1.0)) / math.vec2iTo2f(Sky.Bake_dimensions);

        var y = begin;
        while (y < end) : (y += 1) {
            const v = idf[1] * (@intToFloat(f32, y) + 0.5);

            var x: u32 = 0;
            while (x < Sky.Bake_dimensions[0]) : (x += 1) {
                const u = idf[0] * (@intToFloat(f32, x) + 0.5);
                const uv = Vec2f{ u, v };
                const wi = clippedCanopyMapping(self.trafo, uv, 1.5 * idf[0]);

                const li = self.model.evaluateSky(math.normalize3(wi));

                self.image.Float3.set2D(@intCast(i32, x), @intCast(i32, y), math.vec4fTo3f(li));
            }
        }
    }

    fn clippedCanopyMapping(trafo: ComposedTransformation, uv: Vec2f, e: f32) Vec4f {
        var disk = Vec2f{ 2.0 * uv[0] - 1.0, 2.0 * uv[1] - 1.0 };

        const l = math.length2(disk);
        if (l >= 1.0 - e) {
            disk /= @splat(2, l + e);
        }

        const dir = Canopy.diskToHemisphereEquidistant(disk);

        return trafo.rotation.transformVector(dir);
    }
};
