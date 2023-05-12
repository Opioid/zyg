from ctypes import *
import platform

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

class Progressor:
    def start(self, resolution):
        self.resolution = resolution
        self.progress = 0
        self.threshold = 1.0

    def tick(self):
        if self.progress >= self.resolution:
            pass

        self.progress += 1

        p = float(self.progress) / float(self.resolution) * 100.0

        if p >= self.threshold:
            self.threshold += 1.0
            print("{}%".format(int(p)), end = "\r")

progress = Progressor()

def py_progress_start(resolution):
    global progress
    progress.start(resolution)

def py_progress_tick():
    global progress
    progress.tick()
        
if platform.system() == "Windows":
    zyg = CDLL("./zyg.dll")
else:
    zyg = CDLL("./libzyg.so")

logfunc = LOG_FUNC(py_log_callback)

progstartfunc = PROGRESS_START_FUNC(py_progress_start)
progtickfunc = PROGRESS_TICK_FUNC(py_progress_tick)

zyg.su_register_log(logfunc)

zyg.su_init()

zyg.su_register_progress(progstartfunc, progtickfunc)

#print(zyg.su_mount(c_char_p(b"../../data/")))
zyg.su_mount(c_char_p(b"/home/beni/workspace/sprout/system/../data/"))

camera = zyg.su_perspective_camera_create(1280, 720)

exporter_desc = """{
"Image": {
"format": "PNG",
"_error_diffusion": true
}
}"""

zyg.su_exporters_create(c_char_p(exporter_desc.encode('utf-8')));

zyg.su_sampler_create(64)

integrators_desc = """{
"surface": {
"PTMIS": {}
}
}"""

zyg.su_integrators_create(c_char_p(integrators_desc.encode('utf-8')))

material_a_desc = """{
    "rendering": {
    "Substitute": {
        "color": [0, 1, 0.5],
        "roughness": 0.2,
        "metallic": 0
    }
    }
    }"""

material_a = c_uint(zyg.su_material_create(-1, c_char_p(material_a_desc.encode('utf-8'))));

Buffer = c_float * 12

image_buffer = Buffer(1.0, 0.0, 0.0,
                      0.0, 1.0, 0.0,
                      0.0, 0.0, 1.0,
                      1.0, 1.0, 0.0)

pixel_type = 4
num_channels = 3
width = 2
height = 2
depth = 1
stride = 12

image_a = zyg.su_image_create(-1, pixel_type, num_channels, width, height, depth,
                              stride, image_buffer)

material_b_desc = """{{
"rendering": {{
    "Substitute": {{
        "color": {{"usage": "Color", "id": {} }},
        "roughness": 0.5,
        "metallic": 0
    }}
}}
}}""".format(image_a)

material_b = c_uint(zyg.su_material_create(-1, c_char_p(material_b_desc.encode('utf-8'))));

material_light_desc = """{
"rendering": {
    "Light": {
        "emittance": {
           "spectrum": [10000, 10000, 10000]
         }
    }
}
}"""

material_light = c_uint(zyg.su_material_create(-1, c_char_p(material_light_desc.encode('utf-8'))));

sphere_a = zyg.su_prop_create(8, 1, byref(material_a))

plane_a = zyg.su_prop_create(6, 1, byref(material_b))

distant_sphere = zyg.su_prop_create(4, 1, byref(material_light))
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
                                       uvs, uvs_stride)

triangle_a = zyg.su_prop_create(triangle, 1, byref(material_a))

Transformation = c_float * 16

transformation = Transformation(1.0, 0.0, 0.0, 0.0,
                                0.0, 1.0, 0.0, 0.0,
                                0.0, 0.0, 1.0, 0.0,
                                -0.5, 1.0, 0.0, 1.0)

# zyg.su_prop_set_transformation(camera, transformation)

zyg.su_prop_set_transformation_frame(camera, 0, transformation)

transformation = Transformation(1.0, 0.0, 0.0, 0.0,
                                0.0, 1.0, 0.0, 0.0,
                                0.0, 0.0, 1.0, 0.0,
                                0.5, 1.0, 0.0, 1.0)

zyg.su_prop_set_transformation_frame(camera, 1, transformation)

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

zyg.su_render_frame(0)
zyg.su_export_frame(0)

image_buffer = Buffer(0.0, 1.0, 0.0,
                      1.0, 0.0, 0.0,
                      1.0, 1.0, 0.0,
                      0.0, 0.0, 1.0)

zyg.su_image_update(image_a, stride, image_buffer)

zyg.su_render_frame(1)
zyg.su_export_frame(1)

zyg.su_release()
