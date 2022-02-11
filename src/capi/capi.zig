const core = @import("core");
const log = core.log;
const img = core.image;
const rendering = core.rendering;
const resource = core.resource;
const scn = core.scn;
const tk = core.tk;
const Progressor = core.progress.Progressor;

const base = @import("base");
const math = base.math;
const Vec2i = math.Vec2i;
const Vec3i = math.Vec3i;
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

    resources: resource.Manager = undefined,
    scene_loader: scn.Loader = undefined,
    scene: scn.Scene = undefined,

    take: tk.Take = undefined,
    driver: rendering.Driver = undefined,

    frame: u32 = 0,
    iteration: u32 = 0,

    progress: Progressor = .{ .Null = {} },
};

var engine: ?Engine = null;

export fn su_init() i32 {
    if (engine) |_| {
        return -1;
    }

    const alloc = std.heap.c_allocator;

    engine = .{ .alloc = alloc };

    const num_workers = Threads.availableCores(0);
    engine.?.threads.configure(alloc, num_workers) catch {
        //_ = err;
        engine = null;
        return -1;
    };

    engine.?.resources = resource.Manager.init(alloc, &engine.?.threads) catch {
        engine = null;
        return -1;
    };

    const resources = &engine.?.resources;

    engine.?.scene_loader = scn.Loader.init(alloc, resources, scn.mat.Provider.createFallbackMaterial());

    engine.?.scene = scn.Scene.init(
        alloc,
        &resources.images.resources,
        &resources.materials.resources,
        &resources.shapes.resources,
        engine.?.scene_loader.null_shape,
    ) catch {
        engine = null;
        return -1;
    };

    engine.?.take = tk.Take.init(alloc) catch {
        engine = null;
        return -1;
    };

    engine.?.take.view.num_samples_per_pixel = 1;

    engine.?.driver = rendering.Driver.init(alloc, &engine.?.threads, engine.?.progress) catch {
        engine = null;
        return -1;
    };

    return 0;
}

