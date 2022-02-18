const core = @import("core");
const scn = core.scn;
const Keyframe = scn.Keyframe;
const Scene = scn.Scene;

const base = @import("base");
const json = base.json;
const math = base.math;
const Transformation = math.Transformation;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn load(
    alloc: Allocator,
    value: std.json.Value,
    default_trafo: Transformation,
    entity: u32,
    scene: *Scene,
) !bool {
    var start_time: u64 = 0;
    var frame_step: u64 = 0;

    var iter = value.Object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "frames_per_second", entry.key_ptr.*)) {
            const fps = json.readFloat(f64, entry.value_ptr.*);
            if (fps > 0.0) {
                frame_step = @floatToInt(u64, @round(@intToFloat(f64, scn.cnst.Units_per_second) / fps));
            }
        } else if (std.mem.eql(u8, "keyframes", entry.key_ptr.*)) {
            return loadKeyframes(
                alloc,
                entry.value_ptr.*,
                default_trafo,
                entity,
                start_time,
                frame_step,
                scene,
            );
        }
    }

    return false;
}

pub fn loadKeyframes(
    alloc: Allocator,
    value: std.json.Value,
    default_trafo: Transformation,
    entity: u32,
    start_time: u64,
    frame_step: u64,
    scene: *Scene,
) !bool {
    return switch (value) {
        .Array => |array| {
            const animation = try scene.createAnimation(alloc, entity, @intCast(u32, array.items.len));

            var current_time = start_time;

            for (array.items) |n, i| {
                var keyframe = Keyframe{ .k = default_trafo, .time = current_time };

                var iter = n.Object.iterator();
                while (iter.next()) |entry| {
                    if (std.mem.eql(u8, "time", entry.key_ptr.*)) {
                        keyframe.time = scn.cnst.time(json.readFloat(f64, entry.value_ptr.*));
                    } else if (std.mem.eql(u8, "transformation", entry.key_ptr.*)) {
                        json.readTransformation(entry.value_ptr.*, &keyframe.k);
                    }
                }

                scene.animationSetFrame(animation, i, keyframe);

                current_time += frame_step;
            }

            return true;
        },
        else => false,
    };
}
