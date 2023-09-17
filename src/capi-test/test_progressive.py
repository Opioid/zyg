from ctypes import *
import platform

import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation

LOG_FUNC = CFUNCTYPE(None, c_uint, c_char_p)

PROGRESS_START_FUNC = CFUNCTYPE(None, c_uint)

PROGRESS_TICK_FUNC = CFUNCTYPE(None)

def py_log_callback(msg_type, msg):
    if 1 == msg_type:
        print("Warning: " + str(msg, "utf-8"))
    elif 2 == msg_type:
        print("Error: " + str(msg, "utf-8"))
    else:
        print(str(msg, "utf-8"))

def py_progress_tick():
    print("Tick: ")

        
if platform.system() == "Windows":
    zyg = CDLL("./zyg.dll")
else:
    zyg = CDLL("./libzyg.so")

logfunc = LOG_FUNC(py_log_callback)

zyg.su_register_log(logfunc)

zyg.su_init()

#print(zyg.su_mount(c_char_p(b"../../data/")))
zyg.su_mount(c_char_p(b"/home/beni/workspace/sprout/system/../data/"))

zyg.su_sampler_create(4096)

integrators_desc = """{
"surface": {
"PTMIS": {
"caustics": false
}
}
}"""

zyg.su_integrators_create(c_char_p(integrators_desc.encode('utf-8')))

Int2 = c_int32 * 2
resolution = Int2()
resolution[0] = 1280
resolution[1] = 720

camera = zyg.su_perspective_camera_create(resolution[0], resolution[1])

#print(zyg.su_render_frame(0))
#print(zyg.su_export_frame())

roughness = 0.2

material_a_desc = """{{
"rendering": {{
    "Substitute": {{
        "color": [0, 1, 0.5],
        "roughness": {},
        "metallic": 0
    }}
}}
}}""".format(roughness)

material_a = c_uint(zyg.su_material_create(-1, c_char_p(material_a_desc.encode('utf-8'))))

material_b_desc = """{
"rendering": {
    "Substitute": {
        "checkers": {
             "scale": 2,
             "colors": [[0.9, 0.9, 0.9], [0.1, 0.1, 0.1]]
        },
        "roughness": 0.5,
        "metallic": 0
    }
}
}"""

material_b = c_uint(zyg.su_material_create(-1, c_char_p(material_b_desc.encode('utf-8'))))

def updateRoughness():
    material_desc = """{{
        "roughness": {}
    }}""".format(roughness)
    
    zyg.su_material_update(material_a, c_char_p(material_desc.encode('utf-8')))

material_light_desc = """{
"rendering": {
    "Light": {
        "emittance": {
           "spectrum": [7000, 7000, 7000]
         }
    }
}
}"""

material_light = c_uint(zyg.su_material_create(-1, c_char_p(material_light_desc.encode('utf-8'))))

sphere_a = zyg.su_prop_create(7, 1, byref(material_a))

plane_a = zyg.su_prop_create(5, 1, byref(material_b))

distant_sphere = zyg.su_prop_create(3, 1, byref(material_light))
zyg.su_light_create(distant_sphere)

Vertices = c_float * 9

positions = Vertices(-1.0, -1.0, 0.0,
                      0.0,  1.0, 0.0,
                      1.0, -1.0, 0.0)

normals = Vertices(0.0, 0.0, -1.0,
                   0.0, 0.0, -1.0,
                   0.0, 0.0, -1.0)

Tangents = c_float * 12

tangents = Tangents(1.0, 0.0, 0.0, 1.0,
                    1.0, 0.0, 0.0, 1.0,
                    1.0, 0.0, 0.0, 1.0)

UVs = c_float * 6

uvs = UVs(0.0, 1.0,
          0.5, 0.0,
          1.0, 1.0)

Indices = c_uint * 3

indices = Indices(0, 1, 2)

Parts = c_uint * 3
parts = Parts(0, 3, 0)

