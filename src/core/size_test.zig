const ComposedTransformation = @import("scene/composed_transformation.zig").ComposedTransformation;
const Light = @import("scene/light/light.zig").Light;
const BvhNode = @import("scene/bvh/node.zig").Node;
const LightNode = @import("scene/light/light_tree.zig").Node;
const mt = @import("scene/material/material.zig");
const mtsmpl = @import("scene/material/material_sample.zig");
const mdm = @import("scene/prop/medium.zig");
const Fragment = @import("scene/shape/intersection.zig").Fragment;
const smpl = @import("scene/shape/sample.zig");
const Renderstate = @import("scene/renderstate.zig").Renderstate;
const Vertex = @import("scene/vertex.zig").Vertex;
const Shape = @import("scene/shape/shape.zig").Shape;
const TriangleMesh = @import("scene/shape/triangle/triangle_mesh.zig").Mesh;
const TriangleBvh = @import("scene/shape/triangle/triangle_tree.zig").Tree;
const TriangleMotionMesh = @import("scene/shape/triangle/triangle_motion_mesh.zig").MotionMesh;
const Texture = @import("texture/texture.zig").Texture;
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
    testType(math.Ray, "Ray", 64);
    testType(math.Distribution1D, "Distribution1D", 32);
    testType(ComposedTransformation, "ComposedTransformation", 64);
    testType(Light, "Light", 16);
    testType(Renderstate, "Renderstate", 224);
    testType(Fragment, "Fragment", 224);
    testType(Vertex, "Vertex", 672);
    testType(smpl.To, "SampleTo", 64);
    testType(smpl.From, "SampleFrom", 144);
    testType(BvhNode, "BvhNode", 32);
    testType(LightNode, "LightNode", 32);
    testType(mdm.Medium, "Medium", 80);
    testType(mdm.Stack, "MediumStack", 464);
    testType(mt.Material, "Material", 368);
    testType(mt.Substitute, "SubstituteMaterial", 352);
    testType(mt.Hair, "HairMaterial", 112);
    testType(mt.Sample, "MaterialSample", 288);
    testType(mtsmpl.Substitute, "SubstituteSample", 256);
    testType(mtsmpl.Hair, "HairSample", 272);
    testType(Texture, "Texture", 16);
    testType(Shape, "Shape", 104);
    testType(TriangleMesh, "TriangleMesh", 88);
    testType(TriangleMotionMesh, "TriangleMotionMesh", 96);
    testType(TriangleBvh, "TriangleBvh", 64);
    testType(Worker, "Worker", 368);
}

fn testType(comptime T: type, name: []const u8, expected: usize) void {
    const measured = @sizeOf(T);
    const ao = @alignOf(T);

    if (measured != expected) {
        std.debug.print("alarm: ", .{});
    }

    std.debug.print("{s}: {} ({}); {}\n", .{ name, measured, expected, ao });
}
