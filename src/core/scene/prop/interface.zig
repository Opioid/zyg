const Intersection = @import("intersection.zig").Intersection;
const Worker = @import("../worker.zig").Worker;
const Material = @import("../material/material.zig").Material;
const math = @import("base").math;
const Vec2f = math.Vec2f;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Interface = struct {
    prop: u32,
    part: u32,
    uv: Vec2f,

    pub fn material(self: Interface, worker: Worker) Material {
        return worker.scene.propMaterial(self.prop, self.part);
    }

    pub fn matches(self: Interface, isec: Intersection) bool {
        return self.prop == isec.prop and self.part == isec.geo.part;
    }
};

pub const Stack = struct {
    const Num_entries = 16;

    index: u32,
    stack: [*]Interface,

    pub fn init(alloc: *Allocator) !Stack {
        return Stack{
            .index = 0,
            .stack = (try alloc.alloc(Interface, Num_entries)).ptr,
        };
    }

    pub fn deinit(self: *Stack, alloc: *Allocator) void {
        alloc.free(self.stack[0..Num_entries]);
    }

    pub fn copy(self: Stack, other: *Stack) void {
        const index = self.index;
        other.index = index;
        std.mem.copy(Interface, other.stack[0..index], self.stack[0..index]);
    }

    pub fn empty(self: Stack) bool {
        return 0 == self.index;
    }

    pub fn clear(self: *Stack) void {
        self.index = 0;
    }

    pub fn top(self: Stack) Interface {
        return self.stack[self.index - 1];
    }

    pub fn topIor(self: Stack, worker: Worker) f32 {
        const index = self.index;
        if (index > 0) {
            return self.stack[index - 1].material(worker).ior();
        }

        return 1.0;
    }

    pub fn peekIor(self: Stack, isec: Intersection, worker: Worker) f32 {
        const index = self.index;
        if (index <= 1) {
            return 1.0;
        }

        const back = index - 1;
        if (self.stack[back].matches(isec)) {
            return self.stack[back - 1].material(worker).ior();
        } else {
            return self.stack[back].material(worker).ior();
        }
    }

    pub fn straight(self: Stack, worker: Worker) bool {
        const index = self.index;
        if (index > 0) {
            return 1.0 == self.stack[index - 1].material(worker).ior();
        }

        return true;
    }

    pub fn push(self: *Stack, isec: Intersection) void {
        if (self.index < Num_entries - 1) {
            self.stack[self.index] = .{ .prop = isec.prop, .part = isec.geo.part, .uv = isec.geo.uv };
            self.index += 1;
        }
    }

    pub fn pop(self: *Stack) void {
        if (self.index > 0) {
            self.index -= 1;
        }
    }

    pub fn remove(self: *Stack, isec: Intersection) bool {
        const back = self.index - 1;
        var i = @intCast(i32, back);
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
