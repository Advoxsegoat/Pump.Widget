"""The bpy helpers the scripts of tools/anim share: build_abarax.py, build_knuckle.py and retarget.py. A scene reset,
quiet glTF logging, the one place that says how a model leaves Blender as a GLB (so a model built by one and
round-tripped by another cannot drift apart), and the build steps the two character models share: importing the
Quaternius parts onto one skeleton, keeping a head, palette slots in UV2, triangulating and decimating, and one
material.

    reset_scene()                     an empty scene
    quiet_gltf()                      a context manager: the glTF add-on logs only critical messages inside it
    export_glb(path, error, animations=False)
                                      writes the scene as a GLB; raises `error` (an exception class) if that fails
    BuildError                        what the build steps raise for bad input

    import_gltf, active, world_coords, triangles, strongest_bones, keep_head, weld, tidy_layers, adopt, same_rest,
    slot_u, write_slots, read_slots, triangulate, decimate, finish_mesh, one_material
                                      the build steps (see each)

Scripts run with `python -I`, which leaves their own folder off sys.path, so they add it before importing this:

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from bpy_common import ...
"""
import contextlib
import io
import logging

import bpy  # first: the bpy module is what makes bmesh importable

import bmesh
import numpy as np

# --- palette slots ---

PALETTE_SIZE = 16
SLOTS_UV = "slots"  # the second UV layer, exported as TEXCOORD_1 (Godot's UV2)

# --- the head ---

HEAD_BONES = ("Head", "neck_01")  # body faces whose vertices all lean most on these are kept


class BuildError(Exception):
    pass


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


# --- scene helpers ---

class DropMissingImages(logging.Filter):
    """The base .gltf names two normal maps (T_Hair_1_Normal_png.png, T_Eye_Normal_png.png) the pack
    does not ship. No image ends up in the model and the one we read is checked, so that error says
    nothing; everything else the importer reports still shows. A build adds it to the logger
    "glTFImporter_errors" once."""

    def filter(self, record):
        return not record.getMessage().startswith("Missing image file")


def import_gltf(path, parts):
    """Imports a .gltf; returns ({part name: object}, [armature objects]) for what it created. `parts` maps
    each object the build needs, as the importer names it (from the glTF nodes), to (the mesh data name the
    pack uses, our name)."""
    if not path.is_file():
        raise BuildError(f"missing {path}")
    before = set(bpy.data.objects)
    with quiet_gltf():
        result = bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic="BLENDER", disable_bone_shape=True,
                                           merge_vertices=False, import_shading="NORMALS")
    if result != {"FINISHED"}:
        raise BuildError(f"could not import {path}")
    created = sorted((o for o in bpy.data.objects if o not in before), key=lambda o: o.name)
    armatures = [o for o in created if o.type == "ARMATURE"]
    found = {}
    for name, (mesh_name, _) in parts.items():
        obj = next((o for o in created if o.name == name), None)
        if obj is None or obj.type != "MESH" or obj.data.name != mesh_name:
            raise BuildError(f"{path.name}: expected a mesh object {name} (mesh {mesh_name})")
        found[name] = obj
    if len(armatures) != 1:
        raise BuildError(f"{path.name}: expected one armature, found {len(armatures)}")
    return found, armatures


def active(obj):
    """A context override that makes `obj` the active, only selected object."""
    return bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj],
                                     selected_editable_objects=[obj])


def world_coords(obj):
    m = obj.matrix_world
    return [m @ v.co for v in obj.data.vertices]


