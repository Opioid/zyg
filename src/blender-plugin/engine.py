# <pep8 compliant>
from __future__ import annotations 

from ctypes import *
import platform
import numpy as np

import mathutils
import math

Transformation = c_float * 16

def init():
    import bpy
    import os.path

    global zyg
    
    print("engine.init()")
    path = os.path.dirname(__file__)

    if platform.system() == "Windows":
        zyg = CDLL(path + "/zyg.dll")
    else:
        zyg = CDLL(path + "/libzyg.so")

        
def exit():
    print("engine.exit()")
        
def release(engine):
    print("engine.release()")
    zyg.su_release()
    engine.session = None

def create(engine, data):
    print("engine.create()")
    if engine.session:
        return

    engine.session = 1
    zyg.su_init()

def reset(engine, data, depsgraph):
    if not engine.session:
        return
    print("engine.reset()")

    scene = depsgraph.scene
    scale = scene.render.resolution_percentage / 100.0
    size_x = int(scene.render.resolution_x * scale)
    size_y = int(scene.render.resolution_y * scale)

    zyg.su_create_sampler(16)
    
    camera = zyg.su_create_perspective_camera(size_x, size_y)

    integrators_desc = """{
    "surface": {
    "PTMIS": {}
    }
    }"""

    zyg.su_create_integrators(c_char_p(integrators_desc.encode('utf-8')))

    material_a_desc = """{
    "rendering": {
    "Substitute": {
        "color": [0.5, 0.5, 0.5],
        "roughness": 0.5,
        "metallic": 0
    }
    }
    }"""

    material_a = c_uint(zyg.su_create_material(c_char_p(material_a_desc.encode('utf-8'))));

    for object_instance in depsgraph.object_instances:
        # This is an object which is being instanced.
        obj = object_instance.object
        # `is_instance` denotes whether the object is coming from instances (as an opposite of
        # being an emitting object. )
        if not object_instance.is_instance:
            if obj.type == 'MESH':
                mesh = obj.to_mesh()

                mesh.calc_loop_triangles()

                #   mesh.calc_tangents()
                mesh.calc_normals_split()

                num_triangles = len(mesh.loop_triangles)

                num_loops = len(mesh.loops)

                Indices = c_uint32 * (num_triangles * 3)

                indices = Indices()

                i = 0
                for t in mesh.loop_triangles:
                    for l in t.loops:
                        indices[i] = l
                        i += 1

                Vectors = c_float * (num_loops * 3)

                positions = Vectors()
                normals = Vectors()

                i = 0
                for l in mesh.loops:
                    v = mesh.vertices[l.vertex_index]
                    positions[i * 3 + 0] = v.co[0]
                    positions[i * 3 + 1] = v.co[1]
                    positions[i * 3 + 2] = v.co[2]

                    normals[i * 3 + 0] = l.normal[0]
                    normals[i * 3 + 1] = l.normal[1]
                    normals[i * 3 + 2] = l.normal[2]
                    i += 1

                vertex_stride = 3

                zmesh = zyg.su_create_triangle_mesh(0, None,
                                                    num_triangles, indices,
                                                    num_loops,
                                                    positions, vertex_stride,
                                                    normals, vertex_stride,
                                                    None, 0,
                                                    None, 0)

                zmesh_instance = zyg.su_create_prop(zmesh, 1, byref(material_a))

                trafo = convert_matrix(object_instance.matrix_world)
                zyg.su_prop_set_transformation(zmesh_instance, trafo)

            if obj.type == 'LIGHT':
                material_pattern = """{{
                "rendering": {{
                "Light": {{
                "emission": [{}, {}, {}]
                }}}}}}"""

                light = obj.data
                if light.type == 'POINT':
                    radius = light.shadow_soft_size
                    area = 4.0 * math.pi * (radius * radius)
                    energy = light.energy / area

                    material_desc = material_pattern.format(energy * light.color[0],
                                                            energy * light.color[1],
                                                            energy * light.color[2])

                    material = c_uint(zyg.su_create_material(c_char_p(material_desc.encode('utf-8'))));

                    light_instance = zyg.su_create_prop(8, 1, byref(material))
                    zyg.su_create_light(light_instance)

                    trafo = convert_pointlight_matrix(object_instance.matrix_world, radius)
                    zyg.su_prop_set_transformation(light_instance, trafo)
                    zyg.su_prop_set_visibility(light_instance, 0, 1, 0)

                if light.type == 'SUN':
                    radius = light.angle / 2.0
                    solid_angle = (2.0 * math.pi) * (1.0 - (1.0 / math.sqrt(radius * radius + 1.0)))
                    energy = light.energy / solid_angle

                    material_desc = material_pattern.format(energy * light.color[0],
                                                            energy * light.color[1],
                                                            energy * light.color[2])

                    material = c_uint(zyg.su_create_material(c_char_p(material_desc.encode('utf-8'))));

                    light_instance = zyg.su_create_prop(4, 1, byref(material))
                    zyg.su_create_light(light_instance)

                    trafo = convert_dirlight_matrix(object_instance.matrix_world, radius)
                    zyg.su_prop_set_transformation(light_instance, trafo)
                    zyg.su_prop_set_visibility(light_instance, 0, 1, 0)

            if obj.type == 'CAMERA':
                zyg.su_camera_set_fov(c_float(obj.data.angle))
                trafo = convert_camera_matrix(object_instance.matrix_world)
                zyg.su_prop_set_transformation(camera, trafo)
        else:
            # Instanced will additionally have fields like uv, random_id and others which are
            # specific for instances. See Python API for DepsgraphObjectInstance for details,
            print(f"Instance of {obj.name} at {object_instance.matrix_world}")

    background = True
    if background:
        color = scene.world.color;

        material_desc = """{{
        "rendering": {{
        "Light": {{
        "emission": [{}, {}, {}]
        }}}}}}""".format(color[0], color[1], color[2])

        material = c_uint(zyg.su_create_material(c_char_p(material_desc.encode('utf-8'))));

        light_instance = zyg.su_create_prop(5, 1, byref(material))
        zyg.su_create_light(light_instance)

