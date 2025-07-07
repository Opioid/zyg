const tr = @import("light_tree.zig");
const Tree = tr.Tree;
const PrimitiveTree = tr.PrimitiveTree;
const Node = tr.Node;
const Scene = @import("../scene.zig").Scene;
const Part = @import("../shape/triangle/triangle_mesh.zig").Part;

const base = @import("base");
const enc = base.encoding;
const math = base.math;
const AABB = math.AABB;
const Vec2u = math.Vec2u;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

// Implements most of
// Importance Sampling of Many Lights with Adaptive Tree Splitting
// http://aconty.com/pdf/many-lights-hpg2018.pdf

const Scene_sweep_threshold = 128;
const Part_sweep_threshold = 32;
const Num_slices = 16;

const BuildNode = struct {
    bounds: AABB,
    cone: Vec4f,

    power: f32,
    variance: f32,

    middle: u32,
    children_or_light: u32,
    num_lights: u32,

    two_sided: bool,

    pub fn hasChildren(self: BuildNode) bool {
        return self.middle > 0;
    }

    pub fn countPotentialLights(self: BuildNode, nodes: []const BuildNode, depth: u32, num_lights: []Vec2u, comptime max_depth: u32) void {
        if (!self.hasChildren()) {
            num_lights[depth][0] += 1;
        } else {
            num_lights[depth][1] += 2;

            const next_depth = depth + 1;
            if (next_depth < max_depth) {
                nodes[self.children_or_light].countPotentialLights(nodes, next_depth, num_lights, max_depth);
                nodes[self.children_or_light + 1].countPotentialLights(nodes, next_depth, num_lights, max_depth);
            }
        }
    }
};

