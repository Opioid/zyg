const core = @import("core");
const log = core.log;
const img = core.image;
const rendering = core.rendering;
const resource = core.resource;
const scn = core.scn;
const Take = core.tk.Take;
const prg = core.progress;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec4i = math.Vec4i;
const Pack4f = math.Pack4f;
const Mat3x3 = math.Mat3x3;
const Mat4x4 = math.Mat4x4;
const Transformation = math.Transformation;
const encoding = base.encoding;
const spectrum = base.spectrum;
const Threads = base.thread.Pool;

const std = @import("std");
const Allocator = std.mem.Allocator;

const Format = enum(u32) {
    UInt8,
    UInt16,
    UInt32,
    Float16,
    Float32,
};

const Engine = struct {
    alloc: Allocator,

    threads: Threads = .{},

    scene: scn.Scene = undefined,
    resources: resource.Manager = undefined,
    fallback_material: u32 = undefined,
    materials: std.ArrayListUnmanaged(u32) = .empty,

    take: Take = .{},
    driver: rendering.Driver = undefined,

    frame: u32 = 0,
    iteration: u32 = 0,
};

var engine: ?Engine = null;

export fn su_init() i32 {
    if (engine) |_| {
        return -1;
    }

    const alloc = std.heap.c_allocator;

    engine = .{ .alloc = alloc };

    if (engine) |*e| {
        const num_workers = Threads.availableCores(0);
        e.threads.configure(alloc, num_workers) catch {
            //_ = err;
            engine = null;
            return -1;
        };

        e.scene = scn.Scene.init(alloc) catch {
            engine = null;
            return -1;
        };

        e.take.view.cameras.append(alloc, .{}) catch {
            engine = null;
            return -1;
        };

        e.resources = resource.Manager.init(alloc, &e.scene, &e.threads) catch {
            engine = null;
            return -1;
        };

        const resources = &e.resources;

        e.fallback_material = resources.materials.store(
            alloc,
            resource.Null,
            resource.MaterialProvider.createFallbackMaterial(),
        ) catch {
            engine = null;
            return -1;
        };

        e.take.view.num_samples_per_pixel = 1;

        e.driver = rendering.Driver.init(alloc, &e.threads, &e.resources.fs, .{ .Null = {} }) catch {
            engine = null;
            return -1;
        };

        return 0;
    }

    return -1;
}

export fn su_release() i32 {
    if (engine) |*e| {
        e.driver.deinit(e.alloc);
        e.take.deinit(e.alloc);
        e.materials.deinit(e.alloc);
        e.resources.deinit(e.alloc);
        e.scene.deinit(e.alloc);
        e.threads.deinit(e.alloc);
        engine = null;
        return 0;
    }

    return -1;
}

export fn su_mount(folder: [*:0]const u8) i32 {
    if (engine) |*e| {
        e.resources.fs.pushMount(e.alloc, folder[0..std.mem.len(folder)]) catch {
            return -1;
        };

        return 0;
    }

    return -1;
}

export fn su_perspective_camera_create(width: u32, height: u32) i32 {
    if (engine) |*e| {
        const resolution = Vec2i{ @intCast(width), @intCast(height) };
        const crop = Vec4i{ 0, 0, resolution[0], resolution[1] };

        var camera = &e.take.view.cameras.items[0];

        camera.setResolution(resolution, crop);
        camera.fov = math.degreesToRadians(80.0);

        if (scn.Prop.Null == camera.entity) {
            const prop_id = e.scene.createEntity(e.alloc) catch {
                return -1;
            };

            camera.entity = prop_id;
        }

        e.scene.calculateNumInterpolationFrames(camera.frame_step, camera.frame_duration);

        return @intCast(camera.entity);
    }

    return -1;
}

export fn su_camera_set_fov(fov: f32) i32 {
    if (engine) |*e| {
        e.take.view.cameras.items[0].fov = fov;
        return 0;
    }

    return -1;
}