def render(engine, depsgraph):
    if not engine.session:
        return
    print("engine.render()")

    scene = depsgraph.scene
    scale = scene.render.resolution_percentage / 100.0
    size_x = int(scene.render.resolution_x * scale)
    size_y = int(scene.render.resolution_y * scale)

    buf = np.empty((size_x * size_y, 4), dtype=np.float32)

    zyg.su_render_frame(0)
    
    zyg.su_copy_framebuffer(4, 4, size_x, size_y, buf.ctypes.data_as(POINTER(c_uint8)))

    #zyg.su_export_frame(0)
    
    # Here we write the pixel values to the RenderResult
    result = engine.begin_result(0, 0, size_x, size_y)
    layer = result.layers[0].passes["Combined"]
    layer.rect = buf
    engine.end_result(result)

    
def render_frame_finish(engine):
    if not engine.session:
        return
    print("engine.render_frame_finish()")


def convert_matrix(m):
    return Transformation(m[0][0], m[1][0], m[2][0], 0.0,
                          m[0][1], m[1][1], m[2][1], 0.0,
                          m[0][2], m[1][2], m[2][2], 0.0,
                          m[0][3], m[1][3], m[2][3], 1.0)

def convert_pointlight_matrix(m, s):
    return Transformation(s, 0.0, 0.0, 0.0,
                          0.0, s, 0.0, 0.0,
                          0.0, 0.0, s, 0.0,
                          m[0][3], m[1][3], m[2][3], 1.0)

def convert_dirlight_matrix(m, s):
    return Transformation(s * m[0][0], s * m[1][0], s * m[2][0], 0.0,
                          -s * m[0][1], -s * m[1][1], -s * m[2][1], 0.0,
                          -s * m[0][2], -s * m[1][2], -s * m[2][2], 0.0,
                          m[0][3], m[1][3], m[2][3], 1.0)

def convert_camera_matrix(m):
    return Transformation(m[0][0], m[1][0], m[2][0], 0.0,
                          -m[0][1], -m[1][1], -m[2][1], 0.0,
                          -m[0][2], -m[1][2], -m[2][2], 0.0,
                          m[0][3], m[1][3], m[2][3], 1.0)
