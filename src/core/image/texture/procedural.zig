pub const DetailNormal = @import("procedural_detail_normal.zig").DetailNormal;
pub const Checker = @import("procedural_checker.zig").Checker;
pub const Max = @import("procedural_max.zig").Max;
pub const Mix = @import("procedural_mix.zig").Mix;
pub const Mul = @import("procedural_mul.zig").Mul;
pub const Noise = @import("procedural_noise.zig").Noise;
const Texture = @import("texture.zig").Texture;
const ts = @import("texture_sampler.zig");
const Renderstate = @import("../../scene/renderstate.zig").Renderstate;
const Worker = @import("../../rendering/worker.zig").Worker;
const Sampler = @import("../../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;

pub const Procedural = struct {
    const Error = error{
        UnsupportedType,
    };

    pub const Type = enum {
        Checker,
        DetailNormal,
        Max,
        Mix,
        Mul,
        Noise,
    };

    checkers: List(Checker) = .empty,
    detail_normals: List(DetailNormal) = .empty,
    maxes: List(Max) = .empty,
    mixes: List(Mix) = .empty,
    muls: List(Mul) = .empty,
    noises: List(Noise) = .empty,

    pub fn deinit(self: *Procedural, alloc: Allocator) void {
        self.checkers.deinit(alloc);
        self.detail_normals.deinit(alloc);
        self.maxes.deinit(alloc);
        self.mixes.deinit(alloc);
        self.muls.deinit(alloc);
        self.noises.deinit(alloc);
    }

    pub fn append(self: *Procedural, alloc: Allocator, procedural: anytype) !u32 {
        const ptype = @TypeOf(procedural);

        if (Checker == ptype) {
            return appendItem(ptype, alloc, &self.checkers, procedural);
        } else if (DetailNormal == ptype) {
            return appendItem(ptype, alloc, &self.detail_normals, procedural);
        } else if (Max == ptype) {
            return appendItem(ptype, alloc, &self.maxes, procedural);
        } else if (Mix == ptype) {
            return appendItem(ptype, alloc, &self.mixes, procedural);
        } else if (Mul == ptype) {
            return appendItem(ptype, alloc, &self.muls, procedural);
        } else if (Noise == ptype) {
            return appendItem(ptype, alloc, &self.noises, procedural);
        }

        return Error.UnsupportedType;
    }

    fn appendItem(comptime Value: type, alloc: Allocator, list: *List(Value), item: Value) !u32 {
        const id: u32 = @truncate(list.items.len);
        try list.append(alloc, item);
        return id;
    }

    pub fn sample2D_1(self: Procedural, key: ts.Key, texture: Texture, rs: Renderstate, sampler: *Sampler, worker: *const Worker) f32 {
        const proc: Type = @enumFromInt(texture.data.procedural.id);

        const data = texture.data.procedural.data;

        return switch (proc) {
            .Checker => self.checkers.items[data].evaluate(rs, key, texture.uv_set, worker)[0],
            .DetailNormal => 0.0,
            .Max => self.maxes.items[data].evaluate1(rs, key, sampler, worker),
            .Mix => self.mixes.items[data].evaluate1(rs, key, sampler, worker),
            .Mul => self.muls.items[data].evaluate1(rs, key, sampler, worker),
            .Noise => self.noises.items[data].evaluate1(rs, @splat(0.0), texture.uv_set),
        };
    }

    pub fn sample2D_2(self: Procedural, key: ts.Key, texture: Texture, rs: Renderstate, sampler: *Sampler, worker: *const Worker) Vec2f {
        const proc: Type = @enumFromInt(texture.data.procedural.id);

        const data = texture.data.procedural.data;

        return switch (proc) {
            .Checker => {
                const color = self.checkers.items[data].evaluate(rs, key, texture.uv_set, worker);
                return .{ color[0], color[1] };
            },
            .DetailNormal => self.detail_normals.items[data].evaluate(rs, key, sampler, worker),
            .Max => self.maxes.items[data].evaluate2(rs, key, sampler, worker),
            .Mix => self.mixes.items[data].evaluate2(rs, key, sampler, worker),
            .Mul => self.muls.items[data].evaluate2(rs, key, sampler, worker),
            .Noise => self.noises.items[data].evaluateNormalmap(rs, texture.uv_set, worker),
        };
    }

    pub fn sample2D_3(self: Procedural, key: ts.Key, texture: Texture, rs: Renderstate, sampler: *Sampler, worker: *const Worker) Vec4f {
        const proc: Type = @enumFromInt(texture.data.procedural.id);

        const data = texture.data.procedural.data;

        return switch (proc) {
            .Checker => self.checkers.items[data].evaluate(rs, key, texture.uv_set, worker),
            .DetailNormal => @splat(0.0),
            .Max => self.maxes.items[data].evaluate3(rs, key, sampler, worker),
            .Mix => self.mixes.items[data].evaluate3(rs, key, sampler, worker),
            .Mul => self.muls.items[data].evaluate3(rs, key, sampler, worker),
            .Noise => self.noises.items[data].evaluate3(rs, texture.uv_set),
        };
    }
};
