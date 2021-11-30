const Prop = @import("../scene/prop/prop.zig").Prop;
const Scene = @import("../scene/scene.zig").Scene;

const base = @import("base");
const json = base.json;
const math = base.math;
const Mat3x3 = math.Mat3x3;
const Transformation = math.Transformation;

const std = @import("std");

pub const Sky = struct {
    prop: u32,

    sky: u32 = Prop.Null,
    sun: u32 = Prop.Null,

    sun_rotation: Mat3x3 = Mat3x3.init9(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0),

    const Angular_radius: f32 = math.degreesToRadians(0.5 * 0.5334);
    const Radius: f32 = std.math.tan(Angular_radius);

    const Self = @This();

    pub fn configure(self: *Self, sky: u32, sun: u32, scene: *Scene) void {
        self.sky = sky;
        self.sun = sun;

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

    fn privateUpadate(self: *Self, scene: *Scene) void {
        const trafo = Transformation{
            .position = @splat(4, @as(f32, 0.0)),
            .scale = .{ Radius, Radius, Radius, 1.0 },
            .rotation = math.quaternion.initFromMat3x3(self.sun_rotation),
        };

        scene.propSetWorldTransformation(self.sun, trafo);
    }
};
