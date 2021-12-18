const Photon = @import("photon.zig").Photon;
const Map = @import("photon_map.zig").Map;
const Worker = @import("../../../worker.zig").Worker;
const smp = @import("../../../../sampler/sampler.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Mapper = struct {
    pub const Settings = struct {
        max_bounces: u32,
        full_light_path: bool,
    };

    settings: Settings,
    sampler: smp.Sampler,

    photons: [*]Photon,

    const Self = @This();

    pub fn init(alloc: Allocator, settings: Settings) !Self {
        return Self{
            .settings = settings,
            .sampler = .{ .Random = .{} },
            .photons = (try alloc.alloc(Photon, settings.max_bounces)).ptr,
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.photons[0..self.settings.max_bounces]);
    }

    pub fn bake(
        self: *Self,
        map: *Map,
        begin: u32,
        end: u32,
        frame: u32,
        iteration: u32,
        worker: *Worker,
    ) u32 {
        _ = self;
        _ = map;
        _ = begin;
        _ = end;
        _ = frame;
        _ = iteration;
        _ = worker;
        return 0;
    }
};
