const Model = @import("model.zig").Model;
const JsonWriter = @import("model_json_writer.zig");
const SubWriter = @import("model_sub_writer.zig");

const core = @import("core");
const resource = core.resource;
const Resources = resource.Manager;

const base = @import("base");
const json = base.json;
const math = base.math;
const Vec2f = math.Vec2f;
const Pack3f = math.Pack3f;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub fn merge(alloc: Allocator, resources: *Resources) !bool {
    var model = Model{};
    defer model.deinit(alloc);

    const first_name = "models/wiggle/wiggle_000.json.gz";

    try readInit(alloc, first_name, &model, resources);

    var buf: [64]u8 = undefined;

    for (1..100) |f| {
        const filename = try std.fmt.bufPrint(
            &buf,
            "models/wiggle/wiggle_{d:0>3}.json.gz",
            .{f},
        );

        try readAcum(alloc, filename, &model, resources);
    }

    for (100..160) |f| {
        const filename = try std.fmt.bufPrint(
            &buf,
            "models/wiggle/wiggle_{d:0>3}.json",
            .{f},
        );

        try readAcum(alloc, filename, &model, resources);
    }

    for (160..211) |f| {
        const filename = try std.fmt.bufPrint(
            &buf,
            "models/wiggle/wiggle_{d:0>3}.json.gz",
            .{f},
        );

        try readAcum(alloc, filename, &model, resources);
    }

    const fps = 30;
    model.frame_duration = @intFromFloat(@round(@as(f64, @floatFromInt(core.scene.Scene.UnitsPerSecond)) / fps));

    try JsonWriter.write(alloc, "../data/models/wiggle/wiggle.json", &model);
    try SubWriter.write(alloc, "../data/models/wiggle/wiggle.sub", &model);

    return true;
}

fn readInit(alloc: Allocator, name: []const u8, model: *Model, resources: *Resources) !void {
    var stream = try resources.fs.readStream(alloc, name);
    defer stream.deinit();

    const buffer = try stream.readAll(alloc);
    defer alloc.free(buffer);

    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, buffer, .{});
    defer parsed.deinit();

    const root = parsed.value;

    if (root.object.get("geometry")) |value| {
        try loadInitGeometry(alloc, model, value);
    }
}

fn loadInitGeometry(alloc: Allocator, model: *Model, value: std.json.Value) !void {
    var iter = value.object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "parts", entry.key_ptr.*)) {
            const parts = entry.value_ptr.array.items;

            model.parts = try alloc.alloc(Model.Part, parts.len);

            for (parts, 0..) |p, i| {
                const start_index = json.readUIntMember(p, "start_index", 0);
                const num_indices = json.readUIntMember(p, "num_indices", 0);
                const material_index = json.readUIntMember(p, "material_index", 0);
                model.parts[i] = .{
                    .start_index = start_index,
                    .num_indices = num_indices,
                    .material_index = material_index,
                };
            }
        } else if (std.mem.eql(u8, "vertices", entry.key_ptr.*)) {
            var viter = entry.value_ptr.object.iterator();
            while (viter.next()) |ventry| {
                if (std.mem.eql(u8, "positions", ventry.key_ptr.*)) {
                    const position_items = ventry.value_ptr.array.items;

                    switch (position_items[0]) {
                        .array => {
                            const position_samples = position_items;
                            const num_frames = position_samples.len;

                            model.positions = try List([]Pack3f).initCapacity(alloc, num_frames);
                            try model.positions.resize(alloc, num_frames);

                            for (position_samples, 0..) |frame, f| {
                                const positions = frame.array.items;
                                const num_positions = positions.len / 3;

                                const dest_positions = try alloc.alloc(Pack3f, num_positions);

                                for (dest_positions, 0..) |*p, i| {
                                    p.* = Pack3f.init3(
                                        json.readFloat(f32, positions[i * 3 + 0]),
                                        json.readFloat(f32, positions[i * 3 + 1]),
                                        json.readFloat(f32, positions[i * 3 + 2]),
                                    );
                                }

                                model.positions.items[f] = dest_positions;
                            }
                        },
                        .integer, .float => {
                            const positions = position_items;
                            const num_positions = positions.len / 3;

                            const dest_positions = try alloc.alloc(Pack3f, num_positions);

                            for (dest_positions, 0..) |*p, i| {
                                p.* = Pack3f.init3(
                                    json.readFloat(f32, positions[i * 3 + 0]),
                                    json.readFloat(f32, positions[i * 3 + 1]),
                                    json.readFloat(f32, positions[i * 3 + 2]),
                                );
                            }

                            model.positions = try List([]Pack3f).initCapacity(alloc, 1);
                            model.positions.appendAssumeCapacity(dest_positions);
                        },
                        else => {},
                    }
                } else if (std.mem.eql(u8, "normals", ventry.key_ptr.*)) {
                    const normal_items = ventry.value_ptr.array.items;

                    switch (normal_items[0]) {
                        .array => {
                            const normal_samples = normal_items;
                            const num_frames = normal_samples.len;

                            model.normals = try List([]Pack3f).initCapacity(alloc, num_frames);
                            try model.normals.resize(alloc, num_frames);

                            for (normal_samples, 0..) |frame, f| {
                                const normals = frame.array.items;
                                const num_normals = normals.len / 3;

                                const dest_normals = try alloc.alloc(Pack3f, num_normals);

                                for (dest_normals, 0..) |*n, i| {
                                    n.* = Pack3f.init3(
                                        json.readFloat(f32, normals[i * 3 + 0]),
                                        json.readFloat(f32, normals[i * 3 + 1]),
                                        json.readFloat(f32, normals[i * 3 + 2]),
                                    );
                                }

                                model.normals.items[f] = dest_normals;
                            }
                        },
                        .integer, .float => {
                            const normals = normal_items;
                            const num_normals = normals.len / 3;

                            const dest_normals = try alloc.alloc(Pack3f, num_normals);

                            for (dest_normals, 0..) |*n, i| {
                                n.* = Pack3f.init3(
                                    json.readFloat(f32, normals[i * 3 + 0]),
                                    json.readFloat(f32, normals[i * 3 + 1]),
                                    json.readFloat(f32, normals[i * 3 + 2]),
                                );
                            }

                            model.normals = try List([]Pack3f).initCapacity(alloc, 1);
                            model.normals.appendAssumeCapacity(dest_normals);
                        },
                        else => {},
                    }
                } else if (std.mem.eql(u8, "texture_coordinates_0", ventry.key_ptr.*)) {
                    const uvs = ventry.value_ptr.array.items;
                    const num_uvs = uvs.len / 2;

                    model.uvs = try alloc.alloc(Vec2f, num_uvs);

                    for (model.uvs, 0..) |*uv, i| {
                        uv.* = .{
                            json.readFloat(f32, uvs[i * 2 + 0]),
                            json.readFloat(f32, uvs[i * 2 + 1]),
                        };
                    }
                }
            }
        } else if (std.mem.eql(u8, "indices", entry.key_ptr.*)) {
            const indices = entry.value_ptr.array.items;

            model.indices = try alloc.alloc(u32, indices.len);

            for (model.indices, indices) |*index, source_index| {
                index.* = @intCast(source_index.integer);
            }
        }
    }
}

