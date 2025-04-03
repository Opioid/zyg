pub const DetailNormal = @import("procedural_detail_normal.zig").DetailNormal;
pub const Checker = @import("procedural_checker.zig").Checker;
pub const Max = @import("procedural_max.zig").Max;
pub const Mix = @import("procedural_mix.zig").Mix;
pub const Mul = @import("procedural_mul.zig").Mul;
const Texture = @import("texture.zig").Texture;
const ts = @import("texture_sampler.zig");
const Renderstate = @import("../../scene/renderstate.zig").Renderstate;
const Scene = @import("../../scene/scene.zig").Scene;
const Sampler = @import("../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub const Procedural = struct {
    pub const Type = enum {
        Checker,
        DetailNormal,
        Max,
        Mix,
        Mul,
    };

    checkers: List(Checker) = .empty,
    detail_normals: List(DetailNormal) = .empty,
    maxes: List(Max) = .empty,
    mixes: List(Mix) = .empty,
    muls: List(Mul) = .empty,

    pub fn deinit(self: *Procedural, alloc: Allocator) void {
        self.checkers.deinit(alloc);
        self.detail_normals.deinit(alloc);
        self.maxes.deinit(alloc);
        self.mixes.deinit(alloc);
        self.muls.deinit(alloc);
    }

    pub fn sample2D_1(self: Procedural, key: ts.Key, texture: Texture, rs: Renderstate, sampler: *Sampler, scene: *const Scene) f32 {
        const proc: Type = @enumFromInt(texture.data.procedural.id);

        const data = texture.data.procedural.data;

        return switch (proc) {
            .Checker => self.checkers.items[data].evaluate(rs, key)[0],
            .DetailNormal => 0.0,
            .Max => self.maxes.items[data].evaluate1(rs, key, sampler, scene),
            .Mix => self.mixes.items[data].evaluate1(rs, key, sampler, scene),
            .Mul => self.muls.items[data].evaluate1(rs, key, sampler, scene),
        };
    }

    pub fn sample2D_2(self: Procedural, key: ts.Key, texture: Texture, rs: Renderstate, sampler: *Sampler, scene: *const Scene) Vec2f {
        const proc: Type = @enumFromInt(texture.data.procedural.id);

        const data = texture.data.procedural.data;

        return switch (proc) {
            .Checker => {
                const color = self.checkers.items[data].evaluate(rs, key);
                return .{ color[0], color[1] };
            },
            .DetailNormal => self.detail_normals.items[data].evaluate(rs, key, sampler, scene),
            .Max => self.maxes.items[data].evaluate2(rs, key, sampler, scene),
            .Mix => self.mixes.items[data].evaluate2(rs, key, sampler, scene),
            .Mul => self.muls.items[data].evaluate2(rs, key, sampler, scene),
        };
    }

    pub fn sample2D_3(self: Procedural, key: ts.Key, texture: Texture, rs: Renderstate, sampler: *Sampler, scene: *const Scene) Vec4f {
        const proc: Type = @enumFromInt(texture.data.procedural.id);

        const data = texture.data.procedural.data;

        return switch (proc) {
            .Checker => self.checkers.items[data].evaluate(rs, key),
            .DetailNormal => @splat(0.0),
            .Max => self.maxes.items[data].evaluate3(rs, key, sampler, scene),
            .Mix => self.mixes.items[data].evaluate3(rs, key, sampler, scene),
            .Mul => self.muls.items[data].evaluate3(rs, key, sampler, scene),
        };
    }
};