export fn su_camera_sensor_dimensions(dimensions: [*]i32) i32 {
    if (engine) |*e| {
        const d = e.take.view.cameras.items[0].resolution;
        dimensions[0] = d[0];
        dimensions[1] = d[1];
        return 0;
    }

    return -1;
}

export fn su_exporters_create(string: [*:0]const u8) i32 {
    if (engine) |*e| {
        var parsed = std.json.parseFromSlice(std.json.Value, e.alloc, string[0..std.mem.len(string)], .{}) catch return -1;
        defer parsed.deinit();

        e.take.loadExporters(e.alloc, parsed.value) catch return -1;

        return 0;
    }

    return -1;
}

export fn su_aovs_create(string: [*:0]const u8) i32 {
    if (engine) |*e| {
        var parsed = std.json.parseFromSlice(std.json.Value, e.alloc, string[0..std.mem.len(string)], .{}) catch return -1;
        defer parsed.deinit();

        e.take.view.loadAOV(parsed.value);

        return 0;
    }

    return -1;
}

export fn su_sampler_create(num_samples: u32) i32 {
    if (engine) |*e| {
        e.take.view.num_samples_per_pixel = num_samples;
    }

    return -1;
}

export fn su_integrators_create(string: [*:0]const u8) i32 {
    if (engine) |*e| {
        var parsed = std.json.parseFromSlice(std.json.Value, e.alloc, string[0..std.mem.len(string)], .{}) catch return -1;
        defer parsed.deinit();

        e.take.view.loadIntegrators(parsed.value);

        return 0;
    }

    return -1;
}

export fn su_image_create(
    id: u32,
    format: u32,
    num_channels: u32,
    width: u32,
    height: u32,
    depth: u32,
    pixel_stride: u32,
    data: [*]u8,
) i32 {
    if (engine) |*e| {
        const ef = @as(Format, @enumFromInt(format));
        const bpc: u32 = switch (ef) {
            .UInt8 => 1,
            .UInt16, .Float16 => 2,
            .UInt32, .Float32 => 4,
        };

        const desc = img.Description.init3D(.{ @intCast(width), @intCast(height), @intCast(depth), 1 });

        const buffer = e.alloc.allocWithOptions(u8, bpc * num_channels * width * height * depth, 8, null) catch {
            return -1;
        };

        const bpp = bpc * num_channels;

        if (bpp == pixel_stride) {
            @memcpy(buffer, data[0 .. desc.numPixels() * bpp]);
        }

        const image: ?img.Image = switch (ef) {
            .UInt8 => switch (num_channels) {
                1 => img.Image{ .Byte1 = img.Byte1.initFromBytes(desc, buffer) },
                2 => img.Image{ .Byte2 = img.Byte2.initFromBytes(desc, buffer) },
                3 => img.Image{ .Byte3 = img.Byte3.initFromBytes(desc, buffer) },
                else => null,
            },
            .Float32 => switch (num_channels) {
                1 => img.Image{ .Float1 = img.Float1.initFromBytes(desc, buffer) },
                2 => img.Image{ .Float2 = img.Float2.initFromBytes(desc, buffer) },
                3 => img.Image{ .Float3 = img.Float3.initFromBytes(desc, buffer) },
                4 => img.Image{ .Float4 = img.Float4.initFromBytes(desc, buffer) },
                else => null,
            },
            else => null,
        };

        if (image) |i| {
            const image_id = e.resources.images.store(e.alloc, id, i) catch {
                return -1;
            };
            return @as(i32, @intCast(image_id));
        }

        e.alloc.free(buffer);

        return -1;
    }

    return -1;
}