fn readAcum(alloc: Allocator, name: []const u8, model: *Model, resources: *Resources) !void {
    var stream = resources.fs.readStream(alloc, name) catch |e| {
        std.debug.print("Can't read {s}: {}\n", .{ name, e });
        return e;
    };

    defer stream.deinit();

    const buffer = try stream.readAll(alloc);
    defer alloc.free(buffer);

    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, buffer, .{});
    defer parsed.deinit();

    const root = parsed.value;

    if (root.object.get("geometry")) |value| {
        try loadAcumGeometry(alloc, model, value);
    }
}

fn loadAcumGeometry(alloc: Allocator, model: *Model, value: std.json.Value) !void {
    var iter = value.object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "vertices", entry.key_ptr.*)) {
            var viter = entry.value_ptr.object.iterator();
            while (viter.next()) |ventry| {
                if (std.mem.eql(u8, "positions", ventry.key_ptr.*)) {
                    const position_items = ventry.value_ptr.array.items;

                    switch (position_items[0]) {
                        .array => {
                            const position_samples = position_items;

                            for (position_samples) |frame| {
                                const positions = frame.array.items;
                                const num_positions = positions.len / 3;

                                const dest_positions = try alloc.alloc(Pack3f, num_positions);

                                for (dest_positions, 0..) |*p, i| {
                                    p.* = Pack3f.init3(
                                        json.readFloat(f32, positions[i * 3 + 0]),
                                        json.readFloat(f32, positions[i * 3 + 1]),
                                        json.readFloat(f32, positions[i * 3 + 2]),
                                    );
                                }

                                try model.positions.append(alloc, dest_positions);
                            }
                        },
                        .integer, .float => {
                            const positions = position_items;
                            const num_positions = positions.len / 3;

                            const dest_positions = try alloc.alloc(Pack3f, num_positions);

                            for (dest_positions, 0..) |*p, i| {
                                p.* = Pack3f.init3(
                                    json.readFloat(f32, positions[i * 3 + 0]),
                                    json.readFloat(f32, positions[i * 3 + 1]),
                                    json.readFloat(f32, positions[i * 3 + 2]),
                                );
                            }

                            try model.positions.append(alloc, dest_positions);
                        },
                        else => {},
                    }
                } else if (std.mem.eql(u8, "normals", ventry.key_ptr.*)) {
                    const normal_items = ventry.value_ptr.array.items;

                    switch (normal_items[0]) {
                        .array => {
                            const normal_samples = normal_items;

                            for (normal_samples) |frame| {
                                const normals = frame.array.items;
                                const num_normals = normals.len / 3;

                                const dest_normals = try alloc.alloc(Pack3f, num_normals);

                                for (dest_normals, 0..) |*n, i| {
                                    n.* = Pack3f.init3(
                                        json.readFloat(f32, normals[i * 3 + 0]),
                                        json.readFloat(f32, normals[i * 3 + 1]),
                                        json.readFloat(f32, normals[i * 3 + 2]),
                                    );
                                }

                                try model.normals.append(alloc, dest_normals);
                            }
                        },
                        .integer, .float => {
                            const normals = normal_items;
                            const num_normals = normals.len / 3;

                            const dest_normals = try alloc.alloc(Pack3f, num_normals);

                            for (dest_normals, 0..) |*n, i| {
                                n.* = Pack3f.init3(
                                    json.readFloat(f32, normals[i * 3 + 0]),
                                    json.readFloat(f32, normals[i * 3 + 1]),
                                    json.readFloat(f32, normals[i * 3 + 2]),
                                );
                            }

                            try model.normals.append(alloc, dest_normals);
                        },
                        else => {},
                    }
                }
            }
        }
    }
}
