const base = @import("base");
const math = base.math;

const Vec4f = math.Vec4f;

pub const Value = struct {
    pub const Class = enum(u32) { Depth, MaterialId };

    slots: u32,

    values: [2]Vecf4 = undefined,
};

pub const Factory = struct {
    slots: u32 = 0,

    pub fn create(self: Factory) Value {
        return .{ .slots = self.slots };
    }
};
