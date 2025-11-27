const Shape = @import("shape.zig").Shape;
const Portal = @import("portal.zig").Portal;
const Probe = @import("probe.zig").Probe;
const Scene = @import("../scene.zig").Scene;
const Trafo = @import("../composed_transformation.zig").ComposedTransformation;
const Material = @import("../material/material.zig").Material;
const SamplerMode = @import("../../texture/sampler_mode.zig").Mode;
const LowThreshold = @import("../../rendering/integrator/helper.zig").LightSampling.LowThreshold;

const TriangleTree = @import("triangle/triangle_tree.zig").Tree;
const LightTree = @import("../light/light_tree.zig").PrimitiveTree;
const LightProperties = @import("../light/light.zig").Properties;

const base = @import("base");
const math = base.math;
const Vec2f = math.Vec2f;
const Vec4f = math.Vec4f;
const AABB = math.AABB;
const Bounds2f = math.Bounds2f;
const Distribution1D = math.Distribution1D;
const Distribution2D = math.Distribution2D;
const Distribution3D = math.Distribution3D;
const WindowedDistribution2D = math.WindowedDistribution2D;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Sampler = struct {
    impl: Impl,

    average_emission: Vec4f = @splat(-1.0),

    num_samples: u32 = 1,

    pub fn numSamples(self: *const Sampler, split_threshold: f32) u32 {
        if (split_threshold <= LowThreshold) {
            return 1;
        }

        return self.num_samples;
    }

    pub fn averageEmission(self: *const Sampler, material: *const Material) Vec4f {
        return switch (self.impl) {
            .Mesh => |i| if (i.emission_mapped) self.average_emission else material.uniformRadiance(),
            else => self.average_emission,
        };
    }
};

pub const RadianceSample = struct {
    uvw: Vec4f,

    pub fn init2(uv: Vec2f, pdf_: f32) RadianceSample {
        return .{ .uvw = .{ uv[0], uv[1], 0.0, pdf_ } };
    }

    pub fn init3(uvw: Vec4f, pdf_: f32) RadianceSample {
        return .{ .uvw = .{ uvw[0], uvw[1], uvw[2], pdf_ } };
    }

    pub fn pdf(self: RadianceSample) f32 {
        return self.uvw[3];
    }
};

const Impl = union(enum) {
    Uniform,
    Image: ImageImpl,
    Mesh: MeshImpl,
    Portal: PortalImpl,
    Volume: VolumeImpl,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        switch (self.*) {
            .Uniform => {},
            inline else => |*i| i.deinit(alloc),
        }
    }

    pub fn sample(self: *const Self, r3: Vec4f) RadianceSample {
        return switch (self.*) {
            .Image => |*i| i.sample(r3),
            .Volume => |*i| i.sample(r3),
            else => RadianceSample.init3(r3, 1.0),
        };
    }

    pub fn pdf(self: *const Self, uvw: Vec4f) f32 {
        return switch (self.*) {
            .Image => |*i| i.pdf(.{ uvw[0], uvw[1] }),
            .Volume => |*i| i.pdf(uvw),
            else => 1.0,
        };
    }

    pub fn portalUvw(self: *const Self, uvw: Vec4f, dir: Vec4f, time: u64, scene: *const Scene) Vec4f {
        return switch (self.*) {
            .Portal => |*i| i.portalUvw(dir, time, scene),
            else => uvw,
        };
    }

    pub fn aabb(self: *const Self, shape: *const Shape) AABB {
        return switch (self.*) {
            .Mesh => |*i| i.aabb,
            else => shape.aabb(),
        };
    }

    pub fn cone(self: *const Self, shape: *const Shape) Vec4f {
        return switch (self.*) {
            .Mesh => |*i| i.cone,
            else => shape.cone(),
        };
    }

    pub fn estimateNumBytes(self: *const Self) usize {
        return switch (self.*) {
            inline .Image, .Mesh => |*i| i.estimateNumBytes(),
            else => 0,
        };
    }
};

const ImageImpl = struct {
    distribution: Distribution2D = .{},
    total_weight: f32 = undefined,
    mode: SamplerMode,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.distribution.deinit(alloc);
    }

    pub fn sample(self: *const Self, r3: Vec4f) RadianceSample {
        const result = self.distribution.sampleContinuous(.{ r3[0], r3[1] });

        return RadianceSample.init2(result.uv, result.pdf * self.total_weight);
    }

    pub fn pdf(self: *const Self, uv: Vec2f) f32 {
        return self.distribution.pdf(self.mode.address2(uv)) * self.total_weight;
    }

    pub fn estimateNumBytes(self: *const Self) usize {
        return self.distribution.numBytes();
    }
};

