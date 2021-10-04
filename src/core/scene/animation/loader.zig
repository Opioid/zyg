const Keyframe = @import("animation.zig").Keyframe;
const scn = @import("../constants.zig");
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
    return switch (value) {
        .Array => |array| {
            const animation = try scene.createAnimation(alloc, entity, @intCast(u32, array.items.len));

            for (array.items) |n, i| {
                var keyframe = Keyframe{ .k = default_trafo, .time = 0 };

                var iter = n.Object.iterator();
                while (iter.next()) |entry| {
                    if (std.mem.eql(u8, "time", entry.key_ptr.*)) {
                        keyframe.time = scn.time(json.readFloat(f64, entry.value_ptr.*));
                    } else if (std.mem.eql(u8, "transformation", entry.key_ptr.*)) {
                        json.readTransformation(entry.value_ptr.*, &keyframe.k);
                    }
                }

                scene.animationSetFrame(animation, i, keyframe);
            }

            return true;
        },
        else => false,
    };
}
