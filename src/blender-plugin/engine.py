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

    material_a_desc = """{
    "rendering": {
    "Substitute": {
        "color": [0, 1, 0.5],
        "roughness": 0.2,
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

                    num_triangles = len(mesh.loop_triangles)

                    num_vertices = len(mesh.vertices)
 
                    Indices = c_uint32 * (num_triangles * 3)

                    indices = Indices()


                    Vectors = c_float * (num_vertices * 3)
                    
                    i = 0  
                    for t in mesh.loop_triangles:
                        for v in t.vertices:
                            indices[i] = v
                            i += 1
                    
                   
                    positions = Vectors()
                    normals = Vectors()

                    i = 0
                    for v in mesh.vertices:
                        positions[i * 3 + 0] = v.co[0]
                        positions[i * 3 + 1] = v.co[1]
                        positions[i * 3 + 2] = v.co[2]

                        normals[i * 3 + 0] = v.normal[0]
                        normals[i * 3 + 1] = v.normal[1]
                        normals[i * 3 + 2] = v.normal[2]
                        i += 1

                    vertices_stride = 3

                    zmesh = zyg.su_create_triangle_mesh(0, None,
                                       num_triangles, indices,
                                       num_vertices,
                                       positions, vertices_stride,
                                       normals, vertices_stride,
                                       None, 0, 
                                       None, 0)

                    zmesh_instance = zyg.su_create_prop(zmesh, 1, byref(material_a))

                    converted = convert_matrix(object_instance.matrix_world)
                    zyg.su_prop_set_transformation(zmesh_instance, converted)

                if obj.type == 'CAMERA':
                    zyg.su_camera_set_fov(c_float(obj.data.angle))
                    converted = convert_camera_matrix(object_instance.matrix_world)
                    zyg.su_prop_set_transformation(camera, converted)
            else:
                # Instanced will additionally have fields like uv, random_id and others which are
                # specific for instances. See Python API for DepsgraphObjectInstance for details,
                print(f"Instance of {obj.name} at {object_instance.matrix_world}")

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
    return Transformation(m[0][0], m[1][0], m[2][0], m[3][0],
                          m[0][1], m[1][1], m[2][1], m[3][1],
                          m[0][2], m[1][2], m[2][2], m[3][2],
                          m[0][3], m[1][3], m[2][3], m[3][3]) 

def convert_camera_matrix(m):
    return Transformation(m[0][0], m[1][0], m[2][0], m[3][0],
                          -m[0][1], -m[1][1], -m[2][1], m[3][1],
                          -m[0][2], -m[1][2], -m[2][2], m[3][2],
                          m[0][3], m[1][3], m[2][3], m[3][3]) 
