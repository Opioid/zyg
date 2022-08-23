const Intersection = @import("intersection.zig").Intersection;
const Scene = @import("../scene.zig").Scene;
const Light = @import("../light/light.zig").Light;
const Material = @import("../material/material.zig").Material;

const math = @import("base").math;
const Vec2f = math.Vec2f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Interface = struct {
    prop: u32,
    part: u32,
    uv: Vec2f,

    pub fn material(self: Interface, scene: *const Scene) *const Material {
        return scene.propMaterial(self.prop, self.part);
    }

    pub fn matches(self: Interface, isec: *const Intersection) bool {
        return self.prop == isec.prop and self.part == isec.geo.part;
    }
};

pub const Stack = struct {
    const Num_entries = 16;

    index: u32 = 0,
    stack: [Num_entries]Interface = undefined,

    pub fn copy(self: *Stack, other: *const Stack) void {
        const index = other.index;
        self.index = index;
        std.mem.copy(Interface, self.stack[0..index], other.stack[0..index]);
    }

    pub fn empty(self: *const Stack) bool {
        return 0 == self.index;
    }

    pub fn clear(self: *Stack) void {
        self.index = 0;
    }

    pub fn top(self: *const Stack) Interface {
        return self.stack[self.index - 1];
    }

    pub fn topIor(self: *const Stack, scene: *const Scene) f32 {
        const index = self.index;
        if (index > 0) {
            return self.stack[index - 1].material(scene).ior();
        }

        return 1.0;
    }

    pub fn nextToBottomIor(self: *const Stack, scene: *const Scene) f32 {
        const index = self.index;
        if (index > 1) {
            return self.stack[1].material(scene).ior();
        }

        return 1.0;
    }

    pub fn peekIor(self: *const Stack, isec: *const Intersection, scene: *const Scene) f32 {
        const index = self.index;
        if (index <= 1) {
            return 1.0;
        }

        const back = index - 1;
        if (self.stack[back].matches(isec)) {
            return self.stack[back - 1].material(scene).ior();
        } else {
            return self.stack[back].material(scene).ior();
        }
    }

    pub fn straight(self: *const Stack, scene: *const Scene) bool {
        const index = self.index;
        if (index > 0) {
            return 1.0 == self.stack[index - 1].material(scene).ior();
        }

        return true;
    }

    pub fn push(self: *Stack, isec: *const Intersection) void {
        if (self.index < Num_entries - 1) {
            self.stack[self.index] = .{ .prop = isec.prop, .part = isec.geo.part, .uv = isec.geo.uv };
            self.index += 1;
        }
    }

    pub fn pushVolumeLight(self: *Stack, light: Light) void {
        if (self.index < Num_entries - 1) {
            self.stack[self.index] = .{ .prop = light.prop, .part = light.part, .uv = .{ 0.0, 0.0 } };
            self.index += 1;
        }
    }

    pub fn pop(self: *Stack) void {
        if (self.index > 0) {
            self.index -= 1;
        }
    }

    pub fn remove(self: *Stack, isec: *const Intersection) bool {
        const back = @intCast(i32, self.index) - 1;
        var i = back;
        while (i >= 0) : (i -= 1) {
            const ui = @intCast(u32, i);
            if (self.stack[ui].matches(isec)) {
                var j = ui;
                while (j < back) : (j += 1) {
                    self.stack[j] = self.stack[j + 1];
                }

                self.index -= 1;
                return true;
            }
        }

        return false;
    }
};
