const math = @import("math/math.zig");
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

pub fn floatToUnorm8(x: f32) u8 {
    return @intFromFloat(x * 255.0 + 0.5);
}

pub fn unorm8ToFloat(norm: u8) f32 {
    return @as(f32, @floatFromInt(norm)) * (1.0 / 255.0);
}

pub fn floatToSnorm8(x: f32) u8 {
    return @intFromFloat((x + 1.0) * (if (x > 0.0) @as(f32, 127.5) else @as(f32, 128.0)));
}

pub fn snorm8ToFloat(byte: u8) f32 {
    return @as(f32, @floatFromInt(byte)) * (1.0 / 128.0) - 1.0;
}

fn floatToNorm16Type(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .float => u16,
        .vector => |vector| @Vector(vector.len, u16),
        else => unreachable,
    };
}

pub fn floatToUnorm16(x: anytype) floatToNorm16Type(@TypeOf(x)) {
    return switch (@typeInfo(@TypeOf(x))) {
        .float => @intFromFloat(x * 65535.0 + 0.5),
        .vector => |vector| {
            const Type = @Vector(vector.len, f32);
            return @intFromFloat(x * @as(Type, @splat(65535.0)) + @as(Type, @splat(0.5)));
        },
        else => comptime unreachable,
    };
}

fn normToFloatType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .int => f32,
        .vector => |vector| @Vector(vector.len, f32),
        else => unreachable,
    };
}

pub fn unorm16ToFloat(norm: anytype) normToFloatType(@TypeOf(norm)) {
    return switch (@typeInfo(@TypeOf(norm))) {
        .int => @as(f32, @floatFromInt(norm)) * (1.0 / 65535.0),
        .vector => |vector| {
            const Type = @Vector(vector.len, f32);
            return @as(Type, @floatFromInt(norm)) * @as(Type, @splat(1.0 / 65535.0));
        },
        else => comptime unreachable,
    };
}

pub fn floatToSnorm16(x: anytype) floatToNorm16Type(@TypeOf(x)) {
    return switch (@typeInfo(@TypeOf(x))) {
        .float => @intFromFloat((x + 1.0) * (if (x > 0.0) @as(f32, 32767.5) else @as(f32, 32768.0))),
        .vector => |vector| {
            const Type = @Vector(vector.len, f32);
            return @intFromFloat((x + @as(Type, @splat(1.0))) * @select(f32, x > @as(Type, @splat(0.0)), @as(Type, @splat(32767.5)), @as(Type, @splat(32768.0))));
        },
        else => comptime unreachable,
    };
}

pub fn snorm16ToFloat(norm: anytype) normToFloatType(@TypeOf(norm)) {
    return switch (@typeInfo(@TypeOf(norm))) {
        .int => @as(f32, @floatFromInt(norm)) * (1.0 / 32768.0) - 1.0,
        .vector => |vector| {
            const Type = @Vector(vector.len, f32);
            return @as(Type, @floatFromInt(norm)) * @as(Type, @splat(1.0 / 32768.0)) - @as(Type, @splat(1.0));
        },
        else => comptime unreachable,
    };
}

pub fn octEncode(v: Vec4f) Vec2f {
    const inorm: Vec2f = @splat(1.0 / (@abs(v[0]) + @abs(v[1]) + @abs(v[2])));
    const t: Vec2f = @splat(math.max(v[2], 0.0));
    const v2 = Vec2f{ v[0], v[1] };
    return (v2 + @select(f32, v2 > @as(Vec2f, @splat(0.0)), t, -t)) * inorm;
}

pub fn octDecode(o: Vec2f) Vec4f {
    var v = Vec4f{ o[0], o[1], -1.0 + @abs(o[0]) + @abs(o[1]), 0.0 };

    const t = math.max(v[2], 0.0);

    v[0] += if (v[0] > 0.0) -t else t;
    v[1] += if (v[1] > 0.0) -t else t;

    return math.normalize3(v);
}