export fn su_image_update(id: u32, pixel_stride: u32, data: [*]u8) i32 {
    if (engine) |*e| {
        if (e.resources.images.get(id)) |image| {
            const bpc: u32 = switch (image.*) {
                .Byte1, .Byte2, .Byte3, .Byte4 => 1,
                .Half1, .Half3, .Half4 => 2,
                .Float1, .Float1Sparse, .Float2, .Float3, .Float4 => 4,
            };

            const num_channels: u32 = switch (image.*) {
                .Byte1, .Half1, .Float1, .Float1Sparse => 1,
                .Byte2, .Float2 => 2,
                .Byte3, .Half3, .Float3 => 3,
                .Byte4, .Half4, .Float4 => 4,
            };

            const bpp = bpc * num_channels;

            if (bpp == pixel_stride) {
                const desc = image.description();

                const buffer = switch (image.*) {
                    .Byte1 => |i| std.mem.sliceAsBytes(i.pixels),
                    .Byte2 => |i| std.mem.sliceAsBytes(i.pixels),
                    .Byte3 => |i| std.mem.sliceAsBytes(i.pixels),
                    .Byte4 => |i| std.mem.sliceAsBytes(i.pixels),
                    .Float1 => |i| std.mem.sliceAsBytes(i.pixels),
                    .Float2 => |i| std.mem.sliceAsBytes(i.pixels),
                    .Float3 => |i| std.mem.sliceAsBytes(i.pixels),
                    .Float4 => |i| std.mem.sliceAsBytes(i.pixels),
                    else => return -1,
                };

                @memcpy(buffer, data[0 .. desc.numPixels() * bpp]);
            }

            return 0;
        }
    }

    return -1;
}

export fn su_material_create(id: u32, string: [*:0]const u8) i32 {
    if (engine) |*e| {
        var parsed = std.json.parseFromSlice(std.json.Value, e.alloc, string[0..std.mem.len(string)], .{}) catch return -1;
        defer parsed.deinit();

        const material = e.resources.loadData(scn.Material, e.alloc, id, &parsed.value, .{}) catch return -1;

        return @intCast(material);
    }

    return -1;
}

export fn su_material_update(id: u32, string: [*:0]const u8) i32 {
    if (engine) |*e| {
        var parsed = std.json.parseFromSlice(std.json.Value, e.alloc, string[0..std.mem.len(string)], .{}) catch return -1;
        defer parsed.deinit();

        if (id >= e.scene.materials.items.len) {
            return -3;
        }

        const material = e.scene.material(id);

        e.resources.materials.provider.updateMaterial(
            e.alloc,
            material,
            parsed.value,
            &e.resources,
        ) catch return -4;

        return 0;
    }

    return -1;
}

export fn su_triangle_mesh_create(
    id: u32,
    num_parts: u32,
    parts: ?[*]const u32,
    num_triangles: u32,
    indices: ?[*]const u32,
    num_vertices: u32,
    positions: [*]const f32,
    positions_stride: u32,
    normals: [*]const f32,
    normals_stride: u32,
    tangents: ?[*]const f32,
    tangents_stride: u32,
    uvs: ?[*]const f32,
    uvs_stride: u32,
    asyncr: bool,
) i32 {
    if (engine) |*e| {
        const desc = resource.ShapeProvider.Descriptor{
            .num_parts = num_parts,
            .num_primitives = num_triangles,
            .num_vertices = num_vertices,
            .positions_stride = positions_stride,
            .normals_stride = normals_stride,
            .tangents_stride = tangents_stride,
            .uvs_stride = uvs_stride,
            .parts = parts,
            .indices = indices,
            .positions = positions,
            .normals = normals,
            .tangents = tangents,
            .uvs = uvs,
        };

        const mesh_id = e.resources.loadData(scn.Shape, e.alloc, id, &desc, .{}) catch return -1;

        if (!asyncr) {
            e.resources.commitAsync();
        }

        return @intCast(mesh_id);
    }

    return -1;
}

