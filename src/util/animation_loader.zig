const Graph = @import("scene_graph.zig").Graph;
const Keyframe = @import("animation.zig").Keyframe;

const Scene = @import("core").scn.Scene;

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
    parent_trafo: ?Transformation,
    graph: *Graph,
) !u32 {
    const start_time: u64 = 0;

    const fps = json.readFloatMember(value, "frames_per_second", 0.0);
    const frame_step = if (fps > 0.0) @as(u64, @intFromFloat(@round(@as(f64, @floatFromInt(Scene.UnitsPerSecond)) / fps))) else 0;

    if (value.object.get("keyframes")) |keyframes| {
        return loadKeyframes(
            alloc,
            keyframes,
            default_trafo,
            parent_trafo,
            start_time,
            frame_step,
            graph,
        );
    } else {
        return loadTransformationsAndTimes(
            alloc,
            value.object.get("transformations"),
            value.object.get("times"),
            default_trafo,
            parent_trafo,
            start_time,
            frame_step,
            graph,
        );
    }

    return Graph.Null;
}

pub fn loadKeyframes(
    alloc: Allocator,
    value: std.json.Value,
    default_trafo: Transformation,
    parent_trafo: ?Transformation,
    start_time: u64,
    frame_step: u64,
    graph: *Graph,
) !u32 {
    return switch (value) {
        .array => |array| {
            const animation = try graph.createAnimation(alloc, @intCast(array.items.len));

            var current_time = start_time;

            for (array.items, 0..) |n, i| {
                var keyframe = Keyframe{ .k = default_trafo, .time = current_time };

                var iter = n.object.iterator();
                while (iter.next()) |entry| {
                    if (std.mem.eql(u8, "time", entry.key_ptr.*)) {
                        keyframe.time = Scene.absoluteTime(json.readFloat(f64, entry.value_ptr.*));
                    } else if (std.mem.eql(u8, "transformation", entry.key_ptr.*)) {
                        json.readTransformation(entry.value_ptr.*, &keyframe.k);
                        if (parent_trafo) |pt| {
                            keyframe.k = pt.transform(keyframe.k);
                        }
                    }
                }

                graph.animationSetFrame(animation, i, keyframe);

                current_time += frame_step;
            }

            return animation;
        },
        else => Graph.Null,
    };
}

pub fn loadTransformationsAndTimes(
    alloc: Allocator,
    trafos_value: ?std.json.Value,
    times_value: ?std.json.Value,
    default_trafo: Transformation,
    parent_trafo: ?Transformation,
    start_time: u64,
    frame_step: u64,
    graph: *Graph,
) !u32 {
    if (null == trafos_value) {
        return Graph.Null;
    }

    const trafos = trafos_value.?.array.items;

    const animation = try graph.createAnimation(alloc, @intCast(trafos.len));

    var current_time = start_time;

    for (trafos, 0..) |trafo, i| {
        var keyframe = Keyframe{ .k = default_trafo, .time = current_time };

        if (times_value) |times| {
            if (i < times.array.items.len) {
                keyframe.time = Scene.absoluteTime(json.readFloat(f64, times.array.items[i]));
            }
        }

        json.readTransformation(trafo, &keyframe.k);
        if (parent_trafo) |pt| {
            keyframe.k = pt.transform(keyframe.k);
        }

        graph.animationSetFrame(animation, i, keyframe);

        current_time += frame_step;
    }

    return animation;
}
