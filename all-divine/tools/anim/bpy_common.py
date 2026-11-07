"""The bpy helpers the scripts of tools/anim share: build_abarax.py and retarget.py. A scene reset, quiet
glTF logging, and the one place that says how a model leaves Blender as a GLB, so a model built by one and
round-tripped by the other cannot drift apart.

    reset_scene()                     an empty scene
    quiet_gltf()                      a context manager: the glTF add-on logs only critical messages inside it
    export_glb(path, error, animations=False)
                                      writes the scene as a GLB; raises `error` (an exception class) if that fails

Scripts run with `python -I`, which leaves their own folder off sys.path, so they add it before importing this:

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from bpy_common import ...
"""
import contextlib
import io

import bpy


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


@contextlib.contextmanager
def quiet_gltf():
    """The glTF add-on logs at the level bpy.app.debug_value picks; 3 keeps only critical messages,
    so its info lines stay out of a script's output. The old value is put back afterwards."""
    previous = bpy.app.debug_value
    bpy.app.debug_value = 3
    try:
        yield
    finally:
        bpy.app.debug_value = previous


def export_glb(path, error, animations=False):
    """Writes the scene as a GLB. With `animations`, the scene's one action is baked into it at every frame
    (the caller makes sure it is the only action: the export writes them all); without, none is written.
    The exporter prints an "ERROR ... is not available" line for each optional compression library (Draco,
    MeshOptimizer) the bpy wheel lacks; neither is used here, so those lines are dropped and anything else it
    prints is passed on. Raises `error` if the export does not produce the file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    printed = io.StringIO()
    with quiet_gltf(), contextlib.redirect_stdout(printed):
        result = _export(path, animations)
    for line in printed.getvalue().splitlines():
        if line.strip() and "is not available because library could not be found" not in line:
            print(line)
    if result != {"FINISHED"} or not path.is_file():
        raise error(f"could not export {path}")


def _export(path, animations):
    animation_settings = (
        dict(export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
             export_frame_range=False, export_frame_step=1, export_optimize_animation_size=False,
             export_anim_slide_to_zero=False)
        if animations else dict(export_animations=False))
    return bpy.ops.export_scene.gltf(
        filepath=str(path), check_existing=False, export_format="GLB",
        export_yup=True, use_selection=False, export_apply=False,
        export_texcoords=True, export_normals=True, export_tangents=False,
        export_vertex_color="NONE", export_all_vertex_colors=False, export_attributes=False,
        export_materials="EXPORT", export_image_format="NONE",
        export_skins=True, export_influence_nb=4, export_all_influences=False, export_def_bones=False,
        export_rest_position_armature=True, export_leaf_bone=False,
        export_morph=False, export_cameras=False, export_lights=False, export_extras=False,
        **animation_settings)
