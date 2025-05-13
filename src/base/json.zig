const math = @import("math/math.zig");
const Vec2u = math.Vec2u;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;
const Transformation = math.Transformation;
const Quaternion = math.Quaternion;
const quaternion = math.quaternion;

const spectrum = @import("spectrum/spectrum.zig");

const std = @import("std");
const Value = std.json.Value;

pub fn readBool(value: Value) bool {
    return switch (value) {
        .bool => |b| b,
        else => false,
    };
}

pub fn readBoolMember(value: Value, name: []const u8, default: bool) bool {
    const member = value.object.get(name) orelse return default;

    return readBool(member);
}

pub fn readFloat(comptime T: type, value: Value) T {
    return switch (value) {
        .integer => |int| @floatFromInt(int),
        .float => |float| @floatCast(float),
        else => 0.0,
    };
}

pub fn readFloatMember(value: Value, name: []const u8, default: f32) f32 {
    const member = value.object.get(name) orelse return default;

    return readFloat(f32, member);
}

pub fn readUInt(value: Value) u32 {
    return @truncate(@as(u64, @bitCast(value.integer)));
}

pub fn readUIntMember(value: Value, name: []const u8, default: u32) u32 {
    const member = value.object.get(name) orelse return default;

    return @truncate(@as(u64, @bitCast(member.integer)));
}

pub fn readInt(value: Value) i32 {
    return @truncate(value.integer);
}

pub fn readUInt64Member(value: Value, name: []const u8, default: u64) u64 {
    const member = value.object.get(name) orelse return default;

    return @bitCast(member.integer);
}

pub fn readVec2f(value: Value) Vec2f {
    return switch (value) {
        .array => |a| .{
            readFloat(f32, a.items[0]),
            readFloat(f32, a.items[1]),
        },
        else => @splat(readFloat(f32, value)),
    };
}

pub fn readVec2u(value: Value) Vec2u {
    return .{
        @truncate(@as(u64, @bitCast(value.array.items[0].integer))),
        @truncate(@as(u64, @bitCast(value.array.items[1].integer))),
    };
}

pub fn readVec2i(value: Value) Vec2i {
    return .{
        @intCast(value.array.items[0].integer),
        @intCast(value.array.items[1].integer),
    };
}

pub fn readVec2fMember(value: Value, name: []const u8, default: Vec2f) Vec2f {
    const member = value.object.get(name) orelse return default;

    return readVec2f(member);
}

pub fn readVec2iMember(value: Value, name: []const u8, default: Vec2i) Vec2i {
    const member = value.object.get(name) orelse return default;

    return .{
        @intCast(member.array.items[0].integer),
        @intCast(member.array.items[1].integer),
    };
}

pub fn readVec4i3Member(value: Value, name: []const u8, default: Vec4i) Vec4i {
    const member = value.object.get(name) orelse return default;

    return .{
        @intCast(member.array.items[0].integer),
        @intCast(member.array.items[1].integer),
        @intCast(member.array.items[2].integer),
        1,
    };
}

pub fn readVec4iMember(value: Value, name: []const u8, default: Vec4i) Vec4i {
    const member = value.object.get(name) orelse return default;

    return .{
        @intCast(member.array.items[0].integer),
        @intCast(member.array.items[1].integer),
        @intCast(member.array.items[2].integer),
        @intCast(member.array.items[3].integer),
    };
}

pub fn readVec4f3(value: Value) Vec4f {
    return switch (value) {
        .array => |a| .{
            readFloat(f32, a.items[0]),
            readFloat(f32, a.items[1]),
            readFloat(f32, a.items[2]),
            0.0,
        },
        else => @splat(readFloat(f32, value)),
    };
}

pub fn readVec4f3Member(value: Value, name: []const u8, default: Vec4f) Vec4f {
    const member = value.object.get(name) orelse return default;

    return readVec4f3(member);
}

pub fn readVec4fMember(value: Value, name: []const u8, default: Vec4f) Vec4f {
    const member = value.object.get(name) orelse return default;

    return .{
        readFloat(f32, member.array.items[0]),
        readFloat(f32, member.array.items[1]),
        readFloat(f32, member.array.items[2]),
        readFloat(f32, member.array.items[3]),
    };
}

pub fn readString(value: Value) []const u8 {
    return value.string;
}

