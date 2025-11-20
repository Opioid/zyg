const AnimationLoader = @import("animation_loader.zig");
const anim = @import("animation.zig");
const Animation = anim.Animation;
const Keyframe = anim.Keyframe;

const core = @import("core");
const Take = core.take.Take;
const Scene = core.scene.Scene;
const Material = core.scene.Material;
const Transformation = core.scene.Transformation;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayList;

pub const Graph = struct {
    pub const Null = Scene.Null;

    const Topology = struct {
        next: u32 = Null,
        child: u32 = Null,
    };

    const Properties = packed struct {
        has_parent: bool = false,
        animation: bool = false,
        local_animation: bool = false,
    };

    take: Take = .{},

    scene: Scene,

    materials: List(u32) = .empty,

    prop_props: List(u32),
    prop_properties: List(Properties),
    prop_frames: List(u32),
    prop_topology: List(Topology),

    keyframes: List(math.Transformation),

    animations: List(Animation) = .empty,

    camera_trafos: List(math.Transformation) = .empty,

    const Self = @This();

    pub fn init(alloc: Allocator) !Self {
        return Graph{
            .scene = try Scene.init(alloc),
            .prop_props = try List(u32).initCapacity(alloc, Scene.NumReservedProps),
            .prop_properties = try List(Properties).initCapacity(alloc, Scene.NumReservedProps),
            .prop_frames = try List(u32).initCapacity(alloc, Scene.NumReservedProps),
            .prop_topology = try List(Topology).initCapacity(alloc, Scene.NumReservedProps),
            .keyframes = try List(math.Transformation).initCapacity(alloc, Scene.NumReservedProps),
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.camera_trafos.deinit(alloc);

        for (self.animations.items) |*a| {
            a.deinit(alloc, self.scene.num_interpolation_frames);
        }
        self.animations.deinit(alloc);

        self.keyframes.deinit(alloc);
        self.prop_topology.deinit(alloc);
        self.prop_frames.deinit(alloc);
        self.prop_properties.deinit(alloc);
        self.prop_props.deinit(alloc);

        self.materials.deinit(alloc);

        self.scene.deinit(alloc);

        self.take.deinit(alloc);
    }

    pub fn clear(self: *Self, alloc: Allocator, clear_take: bool) void {
        if (clear_take) {
            self.take.clear(alloc);
            self.camera_trafos.clearRetainingCapacity();
        }

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
        const frames_start = start - (start % Scene.TickDuration);
        const end_rem = end % Scene.TickDuration;
        const frames_end = end + (if (end_rem > 0) Scene.TickDuration - end_rem else 0);

        for (self.animations.items) |*a| {
            a.resample(frames_start, frames_end, Scene.TickDuration);
            a.update(self);
        }

        self.calculateWorldTransformations();
    }

    pub fn createEntity(self: *Self, alloc: Allocator, render_id: u32) !u32 {
        try self.prop_props.append(alloc, render_id);
        try self.prop_properties.append(alloc, .{});
        try self.prop_frames.append(alloc, @intCast(self.keyframes.items.len));
        try self.prop_topology.append(alloc, .{});

        return @intCast(self.prop_props.items.len - 1);
    }

    pub fn propSerializeChild(self: *Self, parent_id: u32, child_id: u32) void {
        self.prop_properties.items[child_id].has_parent = true;

        const pt = &self.prop_topology.items[parent_id];
        if (Null == pt.child) {
            pt.child = child_id;
        } else {
            self.prop_topology.items[self.prop_topology.items.len - 2].next = child_id;
        }
    }

    pub fn propAllocateFrames(self: *Self, alloc: Allocator, entity: u32, world_animation: bool, local_animation: bool) !void {
        if (Null == entity) {
            return;
        }

        const render_id = self.prop_props.items[entity];
        const render_entity = Null != render_id;

        const current_len: u32 = @intCast(self.keyframes.items.len);

        if (world_animation) {
            const nif = self.scene.num_interpolation_frames;
            const num_frames = if (local_animation) (if (render_entity) nif else 2 * nif) else (if (render_entity) 1 else 1 + nif);
            try self.keyframes.resize(alloc, current_len + num_frames);

            if (render_entity) {
                try self.scene.propAllocateFrames(alloc, render_id);
            }
        } else {
            const num_frames: u32 = if (render_entity) 2 else 1;
            try self.keyframes.resize(alloc, current_len + num_frames);
        }

        self.prop_properties.items[entity].animation = world_animation;
        self.prop_properties.items[entity].local_animation = local_animation;
    }

    pub const Node = struct {
        graph_id: u32,
        animated: bool,
        world_trafo: math.Transformation,

        pub const empty = Node{
            .graph_id = Null,
            .animated = false,
            .world_trafo = .identity,
        };
    };

    pub fn propSetTransformation(
        self: *Self,
        alloc: Allocator,
        entity_id: u32,
        trafo: math.Transformation,
        parent: Node,
        animation_value: ?std.json.Value,
    ) !Node {
        const animation = if (animation_value) |animation|
            try AnimationLoader.load(alloc, animation, trafo, if (Null == parent.graph_id) parent.world_trafo else null, self)
        else
            Null;

        const local_animation = Null != animation;
        const world_animation = parent.animated or local_animation;

        var result: Node = .{
            .graph_id = Null,
            .animated = world_animation,
            .world_trafo = parent.world_trafo.transform(trafo),
        };

        if (world_animation) {
            result.graph_id = try self.createEntity(alloc, entity_id);

            try self.propAllocateFrames(alloc, result.graph_id, world_animation, local_animation);

            if (local_animation) {
                self.animationSetEntity(animation, result.graph_id);
            }

            if (Null != parent.graph_id) {
                self.propSerializeChild(parent.graph_id, result.graph_id);
            }
        }

        if (!local_animation) {
            if (Null != result.graph_id) {
                const f = self.prop_frames.items[result.graph_id];
                self.keyframes.items[f] = trafo;
            }

            if (Null != entity_id) {
                self.scene.prop_space.setWorldTransformation(entity_id, result.world_trafo);
            }
        }

        return result;
    }

    pub fn propSetFrames(self: *Self, entity: u32, frames: [*]const math.Transformation) void {
        const len = self.scene.num_interpolation_frames;
        const b = self.prop_frames.items[entity];
        const e = b + len;

        @memcpy(self.keyframes.items[b..e], frames[0..len]);
    }

    pub fn createAnimation(self: *Self, alloc: Allocator, count: u32) !u32 {
        try self.animations.append(alloc, try Animation.init(alloc, count, self.scene.num_interpolation_frames));

        return @intCast(self.animations.items.len - 1);
    }

    pub fn animationSetEntity(self: *Self, animation: u32, entity: u32) void {
        self.animations.items[animation].entity = entity;
    }

    pub fn animationSetFrame(self: *Self, animation: u32, index: u32, keyframe: Keyframe) void {
        self.animations.items[animation].set(index, keyframe);
    }

    fn calculateWorldTransformations(self: *Self) void {
        for (self.prop_properties.items, 0..) |p, entity| {
            if (!p.has_parent) {
                const f = self.prop_frames.items[entity];
                const frames = self.keyframes.items.ptr + f;

                const animation = p.local_animation;

                const render_id = self.prop_props.items[entity];
                if (Null != render_id) {
                    if (animation) {
                        self.scene.prop_space.setFrames(render_id, frames, self.scene.num_interpolation_frames);
                    } else {
                        self.scene.prop_space.setWorldTransformation(render_id, frames[0]);
                    }
                }

                const num_frames = if (animation) self.scene.num_interpolation_frames else 1;
                self.propPropagateTransformation(@intCast(entity), num_frames, frames);
            }
        }
    }

    fn propPropagateTransformation(self: *Self, entity: u32, num_frames: u32, frames: [*]const math.Transformation) void {
        var child = self.prop_topology.items[entity].child;
        while (Null != child) {
            self.propInheritTransformations(child, num_frames, frames);

            child = self.prop_topology.items[child].next;
        }
    }

    fn propInheritTransformations(self: *Self, entity: u32, num_frames: u32, frames: [*]const math.Transformation) void {
        const animation = self.prop_properties.items[entity].local_animation;

        const sf = self.keyframes.items.ptr + self.prop_frames.items[entity];

        const len = self.scene.num_interpolation_frames;

        const render_id = self.prop_props.items[entity];

        if (Null != render_id) {
            const df = self.scene.prop_space.keyframes.items.ptr + self.scene.prop_space.frames.items[render_id];

            var i: u32 = 0;
            while (i < len) : (i += 1) {
                const lf = if (1 == num_frames) 0 else i;
                const lsf = if (animation) i else 0;
                df[i] = frames[lf].transform(sf[lsf]);
            }

            self.propPropagateTransformation(entity, len, df);
        } else {
            const df = sf + if (animation) 1 else len;

            var i: u32 = 0;
            while (i < len) : (i += 1) {
                const lf = if (1 == num_frames) 0 else i;
                const lsf = if (animation) i else 0;
                df[i] = frames[lf].transform(sf[lsf]);
            }

            self.propPropagateTransformation(entity, len, df);
        }
    }
};
