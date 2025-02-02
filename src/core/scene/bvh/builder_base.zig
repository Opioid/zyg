const log = @import("../../log.zig");
const Node = @import("node.zig").Node;
const spc = @import("split_candidate.zig");
const SplitCandidate = spc.SplitCandidate;
const Reference = spc.Reference;
const References = spc.References;

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Parallelize_threshold = 1024;

const Task = struct {
    kernel: Kernel,

    root: u32,
    depth: u32,

    aabb: AABB,

    references: []const Reference,
};

const Tasks = std.ArrayListUnmanaged(Task);

const Kernel = struct {
    pub const Settings = struct {
        num_slices: u32,
        sweep_threshold: u32,
        max_primitives: u32,
        spatial_split_threshold: u32 = undefined,
        parallel_build_depth: u32 = undefined,
    };

    settings: Settings,

    split_candidates: std.ArrayListUnmanaged(SplitCandidate),
    reference_ids: std.ArrayListUnmanaged(u32) = .empty,
    build_nodes: std.ArrayListUnmanaged(Node) = .empty,

    aabb_surface_area: f32 = undefined,
    references: []const Reference = undefined,

    pub fn init(alloc: Allocator, settings: Settings) !Kernel {
        return Kernel{
            .settings = settings,
            .split_candidates = try std.ArrayListUnmanaged(SplitCandidate).initCapacity(
                alloc,
                3 + @max(3 * settings.sweep_threshold, 3 * 2 * settings.num_slices),
            ),
        };
    }

    pub fn deinit(self: *Kernel, alloc: Allocator) void {
        self.split_candidates.deinit(alloc);
        self.reference_ids.deinit(alloc);
        self.build_nodes.deinit(alloc);
    }

    fn split(
        self: *Kernel,
        alloc: Allocator,
        node_id: u32,
        references: []const Reference,
        aabb: AABB,
        depth: u32,
        threads: *Threads,
        tasks: *Tasks,
    ) !void {
        var node = &self.build_nodes.items[node_id];
        node.setAABB(aabb);

        const num_primitives: u32 = @intCast(references.len);
        if (num_primitives <= self.settings.max_primitives) {
            try self.assign(alloc, node, references);
            alloc.free(references);
        } else {
            if (!threads.running_parallel and tasks.capacity > 0 and
                (num_primitives < Parallelize_threshold or depth == self.settings.parallel_build_depth))
            {
                try tasks.append(alloc, .{
                    .kernel = try Kernel.init(alloc, self.settings),
                    .root = node_id,
                    .depth = depth,
                    .aabb = aabb,
                    .references = references,
                });

                return;
            }

            defer alloc.free(references);

            const spo = self.splittingPlane(references, aabb, depth, threads);
            if (spo) |sp| {
                if (num_primitives <= 0xFF and @as(f32, @floatFromInt(num_primitives)) <= sp.cost) {
                    try self.assign(alloc, node, references);
                } else {
                    var references0: References = undefined;
                    var references1: References = undefined;
                    try sp.distribute(alloc, references, &references0, &references1);

                    if (num_primitives <= 0x2FF and (0 == references0.items.len or 0 == references1.items.len)) {
                        // This can happen if we didn't find a good splitting plane.
                        // It means every triangle was (partially) on the same side of the plane.
                        try self.assign(alloc, node, references);
                    } else {
                        const child0: u32 = @intCast(self.build_nodes.items.len);

                        node.setSplitNode(child0);

                        try self.build_nodes.append(alloc, undefined);
                        try self.build_nodes.append(alloc, undefined);

                        const next_depth = depth + 1;

                        try self.split(
                            alloc,
                            child0,
                            try references0.toOwnedSlice(alloc),
                            sp.aabbs[0].intersection(aabb),
                            next_depth,
                            threads,
                            tasks,
                        );

                        try self.split(
                            alloc,
                            child0 + 1,
                            try references1.toOwnedSlice(alloc),
                            sp.aabbs[1].intersection(aabb),
                            next_depth,
                            threads,
                            tasks,
                        );
                    }
                }
            } else {
                if (num_primitives <= 0x2FF) {
                    try self.assign(alloc, node, references);
                } else {
                    log.err("Cannot split node further with {} primitives", .{num_primitives});
                }
            }
        }
    }

    pub fn splittingPlane(
        self: *Kernel,
        references: []const Reference,
        aabb: AABB,
        depth: u32,
        threads: *Threads,
    ) ?SplitCandidate {
        const X = 0;
        const Y = 1;
        const Z = 2;

        self.split_candidates.clearRetainingCapacity();

        const num_references: u32 = @intCast(references.len);

        const position = aabb.position();

        self.split_candidates.appendAssumeCapacity(SplitCandidate.init(X, position, true));
        self.split_candidates.appendAssumeCapacity(SplitCandidate.init(Y, position, true));
        self.split_candidates.appendAssumeCapacity(SplitCandidate.init(Z, position, true));

        if (num_references <= self.settings.sweep_threshold) {
            for (references) |r| {
                const max = r.bound(1);
                self.split_candidates.appendAssumeCapacity(SplitCandidate.init(X, max, false));
                self.split_candidates.appendAssumeCapacity(SplitCandidate.init(Y, max, false));
                self.split_candidates.appendAssumeCapacity(SplitCandidate.init(Z, max, false));
            }
        } else {
            const extent = aabb.extent();
            const min = aabb.bounds[0];

            const la = math.indexMaxComponent3(extent);
            const step = extent[la] / @as(f32, @floatFromInt(self.settings.num_slices));

            for (0..3) |a| {
                const a8: u8 = @intCast(a);
                const extent_a = extent[a];
                const num_steps = @max(1, @as(u32, @intFromFloat(@ceil(extent_a / step))));
                const step_a = extent_a / @as(f32, @floatFromInt(num_steps));

                for (1..num_steps) |i| {
                    const fi: f32 = @floatFromInt(i);

                    var slice = position;
                    slice[a] = min[a] + fi * step_a;
                    self.split_candidates.appendAssumeCapacity(SplitCandidate.init(a8, slice, false));

                    if (depth < self.settings.spatial_split_threshold) {
                        self.split_candidates.appendAssumeCapacity(SplitCandidate.init(a8, slice, true));
                    }
                }
            }
        }

        const aabb_surface_area = aabb.surfaceArea();

        if (threads.running_parallel or references.len < Parallelize_threshold) {
            for (self.split_candidates.items) |*sc| {
                sc.evaluate(references, aabb_surface_area);
            }
        } else {
            self.aabb_surface_area = aabb_surface_area;
            self.references = references;

            _ = threads.runRange(self, evaluateRange, 0, @intCast(self.split_candidates.items.len), 0);
        }

        var sc: usize = 0;
        var min_cost = self.split_candidates.items[0].cost;

        for (self.split_candidates.items[1..], 1..) |c, i| {
            const cost = c.cost;
            if (cost < min_cost) {
                sc = i;
                min_cost = cost;
            }
        }

        const sp = self.split_candidates.items[sc];

        if ((sp.aabbs[0].covers(aabb) and num_references == sp.num_sides[0]) or
            (sp.aabbs[1].covers(aabb) and num_references == sp.num_sides[1]))
        {
            return null;
        }

        return sp;
    }

    fn evaluateRange(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;

        const self: *Kernel = @ptrCast(context);

        const aabb_surface_area = self.aabb_surface_area;
        const references = self.references;

        for (self.split_candidates.items[begin..end]) |*sc| {
            sc.evaluate(references, aabb_surface_area);
        }
    }

    pub fn assign(self: *Kernel, alloc: Allocator, node: *Node, references: []const Reference) !void {
        const num_references: u32 = @intCast(references.len);

        node.setLeafNode(@intCast(self.reference_ids.items.len), num_references);

        for (references) |r| {
            try self.reference_ids.append(alloc, r.primitive());
        }
    }

    pub fn reserve(self: *Kernel, alloc: Allocator, num_primitives: u32, settings: Settings) !void {
        self.settings = settings;

        try self.build_nodes.ensureTotalCapacity(
            alloc,
            @max((3 * num_primitives) / settings.max_primitives, 1),
        );

        self.build_nodes.clearRetainingCapacity();
        try self.build_nodes.append(alloc, undefined);

        try self.reference_ids.ensureTotalCapacity(alloc, (num_primitives * 12) / 10);
        self.reference_ids.clearRetainingCapacity();
    }
};

