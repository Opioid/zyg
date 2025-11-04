const Scene = @import("../scene.zig").Scene;
const Shape = @import("../shape/shape.zig").Shape;
const Part = @import("../shape/triangle/triangle_mesh.zig").Part;
const MeshSampler = @import("../shape/shape_sampler.zig").MeshImpl;

const base = @import("base");
const enc = base.encoding;
const math = base.math;
const Vec4us = math.Vec4us;
const Vec4f = math.Vec4f;
const AABB = math.AABB;
const Distribution1D = math.Distribution1D;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Pick = Distribution1D.Discrete;

const Meta = packed struct {
    has_children: bool,
    two_sided: bool,
    children_or_light: u30,
};

pub const Node = struct {
    center: Vec4us align(32),
    cone: Vec4us,

    power: f32,
    variance: f32,

    meta: Meta,
    num_lights: u32,

    fn decompressCenter(self: Node, bounds: AABB) Vec4f {
        const t = enc.unorm16ToFloat(self.center);
        return math.lerp(bounds.bounds[0], bounds.bounds[1], t);
    }

    pub fn compressCenter(self: *Node, center: Vec4f, bounds: AABB) void {
        const d = center - bounds.bounds[0];
        const e = bounds.extent();
        const div = Vec4f{
            if (0.0 == e[0]) 1.0 else e[0],
            if (0.0 == e[1]) 1.0 else e[1],
            if (0.0 == e[2]) 1.0 else e[2],
            bounds.cachedRadius(),
        };

        // assumes that bounds[0][3] == 0.0, therefore d[3] == center[3]
        const q = d / div;

        self.center = enc.floatToUnorm16(q);
    }

    pub fn weight(self: Node, p: Vec4f, n: Vec4f, bounds: AABB, total_sphere: bool) f32 {
        const center = self.decompressCenter(bounds);
        const r = center[3];

        const cone = enc.snorm16ToFloat(self.cone);

        return importance(p, n, center, cone, r, self.power, self.meta.two_sided, total_sphere);
    }

    pub fn split(self: Node, p: Vec4f, bounds: AABB, threshold: f32) bool {
        const center = self.decompressCenter(bounds);

        const r = center[3];
        const d = math.min(math.distance3(p, center), 1.0e6);
        const a = math.max(d - r, 0.001);
        const b = d + r;

        const eg = 1.0 / (a * b);
        const eg2 = eg * eg;

        const a3 = a * a * a;
        const b3 = b * b * b;

        const e2g = (b3 - a3) / (3.0 * (b - a) * a3 * b3);

        const vg = e2g - eg2;

        const ve = self.variance;
        const ee = self.power;
        const s2 = math.max(ve * vg + ve * eg2 + ee * ee * vg, 0.0);
        const ns = 1.0 / (1.0 + @sqrt(s2));

        return ns < threshold;
    }

    pub fn randomLight(
        self: Node,
        p: Vec4f,
        n: Vec4f,
        total_sphere: bool,
        random: f32,
        light_mapping: [*]const u32,
        set: anytype,
    ) Pick {
        const num_lights = self.num_lights;
        const light = self.meta.children_or_light;

        if (1 == num_lights) {
            return .{ .offset = light_mapping[light], .pdf = 1.0 };
        }

        // Bi-directional CDF idea from
        // Single-pass stratified importance resampling
        // https://www.iliyan.com/publications/StratifiedResampling

        var front = light;
        var back = light + num_lights - 1;

        var w_front = lightWeight(p, n, total_sphere, light_mapping[front], set);
        var w_back = lightWeight(p, n, total_sphere, light_mapping[back], set);

        var w_sum_front = w_front;
        var w_sum_back = w_back;
        var w_sum: f32 = undefined;

        while (front != back) {
            w_sum = w_sum_front + w_sum_back;
            if (w_sum_front <= random * w_sum) {
                front += 1;
                if (front != back) {
                    w_front = lightWeight(p, n, total_sphere, light_mapping[front], set);
                    w_sum_front += w_front;
                } else {
                    w_front = w_back;
                }
            } else {
                back -= 1;
                if (front != back) {
                    w_back = lightWeight(p, n, total_sphere, light_mapping[back], set);
                    w_sum_back += w_back;
                }
            }
        }

        if (0.0 == w_sum) {
            return .{ .offset = undefined, .pdf = 0.0 };
        }

        return .{ .offset = light_mapping[front], .pdf = w_front / w_sum };
    }

    pub fn pdf(
        self: Node,
        p: Vec4f,
        n: Vec4f,
        total_sphere: bool,
        id: u32,
        light_mapping: [*]const u32,
        set: anytype,
    ) f32 {
        const num_lights = self.num_lights;

        if (1 == num_lights) {
            return 1.0;
        }

        const light = self.meta.children_or_light;
        const end = light + num_lights;

        var w_id: f32 = undefined;
        var sum: f32 = 0.0;

        var i = light;
        while (i < end) : (i += 1) {
            const lw = lightWeight(p, n, total_sphere, light_mapping[i], set);
            sum += lw;

            if (id == i) {
                w_id = lw;
            }
        }

        if (0.0 == sum) {
            return 0.0;
        }

        return w_id / sum;
    }
};