const SplitCandidate = struct {
    const Axis = struct {
        d: f32,
        axis: u32,
    };

    const Partition = struct {
        num: u32,
        left: [2]u32,
    };

    const Condition = union(enum) {
        Axis: Axis,
        Angle: Vec4f,
        Partition: Partition,
    };

    aabbs: [2]AABB,
    cones: [2]Vec4f,
    powers: [2]f32,
    condition: Condition,
    cost: f32,
    two_sided: [2]bool,
    exhausted: bool,

    const Self = @This();

    pub fn configure(self: *Self, p: Vec4f, axis: u32) void {
        self.condition = .{ .Axis = .{ .d = p[axis], .axis = axis } };
    }

    pub fn configureAngle(self: *Self, n: Vec4f) void {
        self.condition = .{ .Angle = n };
    }

    pub fn configurePartition(self: *Self, left: []const u32) void {
        self.condition = .{ .Partition = .{ .num = @intCast(left.len), .left = undefined } };
        std.mem.copyForwards(u32, &self.condition.Partition.left, left);
    }

    pub fn leftSide(self: *const Self, comptime T: type, l: u32, set: *const T) bool {
        return switch (self.condition) {
            .Axis => |axis| set.lightAabb(l).bounds[1][axis.axis] < axis.d,
            .Angle => |n| math.dot3(n, set.lightCone(l)) < 0.0,
            .Partition => |part| {
                for (0..part.num) |i| {
                    if (l == part.left[i]) {
                        return true;
                    }
                }
                return false;
            },
        };
    }

    pub fn regularized(self: *const Self, extent: Vec4f) f32 {
        const maxe = math.hmax3(extent);

        return switch (self.condition) {
            .Axis => |axis| maxe / extent[axis.axis],
            else => maxe / math.hmin3(extent),
        };
    }

    pub fn evaluate(self: *Self, comptime T: type, lights: []u32, bounds: AABB, cone_weight: f32, set: *const T, variant: u32) void {
        if (Scene == T) {
            self.evaluateScene(lights, bounds, cone_weight, set);
        } else if (Part == T) {
            self.evaluatePart(lights, bounds, cone_weight, set, variant);
        }
    }

    fn evaluateScene(self: *Self, lights: []u32, bounds: AABB, cone_weight: f32, scene: *const Scene) void {
        var num_sides: [2]u32 = .{ 0, 0 };
        var boxs: [2]AABB = .{ .empty, .empty };
        var cones: [2]Vec4f = .{ @splat(1.0), @splat(1.0) };
        var two_sided: [2]bool = .{ false, false };
        var powers: [2]f32 = .{ 0.0, 0.0 };

        for (lights) |l| {
            const power = scene.lightPower(0, l);
            if (0.0 == power) {
                continue;
            }

            const box = scene.lightAabb(l);
            const lcone = scene.lightCone(l);
            const ltwo_sided = scene.lightTwoSided(0, l);

            const side: u32 = if (self.leftSide(Scene, l, scene)) 0 else 1;

            num_sides[side] += 1;
            boxs[side].mergeAssign(box);
            cones[side] = math.cone.merge(cones[side], lcone);
            two_sided[side] = two_sided[side] or ltwo_sided;
            powers[side] += power;
        }

        const extent = bounds.extent();
        const surface_area = bounds.surfaceArea();

        self.aabbs = boxs;
        self.cones = cones;
        self.powers = powers;
        self.two_sided = two_sided;

        const empty_side = 0 == num_sides[0] or 0 == num_sides[1];
        if (empty_side) {
            const reg = math.hmax3(extent) / math.hmin3(extent);
            self.cost = @as(f32, @floatFromInt(lights.len)) * reg * (powers[0] + powers[1]);
            self.exhausted = true;
        } else {
            const reg = self.regularized(extent);

            const cone_weight_a = coneCost(cones[0][3], two_sided[0]);
            const cone_weight_b = coneCost(cones[1][3], two_sided[1]);

            const surface_area_a = boxs[0].surfaceArea();
            const surface_area_b = boxs[1].surfaceArea();

            self.cost = reg * (((powers[0] * cone_weight_a * surface_area_a) +
                (powers[1] * cone_weight_b * surface_area_b)) /
                (surface_area * cone_weight));

            self.exhausted = false;
        }
    }

    fn evaluatePart(self: *Self, lights: []u32, bounds: AABB, cone_weight: f32, part: *const Part, variant: u32) void {
        var num_sides: [2]u32 = .{ 0, 0 };
        var boxs: [2]AABB = .{ .empty, .empty };
        var dominant_axis: [2]Vec4f = .{ @splat(0.0), @splat(0.0) };
        var powers: [2]f32 = .{ 0.0, 0.0 };

        for (lights) |l| {
            const power = part.lightPower(variant, l);
            if (0.0 == power) {
                continue;
            }

            const box = part.lightAabb(l);
            const n = part.lightCone(l);

            const side: u32 = if (self.leftSide(Part, l, part)) 0 else 1;

            num_sides[side] += 1;
            boxs[side].mergeAssign(box);
            dominant_axis[side] += @as(Vec4f, @splat(power)) * n;
            powers[side] += power;
        }

        dominant_axis[0] = math.normalize3(dominant_axis[0] / @as(Vec4f, @splat(powers[0])));
        dominant_axis[1] = math.normalize3(dominant_axis[1] / @as(Vec4f, @splat(powers[1])));

        var angles: [2]f32 = .{ 0.0, 0.0 };

        for (lights) |l| {
            const power = part.lightPower(variant, l);
            if (0.0 == power) {
                continue;
            }

            const n = part.lightCone(l);

            const side: u32 = if (self.leftSide(Part, l, part)) 0 else 1;

            const c = math.clamp(math.dot3(dominant_axis[side], n), -1.0, 1.0);
            angles[side] = math.max(angles[side], std.math.acos(c));
        }

        const da0 = dominant_axis[0];
        const da1 = dominant_axis[1];
        const cones: [2]Vec4f = .{
            .{ da0[0], da0[1], da0[2], @cos(angles[0]) },
            .{ da1[0], da1[1], da1[2], @cos(angles[1]) },
        };

        const extent = bounds.extent();
        const two_sided = part.lightTwoSided(variant, 0);

        self.aabbs = boxs;
        self.cones = cones;
        self.powers = powers;
        self.two_sided = .{ two_sided, two_sided };

        const empty_side = 0 == num_sides[0] or 0 == num_sides[1];
        if (empty_side) {
            const reg = math.hmax3(extent) / math.hmin3(extent);
            self.cost = @as(f32, @floatFromInt(lights.len)) * reg * (powers[0] + powers[1]);
            self.exhausted = true;
        } else {
            const surface_area = bounds.surfaceArea();

            const reg = self.regularized(extent);

            const cone_weight_a = coneCost(cones[0][3], two_sided);
            const cone_weight_b = coneCost(cones[1][3], two_sided);

            const surface_area_a = boxs[0].surfaceArea();
            const surface_area_b = boxs[1].surfaceArea();

            self.cost = reg * (((powers[0] * cone_weight_a * surface_area_a) +
                (powers[1] * cone_weight_b * surface_area_b)) /
                (surface_area * cone_weight));

            self.exhausted = false;
        }
    }
};

