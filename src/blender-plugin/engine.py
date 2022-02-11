# <pep8 compliant>
from __future__ import annotations 

from ctypes import *
import platform
import numpy as np

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

def render(engine, depsgraph):
    if not engine.session:
        return
    print("engine.render()")

    scene = depsgraph.scene
    scale = scene.render.resolution_percentage / 100.0
    size_x = int(scene.render.resolution_x * scale)
    size_y = int(scene.render.resolution_y * scale)

    # Fill the render result with a flat color. The framebuffer is
    # defined as a list of pixels, each pixel itself being a list of
    # R,G,B,A values.
    # if engine.is_preview:
    #     color = [c_float(0.1), c_float(0.2), c_float(0.1), c_float(1.0)]
    # else:
    #     color = [c_float(0.2), c_float(0.1), c_float(0.1), c_float(1.0)]

    # pixel_count = size_x * size_y
    # rect = [color] * pixel_count


    # print(zyg.su_mount(c_char_p(b"/home/beni/workspace/sprout/system/../data/")))
    # print(zyg.su_load_take(c_char_p(b"takes/cornell.take")))

    
    buf = np.empty((size_x * size_y, 4), dtype=np.float32)

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

    sphere_a = zyg.su_create_prop(8, 1, byref(material_a))

    plane_a = zyg.su_create_prop(6, 1, byref(material_a))


    Transformation = c_float * 16

    transformation = Transformation(1.0, 0.0, 0.0, 0.0,
                                    0.0, 1.0, 0.0, 0.0,
                                    0.0, 0.0, 1.0, 0.0,
                                    0.0, 1.0, 0.0, 1.0)

    zyg.su_prop_set_transformation(camera, transformation)

    transformation = Transformation(1.0, 0.0, 0.0, 0.0,
                                    0.0, 1.0, 0.0, 0.0,
                                    0.0, 0.0, 1.0, 0.0,
                                    0.0, 1.0, 5.0, 1.0)

    zyg.su_prop_set_transformation(sphere_a, transformation)

    transformation = Transformation(1.0, 0.0, 0.0, 0.0,
                                    0.0, 0.0, -1.0, 0.0,
                                    0.0, 1.0, 0.0, 0.0,
                                    0.0, 0.0, 0.0, 1.0)

    zyg.su_prop_set_transformation(plane_a, transformation)
    
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
