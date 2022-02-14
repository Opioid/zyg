
# <pep8 compliant>
from __future__ import annotations

bl_info = {
    "name": "Zyg Render Engine",
    "author": "",
    "blender": (2, 80, 0),
    "description": "Zyg renderer integration",
    "warning": "",
    "doc_url": "https://docs.blender.org/manual/en/latest/render/cycles/",
    "tracker_url": "",
    "support": 'TESTING',
    "category": "Render"}

# Support 'reload' case.
if "bpy" in locals():
    import importlib
    if "engine" in locals():
        importlib.reload(engine)
    if "version_update" in locals():
        importlib.reload(version_update)
    if "ui" in locals():
        importlib.reload(ui)
    if "operators" in locals():
        importlib.reload(operators)
    if "properties" in locals():
        importlib.reload(properties)
    if "presets" in locals():
        importlib.reload(presets)

import bpy

from . import (
    engine,
    #version_update,
)


class ZygRender(bpy.types.RenderEngine):
    bl_idname = 'ZYG'
    bl_label = "Zyg"
    bl_use_eevee_viewport = True
    bl_use_preview = True
    #bl_use_exclude_layers = True
    bl_use_spherical_stereo = True
    bl_use_custom_freestyle = True
    bl_use_alembic_procedural = True

    def __init__(self):
        self.session = None

    def __del__(self):
        engine.release(self)

    # final render
    def update(self, data, depsgraph):
        print("update()")
        if not self.session:
            engine.create(self, data)

        engine.reset(self, data, depsgraph)

    def render(self, depsgraph):
        engine.render(self, depsgraph)

    def render_frame_finish(self):
        engine.render_frame_finish(self)

    def draw(self, context, depsgraph):
        print("draw()")
        #engine.draw(self, depsgraph, context.space_data)

    def bake(self, depsgraph, obj, pass_type, pass_filter, width, height):
        print("bake()")
        #engine.bake(self, depsgraph, obj, pass_type, pass_filter, width, height)

    # viewport render
    def view_update(self, context, depsgraph):
        print("view_update()")
        if not self.session:
            engine.create(self, data)

        engine.reset(self, data, depsgraph)
        # engine.sync(self, depsgraph, context.blend_data)

    def view_draw(self, context, depsgraph):
        print("view_draw()")
        #engine.view_draw(self, depsgraph, context.region, context.space_data, context.region_data)

    def update_script_node(self, node):
        print("update_script_node()")
        #self.report({'ERROR'}, "OSL support disabled in this build.")

    def update_render_passes(self, scene, srl):
        print("update_render_passes()")
        #engine.register_passes(self, scene, srl)


def engine_exit():
    print("engine_exit()")
    engine.exit()


classes = (
    ZygRender,
)


def register():
    from bpy.utils import register_class
    # from . import ui
    # from . import operators
    # from . import properties
    # from . import presets
    import atexit

    # Make sure we only registered the callback once.
    atexit.unregister(engine_exit)
    atexit.register(engine_exit)

    engine.init()

    # properties.register()
    # ui.register()
    # operators.register()
    # presets.register()

    for cls in classes:
        register_class(cls)

    #bpy.app.handlers.version_update.append(version_update.do_versions)


def unregister():
    from bpy.utils import unregister_class
    # from . import ui
    # from . import operators
    # from . import properties
    # from . import presets
    import atexit

    #bpy.app.handlers.version_update.remove(version_update.do_versions)

    # ui.unregister()
    # operators.unregister()
    # properties.unregister()
    # presets.unregister()

    for cls in classes:
        unregister_class(cls)
