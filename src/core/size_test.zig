const ComposedTransformation = @import("scene/composed_transformation.zig").ComposedTransformation;
const Light = @import("scene/light/light.zig").Light;
const BvhNode = @import("scene/bvh/node.zig").Node;
const LightNode = @import("scene/light/light_tree.zig").Node;
const mt = @import("scene/material/material.zig");
const mtsmpl = @import("scene/material/sample.zig");
const intf = @import("scene/prop/interface.zig");
const Intersection = @import("scene/shape/intersection.zig").Intersection;
const smpl = @import("scene/shape/sample.zig");
const Renderstate = @import("scene/renderstate.zig").Renderstate;
const Vertex = @import("scene/vertex.zig").Vertex;
const TriangleMesh = @import("scene/shape/triangle/triangle_mesh.zig").Mesh;
const TriangleBvh = @import("scene/shape/triangle/triangle_tree.zig").Tree;
const Texture = @import("image/texture/texture.zig").Texture;
const Worker = @import("rendering/worker.zig").Worker;

const base = @import("base");
const math = base.math;

const std = @import("std");

pub fn testSize() void {
    std.debug.print("Name: actual size (expected size); alignment\n", .{});

    testType(math.Vec2f, "Vec2f", 8);
    testType(math.Pack3f, "Pack3f", 12);
    testType(math.Vec4f, "Vec4f", 16);
    testType(math.Pack4f, "Pack4f", 16);
    testType(math.Distribution1D, "Distribution1D", 32);
    testType(ComposedTransformation, "ComposedTransformation", 64);
    testType(Light, "Light", 16);
    testType(Renderstate, "Renderstate", 208);
    testType(Intersection, "Intersection", 208);
    testType(Vertex, "Vertex", 480);
    testType(smpl.To, "SampleTo", 128);
    testType(smpl.From, "SampleFrom", 144);
    testType(BvhNode, "BvhNode", 32);
    testType(LightNode, "LightNode", 32);
    testType(intf.Interface, "Interface", 8);
    testType(intf.Stack, "InterfaceStack", 336);
    testType(mt.Material, "Material", 368);
    testType(mt.Substitute, "SubstituteMaterial", 352);
    testType(mt.Hair, "HairMaterial", 224);
    testType(mt.Sample, "MaterialSample", 272);
    testType(mtsmpl.Substitute, "SubstituteSample", 224);
    testType(mtsmpl.Hair, "HairSample", 256);
    testType(Texture, "Texture", 16);
    testType(TriangleMesh, "TriangleMesh", 80);
    testType(TriangleBvh, "TriangleBvh", 56);
    testType(Worker, "Worker", 272);
}

fn testType(comptime T: type, name: []const u8, expected: usize) void {
    const measured = @sizeOf(T);
    const ao = @alignOf(T);

    if (measured != expected) {
        std.debug.print("alarm: ", .{});
    }

    std.debug.print("{s}: {} ({}); {}\n", .{ name, measured, expected, ao });
}
