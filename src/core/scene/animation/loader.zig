const Scene = @import("../scene.zig").Scene;
const base = @import("base");
const json = base.json;
const math = base.math;
const Transformation = math.Transformation;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn load(
    alloc: *Allocator,
    value: std.json.Value,
    default_trafo: Transformation,
    entity: u32,
    scene: *Scene,
) !bool {
    var iter = value.Object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "keyframes", entry.key_ptr.*)) {
            return loadKeyframes(alloc, entry.value_ptr.*, default_trafo, entity, scene);
        }
    }

    return false;
}

pub fn loadKeyframes(
    alloc: *Allocator,
    value: std.json.Value,
    default_trafo: Transformation,
    entity: u32,
    scene: *Scene,
) !bool {
    _ = alloc;
    _ = default_trafo;

    return switch (value) {
        .Array => |array| {
            const animation = try scene.createAnimation(alloc, entity, @intCast(u32, array.items.len));

            _ = animation;

            return true;
        },
        else => false,
    };

    // if (value.Array) |array| {
    //     const animation = scene.createAnimation(entity, @intCast(u32, array.items.len));

    //     _ = animation;

    //     return true;
    // }

    // return false;
}