fn importance(
    p: Vec4f,
    n: Vec4f,
    center: Vec4f,
    cone: Vec4f,
    radius: f32,
    power: f32,
    two_sided: bool,
    total_sphere: bool,
) f32 {
    const axis = p - center;
    const l = math.length3(axis);
    const na = axis / @as(Vec4f, @splat(l));
    const da = cone;

    const sin_cu = math.min(radius / l, 1.0);
    const cos_cone = cone[3];
    const cos_a = math.safe.absDotC(da, na, two_sided);
    const cos_n = math.max(-math.dot3(n, na), 0.0);

    const sa = Vec4f{ sin_cu, cos_cone, cos_a, cos_n };
    const sb = math.max4(@as(Vec4f, @splat(1.0)) - sa * sa, @splat(0.0));
    const sr = @sqrt(sb);

    const cos_cu = sr[0];
    const sin_cone = sr[1];
    const sin_a = sr[2];
    const sin_n = sr[3];

    const ta = clampedCosSub(cos_a, cos_cone, sin_a, sin_cone);
    const tb = clampedSinSub(cos_a, cos_cone, sin_a, sin_cone);
    const tc = clampedCosSub(ta, cos_cu, tb, sin_cu);
    const tn = clampedCosSub(cos_n, cos_cu, sin_n, sin_cu);

    const ra = if (total_sphere) 1.0 else tn;
    const rb = math.max(tc, 0.0);

    const clamped_dist = math.max(l, 0.5 * radius);
    const rc = power / (clamped_dist * clamped_dist);

    return math.max(ra * rb * rc, 0.0);
}

fn clampedCosSub(cos_a: f32, cos_b: f32, sin_a: f32, sin_b: f32) f32 {
    const angle = cos_a * cos_b + sin_a * sin_b;
    return if (cos_a > cos_b) 1.0 else angle;
}

fn clampedSinSub(cos_a: f32, cos_b: f32, sin_a: f32, sin_b: f32) f32 {
    const angle = sin_a * cos_b - sin_b * cos_a;
    return if (cos_a > cos_b) 0.0 else angle;
}

fn lightWeight(p: Vec4f, n: Vec4f, total_sphere: bool, light: u32, set: anytype) f32 {
    const props = set.lightProperties(light);
    const center = props.sphere;
    const radius = center[3];

    return importance(p, n, center, props.cone, radius, props.power, props.two_sided, total_sphere);
}