num_triangles = 1
num_vertices = 3
num_parts = 1

vertices_stride = 3
tangents_stride = 4
uvs_stride = 2

triangle = zyg.su_triangle_mesh_create(-1, num_parts, parts,
                                       num_triangles, indices,
                                       num_vertices,
                                       positions, vertices_stride,
                                       normals, vertices_stride,
                                       tangents, tangents_stride, 
                                       uvs, uvs_stride, False)

triangle_a = zyg.su_prop_create(triangle, 1, byref(material_a))

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

transformation = Transformation(0.01, 0.0, 0.0, 0.0,
                                0.0, 0.0, 0.01, 0.0,
                                0.0, -0.01, 0.0, 0.0,
                                0.0, 0.0, 0.0, 1.0)

zyg.su_prop_set_transformation(distant_sphere, transformation)

transformation = Transformation(1.0, 0.0, 0.0, 0.0,
                                0.0, 1.0, 0.0, 0.0,
                                0.0, 0.0, 1.0, 0.0,
                                -2.0, 1.0, 5.0, 1.0)

zyg.su_prop_set_transformation_frame(triangle_a, 0, transformation)

transformation = Transformation(1.0, 0.0, 0.0, 0.0,
                                0.0, 1.0, 0.0, 0.0,
                                0.0, 0.0, 1.0, 0.0,
                                -2.0, 1.5, 5.0, 1.0)

zyg.su_prop_set_transformation_frame(triangle_a, 1, transformation)



Image = ((c_uint8 * 3) * resolution[0]) * resolution[1]

image = Image()

dpi = 100

fig = plt.figure("sprout", figsize=(resolution[0]/dpi, resolution[1]/dpi), dpi=dpi)
im = fig.figimage(image)

label = plt.figtext(0.0, 1.0, "0", color=(1.0, 1.0, 0.0), verticalalignment="top")

def restart():
    global frame_iteration
    global frame_next_display

    frame_iteration = 0
    frame_next_display = 1
    zyg.su_start_frame(0)
    #sprout.su_set_expected_iterations(1)

restart()

def update(frame_number):
    global frame_iteration
    global frame_next_display

    step = 1
    zyg.su_render_iterations(step)
    frame_iteration += step

  #  if frame_iteration >= frame_next_display:
    zyg.su_resolve_frame()
    zyg.su_copy_framebuffer(0, 3, resolution[0], resolution[1], image)

    im.set_data(image)

    label.set_text(str(frame_iteration))

    frame_next_display = frame_iteration + step

    #sprout.su_set_expected_iterations(frame_next_display - frame_iteration)



animation = FuncAnimation(fig, update, interval=1)


# zyg.su_render_iteration(frame_iteration)
# zyg.su_resolve_frame()
# zyg.su_copy_framebuffer(0, resolution[0], resolution[1], 3, image)

#m.set_data(image)

def press(event):
    global roughness
    # if "left" == event.key or "a" == event.key:
    #     transformation[12] -= 0.1
    #     sprout.su_entity_set_transformation(camera, transformation)
    #     restart()

    # if "right" == event.key or "d" == event.key:
    #     transformation[12] += 0.1
    #     sprout.su_entity_set_transformation(camera, transformation)
    #     restart()

    # if "up" == event.key or "w" == event.key:
    #     transformation[14] += 0.1
    #     sprout.su_entity_set_transformation(camera, transformation)
    #     restart()

    # if "down" == event.key or "s" == event.key:
    #     transformation[14] -= 0.1
    #     sprout.su_entity_set_transformation(camera, transformation)
    #     restart()

    if "o" == event.key:
        roughness = max(0.0, roughness - 0.1)
        updateRoughness()
        restart()

    if "p" == event.key:
        roughness = min(1.0, roughness + 0.1)
        updateRoughness()
        restart()
        
    if "r" == event.key:
        restart()

fig.canvas.mpl_connect('key_press_event', press)

plt.show()

zyg.su_release()