pub const MeshImpl = struct {
    distribution: Distribution1D = .{},

    light_tree: LightTree = .{},

    aabb: AABB,
    cone: Vec4f,

    emission_mapped: bool,
    two_sided: bool,

    triangle_mapping: [*]u32,

    tree: *const TriangleTree,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.light_tree.deinit(alloc);
        self.distribution.deinit(alloc);
    }

    pub fn numTriangles(self: *const Self) u32 {
        return self.distribution.size - 1;
    }

    pub fn power(self: *const Self) f32 {
        return self.distribution.integral;
    }

    pub fn lightAabb(self: *const Self, light: u32) AABB {
        const global = self.triangle_mapping[light];
        return self.tree.data.triangleAabb(self.tree.data.indexTriangle(global));
    }

    pub fn lightCone(self: *const Self, light: u32) Vec4f {
        const global = self.triangle_mapping[light];
        const n = self.tree.data.normal(self.tree.data.indexTriangle(global));
        return .{ n[0], n[1], n[2], 1.0 };
    }

    pub fn lightPower(self: *const Self, light: u32) f32 {
        // I think it is fine to just give the primitives relative power in this case
        return self.distribution.pdfI(light);
    }

    pub fn lightProperties(self: *const Self, light: u32) LightProperties {
        const global = self.triangle_mapping[light];

        const abc = self.tree.data.triangleP(self.tree.data.indexTriangle(global));

        const center = (abc[0] + abc[1] + abc[2]) / @as(Vec4f, @splat(3.0));

        const sra = math.squaredLength3(abc[0] - center);
        const srb = math.squaredLength3(abc[1] - center);
        const src = math.squaredLength3(abc[2] - center);

        const radius = @sqrt(math.max(sra, math.max(srb, src)));

        const e1 = abc[1] - abc[0];
        const e2 = abc[2] - abc[0];
        const n = math.normalize3(math.cross3(e1, e2));

        // I think it is fine to just give the primitives relative power in this case
        const pow = self.distribution.pdfI(light);

        return .{
            .sphere = .{ center[0], center[1], center[2], radius },
            .cone = .{ n[0], n[1], n[2], 1.0 },
            .power = pow,
            .two_sided = self.two_sided,
        };
    }

    pub fn sample(
        self: *const Self,
        p: Vec4f,
        n: Vec4f,
        total_sphere: bool,
        r: f32,
        split_threshold: f32,
        buffer: *LightTree.Samples,
    ) []Distribution1D.Discrete {
        // _ = p;
        // _ = n;
        // _ = total_sphere;

        // return self.sampleRandom(variant, r);

        return self.light_tree.randomLight(p, n, total_sphere, r, split_threshold, self, buffer);
    }

    pub fn pdf(self: *const Self, p: Vec4f, n: Vec4f, total_sphere: bool, split_threshold: f32, id: u32) f32 {
        // _ = p;
        // _ = n;
        // _ = total_sphere;

        // return self.variants.items[variant].distribution.pdfI(id);

        return self.light_tree.pdf(p, n, total_sphere, split_threshold, id, self);
    }

    pub fn estimateNumBytes(self: *const Self) usize {
        var num_bytes = self.distribution.numBytes();
        num_bytes += self.light_tree.estimateNumBytes();
        return num_bytes;
    }
};

const PortalImpl = struct {
    distribution: WindowedDistribution2D,

    light_link: u32,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.distribution.deinit(alloc);
    }

    pub fn portalUvw(self: *const Self, dir: Vec4f, time: u64, scene: *const Scene) Vec4f {
        const light = scene.light(self.light_link);
        const trafo = scene.propTransformationAt(light.prop, time);

        const xyz = math.normalize3(trafo.rotation.transformVectorTransposed(dir));

        return .{
            std.math.atan2(xyz[0], xyz[2]) * (math.pi_inv * 0.5) + 0.5,
            std.math.acos(xyz[1]) * math.pi_inv,
            0.0,
            0.0,
        };
    }

    pub fn sample(self: *const Self, bounds: Bounds2f, r2: Vec2f) RadianceSample {
        const rs = self.distribution.sampleContinuous(r2, bounds);

        return .init2(rs.uv, rs.pdf);
    }

    pub fn pdf(self: *const Self, p: Vec4f, uv: Vec2f, trafo: Trafo) f32 {
        const b = Portal.imageBounds(p, trafo) orelse return 0.0;

        return self.distribution.pdf(uv, b);
    }
};

const VolumeImpl = struct {
    distribution: Distribution3D = .{},
    pdf_factor: f32,
    mode: SamplerMode,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.distribution.deinit(alloc);
    }

    pub fn sample(self: *const Self, r3: Vec4f) RadianceSample {
        const result = self.distribution.sampleContinuous(r3);

        return RadianceSample.init3(result, result[3] * self.pdf_factor);
    }

    pub fn pdf(self: *const Self, uvw: Vec4f) f32 {
        return self.distribution.pdf(self.mode.address3(uvw)) * self.pdf_factor;
    }
};