pub const Builder = struct {
    current_node: u32 = undefined,
    light_order: u32 = undefined,

    build_nodes: []BuildNode = &.{},
    candidates: []SplitCandidate = &.{},

    pub fn deinit(self: *Builder, alloc: Allocator) void {
        alloc.free(self.candidates);
        alloc.free(self.build_nodes);
    }

    pub fn build(
        self: *Builder,
        alloc: Allocator,
        tree: *Tree,
        scene: *const Scene,
        threads: *Threads,
    ) !void {
        const num_lights = scene.numLights();

        try tree.allocateLightMapping(alloc, num_lights);

        self.light_order = 0;

        var lm: u32 = 0;
        {
            var l: u32 = 0;
            while (l < num_lights) : (l += 1) {
                if (!scene.light(l).finite(scene)) {
                    tree.light_mapping[lm] = l;
                    lm += 1;
                }
            }
        }

        const num_infinite_lights = lm;

        {
            var l: u32 = 0;
            while (l < num_lights) : (l += 1) {
                if (scene.light(l).finite(scene)) {
                    tree.light_mapping[lm] = l;
                    lm += 1;
                }
            }
        }

        try tree.allocate(alloc, num_infinite_lights);

        var infinite_total_power: f32 = 0.0;
        for (tree.light_mapping[0..num_infinite_lights], 0..) |l, i| {
            const power = scene.lightPower(0, l);
            tree.infinite_light_powers[i] = power;
            tree.light_orders[l] = self.light_order;
            self.light_order += 1;

            infinite_total_power += power;
        }

        tree.infinite_end = self.light_order;
        try tree.infinite_light_distribution.configure(alloc, tree.infinite_light_powers[0..tree.num_infinite_lights], 0);

        const num_finite_lights = num_lights - num_infinite_lights;

        var max_split_depth: u32 = Tree.MaxSplitDepth;

        if (num_finite_lights > 0) {
            try self.allocate(alloc, num_finite_lights, Scene_sweep_threshold);

            self.current_node = 1;

            var bounds: AABB = .empty;
            var cone: Vec4f = @splat(1.0);
            var two_sided = false;
            var total_power: f32 = 0.0;

            for (tree.light_mapping[num_infinite_lights..num_lights]) |l| {
                bounds.mergeAssign(scene.lightAabb(l));
                cone = math.cone.merge(cone, scene.lightCone(l));
                two_sided = two_sided or scene.lightTwoSided(0, l);
                total_power += scene.lightPower(0, l);
            }

            _ = self.split(tree, 0, num_infinite_lights, num_lights, bounds, cone, two_sided, total_power, 0, scene, threads);

            try tree.allocateNodes(alloc, self.current_node);
            self.build_nodes[0].bounds.cacheRadius();
            self.serialize(tree.nodes, tree.node_middles, self.build_nodes[0].bounds);
            tree.bounds = self.build_nodes[0].bounds;

            var split_lights = [_]Vec2u{.{ 0, 0 }} ** Tree.MaxSplitDepth;
            self.build_nodes[0].countPotentialLights(self.build_nodes, 0, &split_lights, Tree.MaxSplitDepth);

            var num_split_lights: u32 = 0;
            for (split_lights, 0..) |s, i| {
                num_split_lights += s[0];

                if ((num_split_lights + s[1]) > (Tree.MaxLights - num_infinite_lights) or 0 == s[1]) {
                    max_split_depth = @intCast(i);
                    break;
                }
            }
        } else {
            try tree.allocateNodes(alloc, 0);
        }

        tree.max_split_depth = max_split_depth;

        const p0 = infinite_total_power;
        const p1 = if (0 == num_finite_lights) 0.0 else self.build_nodes[0].power;
        const pt = p0 + p1;
        const infinite_weight = if (0 == num_lights or 0.0 == pt) 0.0 else p0 / pt;

        tree.infinite_weight = infinite_weight;

        // This is because I'm afraid of the 1.0 == random case
        tree.infinite_guard = if (0 == num_finite_lights)
            (if (0 == num_infinite_lights) 0.0 else 1.1)
        else
            infinite_weight;
    }

    pub fn buildPrimitive(
        self: *Builder,
        alloc: Allocator,
        tree: *PrimitiveTree,
        part: *const Part,
        variant: u32,
        threads: *Threads,
    ) !void {
        const num_finite_lights = part.num_triangles;
        try tree.allocateLightMapping(alloc, num_finite_lights);

        self.light_order = 0;

        for (tree.light_mapping, 0..num_finite_lights) |*lm, l| {
            lm.* = @intCast(l);
        }

        try self.allocate(alloc, num_finite_lights, Part_sweep_threshold);

        self.current_node = 1;

        const total_power = part.power(variant);

        _ = self.splitPrimitive(
            tree,
            0,
            0,
            num_finite_lights,
            part.aabb(variant),
            part.totalCone(variant),
            total_power,
            part,
            variant,
            threads,
        );

        try tree.allocateNodes(alloc, self.current_node);
        self.build_nodes[0].bounds.cacheRadius();
        self.serialize(tree.nodes, tree.node_middles, self.build_nodes[0].bounds);
        tree.bounds = self.build_nodes[0].bounds;
    }

    fn allocate(self: *Builder, alloc: Allocator, num_lights: u32, sweep_threshold: u32) !void {
        const num_nodes = 2 * num_lights - 1;

        if (num_nodes > self.build_nodes.len) {
            self.build_nodes = try alloc.realloc(self.build_nodes, num_nodes);
        }

        const num_slices = @min(num_lights, sweep_threshold);
        const num_candidates = if (num_slices >= 2) num_slices * 3 + 3 else 0;

        if (num_candidates > self.candidates.len) {
            self.candidates = try alloc.realloc(self.candidates, num_candidates);
        }
    }

    fn split(
        self: *Builder,
        tree: *Tree,
        node_id: u32,
        begin: u32,
        end: u32,
        bounds: AABB,
        cone: Vec4f,
        two_sided: bool,
        total_power: f32,
        depth: u32,
        scene: *const Scene,
        threads: *Threads,
    ) u32 {
        const lights = tree.light_mapping[begin..end];
        const len = end - begin;

        var node = &self.build_nodes[node_id];

        if (1 == len or
            (2 == len and (depth > Tree.MaxSplitDepth or !scene.lightAabb(lights[0]).overlaps(scene.lightAabb(lights[1])))))
        {
            var node_two_sided = false;

            for (lights) |l| {
                tree.light_orders[l] = self.light_order;
                self.light_order += 1;
                node_two_sided = node_two_sided or scene.lightTwoSided(0, l);
            }

            node.bounds = bounds;
            node.cone = cone;
            node.power = total_power;
            node.variance = variance(Scene, lights, scene, 0);
            node.middle = 0;
            node.children_or_light = begin;
            node.num_lights = len;
            node.two_sided = node_two_sided;

            return begin + len;
        }

        const child0 = self.current_node;

        const sc = evaluateSplits(Scene, lights, bounds, cone, two_sided, Scene_sweep_threshold, self.candidates, scene, 0, threads);

        const predicate = Predicate(Scene){ .sc = &sc, .set = scene };
        const split_node = begin + @as(u32, @intCast(base.memory.partition(u32, lights, predicate, Predicate(Scene).f)));

        self.current_node += 2;
        const c0_end = self.split(tree, child0, begin, split_node, sc.aabbs[0], sc.cones[0], sc.two_sided[0], sc.powers[0], depth + 1, scene, threads);
        const c1_end = self.split(tree, child0 + 1, split_node, end, sc.aabbs[1], sc.cones[1], sc.two_sided[1], sc.powers[1], depth + 1, scene, threads);

        node.bounds = bounds;
        node.cone = cone;
        node.power = total_power;
        node.variance = variance(Scene, lights, scene, 0);
        node.middle = c0_end;
        node.children_or_light = child0;
        node.num_lights = len;
        node.two_sided = two_sided;

        return c1_end;
    }

    fn splitPrimitive(
        self: *Builder,
        tree: *PrimitiveTree,
        node_id: u32,
        begin: u32,
        end: u32,
        bounds: AABB,
        cone: Vec4f,
        total_power: f32,
        part: *const Part,
        variant: u32,
        threads: *Threads,
    ) u32 {
        const lights = tree.light_mapping[begin..end];
        const len = end - begin;

        var node = &self.build_nodes[node_id];

        if (len <= 4) {
            return self.assignPrimitive(node, tree, begin, end, bounds, cone, total_power, part, variant);
        }

        const child0 = self.current_node;

        const two_sided = part.lightTwoSided(variant, 0);

        const sc = evaluateSplits(Part, lights, bounds, cone, two_sided, Part_sweep_threshold, self.candidates, part, variant, threads);

        if (sc.exhausted) {
            return self.assignPrimitive(node, tree, begin, end, bounds, cone, total_power, part, variant);
        }

        const predicate = Predicate(Part){ .sc = &sc, .set = part };
        const split_node = begin + @as(u32, @intCast(base.memory.partition(u32, lights, predicate, Predicate(Part).f)));

        self.current_node += 2;
        const c0_end = self.splitPrimitive(tree, child0, begin, split_node, sc.aabbs[0], sc.cones[0], sc.powers[0], part, variant, threads);
        const c1_end = self.splitPrimitive(tree, child0 + 1, split_node, end, sc.aabbs[1], sc.cones[1], sc.powers[1], part, variant, threads);

        node.bounds = bounds;
        node.cone = cone;
        node.power = total_power;
        node.variance = variance(Part, lights, part, variant);
        node.middle = c0_end;
        node.children_or_light = child0;
        node.num_lights = len;
        node.two_sided = two_sided;

        return c1_end;
    }

    pub fn Predicate(comptime T: type) type {
        return struct {
            sc: *const SplitCandidate,
            set: *const T,

            const Self = @This();

            pub fn f(self: Self, l: u32) bool {
                return self.sc.leftSide(T, l, self.set);
            }
        };
    }

    fn assignPrimitive(
        self: *Builder,
        node: *BuildNode,
        tree: *PrimitiveTree,
        begin: u32,
        end: u32,
        bounds: AABB,
        cone: Vec4f,
        total_power: f32,
        part: *const Part,
        variant: u32,
    ) u32 {
        const lights = tree.light_mapping[begin..end];
        const len = end - begin;

        for (lights) |l| {
            tree.light_orders[l] = self.light_order;
            self.light_order += 1;
        }

        node.bounds = bounds;
        node.cone = cone;
        node.power = total_power;
        node.variance = variance(Part, lights, part, variant);
        node.middle = 0;
        node.children_or_light = begin;
        node.num_lights = len;
        node.two_sided = part.lightTwoSided(variant, 0);

        return begin + len;
    }

    fn serialize(self: *const Builder, nodes: [*]Node, node_middles: [*]u32, total_bounds: AABB) void {
        for (self.build_nodes[0..self.current_node], 0..) |source, i| {
            var dest = &nodes[i];

            const bounds = source.bounds;
            const p = bounds.position();
            const center = Vec4f{ p[0], p[1], p[2], 0.5 * math.length3(bounds.extent()) };
            dest.compressCenter(center, total_bounds);

            dest.cone[0] = enc.floatToSnorm16(source.cone[0]);
            dest.cone[1] = enc.floatToSnorm16(source.cone[1]);
            dest.cone[2] = enc.floatToSnorm16(source.cone[2]);
            dest.cone[3] = enc.floatToSnorm16(source.cone[3]);

            dest.power = source.power;
            dest.variance = source.variance;
            dest.meta.has_children = source.hasChildren();
            dest.meta.two_sided = source.two_sided;
            dest.meta.children_or_light = @intCast(source.children_or_light);
            dest.num_lights = source.num_lights;

            node_middles[i] = source.middle;
        }
    }

    fn variance(comptime T: type, lights: []u32, set: *const T, variant: u32) f32 {
        var ap: f32 = 0.0;
        var aps: f32 = 0.0;

        var n: u32 = 0;
        for (lights) |l| {
            const p = set.lightPower(variant, l);
            if (p > 0.0) {
                n += 1;
                const in = 1.0 / @as(f32, @floatFromInt(n));

                ap += (p - ap) * in;
                aps += (p * p - aps) * in;
            }
        }

        return @abs(aps - ap * ap);
    }

    fn evaluateSplits(
        comptime T: type,
        lights: []u32,
        bounds: AABB,
        cone: Vec4f,
        two_sided: bool,
        sweep_threshold: u32,
        candidates: []SplitCandidate,
        set: *const T,
        variant: u32,
        threads: *Threads,
    ) SplitCandidate {
        const X = 0;
        const Y = 1;
        const Z = 2;

        var num_candidates: u32 = 0;

        if (2 == lights.len) {
            candidates[num_candidates].configurePartition(&.{lights[0]});
            num_candidates += 1;
        } else if (3 == lights.len) {
            candidates[num_candidates].configurePartition(&.{lights[0]});
            num_candidates += 1;

            candidates[num_candidates].configurePartition(&.{lights[1]});
            num_candidates += 1;

            candidates[num_candidates].configurePartition(&.{lights[2]});
            num_candidates += 1;
        } else if (4 == lights.len) {
            candidates[num_candidates].configurePartition(&.{lights[0]});
            num_candidates += 1;

            candidates[num_candidates].configurePartition(&.{lights[1]});
            num_candidates += 1;

            candidates[num_candidates].configurePartition(&.{lights[2]});
            num_candidates += 1;

            candidates[num_candidates].configurePartition(&.{lights[3]});
            num_candidates += 1;

            candidates[num_candidates].configurePartition(&.{ lights[0], lights[1] });
            num_candidates += 1;

            candidates[num_candidates].configurePartition(&.{ lights[0], lights[2] });
            num_candidates += 1;

            candidates[num_candidates].configurePartition(&.{ lights[0], lights[3] });
            num_candidates += 1;
        } else {
            if (lights.len <= sweep_threshold) {
                for (lights) |l| {
                    const max = set.lightAabb(l).bounds[1];

                    candidates[num_candidates].configure(max, X);
                    num_candidates += 1;
                    candidates[num_candidates].configure(max, Y);
                    num_candidates += 1;
                    candidates[num_candidates].configure(max, Z);
                    num_candidates += 1;
                }
            } else {
                const position = bounds.position();
                const extent = bounds.extent();
                const min = bounds.bounds[0];

                const la = math.indexMaxComponent3(extent);
                const step = extent[la] / @as(f32, @floatFromInt(Num_slices));

                var a: u32 = 0;
                while (a < 3) : (a += 1) {
                    const extent_a = extent[a];
                    const num_steps: u32 = @intFromFloat(@ceil(extent_a / step));
                    const step_a = extent_a / @as(f32, @floatFromInt(num_steps));

                    var i: u32 = 1;
                    while (i < num_steps) : (i += 1) {
                        const fi: f32 = @floatFromInt(i);

                        var slice = position;
                        slice[a] = min[a] + fi * step_a;

                        candidates[num_candidates].configure(slice, a);
                        num_candidates += 1;
                    }
                }
            }

            const tb = math.orthonormalBasis3(cone);

            candidates[num_candidates].configureAngle(tb[0]);
            candidates[num_candidates].configureAngle(tb[1]);
            candidates[num_candidates].configureAngle(cone);
            num_candidates += 1;
        }

        const cone_weight = coneCost(cone[3], two_sided);

        const Eval = EvaluateContext(T);

        if (lights.len * num_candidates > 1024) {
            var context = Eval{
                .lights = lights,
                .bounds = bounds,
                .cone_weight = cone_weight,
                .candidates = candidates,
                .set = set,
                .variant = variant,
            };

            _ = threads.runRange(&context, Eval.run, 0, num_candidates, 0);
        } else {
            for (candidates[0..num_candidates]) |*c| {
                c.evaluate(T, lights, bounds, cone_weight, set, variant);
            }
        }

        var min_cost = candidates[0].cost;
        var sc: usize = 0;
        for (candidates[1..num_candidates], 0..) |c, i| {
            const cost = c.cost;
            if (cost < min_cost) {
                sc = i + 1;
                min_cost = cost;
            }
        }

        return candidates[sc];
    }

    fn EvaluateContext(comptime T: type) type {
        return struct {
            lights: []u32,
            bounds: AABB,
            cone_weight: f32,
            candidates: []SplitCandidate,
            set: *const T,
            variant: u32,

            const Self = @This();

            pub fn run(context: Threads.Context, id: u32, begin: u32, end: u32) void {
                _ = id;

                const self: *Self = @ptrCast(@alignCast(context));

                for (self.candidates[begin..end]) |*c| {
                    c.evaluate(T, self.lights, self.bounds, self.cone_weight, self.set, self.variant);
                }
            }
        };
    }
};

fn coneCost(cos: f32, two_sided: bool) f32 {
    const o: f32 = if (two_sided) std.math.pi else std.math.acos(cos);
    const w = math.min(o + (std.math.pi / 2.0), std.math.pi);

    const sin = @sin(o);
    const b = (std.math.pi / 2.0) * (2.0 * w * sin - @cos(o - 2.0 * w) - 2.0 * o * sin + cos);

    return (2.0 * std.math.pi) * (1.0 - cos) + b;
}
