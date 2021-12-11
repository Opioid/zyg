const Vec2f = @import("vector2.zig").Vec2f;
const Distribution1D = @import("distribution_1d.zig").Distribution1D;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Distribution2D = struct {
    pub const Continuous = struct {
        uv: Vec2f,
        pdf: f32,
    };

    marginal: Distribution1D = .{},

    conditional: []Distribution1D = &.{},

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        for (self.conditional) |*c| {
            c.deinit(alloc);
        }

        alloc.free(self.conditional);

        self.marginal.deinit(alloc);
    }

    pub fn allocate(self: *Self, alloc: Allocator, num: u32) ![]Distribution1D {
        if (self.conditional.len != num) {
            self.conditional = try alloc.realloc(self.conditional, num);
            std.mem.set(Distribution1D, self.conditional, .{});
        }

        return self.conditional;
    }

    pub fn configure(self: *Self, alloc: Allocator) !void {
        var integrals = try alloc.alloc(f32, self.conditional.len);
        defer alloc.free(integrals);

        for (self.conditional) |c, i| {
            integrals[i] = c.integral;
        }

        try self.marginal.configure(alloc, integrals, 0);
    }

    pub fn sampleContinous(self: Self, r2: Vec2f) Continuous {
        const v = self.marginal.sampleContinous(r2[1]);

        const i = @floatToInt(u32, v.offset * @intToFloat(f32, self.conditional.len));
        const c = std.math.min(i, @intCast(u32, self.conditional.len - 1));

        const u = self.conditional[c].sampleContinous(r2[0]);

        return .{ .uv = .{ u.offset, v.offset }, .pdf = u.pdf * v.pdf };
    }

    pub fn pdf(self: Self, uv: Vec2f) f32 {
        const v_pdf = self.marginal.pdfF(uv[1]);

        const i = @floatToInt(u32, uv[1] * @intToFloat(f32, self.conditional.len));
        const c = std.math.min(i, @intCast(u32, self.conditional.len - 1));

        const u_pdf = self.conditional[c].pdfF(uv[0]);

        return u_pdf * v_pdf;
    }
};
