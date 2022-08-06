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
const Vec3i = math.Vec3i;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

const BuildNode = struct {
    children: []BuildNode, // = &.{},
    data: CM,

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
        scene: Scene,
        threads: *Threads,
    ) !void {
        const d = texture.description(scene).dimensions;

        var num_cells = d.shiftRight(Gridtree.Log2_cell_dim);

        num_cells = num_cells.add(d.sub(num_cells.shiftLeft(Gridtree.Log2_cell_dim)).min1(1));

        const cell_len = @intCast(u32, num_cells.v[0] * num_cells.v[1] * num_cells.v[2]);

        std.debug.print("num_cells {} cell_len {}\n", .{ num_cells, cell_len });

        var context = Context{
            .alloc = alloc,
            .grid = try alloc.alloc(BuildNode, cell_len),
            .splitters = try alloc.alloc(Splitter, threads.numThreads()),
            .num_cells = num_cells,
            .texture = texture,
            .cc = cc,
            .scene = &scene,
        };

        defer {
            for (context.grid) |*c| {
                c.deinit(alloc);
            }

            alloc.free(context.grid);
        }

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

        for (context.grid) |c, i| {
            serialize(c, i, &next, &data_id, nodes, data);
        }
    }

    fn serialize(node: BuildNode, current: usize, next: *u32, data_id: *u32, nodes: [*]Node, data: [*]CM) void {
        var n = &nodes[current];

        if (node.children.len > 0) {
            n.setChildren(next.*);

            const cn = next.*;
            next.* += 8;

            for (node.children) |c, i| {
                serialize(c, cn + i, next, data_id, nodes, data);
            }
        } else if (!node.data.isEmpty()) {
            n.setData(data_id.*);
            data[data_id.*] = node.data;
            data_id.* += 1;
        } else {
            n.setEmpty();
        }
    }
};

