const Vec2f = @import("vector2.zig").Vec2f;
const Vec4f = @import("vector4.zig").Vec4f;
const Distribution1D = @import("distribution_1d.zig").Distribution1D;
const Distribution2D = @import("distribution_2d.zig").Distribution2D;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Distribution3D = struct {
    marginal: Distribution1D = .{},

    conditional: []Distribution2D = &.{},

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        for (self.conditional) |*c| {
            c.deinit(alloc);
        }

        alloc.free(self.conditional);

        self.marginal.deinit(alloc);
    }

    pub fn allocate(self: *Self, alloc: Allocator, num: u32) ![]Distribution2D {
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
            i.* = c.integral();
        }

        try self.marginal.configure(alloc, integrals, 0);
    }

    pub fn sampleContinuous(self: Self, r3: Vec4f) Vec4f {
        const w = self.marginal.sampleContinuous(r3[2]);

        const i: u32 = @intFromFloat(w.offset * @as(f32, @floatFromInt(self.conditional.len)));
        const c = @min(i, @as(u32, @intCast(self.conditional.len - 1)));

        const uv = self.conditional[c].sampleContinuous(.{ r3[0], r3[1] });

        return .{ uv.uv[0], uv.uv[1], w.offset, uv.pdf * w.pdf };
    }

    pub fn pdf(self: Self, uvw: Vec4f) f32 {
        const w_pdf = self.marginal.pdfF(uvw[2]);

        const i: u32 = @intFromFloat(uvw[2] * @as(f32, @floatFromInt(self.conditional.len)));
        const c = @min(i, @as(u32, @intCast(self.conditional.len - 1)));

        const uv_pdf = self.conditional[c].pdf(.{ uvw[0], uvw[1] });
        return uv_pdf * w_pdf;
    }
};
