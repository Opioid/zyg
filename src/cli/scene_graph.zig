const anim = @import("animation.zig");
const Animation = anim.Animation;
const Keyframe = anim.Keyframe;

const core = @import("core");
const Scene = core.scn.Scene;
const Transformation = core.scn.Transformation;

const base = @import("base");
const math = base.math;
const Vec4f = math.Vec4f;
const Flags = base.flags.Flags;

const std = @import("std");
const Allocator = std.mem.Allocator;
const ALU = std.ArrayListUnmanaged;

pub const Graph = struct {
    const Topology = struct {
        next: u32 = Scene.Null,
        child: u32 = Scene.Null,
    };

    const Property = enum(u8) {
        HasParent = 1 << 0,
        LocalAnimation = 1 << 1,
    };

    const Properties = Flags(Property);

    scene: Scene,

    prop_properties: ALU(Properties),
    prop_frames: ALU(u32),
    prop_topology: ALU(Topology),

    keyframes: ALU(math.Transformation),

    animations: ALU(Animation) = .{},

    const Self = @This();

    pub fn init(alloc: Allocator) !Self {
        return Graph{
            .scene = try Scene.init(alloc),
            .prop_properties = try ALU(Properties).initCapacity(alloc, Scene.Num_reserved_props),
            .prop_frames = try ALU(u32).initCapacity(alloc, Scene.Num_reserved_props),
            .prop_topology = try ALU(Topology).initCapacity(alloc, Scene.Num_reserved_props),
            .keyframes = try ALU(math.Transformation).initCapacity(alloc, Scene.Num_reserved_props),
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

    pub fn createEntity(self: *Self, alloc: Allocator) !u32 {
        try self.allocateProp(alloc);

        return try self.scene.createEntity(alloc);
    }

    pub fn createProp(self: *Self, alloc: Allocator, shape_id: u32, materials: []const u32) !u32 {
        try self.allocateProp(alloc);

        return try self.scene.createProp(alloc, shape_id, materials);
    }

    pub fn bumpProps(self: *Self, alloc: Allocator) !void {
        const d = self.scene.props.items.len - self.prop_properties.items.len;
        var i: usize = 0;
        while (i < d) : (i += 1) {
            try self.allocateProp(alloc);
        }
    }

    pub fn propSerializeChild(self: *Self, alloc: Allocator, parent_id: u32, child_id: u32) !void {
        self.prop_properties.items[child_id].set(.HasParent, true);

        if (self.scene.propHasAnimatedFrames(parent_id) and !self.scene.propHasAnimatedFrames(child_id)) {
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
        self.prop_frames.items[entity] = @intCast(u32, self.keyframes.items.len);

        const num_frames = if (local_animation) self.scene.num_interpolation_frames else 1;

        var i: u32 = 0;
        while (i < num_frames) : (i += 1) {
            try self.keyframes.append(alloc, .{});
        }

        self.prop_properties.items[entity].set(.LocalAnimation, local_animation);

        try self.scene.propAllocateFrames(alloc, entity);
    }

    pub fn propSetTransformation(self: *Graph, entity: u32, t: math.Transformation) void {
        const f = self.prop_frames.items[entity];
        self.keyframes.items[f] = t;
    }

    pub fn propSetFrames(self: *Self, entity: u32, frames: [*]const math.Transformation) void {
        const num_frames = self.scene.num_interpolation_frames;
        const f = self.prop_frames.items[entity];

        const b = f;
        const e = b + num_frames;
        const dest_frames = self.keyframes.items[b..e];

        for (dest_frames) |*df, i| {
            df.* = frames[i];
        }
    }

    pub fn createAnimation(self: *Self, alloc: Allocator, entity: u32, count: u32) !u32 {
        try self.animations.append(alloc, try Animation.init(alloc, entity, count, self.scene.num_interpolation_frames));

        try self.propAllocateFrames(alloc, entity, true);

        return @intCast(u32, self.animations.items.len - 1);
    }

    pub fn animationSetFrame(self: *Self, animation: u32, index: usize, keyframe: Keyframe) void {
        self.animations.items[animation].set(index, keyframe);
    }

    fn allocateProp(self: *Self, alloc: Allocator) !void {
        try self.prop_properties.append(alloc, .{});
        try self.prop_frames.append(alloc, Scene.Null);
        try self.prop_topology.append(alloc, .{});
    }

    fn propCalculateWorldTransformation(self: *Graph, entity: usize) void {
        if (self.prop_properties.items[entity].no(.HasParent)) {
            const f = self.prop_frames.items[entity];

            if (Scene.Null != f) {
                const frames = self.keyframes.items.ptr + f;

                self.scene.propSetFrames(@intCast(u32, entity), frames);
            }

            self.propPropagateTransformation(entity);
        }
    }

    fn propPropagateTransformation(self: *Graph, entity: usize) void {
        const f = self.prop_frames.items[entity];

        if (Scene.Null == f) {
            const trafo = self.scene.prop_world_transformations.items[entity];

            var child = self.prop_topology.items[entity].child;
            while (Scene.Null != child) {
                self.propInheritTransformation(child, trafo);

                child = self.prop_topology.items[child].next;
            }
        } else {
            //    const frames = self.keyframes.items.ptr + f;
            const frames = self.scene.keyframes.items.ptr + self.scene.prop_frames.items[entity] + self.scene.num_interpolation_frames;

            var child = self.prop_topology.items[entity].child;
            while (Scene.Null != child) {
                self.propInheritTransformations(child, frames);

                child = self.prop_topology.items[child].next;
            }
        }
    }

    fn propInheritTransformation(self: *Graph, entity: u32, trafo: Transformation) void {
        const f = self.prop_frames.items[entity];

        if (Scene.Null != f) {
            const frames = self.keyframes.items.ptr + f;

            // Logically this has to be true here
            // const local_animation = true; //self.prop(entity).hasLocalAnimation();
            const local_animation = self.prop_properties.items[entity].is(.LocalAnimation);

            const df = self.scene.keyframes.items.ptr + self.scene.prop_frames.items[entity] + self.scene.num_interpolation_frames;

            var i: u32 = 0;
            const len = self.scene.num_interpolation_frames;
            while (i < len) : (i += 1) {
                const lf = if (local_animation) i else 0;
                //self.frames_buffer[i] = trafo.transform(frames[lf]);
                df[i] = trafo.transform(frames[lf]);
            }

            //   self.scene.propSetFrames(entity, self.frames_buffer.ptr);
        }

        self.propPropagateTransformation(entity);
    }

    fn propInheritTransformations(self: *Graph, entity: u32, frames: [*]math.Transformation) void {
        //  const local_animation = self.prop(entity).hasLocalAnimation();
        const local_animation = self.prop_properties.items[entity].is(.LocalAnimation);

        const sf = self.keyframes.items.ptr + self.prop_frames.items[entity];
        const df = self.scene.keyframes.items.ptr + self.scene.prop_frames.items[entity] + self.scene.num_interpolation_frames;

        var i: u32 = 0;
        const len = self.scene.num_interpolation_frames;
        while (i < len) : (i += 1) {
            const lf = if (local_animation) i else 0;
            df[i] = frames[i].transform(sf[lf]);
        }

        self.propPropagateTransformation(entity);
    }
};