const Splitter = struct {
    const SplitError = error{
        OutOfMemory,
    };

    num_nodes: u32,
    num_data: u32,

    const W: i32 = (Gridtree.Cell_dim >> (Gridtree.Log2_cell_dim - 3)) + 1;

    fn split(
        self: *Splitter,
        alloc: Allocator,
        node: *BuildNode,
        box: Box,
        texture: Texture,
        cc: CC,
        depth: u32,
        scene: Scene,
    ) SplitError!void {
        const d = texture.description(scene).dimensions;

        // Include 1 additional voxel on each border to account for filtering
        const minb = box.bounds[0].subScalar(1).max1(0);
        const maxb = box.bounds[1].addScalar(1).min3(d);

        var min_density: f32 = 1.0;
        var max_density: f32 = 0.0;

        var z = minb.v[2];
        while (z < maxb.v[2]) : (z += 1) {
            var y = minb.v[1];
            while (y < maxb.v[1]) : (y += 1) {
                var x = minb.v[0];
                while (x < maxb.v[0]) : (x += 1) {
                    const density = texture.get3D_1(x, y, z, scene);

                    min_density = std.math.min(density, min_density);
                    max_density = std.math.max(density, max_density);
                }
            }
        }

        if (min_density > max_density) {
            min_density = 0.0;
            max_density = 0.0;
        }

        const cm = CM.initCC(cc);

        const minorant_mu_a = min_density * cm.minorant_mu_a;
        const minorant_mu_s = min_density * cm.minorant_mu_s;
        const majorant_mu_a = max_density * cm.majorant_mu_a;
        const majorant_mu_s = max_density * cm.majorant_mu_s;

        const diff = max_density - min_density;

        if (Gridtree.Log2_cell_dim - 3 == depth or diff < 0.1 or maxb.sub(minb).anyLess1(W)) {
            node.children = &.{};

            var data = &node.data;

            if (0.0 == diff) {
                data.minorant_mu_a = minorant_mu_a;
                data.minorant_mu_s = minorant_mu_s;
                data.majorant_mu_a = majorant_mu_a;
                data.majorant_mu_s = majorant_mu_s;
            } else {
                data.minorant_mu_a = std.math.max(minorant_mu_a, 0.0);
                data.minorant_mu_s = std.math.max(minorant_mu_s, 0.0);
                data.majorant_mu_a = majorant_mu_a;
                data.majorant_mu_s = majorant_mu_s;
            }

            if (!data.isEmpty()) {
                self.num_data += 1;
            }

            return;
        }

        const depthp = depth + 1;

        const half = box.bounds[1].sub(box.bounds[0]).shiftRight(1);
        const center = box.bounds[0].add(half);

        node.children = try alloc.alloc(BuildNode, 8);

        {
            const sub = Box{ .bounds = .{ box.bounds[0], center } };
            try self.split(alloc, &node.children[0], sub, texture, cc, depthp, scene);
        }

        {
            const sub = Box{ .bounds = .{
                Vec3i.init3(center.v[0], box.bounds[0].v[1], box.bounds[0].v[2]),
                Vec3i.init3(box.bounds[1].v[0], center.v[1], center.v[2]),
            } };
            try self.split(alloc, &node.children[1], sub, texture, cc, depthp, scene);
        }

        {
            const sub = Box{ .bounds = .{
                Vec3i.init3(box.bounds[0].v[0], center.v[1], box.bounds[0].v[2]),
                Vec3i.init3(center.v[0], box.bounds[1].v[1], center.v[2]),
            } };
            try self.split(alloc, &node.children[2], sub, texture, cc, depthp, scene);
        }

        {
            const sub = Box{ .bounds = .{
                Vec3i.init3(center.v[0], center.v[1], box.bounds[0].v[2]),
                Vec3i.init3(box.bounds[1].v[0], box.bounds[1].v[1], center.v[2]),
            } };
            try self.split(alloc, &node.children[3], sub, texture, cc, depthp, scene);
        }

        {
            const sub = Box{ .bounds = .{
                Vec3i.init3(box.bounds[0].v[0], box.bounds[0].v[1], center.v[2]),
                Vec3i.init3(center.v[0], center.v[1], box.bounds[1].v[2]),
            } };
            try self.split(alloc, &node.children[4], sub, texture, cc, depthp, scene);
        }

        {
            const sub = Box{ .bounds = .{
                Vec3i.init3(center.v[0], box.bounds[0].v[1], center.v[2]),
                Vec3i.init3(box.bounds[1].v[0], center.v[1], box.bounds[1].v[2]),
            } };
            try self.split(alloc, &node.children[5], sub, texture, cc, depthp, scene);
        }

        {
            const sub = Box{ .bounds = .{
                Vec3i.init3(box.bounds[0].v[0], center.v[1], center.v[2]),
                Vec3i.init3(center.v[0], box.bounds[1].v[1], box.bounds[1].v[2]),
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

    num_cells: Vec3i,

    texture: Texture,
    cc: CC,
    scene: *const Scene,

    current_task: i32 = 0,

    fn distribute(context: Threads.Context, id: u32) void {
        const self = @intToPtr(*Context, context);

        var splitter = &self.splitters[id];
        splitter.num_nodes = 0;
        splitter.num_data = 0;

        const num_cells = self.num_cells;
        const area = num_cells.v[0] * num_cells.v[1];
        const cell_len = area * num_cells.v[2];

        while (true) {
            const i = @atomicRmw(i32, &self.current_task, .Add, 1, .Monotonic);

            if (i >= cell_len) {
                return;
            }

            var c: Vec3i = undefined;
            c.v[2] = @divTrunc(i, area);
            const t = c.v[2] * area;
            c.v[1] = @divTrunc(i - t, num_cells.v[0]);
            c.v[0] = i - (t + c.v[1] * num_cells.v[0]);

            const min = c.shiftLeft(Gridtree.Log2_cell_dim);
            const max = min.add(Vec3i.init1(Gridtree.Cell_dim));
            const box = Box{ .bounds = .{ min, max } };

            splitter.split(
                self.alloc,
                &self.grid[@intCast(u32, i)],
                box,
                self.texture,
                self.cc,
                0,
                self.scene.*,
            ) catch {};
        }
    }
};
