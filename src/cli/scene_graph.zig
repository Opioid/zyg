const anim = @import("animation.zig");
const Animation = anim.Animation;
const Keyframe = anim.Keyframe;

const core = @import("core");
const Scene = core.scn.Scene;
const Transformation = core.scn.Transformation;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub const Graph = struct {
    const Topology = struct {
        next: u32 = Scene.Null,
        child: u32 = Scene.Null,
    };

    const Properties = packed struct {
        has_parent: bool = false,
        local_animation: bool = false,
    };

    scene: Scene,

    prop_props: List(u32),
    prop_properties: List(Properties),
    prop_frames: List(u32),
    prop_topology: List(Topology),

    keyframes: List(math.Transformation),

    animations: List(Animation) = .{},

    const Self = @This();

    pub fn init(alloc: Allocator) !Self {
        return Graph{
            .scene = try Scene.init(alloc),
            .prop_props = try List(u32).initCapacity(alloc, Scene.Num_reserved_props),
            .prop_properties = try List(Properties).initCapacity(alloc, Scene.Num_reserved_props),
            .prop_frames = try List(u32).initCapacity(alloc, Scene.Num_reserved_props),
            .prop_topology = try List(Topology).initCapacity(alloc, Scene.Num_reserved_props),
            .keyframes = try List(math.Transformation).initCapacity(alloc, Scene.Num_reserved_props),
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        for (self.animations.items) |*a| {
            a.deinit(alloc, self.scene.num_interpolation_frames);
        }
        self.animations.deinit(alloc);

        self.keyframes.deinit(alloc);
        self.prop_topology.deinit(alloc);
        self.prop_frames.deinit(alloc);
        self.prop_properties.deinit(alloc);
        self.prop_props.deinit(alloc);

        self.scene.deinit(alloc);
    }

    pub fn clear(self: *Self, alloc: Allocator) void {
        for (self.animations.items) |*a| {
            a.deinit(alloc, self.scene.num_interpolation_frames);
        }
        self.animations.clearRetainingCapacity();

        self.keyframes.clearRetainingCapacity();
        self.prop_topology.clearRetainingCapacity();
        self.prop_frames.clearRetainingCapacity();
        self.prop_properties.clearRetainingCapacity();
        self.prop_props.clearRetainingCapacity();

        self.scene.clear();
    }

    pub fn simulate(self: *Self, start: u64, end: u64) void {
        const frames_start = start - (start % Scene.Tick_duration);
        const end_rem = end % Scene.Tick_duration;
        const frames_end = end + (if (end_rem > 0) Scene.Tick_duration - end_rem else 0);

        for (self.animations.items) |*a| {
            a.resample(frames_start, frames_end, Scene.Tick_duration);
            a.update(self);
        }

        for (self.prop_properties.items) |_, i| {
            self.propCalculateWorldTransformation(i);
        }
    }

    pub fn createEntity(self: *Self, alloc: Allocator, render_id: u32) !u32 {
        try self.prop_props.append(alloc, render_id);
        try self.prop_properties.append(alloc, .{});
        try self.prop_frames.append(alloc, @intCast(u32, self.keyframes.items.len));
        try self.prop_topology.append(alloc, .{});

        try self.keyframes.append(alloc, .{});

        return @intCast(u32, self.prop_props.items.len - 1);
    }

    pub fn propSerializeChild(self: *Self, alloc: Allocator, parent_id: u32, child_id: u32) !void {
        self.prop_properties.items[child_id].has_parent = true;

        const parent_render_id = self.prop_props.items[parent_id];
        const child_render_id = self.prop_props.items[child_id];

        if (self.scene.propHasAnimatedFrames(parent_render_id) and !self.scene.propHasAnimatedFrames(child_render_id)) {
            // This is the case if child has no animation attached to it directly
            try self.propAllocateFrames(alloc, child_id, false);
        }

        const pt = &self.prop_topology.items[parent_id];
        if (Scene.Null == pt.child) {
            pt.child = child_id;
        } else {
            self.prop_topology.items[self.prop_topology.items.len - 2].next = child_id;
        }
    }

    pub fn propAllocateFrames(self: *Self, alloc: Allocator, entity: u32, local_animation: bool) !void {
        // self.prop_frames.items[entity] = @intCast(u32, self.keyframes.items.len);

        const num_frames = if (local_animation) self.scene.num_interpolation_frames else 1;

        var i: u32 = 1;
        while (i < num_frames) : (i += 1) {
            try self.keyframes.append(alloc, .{});
        }

        self.prop_properties.items[entity].local_animation = local_animation;

        const render_id = self.prop_props.items[entity];
        if (Scene.Null != render_id) {
            try self.scene.propAllocateFrames(alloc, render_id);
        }
    }

    pub fn propSetTransformation(self: *Self, entity: u32, t: math.Transformation) void {
        const f = self.prop_frames.items[entity];
        self.keyframes.items[f] = t;
    }

    pub fn propSetFrames(self: *Self, entity: u32, frames: [*]const math.Transformation) void {
        const len = self.scene.num_interpolation_frames;
        const b = self.prop_frames.items[entity];
        const e = b + len;

        std.mem.copy(math.Transformation, self.keyframes.items[b..e], frames[0..len]);
    }

    pub fn createAnimation(self: *Self, alloc: Allocator, entity: u32, count: u32) !u32 {
        try self.animations.append(alloc, try Animation.init(alloc, entity, count, self.scene.num_interpolation_frames));

        try self.propAllocateFrames(alloc, entity, true);

        return @intCast(u32, self.animations.items.len - 1);
    }

    pub fn animationSetFrame(self: *Self, animation: u32, index: usize, keyframe: Keyframe) void {
        self.animations.items[animation].set(index, keyframe);
    }

    fn propCalculateWorldTransformation(self: *Self, entity: usize) void {
        if (!self.prop_properties.items[entity].has_parent) {
            const f = self.prop_frames.items[entity];
            const frames = self.keyframes.items.ptr + f;

            const animation = self.prop_properties.items[entity].local_animation;

            const render_id = self.prop_props.items[entity];
            if (Scene.Null != render_id) {
                if (animation) {
                    self.scene.propSetFrames(render_id, frames);
                } else {
                    self.scene.propSetWorldTransformation(render_id, frames[0]);
                }
            }

            const num_frames = if (animation) self.scene.num_interpolation_frames else 1;
            self.propPropagateTransformation(entity, num_frames, frames);
        }
    }

    fn propPropagateTransformation(self: *Self, entity: usize, num_frames: u32, frames: [*]const math.Transformation) void {
        var child = self.prop_topology.items[entity].child;
        while (Scene.Null != child) {
            self.propInheritTransformations(child, num_frames, frames);

            child = self.prop_topology.items[child].next;
        }
    }

    fn propInheritTransformations(self: *Self, entity: u32, num_frames: u32, frames: [*]const math.Transformation) void {
        const animation = self.prop_properties.items[entity].local_animation;

        const render_id = self.prop_props.items[entity];

        const sf = self.keyframes.items.ptr + self.prop_frames.items[entity];
        const df = self.scene.keyframes.items.ptr + self.scene.prop_frames.items[render_id];

        var i: u32 = 0;
        const len = self.scene.num_interpolation_frames;
        while (i < len) : (i += 1) {
            const lf = if (1 == num_frames) 0 else i;
            const lsf = if (animation) i else 0;
            df[i] = frames[lf].transform(sf[lsf]);
        }

        self.propPropagateTransformation(entity, len, df);
    }
};
