const prj = @import("project.zig");
const Project = prj.Project;
const Prototype = prj.Prototype;

const core = @import("core");
const ReadStream = core.file.ReadStream;

const base = @import("base");
const json = base.json;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    NoScene,
};

pub fn load(alloc: Allocator, stream: ReadStream, project: *Project) !void {
    const buffer = try stream.readAll(alloc);
    defer alloc.free(buffer);

    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        alloc,
        buffer,
        .{ .duplicate_field_behavior = .use_last },
    );
    defer parsed.deinit();

    const root = parsed.value;

    if (root.object.get("scene")) |scene_filename| {
        project.scene_filename = try alloc.dupe(u8, scene_filename.string);
    }

    if (0 == project.scene_filename.len) {
        return Error.NoScene;
    }

    var iter = root.object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "grid", entry.key_ptr.*)) {
            project.grid = json.readVec2u(entry.value_ptr.*);
        } else if (std.mem.eql(u8, "prototypes", entry.key_ptr.*)) {
            try loadPrototypes(alloc, entry.value_ptr.*, project);
        }
    }
}

fn loadPrototypes(alloc: Allocator, value: std.json.Value, project: *Project) !void {
    const proto_array = value.array;

    project.prototypes = try alloc.alloc(Prototype, proto_array.items.len);

    const weights = try alloc.alloc(f32, proto_array.items.len);
    defer alloc.free(weights);

    for (proto_array.items, project.prototypes, weights) |proto_value, *prototype, *w| {
        try loadPrototye(alloc, proto_value, prototype, w);
    }

    try project.prototype_distribution.configure(alloc, weights, 0);
}

fn loadPrototye(alloc: Allocator, value: std.json.Value, prototype: *Prototype, weight: *f32) !void {
    var w: f32 = 1.0;

    var iter = value.object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "shape", entry.key_ptr.*)) {
            prototype.shape_file = try alloc.dupe(u8, json.readStringMember(entry.value_ptr.*, "file", ""));
        } else if (std.mem.eql(u8, "materials", entry.key_ptr.*)) {
            const mat_array = entry.value_ptr.array;
            prototype.materials = try alloc.alloc([]u8, mat_array.items.len);

            for (mat_array.items, 0..) |material, i| {
                prototype.materials[i] = try alloc.dupe(u8, material.string);
            }
        } else if (std.mem.eql(u8, "weight", entry.key_ptr.*)) {
            w = json.readFloat(f32, entry.value_ptr.*);
        }
    }

    weight.* = w;
}