def triangles(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


# --- keep only the head of the base body ---

def strongest_bones(obj):
    """For each vertex, the name of the bone (vertex group) with the largest weight, or None."""
    names = {g.index: g.name for g in obj.vertex_groups}
    found = []
    for v in obj.data.vertices:
        best = None
        for g in v.groups:  # ties keep the first group, so the result is stable
            if best is None or g.weight > best.weight:
                best = g
        found.append(names[best.group] if best is not None else None)
    return found


def keep_head(obj):
    """Deletes the body faces that have a vertex whose strongest bone is not Head or neck_01."""
    strongest = strongest_bones(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    doomed = [f for f in bm.faces if any(strongest[v.index] not in HEAD_BONES for v in f.verts)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    if not obj.data.polygons:
        raise BuildError("no head faces were left")


def weld(obj):
    """glTF stores a vertex once per UV or normal seam; weld the copies so decimation cannot open
    cracks along seams. The seams themselves live on in the per-corner UVs."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()


def tidy_layers(obj):
    """Keeps the first UV layer (as UVMap) and drops the others and every colour attribute."""
    me = obj.data
    while len(me.uv_layers) > 1:
        me.uv_layers.remove(me.uv_layers[-1])
    if me.uv_layers:
        me.uv_layers[0].name = "UVMap"
    else:
        me.uv_layers.new(name="UVMap")
    for colour in list(me.color_attributes):
        me.color_attributes.remove(colour)


# --- one armature ---

def adopt(objects, armature):
    """Binds each mesh to `armature` (its vertex groups already carry the bone names)."""
    for obj in objects:
        world = obj.matrix_world.copy()
        obj.parent = armature
        obj.matrix_world = world
        mods = [m for m in obj.modifiers if m.type == "ARMATURE"]
        if len(mods) != 1:
            raise BuildError(f"{obj.name}: expected one armature modifier, found {len(mods)}")
        mods[0].object = armature


def same_rest(a, b, bones, tolerance=1e-4):
    """True when armatures `a` and `b` place each of `bones` alike in their rest poses."""
    for name in bones:
        rest_a, rest_b = a.data.bones[name].matrix_local, b.data.bones[name].matrix_local
        if max(abs(x - y) for row_a, row_b in zip(rest_a, rest_b) for x, y in zip(row_a, row_b)) > tolerance:
            return False
    return True


# --- palette slots ---

def slot_u(slot):
    return (slot + 0.5) / PALETTE_SIZE


def write_slots(obj, slots):
    """Stores one slot per face in the slots UV layer (every corner of a face gets its slot)."""
    me = obj.data
    layer = me.uv_layers.get(SLOTS_UV) or me.uv_layers.new(name=SLOTS_UV)
    per_corner = np.empty(len(me.loops) * 2, dtype=np.float32)
    for p, slot in zip(me.polygons, slots):
        per_corner[p.loop_start * 2:(p.loop_start + p.loop_total) * 2] = (slot_u(slot), 0.5) * p.loop_total
    layer.data.foreach_set("uv", per_corner)


def read_slots(obj, slot_count):
    """Each face's slot from the slots layer: the slot most of its corners are nearest to (on a tie,
    the first corner's), so a face only ever gets a slot one of its corners had. Slots run 0 to slot_count - 1."""
    me = obj.data
    layer = me.uv_layers[SLOTS_UV].data
    slots = []
    for p in me.polygons:
        corners = [min(max(round(layer[i].uv.x * PALETTE_SIZE - 0.5), 0), slot_count - 1) for i in p.loop_indices]
        slots.append(max(corners, key=corners.count))
    return slots


# --- triangles ---

def triangulate(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()


def decimate(obj, ratio):
    """Collapse-decimates `obj` to about `ratio` of its triangles, ahead of its armature modifier."""
    if ratio >= 1.0:
        return
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    with active(obj):
        bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
        bpy.ops.object.modifier_apply(modifier=mod.name)


def finish_mesh(obj):
    """Smooth shading from the decimated geometry, and at most four normalized bone weights per vertex."""
    me = obj.data
    if "custom_normal" in me.attributes:
        me.attributes.remove(me.attributes["custom_normal"])
    me.shade_smooth()
    with active(obj):
        bpy.ops.object.vertex_group_clean(group_select_mode="ALL", limit=1e-4)
        bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
        bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    unweighted = [v.index for v in me.vertices if not any(g.weight > 1e-4 for g in v.groups)]
    if unweighted:
        raise BuildError(f"{obj.name}: {len(unweighted)} vertices have no bone weight")


# --- one material, no images ---

def one_material(objects):
    toon = bpy.data.materials.new("toon")
    for obj in objects:
        me = obj.data
        me.materials.clear()
        me.materials.append(toon)
        me.polygons.foreach_set("material_index", [0] * len(me.polygons))
    for material in list(bpy.data.materials):
        if material != toon:
            bpy.data.materials.remove(material)
    for image in list(bpy.data.images):
        bpy.data.images.remove(image)
