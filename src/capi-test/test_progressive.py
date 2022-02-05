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

print(zyg.su_register_log(logfunc))

print(zyg.su_init())

#print(zyg.su_mount(c_char_p(b"../../data/")))
print(zyg.su_mount(c_char_p(b"/home/beni/workspace/sprout/system/../data/")))

print(zyg.su_load_take(c_char_p(b"takes/cornell.take")))

Int2 = c_int32 * 2
resolution = Int2()

zyg.su_camera_sensor_dimensions(resolution)

#print(zyg.su_render_frame(0))
#print(zyg.su_export_frame())


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
    zyg.su_copy_framebuffer(0, resolution[0], resolution[1], 3, image)

    im.set_data(image)

    label.set_text(str(frame_iteration))

    frame_next_display = frame_iteration + step

    #sprout.su_set_expected_iterations(frame_next_display - frame_iteration)



animation = FuncAnimation(fig, update, interval=1)


# zyg.su_render_iteration(frame_iteration)
# zyg.su_resolve_frame()
# zyg.su_copy_framebuffer(0, resolution[0], resolution[1], 3, image)

#m.set_data(image)


plt.show()

print(zyg.su_release())
