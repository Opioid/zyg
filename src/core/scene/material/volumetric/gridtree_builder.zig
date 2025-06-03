const gt = @import("gridtree.zig");
const Gridtree = gt.Gridtree;
const Node = gt.Node;
const Box = gt.Box;
const Texture = @import("../../../image/texture/texture.zig").Texture;
const ccoef = @import("../collision_coefficients.zig");
const CC = ccoef.CC;
const CM = ccoef.CM;
const Scene = @import("../../scene.zig").Scene;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

const BuildNode = struct {
    children: []BuildNode,
    data: Vec2f,

    pub fn deinit(self: *BuildNode, alloc: Allocator) void {
        for (self.children) |*c| {
            c.deinit(alloc);
        }

        alloc.free(self.children);
    }
};

pub const Builder = struct {
    pub fn build(
        alloc: Allocator,
        tree: *Gridtree,
        texture: Texture,
        cc: CC,
        scene: *const Scene,
        threads: *Threads,
    ) !void {
        const d = texture.dimensions(scene);

        var num_cells = d >> Gridtree.Log2_cell_dim4;

        num_cells = num_cells + @min(d - (num_cells << Gridtree.Log2_cell_dim4), @as(Vec4i, @splat(1)));

        const cell_len = @as(u32, @intCast(num_cells[0] * num_cells[1] * num_cells[2]));

        var context = Context{
            .alloc = alloc,
            .grid = try alloc.alloc(BuildNode, cell_len),
            .splitters = try alloc.alloc(Splitter, threads.numThreads()),
            .num_cells = num_cells,
            .texture = texture,
            .cc = cc,
            .scene = scene,
        };

        defer {
            for (context.grid) |*c| {
                c.deinit(alloc);
            }

            alloc.free(context.grid);
        }

        // Unfortunately this is necessary because of our crappy threadpool
        threads.waitAsync();
        threads.runParallel(&context, Context.distribute, 0);

        var num_nodes = cell_len;
        var num_data: u32 = 0;
        for (context.splitters) |s| {
            num_nodes += s.num_nodes;
            num_data += s.num_data;
        }

        alloc.free(context.splitters);

        tree.setDimensions(d, num_cells);

        const nodes = try tree.allocateNodes(alloc, num_nodes);
        const data = try tree.allocateData(alloc, num_data);

        var next = cell_len;
        var data_id: u32 = 0;

        for (context.grid, 0..) |c, i| {
            serialize(c, i, &next, &data_id, nodes, data);
        }
    }

    fn serialize(node: BuildNode, current: usize, next: *u32, data_id: *u32, nodes: [*]Node, data: [*]Vec2f) void {
        var n = &nodes[current];

        if (node.children.len > 0) {
            n.setChildren(next.*);

            const cn = next.*;
            next.* += 8;

            for (node.children, 0..) |c, i| {
                serialize(c, cn + i, next, data_id, nodes, data);
            }
        } else if (node.data[1] > 0.0) {
            n.setData(data_id.*);
            data[data_id.*] = node.data;
            data_id.* += 1;
        } else {
            n.setEmpty();
        }
    }
};