pub fn readStringMember(value: Value, name: []const u8, default: []const u8) []const u8 {
    const member = value.object.get(name) orelse return default;

    return member.string;
}

pub fn createRotationMatrix(xyz: Vec4f) Mat3x3 {
    const rot_x = Mat3x3.initRotationX(math.degreesToRadians(xyz[0]));
    const rot_y = Mat3x3.initRotationY(math.degreesToRadians(xyz[1]));
    const rot_z = Mat3x3.initRotationZ(math.degreesToRadians(xyz[2]));

    return rot_z.mul(rot_x).mul(rot_y);
}

fn readRotationMatrix(value: Value) Mat3x3 {
    const xyz = readVec4f3(value);
    return createRotationMatrix(xyz);
}

fn readRotation(value: Value) Quaternion {
    return quaternion.initFromMat3x3(readRotationMatrix(value));
}

pub fn readTransformation(value: Value, trafo: *Transformation) void {
    switch (value) {
        .object => |object| {
            var up = Vec4f{ 0.0, 1.0, 0.0, 0.0 };
            var look_at = Vec4f{ 0.0, 0.0, 1.0, 0.0 };

            var look = false;

            var iter = object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "position", entry.key_ptr.*)) {
                    trafo.position = readVec4f3(entry.value_ptr.*);
                } else if (std.mem.eql(u8, "scale", entry.key_ptr.*)) {
                    trafo.scale = readVec4f3(entry.value_ptr.*);
                } else if (std.mem.eql(u8, "rotation", entry.key_ptr.*)) {
                    trafo.rotation = readRotation(entry.value_ptr.*);
                } else if (std.mem.eql(u8, "look_at", entry.key_ptr.*)) {
                    look_at = readVec4f3(entry.value_ptr.*);
                    look = true;
                } else if (std.mem.eql(u8, "up", entry.key_ptr.*)) {
                    up = readVec4f3(entry.value_ptr.*);
                }
            }

            if (look) {
                const dir = math.normalize3(look_at - trafo.position);
                const right = -math.cross3(dir, up);

                const r = Mat3x3.init3(right, up, dir);

                trafo.rotation = quaternion.initFromMat3x3(r);
            }
        },
        .array => |array| {
            const m = Mat4x4.init16(
                readFloat(f32, array.items[0]),
                readFloat(f32, array.items[1]),
                readFloat(f32, array.items[2]),
                readFloat(f32, array.items[3]),
                readFloat(f32, array.items[4]),
                readFloat(f32, array.items[5]),
                readFloat(f32, array.items[6]),
                readFloat(f32, array.items[7]),
                readFloat(f32, array.items[8]),
                readFloat(f32, array.items[9]),
                readFloat(f32, array.items[10]),
                readFloat(f32, array.items[11]),
                readFloat(f32, array.items[12]),
                readFloat(f32, array.items[13]),
                readFloat(f32, array.items[14]),
                readFloat(f32, array.items[15]),
            );

            var rotation: Mat3x3 = undefined;
            m.decompose(&rotation, &trafo.scale, &trafo.position);
            trafo.rotation = quaternion.initFromMat3x3(rotation);
        },
        else => return,
    }
}

fn mapColor(color: Vec4f) Vec4f {
    return spectrum.sRGBtoAP1(color);
}

pub fn readColor(value: std.json.Value) Vec4f {
    return switch (value) {
        .array => mapColor(readVec4f3(value)),
        .integer => |i| mapColor(@splat(@floatFromInt(i))),
        .float => |f| mapColor(@splat(@floatCast(f))),
        .object => |o| {
            var rgb: Vec4f = @splat(0.0);
            var linear = true;

            var iter = o.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "sRGB", entry.key_ptr.*)) {
                    rgb = readColor(entry.value_ptr.*);
                } else if (std.mem.eql(u8, "temperature", entry.key_ptr.*)) {
                    const temperature = readFloat(f32, entry.value_ptr.*);
                    rgb = spectrum.blackbody(math.max(800.0, temperature));
                } else if (std.mem.eql(u8, "linear", entry.key_ptr.*)) {
                    linear = readBool(entry.value_ptr.*);
                }
            }

            if (!linear) {
                rgb = spectrum.linearToGamma_sRGB3(rgb);
            }

            return mapColor(rgb);
        },
        else => @splat(0.0),
    };
}
