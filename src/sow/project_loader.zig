const prj = @import("project.zig");
const Project = prj.Project;
const Prototype = prj.Prototype;

const core = @import("core");
const ReadStream = core.file.ReadStream;

const base = @import("base");
const json = base.json;
const math = base.math;
const Vec2f = math.Vec2f;
const Transformation = math.Transformation;

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
        if (std.mem.eql(u8, "mount_folder", entry.key_ptr.*)) {
            project.mount_folder = try alloc.dupe(u8, json.readString(entry.value_ptr.*));
        } else if (std.mem.eql(u8, "depth_offset_range", entry.key_ptr.*)) {
            project.depth_offset_range = json.readVec2f(entry.value_ptr.*);
        } else if (std.mem.eql(u8, "density", entry.key_ptr.*)) {
            project.density = json.readFloat(f32, entry.value_ptr.*);
        } else if (std.mem.eql(u8, "align_to_normal", entry.key_ptr.*)) {
            project.align_to_normal = json.readBool(entry.value_ptr.*);
        } else if (std.mem.eql(u8, "tileable", entry.key_ptr.*)) {
            project.tileable = json.readBool(entry.value_ptr.*);
        } else if (std.mem.eql(u8, "triplanar", entry.key_ptr.*)) {
            project.triplanar = json.readBool(entry.value_ptr.*);
        } else if (std.mem.eql(u8, "materials", entry.key_ptr.*)) {
            try std.json.stringify(entry.value_ptr.*, .{ .whitespace = .indent_4 }, project.materials.writer(alloc));
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
    var trafo = Transformation.Identity;
    var position_jitter: Vec2f = @splat(0.0);
    var incline_jitter: Vec2f = @splat(0.0);
    var scale_range: Vec2f = @splat(1.0);

    prototype.shape_type = &.{};
    prototype.shape_file = &.{};

    var iter = value.object.iterator();
    while (iter.next()) |entry| {
        if (std.mem.eql(u8, "shape", entry.key_ptr.*)) {
            prototype.shape_type = try alloc.dupe(u8, json.readStringMember(entry.value_ptr.*, "type", ""));
            prototype.shape_file = try alloc.dupe(u8, json.readStringMember(entry.value_ptr.*, "file", ""));
        } else if (std.mem.eql(u8, "materials", entry.key_ptr.*)) {
            const mat_array = entry.value_ptr.array;
            prototype.materials = try alloc.alloc([]u8, mat_array.items.len);

            for (mat_array.items, 0..) |material, i| {
                prototype.materials[i] = try alloc.dupe(u8, material.string);
            }
        } else if (std.mem.eql(u8, "transformation", entry.key_ptr.*)) {
            json.readTransformation(entry.value_ptr.*, &trafo);
        } else if (std.mem.eql(u8, "position_jitter", entry.key_ptr.*)) {
            position_jitter = json.readVec2f(entry.value_ptr.*);
        } else if (std.mem.eql(u8, "incline_jitter", entry.key_ptr.*)) {
            incline_jitter = json.readVec2f(entry.value_ptr.*);
        } else if (std.mem.eql(u8, "scale_range", entry.key_ptr.*)) {
            scale_range = json.readVec2f(entry.value_ptr.*);
        } else if (std.mem.eql(u8, "weight", entry.key_ptr.*)) {
            w = json.readFloat(f32, entry.value_ptr.*);
        }
    }

    prototype.trafo = trafo;
    prototype.position_jitter = position_jitter;
    prototype.incline_jitter = incline_jitter;
    prototype.scale_range = scale_range;

    weight.* = w;
}