pub const Base = struct {
    settings: Kernel.Settings,

    kernel: Kernel,

    current_node: u32 = undefined,
    current_task: u32 = undefined,

    alloc: Allocator = undefined,
    threads: *Threads = undefined,
    tasks: *Tasks = undefined,

    pub fn init(alloc: Allocator, num_slices: u32, sweep_threshold: u32, max_primitives: u32) !Base {
        const settings = Kernel.Settings{
            .num_slices = num_slices,
            .sweep_threshold = sweep_threshold,
            .max_primitives = max_primitives,
        };

        return Base{
            .settings = settings,
            .kernel = try Kernel.init(alloc, settings),
        };
    }

    pub fn deinit(self: *Base, alloc: Allocator) void {
        self.kernel.deinit(alloc);
    }

    pub fn numReferenceIds(self: *const Base) u32 {
        return @intCast(self.kernel.reference_ids.items.len);
    }

    pub fn numBuildNodes(self: *const Base) u32 {
        return @intCast(self.kernel.build_nodes.items.len);
    }

    pub fn split(
        self: *Base,
        alloc: Allocator,
        references: []const Reference,
        aabb: AABB,
        threads: *Threads,
    ) !void {
        const log2_num_references = std.math.log2(@as(f32, @floatFromInt(references.len)));
        self.settings.spatial_split_threshold = @intFromFloat(@round(log2_num_references / 2.0));
        self.settings.parallel_build_depth = @min(self.settings.spatial_split_threshold, 6);

        try self.kernel.reserve(alloc, @intCast(references.len), self.settings);
        self.current_node = 0;

        const num_tasks = @min(
            try std.math.powi(u32, 2, self.settings.parallel_build_depth),
            @as(u32, @intCast(references.len / Parallelize_threshold)),
        );

        var tasks: Tasks = if (num_tasks > 0) try Tasks.initCapacity(alloc, num_tasks) else .{};
        defer {
            for (tasks.items) |*t| {
                t.kernel.deinit(alloc);
            }
            tasks.deinit(alloc);
        }

        try self.kernel.split(alloc, 0, references, aabb, 0, threads, &tasks);
        try self.workOnTasks(alloc, threads, &tasks);
    }

    pub fn workOnTasks(self: *Base, alloc: Allocator, threads: *Threads, tasks: *Tasks) !void {
        if (0 == tasks.items.len) {
            return;
        }

        self.current_task = 0;
        self.alloc = alloc;
        self.threads = threads;
        self.tasks = tasks;
        threads.runParallel(self, workOnTasksParallel, @intCast(tasks.items.len));

        for (tasks.items) |t| {
            const children = t.kernel.build_nodes.items;

            var parent = &self.kernel.build_nodes.items[t.root];

            parent.* = children[0];

            if (1 == children.len) {
                continue;
            }

            const node_offset: u32 = @intCast(self.kernel.build_nodes.items.len - 1);
            const reference_offset: u32 = @intCast(self.kernel.reference_ids.items.len);

            try self.kernel.reference_ids.appendSlice(alloc, t.kernel.reference_ids.items);

            parent.offset(node_offset);

            for (children[1..]) |sn| {
                try self.kernel.build_nodes.append(
                    alloc,
                    Node.initFrom(sn, if (0 == sn.numIndices()) node_offset else reference_offset),
                );
            }
        }
    }

    fn workOnTasksParallel(context: Threads.Context, id: u32) void {
        _ = id;

        const self: *Base = @ptrCast(context);

        const num_tasks: u32 = @intCast(self.tasks.items.len);

        while (true) {
            const current = @atomicRmw(u32, &self.current_task, .Add, 1, .monotonic);

            if (current >= num_tasks) {
                return;
            }

            var t = &self.tasks.items[current];
            t.kernel.reserve(self.alloc, @intCast(t.references.len), self.settings) catch {};
            t.kernel.split(self.alloc, 0, t.references, t.aabb, t.depth, self.threads, self.tasks) catch {};
        }
    }

    pub fn newNode(self: *Base) void {
        self.current_node += 1;
    }

    pub fn currentNodeIndex(self: *const Base) u32 {
        return self.current_node;
    }
};
