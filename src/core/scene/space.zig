const Transformation = @import("composed_transformation.zig").ComposedTransformation;
const Prop = @import("prop/prop.zig").Prop;

const math = @import("base").math;
const AABB = math.AABB;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub const Space = struct {
    const Null = Prop.Null;

    const NumSteps = 4;
    const Interval = 1.0 / @as(f32, @floatFromInt(NumSteps));

    pub const UnitsPerSecond: u64 = 705600000;
    pub const TickDuration = UnitsPerSecond / 60;

    origin: Vec4f,

    world_transformations: List(Transformation),
    frames: List(u32),
    aabbs: List(AABB),
    keyframes: List(math.Transformation),

    const Self = @This();

    pub fn init(alloc: Allocator, num_reserve: u32) !Self {
        return Self{
            .origin = @splat(0.0),
            .world_transformations = try List(Transformation).initCapacity(alloc, num_reserve),
            .frames = try List(u32).initCapacity(alloc, num_reserve),
            .aabbs = try List(AABB).initCapacity(alloc, num_reserve),
            .keyframes = try List(math.Transformation).initCapacity(alloc, num_reserve),
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.keyframes.deinit(alloc);
        self.aabbs.deinit(alloc);
        self.frames.deinit(alloc);
        self.world_transformations.deinit(alloc);
    }

    pub fn clear(self: *Self) void {
        self.keyframes.clearRetainingCapacity();
        self.aabbs.clearRetainingCapacity();
        self.frames.clearRetainingCapacity();
        self.world_transformations.clearRetainingCapacity();
    }

    pub fn allocateInstance(self: *Self, alloc: Allocator) !void {
        try self.world_transformations.append(alloc, undefined);
        try self.frames.append(alloc, Prop.Null);
        try self.aabbs.append(alloc, undefined);
    }

    pub fn calculateWorldBounds(self: *Self, entity: u32, shape_aabb: AABB, origin: Vec4f, num_interpolation_frames: u32) void {
        self.origin = origin;

        const f = self.frames.items[entity];

        var bounds: AABB = undefined;

        if (Null == f) {
            const trafo = self.world_transformations.items[entity];

            bounds = shape_aabb.transform(trafo.objectToWorld());
        } else {
            const frames = self.keyframes.items.ptr + f;

            bounds = shape_aabb.transform(frames[0].toMat4x4());

            var i: u32 = 0;
            const len = num_interpolation_frames - 1;
            while (i < len) : (i += 1) {
                const a = frames[i];
                const b = frames[i + 1];

                var t = Interval;
                var j: u32 = NumSteps - 1;
                while (j > 0) : (j -= 1) {
                    const inter = a.lerp(b, t);
                    bounds.mergeAssign(shape_aabb.transform(inter.toMat4x4()));
                    t += Interval;
                }
            }

            bounds.mergeAssign(shape_aabb.transform(frames[len].toMat4x4()));
        }

        bounds.translate(-origin);
        bounds.cacheRadius();
        self.aabbs.items[entity] = bounds;
    }

    pub fn intersectAABB(self: *const Self, entity: u32, ray: math.Ray) bool {
        return self.aabbs.items[entity].intersect(ray);
    }

    pub fn transformationAt(self: *const Self, entity: u32, time: u64, frame_start: u64) Transformation {
        const f = self.frames.items[entity];
        return self.transformationAtMaybeStatic(entity, time, frame_start, Prop.Null == f);
    }

    pub fn transformationAtMaybeStatic(self: *const Self, entity: u32, time: u64, frame_start: u64, static: bool) Transformation {
        if (static) {
            var trafo = self.world_transformations.items[entity];
            trafo.translate(-self.origin);
            return trafo;
        }

        return self.animatedTransformationAt(self.frames.items[entity], time, frame_start);
    }

    fn animatedTransformationAt(self: *const Self, frames_id: u32, time: u64, frame_start: u64) Transformation {
        const f = frameAt(time, frame_start);

        const frames = self.keyframes.items.ptr + frames_id;

        const a = frames[f.f];
        const b = frames[f.f + 1];

        var inter = a.lerp(b, f.w);
        inter.position -= self.origin;

        return Transformation.init(inter);
    }

    const Frame = struct {
        f: u32,
        w: f32,
    };

    fn frameAt(time: u64, frame_start: u64) Frame {
        const i = (time - frame_start) / TickDuration;
        const a_time = frame_start + i * TickDuration;
        const delta = time - a_time;

        const t: f32 = @floatCast(@as(f64, @floatFromInt(delta)) / @as(f64, @floatFromInt(TickDuration)));

        return .{ .f = @intCast(i), .w = t };
    }

    pub fn setWorldTransformation(self: *Self, entity: u32, t: math.Transformation) void {
        self.world_transformations.items[entity] = Transformation.init(t);
    }

    pub fn allocateFrames(self: *Self, alloc: Allocator, entity: u32, num_frames: u32) !void {
        const current_len: u32 = @intCast(self.keyframes.items.len);
        self.frames.items[entity] = current_len;

        try self.keyframes.resize(alloc, current_len + num_frames);
    }

    pub fn hasAnimatedFrames(self: *const Self, entity: u32) bool {
        return Prop.Null != self.frames.items[entity];
    }

    pub fn setFrame(self: *Self, entity: u32, index: u32, frame: math.Transformation) void {
        const b = self.frames.items[entity];

        self.keyframes.items[b + index] = frame;
    }

    pub fn setFrames(self: *Self, entity: u32, frames: [*]const math.Transformation, len: u32) void {
        const b = self.frames.items[entity];
        const e = b + len;

        @memcpy(self.keyframes.items[b..e], frames[0..len]);
    }

    pub fn setFramesScale(self: *Self, entity: u32, scale: Vec4f, len: u32) void {
        const b = self.frames.items[entity];
        const e = b + len;

        for (self.keyframes.items[b..e]) |*f| {
            f.scale = scale;
        }
    }
};