pub const Tree = struct {
    pub const MaxSplitDepth = 10;
    pub const MaxLights = 64;

    pub const Lights = [MaxLights]Pick;

    const TraversalStack = TraversalStackT(MaxSplitDepth);

    bounds: AABB = undefined,

    infinite_weight: f32 = undefined,
    infinite_guard: f32 = undefined,

    infinite_end: u32 = undefined,
    max_split_depth: u32 = undefined,
    num_lights: u32 = 0,
    num_infinite_lights: u32 = 0,
    num_nodes: u32 = 0,

    nodes: [*]Node = undefined,
    node_middles: [*]u32 = undefined,

    light_orders: [*]u32 = undefined,
    light_mapping: [*]u32 = undefined,

    infinite_light_powers: [*]f32 = undefined,
    infinite_light_distribution: Distribution1D = .{},

    pub fn deinit(self: *Tree, alloc: Allocator) void {
        self.infinite_light_distribution.deinit(alloc);
        alloc.free(self.infinite_light_powers[0..self.num_infinite_lights]);

        const num_lights = self.num_lights;
        alloc.free(self.light_orders[0..num_lights]);
        alloc.free(self.light_mapping[0..num_lights]);

        const num_nodes = self.num_nodes;
        alloc.free(self.node_middles[0..num_nodes]);
        alloc.free(self.nodes[0..num_nodes]);
    }

    pub fn allocateLightMapping(self: *Tree, alloc: Allocator, num_lights: u32) !void {
        if (self.num_lights != num_lights) {
            const nl = self.num_lights;
            self.light_mapping = (try alloc.realloc(self.light_mapping[0..nl], num_lights)).ptr;
            self.light_orders = (try alloc.realloc(self.light_orders[0..nl], num_lights)).ptr;

            self.num_lights = num_lights;
        }
    }

    pub fn allocateNodes(self: *Tree, alloc: Allocator, num_nodes: u32) !void {
        if (self.num_nodes != num_nodes) {
            const nn = self.num_nodes;
            self.nodes = (try alloc.realloc(self.nodes[0..nn], num_nodes)).ptr;
            self.node_middles = (try alloc.realloc(self.node_middles[0..nn], num_nodes)).ptr;

            self.num_nodes = num_nodes;
        }
    }

    pub fn allocate(self: *Tree, alloc: Allocator, num_infinite_lights: u32) !void {
        if (self.num_infinite_lights != num_infinite_lights) {
            self.infinite_light_powers = (try alloc.realloc(
                self.infinite_light_powers[0..self.num_infinite_lights],
                num_infinite_lights,
            )).ptr;

            self.num_infinite_lights = num_infinite_lights;
        }
    }

    pub fn potentialMaxLights(self: *const Tree, scene: *const Scene) u32 {
        // const num_finite: u32 = @intFromFloat(std.math.pow(f32, 2.0, @floatFromInt(self.max_split_depth)));
        // return num_finite + self.num_infinite_lights;

        var num: u32 = 0;
        for (self.light_mapping[0..self.num_lights]) |lm| {
            num += scene.light(lm).potentialMaxSamples(scene);
        }

        return num;
    }

    pub fn randomLight(
        self: *const Tree,
        p: Vec4f,
        n: Vec4f,
        total_sphere: bool,
        random: f32,
        split_threshold: f32,
        scene: *const Scene,
        buffer: *Lights,
    ) []Pick {
        var current_light: u32 = 0;

        var ip: f32 = 0.0;
        const num_infinite_lights = self.num_infinite_lights;
        const split = split_threshold > 0.0;

        if (split and num_infinite_lights < MaxLights - 1) {
            for (self.light_mapping[0..num_infinite_lights]) |lm| {
                buffer[current_light] = .{ .offset = lm, .pdf = 1.0 };
                current_light += 1;
            }
        } else {
            ip = self.infinite_weight;

            if (random < self.infinite_guard) {
                const l = self.infinite_light_distribution.sampleDiscrete(random);
                buffer[0] = .{ .offset = self.light_mapping[l.offset], .pdf = l.pdf * ip };
                return buffer[0..1];
            }
        }

        if (0 == self.num_nodes) {
            return buffer[0..current_light];
        }

        const pd = 1.0 - ip;

        const max_split_depth = self.max_split_depth;

        var stack: TraversalStack = .{};

        var t: TraversalStack.Value = .{
            .pdf = pd,
            .random = (random - ip) / pd,
            .node = 0,
            .depth = if (split) 0 else max_split_depth,
        };

        stack.push(t);

        while (!stack.empty()) {
            const node = self.nodes[t.node];

            if (node.meta.has_children) {
                const do_split = t.depth < max_split_depth and node.split(p, self.bounds, split_threshold);

                const c0 = node.meta.children_or_light;
                const c1 = c0 + 1;

                if (do_split) {
                    t.depth += 1;
                    t.node = c0;
                    stack.push(.{ .pdf = t.pdf, .random = t.random, .node = c1, .depth = t.depth });
                } else {
                    t.depth = max_split_depth;

                    var p0 = self.nodes[c0].weight(p, n, self.bounds, total_sphere);
                    var p1 = self.nodes[c1].weight(p, n, self.bounds, total_sphere);

                    const pt = p0 + p1;

                    if (0.0 == pt) {
                        t = stack.pop();
                        continue;
                    }

                    p0 /= pt;
                    p1 /= pt;

                    if (t.random < p0) {
                        t.node = c0;
                        t.pdf *= p0;
                        t.random /= p0;
                    } else {
                        t.node = c1;
                        t.pdf *= p1;
                        t.random = math.min((t.random - p0) / p1, 1.0);
                    }
                }
            } else {
                const pick = node.randomLight(p, n, total_sphere, t.random, self.light_mapping, scene);
                if (pick.pdf > 0.0) {
                    buffer[current_light] = .{ .offset = pick.offset, .pdf = pick.pdf * t.pdf };
                    current_light += 1;
                }

                t = stack.pop();
            }
        }

        return buffer[0..current_light];
    }

    pub fn pdf(self: *const Tree, p: Vec4f, n: Vec4f, total_sphere: bool, split_threshold: f32, id: u32, scene: *const Scene) f32 {
        const lo = self.light_orders[id];
        const num_infinite_lights = self.num_infinite_lights;
        const split = split_threshold > 0.0;

        const split_infinite = split and num_infinite_lights < MaxLights - 1;

        if (lo < self.infinite_end) {
            if (split_infinite) {
                return 1.0;
            } else {
                return self.infinite_weight * self.infinite_light_distribution.pdfI(lo);
            }
        }

        if (0 == self.num_nodes) {
            return 0.0;
        }

        const ip = if (split_infinite) 0.0 else self.infinite_weight;
        const max_split_depth = self.max_split_depth;

        var pd = 1.0 - ip;

        var nid: u32 = 0;
        var depth: u32 = if (split) 0 else max_split_depth;
        while (true) {
            const node = self.nodes[nid];

            if (node.meta.has_children) {
                const do_split = depth < max_split_depth and node.split(p, self.bounds, split_threshold);

                const c0 = node.meta.children_or_light;
                const c1 = c0 + 1;

                const middle = self.node_middles[nid];

                if (do_split) {
                    depth += 1;

                    if (lo < middle) {
                        nid = c0;
                    } else {
                        nid = c1;
                    }
                } else {
                    depth = max_split_depth;

                    const p0 = self.nodes[c0].weight(p, n, self.bounds, total_sphere);
                    const p1 = self.nodes[c1].weight(p, n, self.bounds, total_sphere);
                    const pt = p0 + p1;

                    if (0.0 == pt) {
                        return 0.0;
                    }

                    if (lo < middle) {
                        nid = c0;
                        pd *= p0 / pt;
                    } else {
                        nid = c1;
                        pd *= p1 / pt;
                    }
                }
            } else {
                return pd * node.pdf(p, n, total_sphere, lo, self.light_mapping, scene);
            }
        }
    }
};

