from ctypes import *
import platform

if platform.system() == "Windows":
    zyg = CDLL("./zyg.dll")
else:
    zyg = CDLL("./libzyg.so")

#sprout.su_init(False) 

print(zyg.su_init())

print(zyg.su_add(4, 8))
