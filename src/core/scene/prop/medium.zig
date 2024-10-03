const Fragment = @import("../shape/intersection.zig").Fragment;
const Scene = @import("../scene.zig").Scene;
const Light = @import("../light/light.zig").Light;
const CC = @import("../material/collision_coefficients.zig").CC;
const Material = @import("../material/material.zig").Material;

const math = @import("base").math;
const Vec2f = math.Vec2f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Medium = struct {
    prop: u32,
    part: u32,

    pub fn material(self: Medium, scene: *const Scene) *const Material {
        return scene.propMaterial(self.prop, self.part);
    }

    pub fn matches(self: Medium, frag: *const Fragment) bool {
        return self.prop == frag.prop and self.part == frag.part;
    }
};

pub const Stack = struct {
    const Num_entries = 6;

    index: u32 = 0,
    m_stack: [Num_entries]Medium = undefined,
    cc_stack: [Num_entries]CC = undefined,

    pub fn clone(self: *const Stack) Stack {
        const index = self.index;
        var result: Stack = .{ .index = index };
        @memcpy(result.m_stack[0..index], self.m_stack[0..index]);
        @memcpy(result.cc_stack[0..index], self.cc_stack[0..index]);
        return result;
    }

    pub fn empty(self: *const Stack) bool {
        return 0 == self.index;
    }

    pub fn clear(self: *Stack) void {
        self.index = 0;
    }

    pub fn top(self: *const Stack) Medium {
        return self.m_stack[self.index - 1];
    }

    pub fn topCC(self: *const Stack) CC {
        return self.cc_stack[self.index - 1];
    }

    pub fn topIor(self: *const Stack, scene: *const Scene) f32 {
        const index = self.index;
        if (index > 0) {
            return self.m_stack[index - 1].material(scene).ior();
        }

        return 1.0;
    }

    pub fn surroundingIor(self: *const Stack, scene: *const Scene) f32 {
        const index = self.index;
        if (index > 1) {
            return self.m_stack[1].material(scene).ior();
        }

        return 1.0;
    }

    pub fn peekIor(self: *const Stack, frag: *const Fragment, scene: *const Scene) f32 {
        const index = self.index;
        if (index <= 1) {
            return 1.0;
        }

        const back = index - 1;
        if (self.m_stack[back].matches(frag)) {
            return self.m_stack[back - 1].material(scene).ior();
        } else {
            return self.m_stack[back].material(scene).ior();
        }
    }

    pub fn push(self: *Stack, frag: *const Fragment, cc: CC) void {
        const index = self.index;
        if (index < Num_entries - 1) {
            self.m_stack[index] = .{ .prop = frag.prop, .part = frag.part };
            self.cc_stack[index] = cc;
            self.index += 1;
        }
    }

    pub fn pushVolumeLight(self: *Stack, light: Light) void {
        const index = self.index;
        if (index < Num_entries - 1) {
            self.m_stack[index] = .{ .prop = light.prop, .part = light.part };
            self.index += 1;
        }
    }

    pub fn pop(self: *Stack) void {
        if (self.index > 0) {
            self.index -= 1;
        }
    }

    pub fn remove(self: *Stack, frag: *const Fragment) void {
        const back = @as(i32, @intCast(self.index)) - 1;
        var i = back;
        while (i >= 0) : (i -= 1) {
            const ui: u32 = @intCast(i);
            if (self.m_stack[ui].matches(frag)) {
                var j = ui;
                while (j < back) : (j += 1) {
                    self.m_stack[j] = self.m_stack[j + 1];
                    self.cc_stack[j] = self.cc_stack[j + 1];
                }

                self.index -= 1;
                return;
            }
        }
    }
};