const Splitter = struct {
    num_nodes: u32,
    num_data: u32,

    // Plus 2 bececause of the filtering border mentioned below
    const W = 8 + 2;

    fn split(
        self: *Splitter,
        alloc: Allocator,
        node: *BuildNode,
        box: Box,
        texture: Texture,
        cc: CC,
        depth: u32,
        scene: *const Scene,
    ) !void {
        const d = texture.dimensions(scene);

        // Include 1 additional voxel on each border to account for filtering
        const minb = @max(box.bounds[0] - @as(Vec4i, @splat(1)), @as(Vec4i, @splat(0)));
        const maxb = @min(box.bounds[1] + @as(Vec4i, @splat(1)), d);

        var min_density: f32 = std.math.floatMax(f32);
        var max_density: f32 = 0.0;

        var z = minb[2];
        while (z < maxb[2]) : (z += 1) {
            var y = minb[1];
            while (y < maxb[1]) : (y += 1) {
                var x = minb[0];
                while (x < maxb[0]) : (x += 1) {
                    const density = texture.image3D_1(x, y, z, scene);

                    min_density = math.min(density, min_density);
                    max_density = math.max(density, max_density);
                }
            }
        }

        min_density = math.max(min_density, 0.0);
        max_density = math.max(max_density, 0.0);

        if (min_density > max_density) {
            min_density = 0.0;
            max_density = 0.0;
        }

        const diff = max_density - min_density;

        if (math.allLessEqual4i((maxb - minb), .{ W, W, W, std.math.maxInt(i32) }) or diff < 0.1) {
            node.children = &.{};
            node.data = .{ min_density, max_density };

            if (max_density > 0.0) {
                self.num_data += 1;
            }

            return;
        }

        const depthp = depth + 1;

        const half = (box.bounds[1] - box.bounds[0]) >> @as(@Vector(4, u5), @splat(1));
        const center = box.bounds[0] + half;

        node.children = try alloc.alloc(BuildNode, 8);

        {
            const sub = Box{ .bounds = .{ box.bounds[0], center } };
            try self.split(alloc, &node.children[0], sub, texture, cc, depthp, scene);
        }

        {
            const sub = Box{ .bounds = .{
                .{ center[0], box.bounds[0][1], box.bounds[0][2], 0 },
                .{ box.bounds[1][0], center[1], center[2], 0 },
            } };
            try self.split(alloc, &node.children[1], sub, texture, cc, depthp, scene);
        }

        {
            const sub = Box{ .bounds = .{
                .{ box.bounds[0][0], center[1], box.bounds[0][2], 0 },
                .{ center[0], box.bounds[1][1], center[2], 0 },
            } };
            try self.split(alloc, &node.children[2], sub, texture, cc, depthp, scene);
        }

        {
            const sub = Box{ .bounds = .{
                .{ center[0], center[1], box.bounds[0][2], 0 },
                .{ box.bounds[1][0], box.bounds[1][1], center[2], 0 },
            } };
            try self.split(alloc, &node.children[3], sub, texture, cc, depthp, scene);
        }

        {
            const sub = Box{ .bounds = .{
                .{ box.bounds[0][0], box.bounds[0][1], center[2], 0 },
                .{ center[0], center[1], box.bounds[1][2], 0 },
            } };
            try self.split(alloc, &node.children[4], sub, texture, cc, depthp, scene);
        }

        {
            const sub = Box{ .bounds = .{
                .{ center[0], box.bounds[0][1], center[2], 0 },
                .{ box.bounds[1][0], center[1], box.bounds[1][2], 0 },
            } };
            try self.split(alloc, &node.children[5], sub, texture, cc, depthp, scene);
        }

        {
            const sub = Box{ .bounds = .{
                .{ box.bounds[0][0], center[1], center[2], 0 },
                .{ center[0], box.bounds[1][1], box.bounds[1][2], 0 },
            } };
            try self.split(alloc, &node.children[6], sub, texture, cc, depthp, scene);
        }

        {
            const sub = Box{ .bounds = .{ center, box.bounds[1] } };
            try self.split(alloc, &node.children[7], sub, texture, cc, depthp, scene);
        }

        self.num_nodes += 8;
    }
};

const Context = struct {
    alloc: Allocator,

    grid: []BuildNode,
    splitters: []Splitter,

    num_cells: Vec4i,

    texture: Texture,
    cc: CC,
    scene: *const Scene,

    current_task: i32 = 0,

    fn distribute(context: Threads.Context, id: u32) void {
        const self: *Context = @ptrCast(@alignCast(context));

        var splitter = &self.splitters[id];
        splitter.num_nodes = 0;
        splitter.num_data = 0;

        const num_cells = self.num_cells;
        const area = num_cells[0] * num_cells[1];
        const cell_len = area * num_cells[2];

        while (true) {
            const i = @atomicRmw(i32, &self.current_task, .Add, 1, .monotonic);

            if (i >= cell_len) {
                return;
            }

            var c: Vec4i = undefined;
            c[2] = @divTrunc(i, area);
            const t = c[2] * area;
            c[1] = @divTrunc(i - t, num_cells[0]);
            c[0] = i - (t + c[1] * num_cells[0]);
            c[3] = 0;

            const min = c << Gridtree.Log2_cell_dim4;
            const max = min + @as(Vec4i, @splat(Gridtree.Cell_dim));
            const box = Box{ .bounds = .{ min, max } };

            splitter.split(
                self.alloc,
                &self.grid[@as(u32, @intCast(i))],
                box,
                self.texture,
                self.cc,
                0,
                self.scene,
            ) catch {};
        }
    }
};