export fn su_release() i32 {
    if (engine) |*e| {
        e.driver.deinit(e.alloc);
        e.take.deinit(e.alloc);
        e.scene.deinit(e.alloc);
        e.scene_loader.deinit(e.alloc);
        e.resources.deinit(e.alloc);
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

export fn su_load_take(string: [*:0]const u8) i32 {
    if (engine) |*e| {
        var stream = e.resources.fs.readStream(e.alloc, string[0..std.mem.len(string)]) catch {
            //  log.err("Open stream \"{s}\": {}", .{ string, err });
            return -1;
        };

        var take = tk.load(e.alloc, stream, &e.scene, &e.resources) catch {
            //    log.err("Loading take: {}", .{err});
            return -1;
        };

        e.scene_loader.load(e.alloc, take.scene_filename, take, &e.scene) catch {
            // log.err("Loading scene: {}", .{err});
            return -1;
        };

        e.take.deinit(e.alloc);
        e.take = take;

        return 0;
    }

    return -1;
}

export fn su_create_perspective_camera(width: u32, height: u32) i32 {
    if (engine) |*e| {
        const resolution = Vec2i{ @intCast(i32, width), @intCast(i32, height) };
        const crop = Vec4i{ 0, 0, resolution[0], resolution[1] };

        var camera = &e.take.view.camera;

        camera.setResolution(resolution, crop);
        camera.fov = math.degreesToRadians(80.0);

        if (scn.Prop.Null == camera.entity) {
            const prop_id = e.scene.createEntity(e.alloc) catch {
                return -1;
            };

            camera.entity = prop_id;
        }

        return @intCast(i32, camera.entity);
    }

    return -1;
}

export fn su_camera_sensor_dimensions(dimensions: [*]i32) i32 {
    if (engine) |*e| {
        const d = e.take.view.camera.sensorDimensions();
        dimensions[0] = d[0];
        dimensions[1] = d[1];
        return 0;
    }

    return -1;
}

export fn su_create_exporters(string: [*:0]const u8) i32 {
    if (engine) |*e| {
        var parser = std.json.Parser.init(e.alloc, false);
        defer parser.deinit();

        var document = parser.parse(string[0..std.mem.len(string)]) catch return -1;
        defer document.deinit();

        tk.loadExporters(e.alloc, document.root, &e.take) catch return -1;

        return 0;
    }

    return -1;
}

export fn su_create_sampler(num_samples: u32) i32 {
    if (engine) |*e| {
        e.take.view.num_samples_per_pixel = num_samples;
    }

    return -1;
}

export fn su_create_integrators(string: [*:0]const u8) i32 {
    if (engine) |*e| {
        var parser = std.json.Parser.init(e.alloc, false);
        defer parser.deinit();

        var document = parser.parse(string[0..std.mem.len(string)]) catch return -1;
        defer document.deinit();

        tk.loadIntegrators(document.root, &e.take.view);

        return 0;
    }

    return -1;
}

export fn su_create_image(format: u32, num_channels: u32, width: u32, height: u32, depth: u32, pixel_stride: u32, data: [*]u8) i32 {
    if (engine) |*e| {
        const ef = @intToEnum(Format, format);
        const bpc: u32 = switch (ef) {
            .UInt8 => 1,
            .UInt16, .Float16 => 2,
            .UInt32, .Float32 => 4,
        };

        const desc = img.Description.init3D(
            Vec3i.init3(@intCast(i32, width), @intCast(i32, height), @intCast(i32, depth)),
            Vec3i.init1(0),
        );

        var buffer = e.alloc.allocWithOptions(u8, bpc * num_channels * width * height * depth, 8, null) catch {
            return -1;
        };

        const bpp = bpc * num_channels;

        if (bpp == pixel_stride) {
            std.mem.copy(u8, buffer, data[0 .. desc.numPixels() * bpp]);
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
            const image_id = e.resources.images.store(e.alloc, i) catch {
                return -1;
            };
            return @intCast(i32, image_id);
        }

        e.alloc.free(buffer);

        return -1;
    }

    return -1;
}

export fn su_create_material(string: [*:0]const u8) i32 {
    if (engine) |*e| {
        var parser = std.json.Parser.init(e.alloc, false);
        defer parser.deinit();

        var document = parser.parse(string[0..std.mem.len(string)]) catch return -1;
        defer document.deinit();

        const data = @ptrToInt(&document.root);

        const material = e.resources.loadData(scn.Material, e.alloc, "", data, .{}) catch return -1;

        if (e.resources.get(scn.Material, material)) |mp| {
            mp.commit(e.alloc, e.scene, &e.threads) catch return -1;
        }

        return @intCast(i32, material);
    }

    return -1;
}

export fn su_create_prop(shape: u32, num_materials: u32, materials: [*]const u32) i32 {
    if (engine) |*e| {
        if (shape >= e.scene.shapes.items.len) {
            return -1;
        }

        const scene_mat_len = e.scene.materials.items.len;
        const num_expected_mats = e.scene.shape(shape).numMaterials();
        const fallback_mat = e.scene_loader.fallback_material;

        var matbuf = &e.scene_loader.materials;

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

        const prop = e.scene.createProp(e.alloc, shape, matbuf.items) catch return -1;

        return @intCast(i32, prop);
    }

    return -1;
}

export fn su_create_light(prop: u32) i32 {
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

export fn su_render_frame(frame: u32) i32 {
    if (engine) |*e| {
        e.threads.waitAsync();

        e.take.view.configure();
        e.driver.configure(e.alloc, &e.take.view, &e.scene) catch {
            return -1;
        };

        e.frame = frame;

        e.driver.render(e.alloc, frame) catch {
            return -1;
        };

        return 0;
    }

    return -1;
}

export fn su_export_frame() i32 {
    if (engine) |*e| {
        e.driver.exportFrame(e.alloc, e.frame, e.take.exporters.items) catch {
            return -1;
        };

        return 0;
    }

    return -1;
}

export fn su_start_frame(frame: u32) i32 {
    if (engine) |*e| {
        e.threads.waitAsync();

        e.take.view.configure();
        e.driver.configure(e.alloc, &e.take.view, &e.scene) catch {
            return -1;
        };

        e.frame = frame;
        e.iteration = 0;
        e.driver.startFrame(e.alloc, frame) catch {
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

export fn su_resolve_frame() i32 {
    if (engine) |*e| {
        e.driver.resolve();
        return 0;
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
    const bpc: u32 = if (0 == format) 1 else 4;

    if (engine) |*e| {
        var context = CopyFramebufferContext{
            .format = @intToEnum(Format, format),
            .num_channels = num_channels,
            .width = width,
            .destination = destination[0 .. bpc * num_channels * width * height],
            .source = e.driver.target,
        };

        const buffer = e.driver.target;
        const d = buffer.description.dimensions;
        const used_height = @minimum(height, @intCast(u32, d.v[1]));

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

        const self = @intToPtr(*CopyFramebufferContext, context);

        const d = self.source.description.dimensions;

        const width = self.width;
        const used_width = @minimum(self.width, @intCast(u32, d.v[0]));

        if (3 == self.num_channels) {
            var destination = self.destination;

            var y: u32 = begin;
            while (y < end) : (y += 1) {
                var o: u32 = y * width * 3;
                var x: u32 = 0;
                while (x < used_width) : (x += 1) {
                    const color = self.source.get2D(@intCast(i32, x), @intCast(i32, y));

                    destination[o + 0] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(color.v[0]));
                    destination[o + 1] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(color.v[1]));
                    destination[o + 2] = encoding.floatToUnorm(spectrum.linearToGamma_sRGB(color.v[2]));

                    o += 3;
                }
            }
        } else if (4 == self.num_channels) {
            var destination = std.mem.bytesAsSlice(Pack4f, self.destination);

            var y: u32 = begin;
            while (y < end) : (y += 1) {
                var o: u32 = y * width;
                var x: u32 = 0;
                while (x < used_width) : (x += 1) {
                    const color = self.source.get2D(@intCast(i32, x), @intCast(i32, y));

                    destination[o] = color;

                    o += 1;
                }
            }
        }
    }
};

export fn su_register_log(post: log.CFunc.Func) i32 {
    log.log = .{ .CFunc = .{ .func = post } };
    return 0;
}
