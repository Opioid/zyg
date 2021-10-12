const math = @import("math/math.zig");
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Mat3x3 = math.Mat3x3;
const Transformation = math.Transformation;
const Quaternion = math.Quaternion;
const quaternion = math.quaternion;
const std = @import("std");
const Value = std.json.Value;

pub fn readBool(value: Value) bool {
    return switch (value) {
        .Bool => |b| b,
        else => false,
    };
}

pub fn readBoolMember(value: Value, name: []const u8, default: bool) bool {
    const member = value.Object.get(name) orelse return default;

    return readBool(member);
}

pub fn readFloat(comptime T: type, value: Value) T {
    return switch (value) {
        .Integer => |int| @intToFloat(T, int),
        .Float => |float| @floatCast(T, float),
        else => 0.0,
    };
}

pub fn readFloatMember(value: Value, name: []const u8, default: f32) f32 {
    const member = value.Object.get(name) orelse return default;

    return readFloat(f32, member);
}

pub fn readUInt(value: Value) u32 {
    return @intCast(u32, value.Integer);
}

pub fn readUIntMember(value: Value, name: []const u8, default: u32) u32 {
    const member = value.Object.get(name) orelse return default;

    return @intCast(u32, member.Integer);
}

pub fn readUInt64Member(value: Value, name: []const u8, default: u64) u64 {
    const member = value.Object.get(name) orelse return default;

    return @intCast(u64, member.Integer);
}

pub fn readVec2iMember(value: Value, name: []const u8, default: Vec2i) Vec2i {
    const member = value.Object.get(name) orelse return default;

    return .{
        @intCast(i32, member.Array.items[0].Integer),
        @intCast(i32, member.Array.items[1].Integer),
    };
}

pub fn readVec4iMember(value: Value, name: []const u8, default: Vec4i) Vec4i {
    const member = value.Object.get(name) orelse return default;

    return Vec4i.init4(
        @intCast(i32, member.Array.items[0].Integer),
        @intCast(i32, member.Array.items[1].Integer),
        @intCast(i32, member.Array.items[2].Integer),
        @intCast(i32, member.Array.items[3].Integer),
    );
}

pub fn readVec4f3(value: Value) Vec4f {
    return .{
        readFloat(f32, value.Array.items[0]),
        readFloat(f32, value.Array.items[1]),
        readFloat(f32, value.Array.items[2]),
        0.0,
    };
}

pub fn readString(value: Value) []const u8 {
    return value.String;
}

pub fn readStringMember(value: Value, name: []const u8, default: []const u8) []const u8 {
    const member = value.Object.get(name) orelse return default;

    return member.String;
}

fn createRotationMatrix(xyz: Vec4f) Mat3x3 {
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
        .Object => |object| {
            var iter = object.iterator();
            while (iter.next()) |entry| {
                if (std.mem.eql(u8, "position", entry.key_ptr.*)) {
                    trafo.position = readVec4f3(entry.value_ptr.*);
                } else if (std.mem.eql(u8, "scale", entry.key_ptr.*)) {
                    trafo.scale = readVec4f3(entry.value_ptr.*);
                } else if (std.mem.eql(u8, "rotation", entry.key_ptr.*)) {
                    trafo.rotation = readRotation(entry.value_ptr.*);
                }
            }
        },
        else => return,
    }
}
