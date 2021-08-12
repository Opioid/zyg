const base = @import("base");
usingnamespace base;
usingnamespace base.math;

const std = @import("std");

pub const Reference = struct {
    const Vector = struct {
        v: [3]f32,
        index: u32,
    };

    bounds: [2]Vector,

    pub fn aabb(self: Reference) AABB {
        return AABB.init(
            Vec4f.init3(bounds[0].v[0], bounds[0].v[1], bounds[0].v[2]),
            Vec4f.init3(bounds[1].v[0], bounds[1].v[1], bounds[1].v[2]),
        );
    }

    pub fn primitive(self: Reference) u32 {
        return self.bounds[0].index;
    }

    pub fn set(self: *Reference, min: Vec4f, max: Vec4f, primitive: u32) void {
        self.bounds[0].v[0] = min.v[0];
        self.bounds[0].v[1] = min.v[1];
        self.bounds[0].v[2] = min.v[2];
        self.bounds[0].index = primitive;

        self.bounds[1].v[0] = max.v[0];
        self.bounds[1].v[1] = max.v[1];
        self.bounds[1].v[2] = max.v[2];
    }

    pub fn clippedMin(self: Reference, d: f32, axis: u8) Reference {
        var bounds0 = self.bounds[0];

        bounds0.v[axis] = std.math.max(d, bounds0.v[axis]);

        return .{ .bounds = .{ bounds0, self.bounds[1] } };
    }

    pub fn clippedMax(self: Reference, d: f32, axis: u8) Reference {
        var bounds1 = self.bounds[1];

        bounds1.v[axis] = std.math.min(d, bounds1.v[axis]);

        return .{ .bounds = .{ self.bounds[0], bounds[1] } };
    }
};

pub const SplitCandidate = struct {
    aabbs: [2]AABB = undefined,
    num_sides: [2]u32 = undefined,

    d: f32,
    cost: f32 = undefined,

    axis: u8,

    spatial: bool,

    const Self = @This();

    pub fn init(split_axis: u8, p: Vec4f, spatial: bool) SplitCandidate {
        return .{
            .d = p.v[split_axis],
            .axis = split_axis,
            .spatial = spatial,
        };
    }

    pub fn evaluate(self: *Self, referenes: []const Reference, aabb_surface_area: f32) void {
        var num_sides: [2]u32 = .{ 0, 0 };
        var aabbs: [2]AABB = .{ math.aabb.emtpy, math.aabb.empty };

        if (self.spatial) {
            var used_spatial: bool = false;

            for (references) |r| {
                const b = r.aabb();

                if (self.behind(b.bounds[1])) {
                    num_sides[0] += 1;

                    aabbs[0].mergeAssign(b);
                } else if (!self.behind(b.bounds[0])) {
                    num_sides[1] += 1;

                    aabbs[1].mergeAssign(b);
                } else {
                    num_sides[0] += 1;
                    num_sides[1] += 1;

                    aabbs[0].mergeAssign(b);
                    aabbs[1].mergeAssign(b);

                    used_spatial = true;
                }
            }

            if (used_spatial) {
                aabbs[0].clipMax(self.d, self.axis);
                aabbs[1].clipMin(self.d, self.axis);
            } else {
                self.spatial = false;
            }
        } else {
            for (references) |r| {
                const b = r.aabb();

                if (self.behind(b.bounds[1])) {
                    num_sides[0] += 1;

                    aabbs[0].mergeAssign(b);
                } else {
                    num_sides[1] += 1;

                    aabbs[1].mergeAssign(b);
                }
            }
        }

        const empty_side = 0 == num_sides[0] or 0 == num_sides[1];
        if (empty_side) {
            self.cost = 2.0 + @intToFloat(f32, references.len);
        } else {
            const weight_0 = @intToFloat(f32, num_sides[0]) * aabbs[0].surfaceArea();
            const weight_1 = @intToFloat(f32, num_sides[1]) * aabbs[1].surfaceArea();

            self.cost = 2.0 + (weight_0 + weight_1) / aabb_surface_area;
        }

        self.num_sides[0] = num_sides[0];
        self.num_sides[1] = num_sides[1];

        self.aabbs[0] = aabbs[0];
        self.aabbs[1] = aabbs[1];
    }

    pub fn beind(self: Self, point: Vec4f) bool {
        return point.v[self.axis] < self.d;
    }
};
