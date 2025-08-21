pub const ChannelMix = @import("procedural_channel_mix.zig").ChannelMix;
pub const Checker = @import("procedural_checker.zig").Checker;
pub const DetailNormal = @import("procedural_detail_normal.zig").DetailNormal;
pub const Max = @import("procedural_max.zig").Max;
pub const Mix = @import("procedural_mix.zig").Mix;
pub const Mul = @import("procedural_mul.zig").Mul;
pub const Noise = @import("procedural_noise.zig").Noise;
const Texture = @import("texture.zig").Texture;
const ts = @import("texture_sampler.zig");
const Context = @import("../scene/context.zig").Context;
const Renderstate = @import("../scene/renderstate.zig").Renderstate;
const Sampler = @import("../sampler/sampler.zig").Sampler;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayList;

pub const Procedural = struct {
    const Error = error{
        UnsupportedType,
    };

    pub const Type = enum {
        ChannelMix,
        Checker,
        DetailNormal,
        Max,
        Mix,
        Mul,
        Noise,
    };

    channel_mixes: List(ChannelMix) = .empty,
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

        if (ChannelMix == ptype) {
            return appendItem(ptype, alloc, &self.channel_mixes, procedural);
        } else if (Checker == ptype) {
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

    pub fn sample2D_1(self: Procedural, texture: Texture, rs: Renderstate, sampler: *Sampler, context: Context) f32 {
        const proc: Type = @enumFromInt(texture.data.procedural.id);

        const data = texture.data.procedural.data;

        return switch (proc) {
            .ChannelMix => self.channel_mixes.items[data].evaluate1(rs, sampler, context),
            .Checker => self.checkers.items[data].evaluate(rs, texture.mode, context)[0],
            .DetailNormal => 0.0,
            .Max => self.maxes.items[data].evaluate1(rs, sampler, context),
            .Mix => self.mixes.items[data].evaluate1(rs, sampler, context),
            .Mul => self.muls.items[data].evaluate1(rs, sampler, context),
            .Noise => self.noises.items[data].evaluate1(rs, @splat(0.0), texture.mode),
        };
    }

    pub fn sample2D_2(self: Procedural, texture: Texture, rs: Renderstate, sampler: *Sampler, context: Context) Vec2f {
        const proc: Type = @enumFromInt(texture.data.procedural.id);

        const data = texture.data.procedural.data;

        return switch (proc) {
            .ChannelMix => self.channel_mixes.items[data].evaluate2(rs, sampler, context),
            .Checker => {
                const color = self.checkers.items[data].evaluate(rs, texture.mode, context);
                return .{ color[0], color[1] };
            },
            .DetailNormal => self.detail_normals.items[data].evaluate(rs, sampler, context),
            .Max => self.maxes.items[data].evaluate2(rs, sampler, context),
            .Mix => self.mixes.items[data].evaluate2(rs, sampler, context),
            .Mul => self.muls.items[data].evaluate2(rs, sampler, context),
            .Noise => self.noises.items[data].evaluateNormalmap(rs, texture.mode, context),
        };
    }

    pub fn sample2D_3(self: Procedural, texture: Texture, rs: Renderstate, sampler: *Sampler, context: Context) Vec4f {
        const proc: Type = @enumFromInt(texture.data.procedural.id);

        const data = texture.data.procedural.data;

        return switch (proc) {
            .ChannelMix => self.channel_mixes.items[data].evaluate3(rs, sampler, context),
            .Checker => self.checkers.items[data].evaluate(rs, texture.mode, context),
            .DetailNormal => @splat(0.0),
            .Max => self.maxes.items[data].evaluate3(rs, sampler, context),
            .Mix => self.mixes.items[data].evaluate3(rs, sampler, context),
            .Mul => self.muls.items[data].evaluate3(rs, sampler, context),
            .Noise => self.noises.items[data].evaluate3(rs, texture.mode),
        };
    }
};
