const anim = @import("animation.zig");
const Animation = anim.Animation;
const Keyframe = anim.Keyframe;

const core = @import("core");
const Scene = core.scn.Scene;

const std = @import("std");
const Allocator = std.mem.Allocator;
const ALU = std.ArrayListUnmanaged;

pub const Graph = struct {
    scene: Scene,

    animations: ALU(Animation) = .{},

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        for (self.animations.items) |*a| {
            a.deinit(alloc, self.scene.num_interpolation_frames);
        }
        self.animations.deinit(alloc);

        self.scene.deinit(alloc);
    }

    pub fn clear(self: *Self, alloc: Allocator) void {
        for (self.animations.items) |*a| {
            a.deinit(alloc, self.scene.num_interpolation_frames);
        }
        self.animations.clearRetainingCapacity();

        self.scene.clear();
    }

    pub fn simulate(self: *Self, start: u64, end: u64) void {
        const frames_start = start - (start % Scene.Tick_duration);
        const end_rem = end % Scene.Tick_duration;
        const frames_end = end + (if (end_rem > 0) Scene.Tick_duration - end_rem else 0);

        for (self.animations.items) |*a| {
            a.resample(frames_start, frames_end, Scene.Tick_duration);
            a.update(&self.scene);
        }
    }

    pub fn createAnimation(self: *Self, alloc: Allocator, entity: u32, count: u32) !u32 {
        try self.animations.append(alloc, try Animation.init(alloc, entity, count, self.scene.num_interpolation_frames));

        try self.scene.propAllocateFrames(alloc, entity, true);

        return @intCast(u32, self.animations.items.len - 1);
    }

    pub fn animationSetFrame(self: *Self, animation: u32, index: usize, keyframe: Keyframe) void {
        self.animations.items[animation].set(index, keyframe);
    }
};
