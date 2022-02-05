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

if platform.system() == "Windows":
    zyg = CDLL("./zyg.dll")
else:
    zyg = CDLL("./libzyg.so")

#sprout.su_init(False) 

logfunc = LOG_FUNC(py_log_callback)

#print(zyg.su_register_log(logfunc))

print(zyg.su_init())

#print(zyg.su_mount(c_char_p(b"../../data/")))
print(zyg.su_mount(c_char_p(b"/home/beni/workspace/sprout/system/../data/")))

print(zyg.su_load_take(c_char_p(b"takes/cornell.take")))

print(zyg.su_render_frame(0))
print(zyg.su_export_frame(0))

print(zyg.su_release())
