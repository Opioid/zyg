const Camera = @import("../camera/camera.zig").Camera;
const Scene = @import("scene.zig").Scene;
const vt = @import("vertex.zig");
const Vertex = vt.Vertex;
const RayDif = vt.RayDif;
const rst = @import("renderstate.zig");
const Renderstate = rst.Renderstate;
const Probe = @import("shape/probe.zig").Probe;
const MediumStack = @import("prop/medium.zig").Stack;
const Material = @import("material/material.zig").Material;
const MaterialSample = @import("material/material_sample.zig").Sample;
const hlp = @import("material/material_helper.zig");
const ro = @import("ray_offset.zig");
const int = @import("shape/intersection.zig");
const Fragment = int.Fragment;
const Volume = int.Volume;
const DifferentialSurface = int.DifferentialSurface;
const Texture = @import("../image/texture/texture.zig").Texture;
const ts = @import("../image/texture/texture_sampler.zig");
const smpl = @import("../sampler/sampler.zig");
const Sampler = smpl.Sampler;
const VolumeIntegrator = @import("../rendering/integrator/volume/volume_integrator.zig").Integrator;

const base = @import("base");
const math = base.math;
const Mat3x3 = math.Mat3x3;
const Vec2b = math.Vec2b;
const Vec2i = math.Vec2i;
const Vec2ul = math.Vec2ul;
const Vec2f = math.Vec2f;
const Vec4i = math.Vec4i;
const Vec4f = math.Vec4f;
const Ray = math.Ray;

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Context = struct {
    camera: *Camera,
    scene: *Scene,

    layer: u32,

    const Self = @This();

    pub fn intersect(self: Self, probe: *Probe, sampler: *Sampler, frag: *Fragment) bool {
        return self.scene.intersect(probe, sampler, frag);
    }

    pub fn visibility(self: Self, probe: Probe, sampler: *Sampler, tr: *Vec4f) bool {
        return self.scene.visibility(probe, sampler, self, tr);
    }

    pub fn nextEvent(self: Self, vertex: *Vertex, frag: *Fragment, sampler: *Sampler) void {
        if (!vertex.mediums.empty()) {
            VolumeIntegrator.integrate(vertex, frag, sampler, self);
            return;
        }

        const origin = vertex.probe.ray.origin;

        _ = self.intersect(&vertex.probe, sampler, frag);

        const dif_t = math.distance3(origin, vertex.probe.ray.origin);
        vertex.probe.ray.origin = origin;
        vertex.probe.ray.max_t += dif_t;

        self.scene.scatter(&vertex.probe, frag, &vertex.throughput, sampler, self);
    }

    pub fn emission(self: Self, vertex: *const Vertex, frag: *Fragment, split_threshold: f32, sampler: *Sampler) Vec4f {
        return self.scene.unoccluding_bvh.emission(vertex, frag, split_threshold, sampler, self);
    }

    pub fn propTransmittance(
        self: Self,
        ray: Ray,
        material: *const Material,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
        tr: *Vec4f,
    ) bool {
        const cc = material.collisionCoefficients();
        return VolumeIntegrator.propTransmittance(ray, material, cc, entity, depth, sampler, self, tr);
    }

    pub fn propScatter(
        self: Self,
        ray: Ray,
        throughput: Vec4f,
        material: *const Material,
        entity: u32,
        depth: u32,
        sampler: *Sampler,
    ) Volume {
        const cc = material.collisionCoefficients();
        return VolumeIntegrator.propScatter(ray, throughput, material, cc, entity, depth, sampler, self);
    }

    pub fn propIntersect(self: Self, entity: u32, probe: Probe, sampler: *Sampler, frag: *Fragment) bool {
        if (self.scene.prop(entity).intersect(entity, entity, probe, sampler, self.scene, &self.scene.prop_space, &frag.isec)) {
            frag.prop = entity;
            return true;
        }

        return false;
    }

    pub fn propInterpolateFragment(self: Self, entity: u32, probe: Probe, frag: *Fragment) void {
        self.scene.propShape(entity).fragment(probe.ray, frag);
    }

    pub fn sampleProcedural2D_1(self: Self, texture: Texture, rs: Renderstate, sampler: *Sampler) f32 {
        return self.scene.procedural.sample2D_1(texture, rs, sampler, self);
    }

    pub fn sampleProcedural2D_2(self: Self, texture: Texture, rs: Renderstate, sampler: *Sampler) Vec2f {
        return self.scene.procedural.sample2D_2(texture, rs, sampler, self);
    }

    pub fn sampleProcedural2D_3(self: Self, texture: Texture, rs: Renderstate, sampler: *Sampler) Vec4f {
        return self.scene.procedural.sample2D_3(texture, rs, sampler, self);
    }

    pub fn absoluteTime(self: Self, frame: u32, frame_delta: f32) u64 {
        return self.camera.super().absoluteTime(frame, frame_delta);
    }

    pub fn screenspaceDifferential(self: Self, rs: Renderstate, texcoord: Texture.Mode.TexCoord) Vec4f {
        const rd = self.camera.calculateRayDifferential(self.layer, rs.p, rs.time, self.scene);

        const ds: DifferentialSurface =
            if (.UV0 == texcoord)
                self.scene.propShape(rs.prop).surfaceDifferential(rs.primitive, rs.trafo)
            else
                hlp.triplanarDifferential(rs.geo_n, rs.trafo);

        return calculateScreenspaceDifferential(rs.p, rs.geo_n, rd, ds.dpdu, ds.dpdv);
    }

    // https://blog.yiningkarlli.com/2018/10/bidirectional-mipmap.html
    fn calculateScreenspaceDifferential(p: Vec4f, n: Vec4f, rd: RayDif, dpdu: Vec4f, dpdv: Vec4f) Vec4f {
        // Compute offset-ray frag points with tangent plane
        const d = math.dot3(n, p);

        const tx = -(math.dot3(n, rd.x_origin) - d) / math.dot3(n, rd.x_direction);
        const ty = -(math.dot3(n, rd.y_origin) - d) / math.dot3(n, rd.y_direction);

        const px = rd.x_origin + @as(Vec4f, @splat(tx)) * rd.x_direction;
        const py = rd.y_origin + @as(Vec4f, @splat(ty)) * rd.y_direction;

        // Compute uv offsets at offset-ray frag points
        // Choose two dimensions to use for ray offset computations
        const dim = if (@abs(n[0]) > @abs(n[1]) and @abs(n[0]) > @abs(n[2])) Vec2b{
            1,
            2,
        } else if (@abs(n[1]) > @abs(n[2])) Vec2b{
            0,
            2,
        } else Vec2b{
            0,
            1,
        };

        // Initialize A, bx, and by matrices for offset computation
        const a: [2][2]f32 = .{ .{ dpdu[dim[0]], dpdv[dim[0]] }, .{ dpdu[dim[1]], dpdv[dim[1]] } };

        const bx = Vec2f{ px[dim[0]] - p[dim[0]], px[dim[1]] - p[dim[1]] };
        const by = Vec2f{ py[dim[0]] - p[dim[0]], py[dim[1]] - p[dim[1]] };

        const det = a[0][0] * a[1][1] - a[0][1] * a[1][0];

        if (@abs(det) < 1.0e-10) {
            return @splat(0.0);
        }

        const dudx = (a[1][1] * bx[0] - a[0][1] * bx[1]) / det;
        const dvdx = (a[0][0] * bx[1] - a[1][0] * bx[0]) / det;

        const dudy = (a[1][1] * by[0] - a[0][1] * by[1]) / det;
        const dvdy = (a[0][0] * by[1] - a[1][0] * by[0]) / det;

        return .{ dudx, dvdx, dudy, dvdy };
    }

    // Adapted from PBRT
    // https://github.com/mmp/pbrt-v4/blob/f140d7cba5dc7b941f9346d6b7d1476a05c28c37/src/pbrt/cameras.h#L155
    pub fn approximateDpDxy(self: Self, rs: Renderstate) [2]Vec4f {
        const Origin: Vec4f = comptime @splat(0.0);
        const Z: Vec4f = comptime .{ 0.0, 0.0, 1.0, 0.0 };

        const min_pos_differential_x: Vec4f = @splat(0.0);
        const min_pos_differential_y: Vec4f = @splat(0.0);

        const min_dir_differential_x, const min_dir_differential_y = self.camera.minDirDifferential(self.layer);

        const trafo = self.scene.propTransformationAt(self.camera.super().entity, rs.time);

        const p_o = trafo.worldToObjectPoint(rs.p);
        const n_o = trafo.worldToObjectNormal(rs.geo_n);

        const down_z_from_camera = Mat3x3.initRotationAlign(math.normalize3(p_o), Z);
        const p_down_z = down_z_from_camera.transformVector(p_o);
        const n_down_z = down_z_from_camera.transformVector(n_o);
        const d = n_down_z[2] * p_down_z[2];

        const x_ray = Ray.init(Origin + min_pos_differential_x, Z + min_dir_differential_x, 0.0, 1.0);
        const tx = -(math.dot3(n_down_z, x_ray.origin) - d) / math.dot3(n_down_z, x_ray.direction);

        const y_ray = Ray.init(Origin + min_pos_differential_y, Z + min_dir_differential_y, 0.0, 1.0);
        const ty = -(math.dot3(n_down_z, y_ray.origin) - d) / math.dot3(n_down_z, y_ray.direction);

        const px = x_ray.point(tx);
        const py = y_ray.point(ty);

        const dpdx = trafo.objectToWorldVector(down_z_from_camera.transformVectorTransposed(px - p_down_z));
        const dpdy = trafo.objectToWorldVector(down_z_from_camera.transformVectorTransposed(py - p_down_z));

        return .{
            dpdx,
            dpdy,
        };
    }
};