export fn su_prop_create(shape: u32, num_materials: u32, materials: [*]const u32) i32 {
    if (engine) |*e| {
        if (shape >= e.scene.shapes.items.len) {
            return -1;
        }

        const scene_mat_len = e.scene.materials.items.len;
        const num_expected_mats = e.scene.shape(shape).numMaterials();
        const fallback_mat = e.fallback_material;

        var matbuf = &e.materials;
        matbuf.ensureTotalCapacity(e.alloc, num_expected_mats) catch return -1;
        matbuf.clearRetainingCapacity();

        var i: u32 = 0;
        while (i < num_materials) : (i += 1) {
            const m = materials[i];
            matbuf.appendAssumeCapacity(if (m >= scene_mat_len) fallback_mat else m);
        }

        while (matbuf.items.len < num_expected_mats) {
            matbuf.appendAssumeCapacity(fallback_mat);
        }

        const prop = e.scene.createProp(e.alloc, shape, matbuf.items, false) catch return -1;

        return @as(i32, @intCast(prop));
    }

    return -1;
}

export fn su_prop_create_instance(entity: u32) i32 {
    if (engine) |*e| {
        if (entity >= e.scene.props.items.len) {
            return -1;
        }

        const prop = e.scene.createPropInstance(e.alloc, entity) catch return -1;

        return @as(i32, @intCast(prop));
    }

    return -1;
}

export fn su_light_create(prop: u32) i32 {
    if (engine) |*e| {
        if (prop >= e.scene.props.items.len) {
            return -1;
        }

        e.scene.createLight(e.alloc, prop) catch return -1;

        return 0;
    }

    return -1;
}

export fn su_prop_set_transformation(prop: u32, trafo: [*]const f32) i32 {
    if (engine) |*e| {
        if (prop >= e.scene.props.items.len) {
            return -1;
        }

        const m = Mat4x4.initArray(trafo[0..16].*);

        var r: Mat3x3 = undefined;
        var t: Transformation = undefined;
        m.decompose(&r, &t.scale, &t.position);

        t.rotation = math.quaternion.initFromMat3x3(r);

        e.scene.propSetWorldTransformation(prop, t);
        return 0;
    }

    return -1;
}

export fn su_prop_set_transformation_frame(prop: u32, frame: u32, trafo: [*]const f32) i32 {
    if (engine) |*e| {
        if (prop >= e.scene.props.items.len) {
            return -1;
        }

        if (frame >= e.scene.num_interpolation_frames) {
            return -1;
        }

        if (scn.Prop.Null == e.scene.prop_frames.items[prop]) {
            e.scene.propAllocateFrames(e.alloc, prop) catch return -1;
        }

        const m = Mat4x4.initArray(trafo[0..16].*);

        var r: Mat3x3 = undefined;
        var t: Transformation = undefined;
        m.decompose(&r, &t.scale, &t.position);

        t.rotation = math.quaternion.initFromMat3x3(r);

        e.scene.propSetFrame(prop, frame, t);
        return 0;
    }

    return -1;
}

export fn su_prop_set_visibility(prop: u32, in_camera: u32, in_reflection: u32) i32 {
    if (engine) |*e| {
        if (prop >= e.scene.props.items.len) {
            return -1;
        }

        e.scene.propSetVisibility(prop, in_camera > 0, in_reflection > 0, false);
        return 0;
    }

    return -1;
}

export fn su_render_frame(frame: u32) i32 {
    if (engine) |*e| {
        e.resources.commitAsync();

        e.take.view.configure();
        e.driver.configure(e.alloc, &e.take.view, &e.scene) catch {
            return -1;
        };

        e.frame = frame;

        e.driver.render(e.alloc, 0, frame, 0, 0) catch {
            return -1;
        };

        return 0;
    }

    return -1;
}

export fn su_export_frame() i32 {
    if (engine) |*e| {
        e.driver.exportFrame(e.alloc, 0, e.frame, e.take.exporters.items) catch {
            return -1;
        };

        return 0;
    }

    return -1;
}

export fn su_start_frame(frame: u32) i32 {
    if (engine) |*e| {
        e.resources.commitAsync();

        e.take.view.configure();
        e.driver.configure(e.alloc, &e.take.view, &e.scene) catch {
            return -1;
        };

        e.frame = frame;
        e.iteration = 0;
        e.driver.startFrame(e.alloc, 0, frame, true) catch {
            return -1;
        };

        return 0;
    }

    return -1;
}

