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
const TriangleMesh = @import("scene/shape/triangle/triangle_mesh.zig").Mesh;
const TriangleBvh = @import("scene/shape/triangle/triangle_tree.zig").Tree;
const Texture = @import("image/texture/texture.zig").Texture;
const SamplerKey = @import("image/texture/texture_sampler.zig").Key;
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
    testType(Renderstate, "Renderstate", 240);
    testType(Fragment, "Fragment", 208);
    testType(Vertex, "Vertex", 416);
    testType(smpl.To, "SampleTo", 64);
    testType(smpl.From, "SampleFrom", 144);
    testType(BvhNode, "BvhNode", 32);
    testType(LightNode, "LightNode", 32);
    testType(mdm.Medium, "Medium", 16);
    testType(mdm.Stack, "MediumStack", 208);
    testType(mt.Material, "Material", 352);
    testType(mt.Substitute, "SubstituteMaterial", 336);
    testType(mt.Hair, "HairMaterial", 112);
    testType(mt.Sample, "MaterialSample", 288);
    testType(mtsmpl.Substitute, "SubstituteSample", 240);
    testType(mtsmpl.Hair, "HairSample", 272);
    testType(Texture, "Texture", 16);
    testType(SamplerKey, "SamplerKey", 3);
    testType(TriangleMesh, "TriangleMesh", 80);
    testType(TriangleBvh, "TriangleBvh", 56);
    testType(Worker, "Worker", 352);
}

fn testType(comptime T: type, name: []const u8, expected: usize) void {
    const measured = @sizeOf(T);
    const ao = @alignOf(T);

    if (measured != expected) {
        std.debug.print("alarm: ", .{});
    }

    std.debug.print("{s}: {} ({}); {}\n", .{ name, measured, expected, ao });
}
