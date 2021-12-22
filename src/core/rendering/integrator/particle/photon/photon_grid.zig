const Photon = @import("photon.zig").Photon;
const Worker = @import("../../../worker.zig").Worker;
const Intersection = @import("../../../../scene/prop/intersection.zig").Intersection;
const MaterialSample = @import("../../../../scene/material/sample.zig").Sample;
const mat = @import("../../../../scene/material/sample_helper.zig");

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec2i = math.Vec2i;
const Vec2f = math.Vec2f;
const Vec3i = math.Vec3i;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Grid = struct {
    const Adjacency = struct {
        num_cells: u32,
        cells: [4]Vec2i,
    };

    photons: []Photon = &.{},

    aabb: AABB = undefined,

    search_radius: f32 = undefined,
    grid_cell_factor: f32 = undefined,
    surface_normalization: f32 = undefined,

    cell_bound: Vec2f = undefined,

    dimensions: Vec3i = undefined,

    local_to_texture: Vec4f = undefined,

    grid: []u32 = &.{},

    adjacencies: [43]Adjacency = undefined,

    const Self = @This();

    pub fn configure(self: *Self, search_radius: f32, grid_cell_factor: f32) void {
        self.search_radius = search_radius;
        self.grid_cell_factor = grid_cell_factor;
        self.cell_bound = .{ 0.5 / grid_cell_factor, 1.0 - (0.5 / grid_cell_factor) };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.grid);
    }

    pub fn resize(self: *Self, alloc: Allocator, aabb: AABB) !void {
        self.aabb = aabb;

        const diameter = 2.0 * self.search_radius;
        const dimensions = math.vec4fTo3i(@ceil(aabb.extent() / @splat(4, diameter * self.grid_cell_factor))).addScalar(2);

        if (!self.dimensions.equal(dimensions)) {
            std.debug.print("{}\n", .{dimensions});

            self.dimensions = dimensions;

            self.local_to_texture = @splat(4, @as(f32, 1.0)) / aabb.extent() * math.vec3iTo4f(dimensions.subScalar(2));

            const num_cells = @intCast(usize, dimensions.v[0]) * @intCast(usize, dimensions.v[1]) * @intCast(usize, dimensions.v[2]) + 1;

            self.grid = try alloc.realloc(self.grid, num_cells);

            const area = dimensions.v[0] * dimensions.v[1];

            const o_m1__0__0 = -1;
            const o_p1__0__0 = 1;

            const o__0_m1__0 = -dimensions.v[0];
            const o__0_p1__0 = dimensions.v[0];

            const o__0__0_m1 = -area;
            const o__0__0_p1 = area;

            const o_m1_m1__0 = -1 - dimensions.v[0];
            const o_m1_p1__0 = -1 + dimensions.v[0];
            const o_p1_m1__0 = 1 - dimensions.v[0];
            const o_p1_p1__0 = 1 + dimensions.v[0];

            const o_m1_m1_m1 = -1 - dimensions.v[0] - area;
            const o_m1_m1_p1 = -1 - dimensions.v[0] + area;
            const o_m1_p1_m1 = -1 + dimensions.v[0] - area;
            const o_m1_p1_p1 = -1 + dimensions.v[0] + area;

            const o_p1_m1_m1 = 1 - dimensions.v[0] - area;
            const o_p1_m1_p1 = 1 - dimensions.v[0] + area;
            const o_p1_p1_m1 = 1 + dimensions.v[0] - area;
            const o_p1_p1_p1 = 1 + dimensions.v[0] + area;

            const o_m1__0_m1 = -1 - area;
            const o_m1__0_p1 = -1 + area;
            const o_p1__0_m1 = 1 - area;
            const o_p1__0_p1 = 1 + area;

            const o__0_m1_m1 = -dimensions.v[0] - area;
            const o__0_m1_p1 = -dimensions.v[0] + area;
            const o__0_p1_m1 = dimensions.v[0] - area;
            const o__0_p1_p1 = dimensions.v[0] + area;

            // 00, 00, 00
            self.adjacencies[0] = .{
                .num_cells = 1,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 00, 00, 01
            self.adjacencies[1] = .{
                .num_cells = 2,
                .cells = .{ .{ 0, 0 }, @splat(2, o__0__0_p1), .{ 0, 0 }, .{ 0, 0 } },
            };

            // 00, 00, 10
            self.adjacencies[2] = .{
                .num_cells = 2,
                .cells = .{ @splat(2, o__0__0_m1), .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };
            self.adjacencies[3] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 00, 01, 00
            self.adjacencies[4] = .{
                .num_cells = 2,
                .cells = .{ .{ 0, 0 }, @splat(2, o__0_p1__0), .{ 0, 0 }, .{ 0, 0 } },
            };

            // 00, 01, 01
            self.adjacencies[5] = .{
                .num_cells = 4,
                .cells = .{ .{ 0, 0 }, @splat(2, o__0_p1__0), @splat(2, o__0__0_p1), @splat(2, o__0_p1_p1) },
            };

            // 00, 01, 10
            self.adjacencies[6] = .{
                .num_cells = 4,
                .cells = .{ @splat(2, o__0__0_m1), @splat(2, o__0_p1_m1), .{ 0, 0 }, @splat(2, o__0_p1__0) },
            };
            self.adjacencies[7] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 00, 10, 00
            self.adjacencies[8] = .{
                .num_cells = 2,
                .cells = .{ @splat(2, o__0_m1__0), .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 00, 10, 01
            self.adjacencies[9] = .{
                .num_cells = 4,
                .cells = .{ @splat(2, o__0_m1__0), @splat(2, o__0_m1_p1), .{ 0, 0 }, @splat(2, o__0__0_p1) },
            };

            // 00, 10, 10
            self.adjacencies[10] = .{
                .num_cells = 4,
                .cells = .{ @splat(2, o__0_m1_m1), @splat(2, o__0__0_m1), @splat(2, o__0_m1__0), .{ 0, 0 } },
            };
            self.adjacencies[11] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };
            self.adjacencies[12] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };
            self.adjacencies[13] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };
            self.adjacencies[14] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };
            self.adjacencies[15] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 01, 00, 00
            self.adjacencies[16] = .{
                .num_cells = 1,
                .cells = .{ .{ 0, o_p1__0__0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 01, 00, 01
            self.adjacencies[17] = .{
                .num_cells = 2,
                .cells = .{ .{ 0, o_p1__0__0 }, .{ o__0__0_p1, o_p1__0_p1 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 01, 00, 10
            self.adjacencies[18] = .{
                .num_cells = 2,
                .cells = .{ .{ o__0__0_m1, o_p1__0_m1 }, .{ 0, o_p1__0__0 }, .{ 0, 0 }, .{ 0, 0 } },
            };
            self.adjacencies[19] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 01, 01, 00
            self.adjacencies[20] = .{
                .num_cells = 2,
                .cells = .{ .{ 0, o_p1__0__0 }, .{ o__0_p1__0, o_p1_p1__0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 01, 01, 01
            self.adjacencies[21] = .{
                .num_cells = 4,
                .cells = .{ .{ 0, o_p1__0__0 }, .{ o__0_p1__0, o_p1_p1__0 }, .{ o__0__0_p1, o_p1__0_p1 }, .{ o__0_p1_p1, o_p1_p1_p1 } },
            };

            // 01, 01, 10
            self.adjacencies[22] = .{
                .num_cells = 4,
                .cells = .{ .{ o__0__0_m1, o_p1__0_m1 }, .{ o__0_p1_m1, o_p1_p1_m1 }, .{ 0, o_p1__0__0 }, .{ o__0_p1__0, o_p1_p1__0 } },
            };
            self.adjacencies[23] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 01, 10, 00
            self.adjacencies[24] = .{
                .num_cells = 2,
                .cells = .{ .{ o__0_m1__0, o_p1_m1__0 }, .{ 0, o_p1__0__0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 01, 10, 01
            self.adjacencies[25] = .{
                .num_cells = 4,
                .cells = .{ .{ o__0_m1__0, o_p1_m1__0 }, .{ o__0_m1_p1, o_p1_m1_p1 }, .{ 0, o_p1__0__0 }, .{ o__0__0_p1, o_p1__0_p1 } },
            };

            // 01, 10, 10
            self.adjacencies[26] = .{
                .num_cells = 4,
                .cells = .{ .{ o__0_m1_m1, o_p1_m1_m1 }, .{ o__0__0_m1, o_p1__0_m1 }, .{ o__0_m1__0, o_p1_m1__0 }, .{ 0, o_p1__0__0 } },
            };
            self.adjacencies[27] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };
            self.adjacencies[28] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };
            self.adjacencies[29] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };
            self.adjacencies[30] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };
            self.adjacencies[31] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 10, 00, 00
            self.adjacencies[32] = .{
                .num_cells = 1,
                .cells = .{ .{ o_m1__0__0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 10, 00, 01
            self.adjacencies[33] = .{
                .num_cells = 2,
                .cells = .{ .{ o_m1__0__0, 0 }, .{ o_m1__0_p1, o__0__0_p1 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 10, 00, 10
            self.adjacencies[34] = .{
                .num_cells = 2,
                .cells = .{ .{ o_m1__0_m1, o__0__0_m1 }, .{ o_m1__0__0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };
            self.adjacencies[35] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 10, 01, 00
            self.adjacencies[36] = .{
                .num_cells = 2,
                .cells = .{ .{ o_m1__0__0, 0 }, .{ o_m1_p1__0, o__0_p1__0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 10, 01, 01
            self.adjacencies[37] = .{
                .num_cells = 4,
                .cells = .{ .{ o_m1__0__0, 0 }, .{ o_m1__0_p1, o__0__0_p1 }, .{ o_m1_p1__0, o__0_p1__0 }, .{ o_m1_p1_p1, o__0_p1_p1 } },
            };

            // 10, 01, 10
            self.adjacencies[38] = .{
                .num_cells = 4,
                .cells = .{ .{ o_m1__0_m1, o__0__0_m1 }, .{ o_m1_p1_m1, o__0_p1_m1 }, .{ o_m1__0__0, 0 }, .{ o_m1_p1__0, o__0_p1__0 } },
            };
            self.adjacencies[39] = .{
                .num_cells = 0,
                .cells = .{ .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 10, 10, 00
            self.adjacencies[40] = .{
                .num_cells = 2,
                .cells = .{ .{ o_m1_m1__0, o__0_m1__0 }, .{ o_m1__0__0, 0 }, .{ 0, 0 }, .{ 0, 0 } },
            };

            // 10, 10, 01
            self.adjacencies[41] = .{
                .num_cells = 4,
                .cells = .{ .{ o_m1_m1__0, o__0_m1__0 }, .{ o_m1_m1_p1, o__0_m1_p1 }, .{ o_m1__0__0, 0 }, .{ o_m1__0_p1, o__0__0_p1 } },
            };

            // 10, 10, 10
            self.adjacencies[42] = .{
                .num_cells = 4,
                .cells = .{ .{ o_m1_m1_m1, o__0_m1_m1 }, .{ o_m1__0_m1, o__0__0_m1 }, .{ o_m1_m1__0, o__0_m1__0 }, .{ o_m1__0__0, 0 } },
            };
        }
    }

    pub fn initCells(self: *Self, photons: []Photon) void {
        self.photons = photons;

        std.sort.sort(Photon, photons, self.*, compareByMap);

        var current: u32 = 0;
        for (self.grid) |*cell, c| {
            cell.* = current;
            while (current < photons.len) : (current += 1) {
                if (self.map1(self.photons[current].p) != c) {
                    break;
                }
            }
        }
    }

    pub fn reduceAndMove(self: *Self, photons: []Photon, threads: *Threads) u32 {
        self.photons = photons;

        _ = threads.runRange(self, reduceRange, 0, @intCast(u32, photons.len));

        return @intCast(u32, base.memory.partition(Photon, photons, {}, alphaPositive));
    }

    fn alphaPositive(context: void, p: Photon) bool {
        _ = context;
        return p.alpha[0] >= 0.0;
    }

    pub fn reduceRange(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;
        const self = @intToPtr(*Self, context);

        const merge_radius: f32 = self.search_radius / 10.0;
        const merge_grid_cell_factor = (self.search_radius * self.grid_cell_factor) / merge_radius;
        const cell_bound = Vec2f{ 0.5 / merge_grid_cell_factor, 1.0 - (0.5 / merge_grid_cell_factor) };
        const merge_radius2 = merge_radius * merge_radius;

        var i = begin;
        while (i < end) : (i += 1) {
            var a = &self.photons[i];

            if (a.alpha[0] < 0.0) {
                continue;
            }

            var a_alpha = Vec4f{ a.alpha[0], a.alpha[1], a.alpha[2], 0.0 };
            var total_weight = math.average3(a_alpha);
            var position = @splat(4, total_weight) * a.p;
            var wi = a.wi;

            var local_reduced: u32 = 0;

            const adjacency = self.adjacentCells(a.p, cell_bound);

            for (adjacency.cells[0..adjacency.num_cells]) |cell| {
                var j = std.math.max(@intCast(u32, cell[0]), i + 1);
                const jlen = std.math.min(@intCast(u32, cell[1]), end);
                while (j < jlen) : (j += 1) {
                    if (j == i) {
                        continue;
                    }

                    var b = &self.photons[j];

                    if (b.alpha[0] < 0.0) {
                        continue;
                    }

                    if (math.squaredDistance3(a.p, b.p) > merge_radius2) {
                        continue;
                    }

                    const b_alpha = Vec4f{ b.alpha[0], b.alpha[1], b.alpha[2], 0.0 };
                    const weight = math.average3(b_alpha);
                    const ratio = if (total_weight > weight) weight / total_weight else total_weight / weight;
                    const threshold = std.math.max(ratio - 0.1, 0.0);

                    if (math.dot3(wi, b.wi) < threshold) {
                        continue;
                    }

                    a_alpha += b_alpha;

                    b.alpha[0] = -1.0;

                    if (weight > total_weight) {
                        wi = b.wi;
                    }

                    total_weight += weight;

                    position += @splat(4, weight) * b.p;

                    local_reduced += 1;
                }
            }

            if (local_reduced > 0) {
                if (total_weight < 1.0e-10) {
                    a.alpha[0] = -1.0;
                    local_reduced += 1;
                } else {
                    a.p = position / @splat(4, total_weight);
                    a.wi = wi;
                    a.alpha[0] = a_alpha[0];
                    a.alpha[1] = a_alpha[1];
                    a.alpha[2] = a_alpha[2];
                }
            }
        }
    }

    fn compareByMap(self: Self, a: Photon, b: Photon) bool {
        const ida = self.map1(a.p);
        const idb = self.map1(b.p);
        return ida < idb;
    }

    fn map1(self: Self, v: Vec4f) u32 {
        const c = math.vec4fTo3i((v - self.aabb.bounds[0]) * self.local_to_texture).addScalar(1);
        return (@intCast(u32, c.v[2]) * @intCast(u32, self.dimensions.v[1]) + @intCast(u32, c.v[1])) *
            @intCast(u32, self.dimensions.v[0]) +
            @intCast(u32, c.v[0]);
    }

    fn map3(self: Self, v: Vec4f, cell_bound: Vec2f, adjacents: *u8) Vec3i {
        const r = (v - self.aabb.bounds[0]) * self.local_to_texture;
        const c = math.vec4fTo3i(r);
        const d = r - math.vec3iTo4f(c);

        adjacents.* = adjacent(d[0], cell_bound) << 4;
        adjacents.* |= adjacent(d[1], cell_bound) << 2;
        adjacents.* |= adjacent(d[2], cell_bound);

        return c.addScalar(1);
    }

    const Adjacent = enum(u8) {
        None = 0,
        Positive = 1,
        Negative = 2,
    };

    fn adjacent(s: f32, cell_bound: Vec2f) u8 {
        if (s < cell_bound[0]) {
            return @enumToInt(Adjacent.Negative);
        }

        if (s > cell_bound[1]) {
            return @enumToInt(Adjacent.Positive);
        }

        return @enumToInt(Adjacent.None);
    }

    fn adjacentCells(self: Self, v: Vec4f, cell_bound: Vec2f) Adjacency {
        var adjacents: u8 = undefined;
        const c = self.map3(v, cell_bound, &adjacents);
        const ic = (c.v[2] * self.dimensions.v[1] + c.v[1]) * self.dimensions.v[0] + c.v[0];

        var adjacency = self.adjacencies[adjacents];

        var i: u32 = 0;
        while (i < adjacency.num_cells) : (i += 1) {
            const cells = adjacency.cells[i];

            adjacency.cells[i][0] = @intCast(i32, self.grid[@intCast(usize, cells[0] + ic)]);
            adjacency.cells[i][1] = @intCast(i32, self.grid[@intCast(usize, cells[1] + ic + 1)]);
        }

        return adjacency;
    }

    pub fn setNumPaths(self: *Self, num_paths: u64) void {
        const radius = self.search_radius;
        const radius2 = radius * radius;

        // conely
        // self.surface_normalization = 1.0 / (((1.0 / 2.0) * std.math.pi) * @intToFloat(f32, num_paths) * radius2);

        // cone
        self.surface_normalization = 1.0 / (((1.0 / 3.0) * std.math.pi) * @intToFloat(f32, num_paths) * radius2);
    }

    pub fn li(self: Self, isec: Intersection, sample: MaterialSample, worker: Worker) Vec4f {
        _ = worker;

        var result = @splat(4, @as(f32, 0.0));

        const position = isec.geo.p;

        if (!self.aabb.pointInside(position)) {
            return result;
        }

        const adjacency = self.adjacentCells(position, self.cell_bound);

        const radius = self.search_radius;
        const radius2 = radius * radius;
        const inv_radius2 = 1.0 / radius2;

        const disk = math.plane.createPN(isec.geo.n, position);
        const disk_thickness = radius * 0.125;

        for (adjacency.cells[0..adjacency.num_cells]) |cell| {
            var i = cell[0];
            const len = cell[1];
            while (i < len) : (i += 1) {
                const p = self.photons[@intCast(usize, i)];

                const distance2 = math.squaredDistance3(p.p, position);
                if (distance2 < radius2) {
                    if (math.dot3(sample.super().interpolatedNormal(), p.wi) > 0.0) {
                        if (@fabs(math.plane.dot(disk, p.p)) > disk_thickness) {
                            continue;
                        }

                        const k = coneFilter(distance2, inv_radius2);

                        const n_dot_wi = mat.clampDot(sample.super().shadingNormal(), p.wi);

                        const bxdf = sample.evaluate(p.wi);

                        result += @splat(4, k / n_dot_wi) * Vec4f{ p.alpha[0], p.alpha[1], p.alpha[2] } * bxdf.reflection;
                    }
                }
            }
        }

        // for (self.photons) |p| {
        //     const distance2 = math.squaredDistance3(p.p, position);
        //     if (distance2 < radius2) {
        //         if (math.dot3(sample.super().interpolatedNormal(), p.wi) > 0.0) {
        //             if (@fabs(math.plane.dot(disk, p.p)) > disk_thickness) {
        //                 continue;
        //             }

        //             const k = coneFilter(distance2, inv_radius2);

        //             const n_dot_wi = mat.clampDot(sample.super().shadingNormal(), p.wi);

        //             const bxdf = sample.evaluate(p.wi);

        //             result += @splat(4, k / n_dot_wi) * Vec4f{ p.alpha[0], p.alpha[1], p.alpha[2] } * bxdf.reflection;
        //         }
        //     }
        // }

        return result * @splat(4, self.surface_normalization);
    }

    fn coneFilter(squared_distance: f32, inv_squared_radius: f32) f32 {
        const s = 1.0 - squared_distance * inv_squared_radius;
        return s * s;
    }

    fn conelyFilter(squared_distance: f32, inv_squared_radius: f32) f32 {
        return 1.0 - squared_distance * inv_squared_radius;
    }
};
