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
            for (self.conditional) |*c| {
                c.deinit(alloc);
            }

            self.conditional = try alloc.realloc(self.conditional, num);
            @memset(self.conditional, .{});
        }

        return self.conditional;
    }

    pub fn configure(self: *Self, alloc: Allocator) !void {
        const integrals = try alloc.alloc(f32, self.conditional.len);
        defer alloc.free(integrals);

        for (integrals, self.conditional) |*i, c| {
            i.* = c.integral;
        }

        try self.marginal.configure(alloc, integrals, 0);
    }

    pub fn integral(self: Self) f32 {
        return self.marginal.integral;
    }

    pub fn sampleContinuous(self: Self, r2: Vec2f) Continuous {
        const v = self.marginal.sampleContinuous(r2[1]);

        const i: u32 = @intFromFloat(v.offset * @as(f32, @floatFromInt(self.conditional.len)));
        const c = @min(i, @as(u32, @intCast(self.conditional.len - 1)));

        const u = self.conditional[c].sampleContinuous(r2[0]);

        return .{ .uv = .{ u.offset, v.offset }, .pdf = u.pdf * v.pdf };
    }

    pub fn pdf(self: Self, uv: Vec2f) f32 {
        const v_pdf = self.marginal.pdfF(uv[1]);

        const i: u32 = @intFromFloat(uv[1] * @as(f32, @floatFromInt(self.conditional.len)));
        const c = @min(i, @as(u32, @intCast(self.conditional.len - 1)));

        const u_pdf = self.conditional[c].pdfF(uv[0]);

        return u_pdf * v_pdf;
    }
};
