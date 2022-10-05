const ComposedTransformation = @import("scene/composed_transformation.zig").ComposedTransformation;
const Light = @import("scene/light/light.zig").Light;
const BvhNode = @import("scene/bvh/node.zig").Node;
const mt = @import("scene/material/material.zig");
const Interface = @import("scene/prop/interface.zig").Interface;
const PropIntersection = @import("scene/prop/intersection.zig").Intersection;
const smpl = @import("scene/shape/sample.zig");
const Texture = @import("image/texture/texture.zig").Texture;

const base = @import("base");
const math = base.math;

const std = @import("std");

pub fn testSize() void {
    std.debug.print("Name: measured size (expected size); align\n", .{});

    testType(math.Vec2f, "Vec2f", 8);
    testType(math.Pack3f, "Pack3f", 12);
    testType(math.Vec4f, "Vec4f", 16);
    testType(math.Pack4f, "Pack4f", 16);
    testType(math.Distribution1D, "Distribution1D", 32);
    testType(ComposedTransformation, "ComposedTransformation", 64);
    testType(Light, "Light", 16);
    //testType(PropIntersection, "PropIntersection", 176);
    //testType(smpl.To, "SampleTo", 112);
    //testType(smpl.From, "SampleFrom", 144);
    testType(BvhNode, "BvhNode", 32);
    testType(Interface, "Interface", 16);
    testType(mt.Material, "Material", 400);
    testType(mt.Substitute, "SubstituteMaterial", 352);
    testType(Texture, "Texture", 16);
}

fn testType(comptime T: type, name: []const u8, expected: usize) void {
    const measured = @sizeOf(T);
    const ao = @alignOf(T);

    if (measured != expected) {
        std.debug.print("alarm: ", .{});
    }

    std.debug.print("{s}: {} ({}); {}\n", .{ name, measured, expected, ao });
}
