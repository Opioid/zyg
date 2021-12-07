const Prop = @import("../scene/prop/prop.zig").Prop;
const Scene = @import("../scene/scene.zig").Scene;
const Shape = @import("../scene/shape/shape.zig").Shape;
const Worker = @import("../scene/worker.zig").Worker;
const img = @import("../image/image.zig");
const Image = img.Image;

const base = @import("base");
const json = base.json;
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4f = math.Vec4f;
const Mat3x3 = math.Mat3x3;
const Transformation = math.Transformation;
const Threads = base.thread.Pool;

const std = @import("std");

pub const Sky = struct {
    prop: u32,

    sky: u32 = Prop.Null,
    sun: u32 = Prop.Null,

    sky_image: u32 = Prop.Null,

    sun_rotation: Mat3x3 = Mat3x3.init9(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0),

    const Angular_radius: f32 = math.degreesToRadians(0.5 * 0.5334);
    const Radius: f32 = std.math.tan(Angular_radius);

    pub const Bake_dimensions = Vec2i{ 256, 256 };

    const Self = @This();

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
        var iter = value.Object.iterator();
        while (iter.next()) |entry| {
            if (std.mem.eql(u8, "sun", entry.key_ptr.*)) {
                const angles = json.readVec4f3Member(entry.value_ptr.*, "rotation", @splat(4, @as(f32, 0.0)));
                self.sun_rotation = json.createRotationMatrix(angles);
            }
        }

        self.privateUpadate(scene);
    }

    pub fn compile(
        self: *Self,
        scene: Scene,
        threads: *Threads,
    ) void {
        var context = SkyContext{
            .shape = scene.propShapeRef(self.sky),
            .image = scene.imageRef(self.sky_image),
        };

        _ = threads.runRange(&context, SkyContext.calculate, 0, @intCast(u32, Bake_dimensions[1]));
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
    shape: *const Shape,
    image: *Image,

    pub fn calculate(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;

        const self = @intToPtr(*SkyContext, context);

        var y = begin;
        while (y < end) : (y += 1) {
            var x: u32 = 0;
            while (x < Sky.Bake_dimensions[0]) : (x += 1) {
                const li = Vec4f{ 0.0, 0.0, 2.0, 0.0 }; //self.texture.get2D_3(@intCast(i32, x), @intCast(i32, y), self.scene.*);

                self.image.Float3.set2D(@intCast(i32, x), @intCast(i32, y), math.vec4fTo3f(li));
            }
        }
    }
};