pub const PrimitiveTree = struct {
    pub const Samples = [Shape.MaxSamples]Pick;

    const MaxSplitDepth = 6;

    const TraversalStack = TraversalStackT(MaxSplitDepth);

    bounds: AABB = .empty,

    num_lights: u32 = 0,
    num_nodes: u32 = 0,

    nodes: [*]Node = undefined,
    node_middles: [*]u32 = undefined,

    light_orders: [*]u32 = undefined,
    light_mapping: [*]u32 = undefined,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        const num_lights = self.num_lights;
        alloc.free(self.light_orders[0..num_lights]);
        alloc.free(self.light_mapping[0..num_lights]);

        const num_nodes = self.num_nodes;
        alloc.free(self.node_middles[0..num_nodes]);
        alloc.free(self.nodes[0..num_nodes]);
    }

    pub fn allocateLightMapping(self: *Self, alloc: Allocator, num_lights: u32) !void {
        if (self.num_lights != num_lights) {
            const nl = self.num_lights;
            self.light_mapping = (try alloc.realloc(self.light_mapping[0..nl], num_lights)).ptr;
            self.light_orders = (try alloc.realloc(self.light_orders[0..nl], num_lights)).ptr;

            self.num_lights = num_lights;
        }
    }

    pub fn allocateNodes(self: *Self, alloc: Allocator, num_nodes: u32) !void {
        if (self.num_nodes != num_nodes) {
            const nn = self.num_nodes;
            self.nodes = (try alloc.realloc(self.nodes[0..nn], num_nodes)).ptr;
            self.node_middles = (try alloc.realloc(self.node_middles[0..nn], num_nodes)).ptr;
            self.num_nodes = num_nodes;
        }
    }

    pub fn randomLight(
        self: *const Self,
        p: Vec4f,
        n: Vec4f,
        total_sphere: bool,
        random: f32,
        split_threshold: f32,
        shape_samppler: *const MeshSampler,
        buffer: *Samples,
    ) []Pick {
        var current_light: u32 = 0;

        const split = split_threshold > 0.0;

        var stack: TraversalStack = .{};

        var t: TraversalStack.Value = .{
            .pdf = 1.0,
            .random = random,
            .node = 0,
            .depth = if (split) 0 else MaxSplitDepth,
        };

        stack.push(t);

        while (!stack.empty()) {
            const node = self.nodes[t.node];

            if (node.meta.has_children) {
                const do_split = t.depth < MaxSplitDepth and node.split(p, self.bounds, split_threshold);

                const c0 = node.meta.children_or_light;
                const c1 = c0 + 1;

                if (do_split) {
                    t.depth += 1;
                    t.node = c0;
                    stack.push(.{ .pdf = t.pdf, .random = t.random, .node = c1, .depth = t.depth });
                } else {
                    t.depth = MaxSplitDepth;

                    var p0 = self.nodes[c0].weight(p, n, self.bounds, total_sphere);
                    var p1 = self.nodes[c1].weight(p, n, self.bounds, total_sphere);

                    const pt = p0 + p1;

                    if (0.0 == pt) {
                        t = stack.pop();
                        continue;
                    }

                    p0 /= pt;
                    p1 /= pt;

                    if (t.random < p0) {
                        t.node = c0;
                        t.pdf *= p0;
                        t.random /= p0;
                    } else {
                        t.node = c1;
                        t.pdf *= p1;
                        t.random = math.min((t.random - p0) / p1, 1.0);
                    }
                }
            } else {
                const pick = node.randomLight(p, n, total_sphere, t.random, self.light_mapping, shape_samppler);
                if (pick.pdf > 0.0) {
                    buffer[current_light] = .{ .offset = pick.offset, .pdf = pick.pdf * t.pdf };
                    current_light += 1;
                }

                t = stack.pop();
            }
        }

        return buffer[0..current_light];
    }

    pub fn pdf(
        self: *const Self,
        p: Vec4f,
        n: Vec4f,
        total_sphere: bool,
        split_threshold: f32,
        id: u32,
        shape_sampler: *const MeshSampler,
    ) f32 {
        const lo = self.light_orders[id];

        const split = split_threshold > 0.0;

        var pd: f32 = 1.0;

        var nid: u32 = 0;
        var depth: u32 = if (split) 0 else MaxSplitDepth;
        while (true) {
            const node = self.nodes[nid];

            if (node.meta.has_children) {
                const do_split = depth < MaxSplitDepth and node.split(p, self.bounds, split_threshold);

                const c0 = node.meta.children_or_light;
                const c1 = c0 + 1;

                const middle = self.node_middles[nid];

                if (do_split) {
                    depth += 1;

                    if (lo < middle) {
                        nid = c0;
                    } else {
                        nid = c1;
                    }
                } else {
                    depth = MaxSplitDepth;

                    const p0 = self.nodes[c0].weight(p, n, self.bounds, total_sphere);
                    const p1 = self.nodes[c1].weight(p, n, self.bounds, total_sphere);
                    const pt = p0 + p1;

                    if (0.0 == pt) {
                        return 0.0;
                    }

                    if (lo < middle) {
                        nid = c0;
                        pd *= p0 / pt;
                    } else {
                        nid = c1;
                        pd *= p1 / pt;
                    }
                }
            } else {
                return pd * node.pdf(p, n, total_sphere, lo, self.light_mapping, shape_sampler);
            }
        }
    }
};

pub fn TraversalStackT(comptime MaxSplitDepth: comptime_int) type {
    return struct {
        pub const Value = struct {
            pdf: f32,
            random: f32,
            node: u32,
            depth: u32,
        };

        const StackSize = MaxSplitDepth + 1;

        end: u32 = 0,
        stack: [StackSize]Value = undefined,

        const Self = @This();

        pub fn empty(self: Self) bool {
            return 0 == self.end;
        }

        pub fn push(self: *Self, value: Value) void {
            self.stack[self.end] = value;
            self.end += 1;
        }

        pub fn pop(self: *Self) Value {
            self.end -= 1;
            return self.stack[self.end];
        }
    };
}
