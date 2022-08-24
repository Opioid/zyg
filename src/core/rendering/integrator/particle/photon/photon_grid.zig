const Photon = @import("photon.zig").Photon;
const Scene = @import("../../../../scene/scene.zig").Scene;
const Intersection = @import("../../../../scene/prop/intersection.zig").Intersection;
const MaterialSample = @import("../../../../scene/material/sample.zig").Sample;
const mat = @import("../../../../scene/material/sample_helper.zig");

const base = @import("base");
const math = base.math;
const AABB = math.AABB;
const Vec2i = math.Vec2i;
const Vec2u = math.Vec2u;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Grid = struct {
    const InnerAdjacency = struct {
        num_cells: u32,
        cells: [4]Vec2i,
    };

    const Adjacency = struct {
        num_cells: u32,
        cells: [4]Vec2u,
    };

    photons: []Photon = &.{},

    aabb: AABB = undefined,

    search_radius: f32 = undefined,
    grid_cell_factor: f32 = undefined,
    surface_normalization: f32 = undefined,

    num_paths: f64 = undefined,

    cell_bound: Vec2f = undefined,

    dimensions: Vec4i = @splat(4, @as(i32, 0)),

    local_to_texture: Vec4f = undefined,

    grid: []u32 = &.{},

    adjacencies: [43]InnerAdjacency = undefined,

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
        const dimensions = math.vec4fTo4i(@ceil(aabb.extent() / @splat(4, diameter * self.grid_cell_factor))) + @splat(4, @as(i32, 2));

        if (!math.equal4i(dimensions, self.dimensions)) {
            std.debug.print("{}\n", .{dimensions});

            self.dimensions = dimensions;

            self.local_to_texture = @splat(4, @as(f32, 1.0)) / aabb.extent() * math.vec4iTo4f(dimensions - @splat(4, @as(i32, 2)));

            const num_cells = @intCast(usize, dimensions[0]) * @intCast(usize, dimensions[1]) * @intCast(usize, dimensions[2]) + 1;

            self.grid = try alloc.realloc(self.grid, num_cells);

            const area = dimensions[0] * dimensions[1];

            const o_m1__0__0 = -1;
            const o_p1__0__0 = 1;

            const o__0_m1__0 = -dimensions[0];
            const o__0_p1__0 = dimensions[0];

            const o__0__0_m1 = -area;
            const o__0__0_p1 = area;

            const o_m1_m1__0 = -1 - dimensions[0];
            const o_m1_p1__0 = -1 + dimensions[0];
            const o_p1_m1__0 = 1 - dimensions[0];
            const o_p1_p1__0 = 1 + dimensions[0];

            const o_m1_m1_m1 = -1 - dimensions[0] - area;
            const o_m1_m1_p1 = -1 - dimensions[0] + area;
            const o_m1_p1_m1 = -1 + dimensions[0] - area;
            const o_m1_p1_p1 = -1 + dimensions[0] + area;

            const o_p1_m1_m1 = 1 - dimensions[0] - area;
            const o_p1_m1_p1 = 1 - dimensions[0] + area;
            const o_p1_p1_m1 = 1 + dimensions[0] - area;
            const o_p1_p1_p1 = 1 + dimensions[0] + area;

            const o_m1__0_m1 = -1 - area;
            const o_m1__0_p1 = -1 + area;
            const o_p1__0_m1 = 1 - area;
            const o_p1__0_p1 = 1 + area;

            const o__0_m1_m1 = -dimensions[0] - area;
            const o__0_m1_p1 = -dimensions[0] + area;
            const o__0_p1_m1 = dimensions[0] - area;
            const o__0_p1_p1 = dimensions[0] + area;

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

        std.sort.sort(Photon, photons, self, compareByMap);

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

    pub fn reduce(self: *Self, photons: []Photon, threads: *Threads) u32 {
        self.photons = photons;

        // _ = threads.runRange(self, reduceRange, 0, @intCast(u32, photons.len));

        // return @intCast(u32, base.memory.partition(Photon, photons, {}, alphaPositive));

        _ = threads;
        return @intCast(u32, photons.len);
    }

    fn alphaPositive(context: void, p: Photon) bool {
        _ = context;
        return p.alpha[0] >= 0.0;
    }

    pub fn reduceRange(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;
        const self = @intToPtr(*Self, context);

        const merge_radius: f32 = 0.0001; //self.search_radius / 10.0;
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
                const jlen = std.math.min(cell[1], end);
                var j = std.math.max(cell[0], i + 1);
                while (j < jlen) : (j += 1) {
                    if (j == i) {
                        continue;
                    }

                    var b = &self.photons[j];

                    if (a.volumetric != b.volumetric or b.alpha[0] < 0.0) {
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

    fn compareByMap(self: *const Self, a: Photon, b: Photon) bool {
        const ida = self.map1(a.p);
        const idb = self.map1(b.p);
        return ida < idb;
    }

    fn map1(self: *const Self, v: Vec4f) u64 {
        const c = math.vec4fTo4i((v - self.aabb.bounds[0]) * self.local_to_texture) + @splat(4, @as(i32, 1));
        return @intCast(u64, (@as(i64, c[2]) * @as(i64, self.dimensions[1]) + @as(i64, c[1])) *
            @as(i64, self.dimensions[0]) +
            @as(i64, c[0]));
    }

    fn map3(self: *const Self, v: Vec4f, cell_bound: Vec2f, adjacents: *u8) Vec4i {
        const r = (v - self.aabb.bounds[0]) * self.local_to_texture;
        const c = math.vec4fTo4i(r);
        const d = r - math.vec4iTo4f(c);

        var adj = adjacent(d[0], cell_bound) << 4;
        adj |= adjacent(d[1], cell_bound) << 2;
        adj |= adjacent(d[2], cell_bound);

        adjacents.* = adj;

        return c + @splat(4, @as(i32, 1));
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

    fn adjacentCells(self: *const Self, v: Vec4f, cell_bound: Vec2f) Adjacency {
        var adjacents: u8 = undefined;
        const c = self.map3(v, cell_bound, &adjacents);
        const ic = (@as(i64, c[2]) * @as(i64, self.dimensions[1]) + @as(i64, c[1])) *
            @as(i64, self.dimensions[0]) +
            @as(i64, c[0]);

        const adjacency = self.adjacencies[adjacents];

        var result: Adjacency = undefined;
        result.num_cells = adjacency.num_cells;

        for (adjacency.cells[0..adjacency.num_cells]) |cell, i| {
            result.cells[i][0] = self.grid[@intCast(usize, @as(i64, cell[0]) + ic)];
            result.cells[i][1] = self.grid[@intCast(usize, @as(i64, cell[1]) + ic + 1)];
        }

        return result;
    }

    pub fn setNumPaths(self: *Self, num_paths: u64) void {
        const radius = self.search_radius;
        const radius2 = radius * radius;

        // conely
        // self.surface_normalization = 1.0 / (((1.0 / 2.0) * std.math.pi) * @intToFloat(f32, num_paths) * radius2);

        // cone
        self.surface_normalization = 1.0 / (((1.0 / 3.0) * std.math.pi) * @intToFloat(f32, num_paths) * radius2);

        self.num_paths = @intToFloat(f64, num_paths);
    }

    pub fn li(self: *const Self, isec: *const Intersection, sample: MaterialSample, scene: *const Scene) Vec4f {
        var result = @splat(4, @as(f32, 0.0));

        const position = isec.geo.p;

        if (!self.aabb.pointInside(position)) {
            return result;
        }

        const adjacency = self.adjacentCells(position, self.cell_bound);

        const radius = self.search_radius;
        const radius2 = radius * radius;

        if (isec.subsurface) {} else {
            const inv_radius2 = 1.0 / radius2;

            const two_sided = isec.material(scene).twoSided();

            for (adjacency.cells[0..adjacency.num_cells]) |cell| {
                var i = cell[0];
                const len = cell[1];
                while (i < len) : (i += 1) {
                    const p = self.photons[i];

                    if (p.volumetric) {
                        continue;
                    }

                    const distance2 = math.squaredDistance3(p.p, position);
                    if (distance2 < radius2) {
                        if (two_sided) {
                            const k = coneFilter(distance2, inv_radius2);

                            const n_dot_wi = mat.clampAbsDot(sample.super().shadingNormal(), p.wi);

                            const bxdf = sample.evaluate(p.wi);

                            result += @splat(4, k / n_dot_wi) * Vec4f{ p.alpha[0], p.alpha[1], p.alpha[2] } * bxdf.reflection;
                        } else if (math.dot3(sample.super().interpolatedNormal(), p.wi) > 0.0) {
                            const k = coneFilter(distance2, inv_radius2);

                            const n_dot_wi = mat.clampDot(sample.super().shadingNormal(), p.wi);

                            const bxdf = sample.evaluate(p.wi);

                            result += @splat(4, k / n_dot_wi) * Vec4f{ p.alpha[0], p.alpha[1], p.alpha[2] } * bxdf.reflection;
                        }
                    }
                }
            }
        }

        return result * @splat(4, self.surface_normalization);
    }

    pub fn li2(self: *const Self, isec: *const Intersection, sample: MaterialSample, scene: *const Scene) Vec4f {
        var result = @splat(4, @as(f32, 0.0));

        const position = isec.geo.p;

        if (!self.aabb.pointInside(position)) {
            return result;
        }

        const adjacency = self.adjacentCells(position, self.cell_bound);

        const radius = self.search_radius;
        const radius2 = radius * radius;

        var buffer = Buffer{};
        buffer.clear();

        const subsurface = isec.subsurface;

        for (adjacency.cells[0..adjacency.num_cells]) |cell| {
            for (self.photons[cell[0]..cell[1]]) |p, i| {
                if (subsurface != p.volumetric) {
                    continue;
                }

                const distance2 = math.squaredDistance3(p.p, position);
                if (distance2 < radius2) {
                    buffer.consider(.{ .id = cell[0] + @intCast(u32, i), .d2 = distance2 });
                }
            }
        }

        if (buffer.num_entries > 0) {
            const used_entries = buffer.num_entries;
            const max_radius2 = buffer.entries[used_entries - 1].d2;

            if (subsurface) {
                const max_radius3 = max_radius2 * @sqrt(max_radius2);

                for (buffer.entries[0..used_entries]) |entry| {
                    const p = self.photons[entry.id];

                    const bxdf = sample.evaluate(p.wi);

                    result += Vec4f{ p.alpha[0], p.alpha[1], p.alpha[2], 0.0 } * bxdf.reflection;
                }

                const normalization = @floatCast(f32, (((4.0 / 3.0) * std.math.pi) * self.num_paths * @floatCast(f64, max_radius3)));
                const mu_s = scatteringCoefficient(isec, scene);

                result /= @splat(4, normalization) * mu_s;
            } else {
                const two_sided = isec.material(scene).twoSided();
                const inv_max_radius2 = 1.0 / max_radius2;

                for (buffer.entries[0..used_entries]) |entry| {
                    const p = self.photons[entry.id];

                    if (two_sided) {
                        const k = coneFilter(entry.d2, inv_max_radius2);

                        const n_dot_wi = mat.clampAbsDot(sample.super().shadingNormal(), p.wi);

                        const bxdf = sample.evaluate(p.wi);

                        result += @splat(4, k / n_dot_wi) * Vec4f{ p.alpha[0], p.alpha[1], p.alpha[2], 0.0 } * bxdf.reflection;
                    } else if (math.dot3(sample.super().interpolatedNormal(), p.wi) > 0.0) {
                        const k = coneFilter(entry.d2, inv_max_radius2);

                        const n_dot_wi = mat.clampDot(sample.super().shadingNormal(), p.wi);

                        const bxdf = sample.evaluate(p.wi);

                        result += @splat(4, k / n_dot_wi) * Vec4f{ p.alpha[0], p.alpha[1], p.alpha[2], 0.0 } * bxdf.reflection;
                    }
                }

                const normalization = @floatCast(f32, (((1.0 / 3.0) * std.math.pi) * self.num_paths * @floatCast(f64, max_radius2)));

                result /= @splat(4, normalization);
            }
        }

        return result;
    }

    fn coneFilter(squared_distance: f32, inv_squared_radius: f32) f32 {
        const s = 1.0 - squared_distance * inv_squared_radius;
        return s * s;
    }

    fn scatteringCoefficient(isec: *const Intersection, scene: *const Scene) Vec4f {
        const material = isec.material(scene);

        if (material.heterogeneousVolume()) {
            const trafo = scene.propTransformationAt(isec.prop, scene.current_time_start);
            const local_position = trafo.worldToObjectPoint(isec.geo.p);

            const aabb = scene.propShape(isec.prop).aabb();
            const uvw = (local_position - aabb.bounds[0]) / aabb.extent();

            return material.collisionCoefficients(uvw, null, scene).s;
        }

        return material.collisionCoefficients(@splat(4, @as(f32, 0.0)), null, scene).s;
    }
};

const Buffer = struct {
    pub const Entry = struct {
        id: u32,
        d2: f32,
    };

    num_entries: u32 = undefined,
    entries: [1024]Entry = undefined,

    const Self = @This();

    pub fn clear(self: *Self) void {
        self.num_entries = 0;
    }

    pub fn consider(self: *Self, c: Entry) void {
        const num = self.num_entries;

        if (self.entries.len == num and c.d2 >= self.entries[self.entries.len - 1].d2) {
            return;
        }

        const lb = base.memory.lowerBoundFn(Entry, self.entries[0..num], c, {}, lessThan);

        if (lb < num) {
            const begin = lb + 1;
            const end = std.math.min(num + 1, self.entries.len);
            const range = end - begin;
            std.mem.copyBackwards(Entry, self.entries[begin..end], self.entries[lb .. lb + range]);

            self.entries[lb] = c;
            self.num_entries = end;
        } else if (num < self.entries.len) {
            self.entries[num] = c;
            self.num_entries += 1;
        }
    }

    fn lessThan(context: void, a: Entry, b: Entry) bool {
        _ = context;
        return a.d2 < b.d2;
    }
};