export fn su_render_iterations(num_steps: u32) i32 {
    if (engine) |*e| {
        e.driver.renderIterations(e.iteration, num_steps);
        e.iteration += num_steps;

        return 0;
    }

    return -1;
}

export fn su_resolve_frame(aov: u32) i32 {
    if (engine) |*e| {
        if (aov >= core.tk.View.AovValue.NumClasses) {
            e.driver.resolve(0, 0);
            return 0;
        }

        return if (e.driver.resolveAov(0, @enumFromInt(aov))) 0 else -2;
    }

    return -1;
}

export fn su_resolve_frame_to_buffer(aov: u32, width: u32, height: u32, buffer: [*]f32) i32 {
    if (engine) |*e| {
        const num_pixels = @min(width * height, @as(u32, @intCast(e.driver.target.description.numPixels())));

        const target: [*]Pack4f = @ptrCast(buffer);

        if (aov >= core.tk.View.AovValue.NumClasses) {
            e.driver.resolveToBuffer(0, 0, target, num_pixels);
            return 0;
        }

        return if (e.driver.resolveAovToBuffer(0, @enumFromInt(aov), target, num_pixels)) 0 else -2;
    }

    return -1;
}

export fn su_copy_framebuffer(
    format: u32,
    num_channels: u32,
    width: u32,
    height: u32,
    destination: [*]u8,
) i32 {
    if (engine) |*e| {
        const bpc: u32 = if (0 == format) 1 else 4;

        var context = CopyFramebufferContext{
            .format = @enumFromInt(format),
            .num_channels = num_channels,
            .width = width,
            .destination = destination[0 .. bpc * num_channels * width * height],
            .source = e.driver.target,
        };

        const buffer = e.driver.target;
        const d = buffer.description.dimensions;
        const used_height = @min(height, @as(u32, @intCast(d[1])));

        _ = e.threads.runRange(&context, CopyFramebufferContext.copy, 0, used_height, 0);

        return 0;
    }

    return -1;
}

const CopyFramebufferContext = struct {
    format: Format,
    num_channels: u32,
    width: u32,
    destination: []u8,
    source: img.Float4,

    fn copy(context: Threads.Context, id: u32, begin: u32, end: u32) void {
        _ = id;

        const self = @as(*CopyFramebufferContext, @ptrCast(@alignCast(context)));

        const d = self.source.description.dimensions;

        const width = self.width;
        const used_width = @min(self.width, @as(u32, @intCast(d[0])));

        if (3 == self.num_channels) {
            const destination = self.destination;

            var y: u32 = begin;
            while (y < end) : (y += 1) {
                var o: u32 = y * width * 3;
                var x: u32 = 0;
                while (x < used_width) : (x += 1) {
                    const color = self.source.get2D(@intCast(x), @intCast(y));

                    destination[o + 0] = encoding.floatToUnorm8(spectrum.linearToGamma_sRGB(color.v[0]));
                    destination[o + 1] = encoding.floatToUnorm8(spectrum.linearToGamma_sRGB(color.v[1]));
                    destination[o + 2] = encoding.floatToUnorm8(spectrum.linearToGamma_sRGB(color.v[2]));

                    o += 3;
                }
            }
        } else if (4 == self.num_channels) {
            const destination = std.mem.bytesAsSlice(Pack4f, self.destination);

            var y: u32 = begin;
            while (y < end) : (y += 1) {
                var o: u32 = y * width;
                var x: u32 = 0;
                while (x < used_width) : (x += 1) {
                    const color = self.source.get2D(@intCast(x), @intCast(y));

                    destination[o] = color;

                    o += 1;
                }
            }
        }
    }
};

export fn su_register_log(post: log.CFunc.Func) i32 {
    log.log = log.Log{ .CFunc = .{ .func = post } };
    return 0;
}

export fn su_register_progress(start: prg.CFunc.Start, tick: prg.CFunc.Tick) i32 {
    if (engine) |*e| {
        e.driver.progressor = .{ .CFunc = .{ .start_func = start, .tick_func = tick } };
        return 0;
    }

    return -1;
}
