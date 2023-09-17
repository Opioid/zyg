const Encoding = @import("../../../image/image_writer.zig").Writer.Encoding;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

const std = @import("std");

pub const Value = struct {
    pub const Class = enum(u4) {
        Albedo,
        Depth,
        MaterialId,
        GeometricNormal,
        ShadingNormal,

        pub fn default(class: Class) Vec4f {
            return switch (class) {
                .Depth => @splat(std.math.floatMax(f32)),
                else => @splat(0.0),
            };
        }

        pub fn activeIn(class: Class, slots: u32) bool {
            const bit = @as(u32, 1) << @intFromEnum(class);
            return 0 != (slots & bit);
        }

        pub fn encoding(class: Class) Encoding {
            return switch (class) {
                .Albedo => .Color,
                .Depth => .Depth,
                .MaterialId => .Id,
                .GeometricNormal, .ShadingNormal => .Normal,
            };
        }
    };

    pub const Num_classes = @typeInfo(Class).Enum.fields.len;

    slots: u32,

    values: [Num_classes]Vec4f = undefined,

    pub fn active(self: Value) bool {
        return 0 != self.slots;
    }

    pub fn activeClass(self: Value, class: Class) bool {
        return class.activeIn(self.slots);
    }

    pub fn clear(self: *Value) void {
        if (0 == self.slots) {
            return;
        }

        var i: u4 = 0;
        while (i < Num_classes) : (i += 1) {
            const class = @as(Class, @enumFromInt(i));
            if (self.activeClass(class)) {
                self.values[i] = class.default();
            }
        }
    }

    pub fn insert3(self: *Value, class: Class, value: Vec4f) void {
        self.values[@intFromEnum(class)] = value;
    }

    pub fn insert1(self: *Value, class: Class, value: f32) void {
        self.values[@intFromEnum(class)][0] = value;
    }
};

pub const Factory = struct {
    slots: u32 = 0,

    pub fn create(self: Factory) Value {
        return .{ .slots = self.slots };
    }

    pub fn activeClass(self: Factory, class: Value.Class) bool {
        return class.activeIn(self.slots);
    }

    pub fn set(self: *Factory, class: Value.Class, value: bool) void {
        const bit = @as(u32, 1) << @intFromEnum(class);

        if (value) {
            self.slots |= bit;
        } else {
            self.slots &= ~bit;
        }
    }
};
