#!/usr/bin/env python3
"""Builds Abarax's model with bpy: the head of Quaternius's base character, the Fantasy Outfits
peasant and a hairstyle on one skeleton, plus a scarf with four bones of its own. The model has
palette slots in UV2 instead of textures, one material, and at most 4,000 triangles.

    tools/.venv/bin/python -I tools/anim/build_abarax.py --ubc <dir> --outfits <dir> --out <glb>

<dir> are the folders `python3 -I tools/assets/fetch.py path ubc|outfits` prints. They hold
downloaded data: this script only reads three .gltf files (with their .bin) and one PNG from them.
The same inputs always give the same bytes.

Palette slots are stored as UV2.x = (slot + 0.5) / 16 (UV2.y = 0.5). Vertex colours are dropped.

    slot  name   taken from
    0     skin   the head kept from the base body, and outfit faces using MI_Regular_Male
    1     hair   the hairstyle, and the base's `Face` mesh (MI_Hair_1: brows and stubble)
    2     eyes   the base's `Face.001` mesh (MI_Eyes)
    3     main   Male_Peasant_Body and Male_Peasant_Arms faces using MI_Peasant
    4     sec    Male_Peasant_Body faces whose T_Peasant_BaseColor luminance, sampled at the
                 face's UV centroid, is below SPLIT_LUMA
    5     pants  Male_Peasant_Legs
    6     boots  Male_Peasant_Feet
    7     rose   the scarf
    8     gold   reserved, unused in F0

Bones: the 65 joints the base, the outfit and the hairstyle share, plus scarf_01 to scarf_04
(scarf_01's parent is neck_01; each bone is 0.175 m long and they hang down the back).

Blender works Z up with this character facing -Y, so "back" below is +Y. The exporter writes
glTF's Y up, facing +Z.
"""
import argparse
import contextlib
import io
import logging
import math
import sys
from pathlib import Path

import bpy  # first: the bpy module is what makes bmesh and mathutils importable

import bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

# --- inputs (inside the extract folders) ---

BASE_GLTF = Path("Universal Base Characters[Standard]", "Base Characters", "Godot - UE", "Superhero_Male_FullBody.gltf")
HAIR_GLTF = Path("Universal Base Characters[Standard]", "Hairstyles", "Rigged to Head Bone", "glTF (Godot -Unreal)",
                 "Hair_SimpleParted.gltf")
OUTFIT_GLTF = Path("Modular Character Outfits - Fantasy[Standard]", "Exports", "glTF (Godot-Unreal)", "Outfits",
                   "Male_Peasant.gltf")
PEASANT_TEXTURE = "T_Peasant_BaseColor"  # the image the outfit import loads for MI_Peasant

# Objects as the importer names them (from the glTF nodes) -> (mesh data name the pack uses, our name).
BASE_PARTS = {
    "SuperHero_Male": ("Sphere.005_Retopology.004", "Abarax_Head"),
    "Eyebrows": ("Face", "Abarax_Brows"),
    "Eyes": ("Face.001", "Abarax_Eyes"),
}
HAIR_PARTS = {"Hair_SimpleParted": ("Plane.002", "Abarax_Hair")}
OUTFIT_PARTS = {name: (name, name) for name in
                ("Male_Peasant_Arms", "Male_Peasant_Body", "Male_Peasant_Feet", "Male_Peasant_Legs")}
SCARF_MESH = "Abarax_Scarf"
ARMATURE = "Armature"

# --- palette slots ---

SKIN, HAIR, EYES, MAIN, SEC, PANTS, BOOTS, ROSE, GOLD = range(9)
SLOT_COUNT = 9
PALETTE_SIZE = 16
SLOTS_UV = "slots"  # the second UV layer, exported as TEXCOORD_1 (Godot's UV2)
SKIN_MATERIAL = "MI_Regular_Male"
CLOTH_MATERIAL = "MI_Peasant"

# On Male_Peasant_Body, T_Peasant_BaseColor (Rec. 709 luma of the stored sRGB values, sampled at each
# face's UV centroid) has two clusters: the cream shirt at 0.50-0.55 (966 of 3,856 faces, plus about
# 200 highlights at 0.65-0.75) and the dark brown placket, belt, cuff trim and the shirt's inside at
# 0.05-0.25 (2,372 faces). Between them about 250 faces of mid-brown leather and shading thin out to
# a near-empty band at 0.40-0.50 (48 faces, never more than 19 per 0.025). 0.45 is the middle of
# that band: the shirt stays main (1,255 faces, 0.60 m²) and the dark trim and belt become sec
# (2,601 faces but only 0.31 m²: the trim is finely modelled, and 668 of them face the shirt's inside).
SPLIT_LUMA = 0.45

# --- triangles ---

TARGET_TRIANGLES = 3800  # the whole model; the budget is 1,500-4,000
MIN_TRIANGLES = 12  # per mesh

# --- the head ---

HEAD_BONES = ("Head", "neck_01")  # body faces whose vertices all lean most on these are kept

# --- the scarf ---

SCARF_BONES = ("scarf_01", "scarf_02", "scarf_03", "scarf_04")
SCARF_BONE_LENGTH = 0.175
RIBBON_LENGTH = SCARF_BONE_LENGTH * len(SCARF_BONES)  # 0.7 m
RIBBON_WIDTH = 0.12
RIBBON_THICKNESS = 0.012
RIBBON_ROWS_PER_BONE = 2  # cross-sections per bone, so each bone has a row to bend
LOOP_SEGMENTS = 8
# The loop's band wraps the neck just above the shirt collar (which tops out at 1.559 m) and covers
# the edge of the kept head, which is ragged between 1.54 and 1.58 m.
LOOP_BOTTOM, LOOP_TOP = 1.555, 1.60
LOOP_DEPTH = 0.025  # radial thickness of the band
CLEARANCE = 0.008  # gap kept between the scarf and the body
MAX_REACH = 0.15  # how far from the neck's axis a surface may be and still shape the loop
MAX_TILT = 60  # degrees a ribbon bone may lean back from hanging straight down to clear the body


class BuildError(Exception):
    pass


# --- scene helpers ---

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


@contextlib.contextmanager
def quiet_gltf():
    """The glTF add-on logs at the level bpy.app.debug_value picks; 3 keeps only critical messages,
    so its info lines stay out of the build's output. The old value is put back afterwards."""
    previous = bpy.app.debug_value
    bpy.app.debug_value = 3
    try:
        yield
    finally:
        bpy.app.debug_value = previous


class _DropMissingImages(logging.Filter):
    """The base .gltf names two normal maps (T_Hair_1_Normal_png.png, T_Eye_Normal_png.png) the pack
    does not ship. No image ends up in the model and the one we read is checked, so that error says
    nothing; everything else the importer reports still shows."""

    def filter(self, record):
        return not record.getMessage().startswith("Missing image file")


def import_gltf(path, parts):
    """Imports a .gltf; returns ({part name: object}, [armature objects]) for what it created."""
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


# --- step 2: keep only the head of the base body ---

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


# --- step 3: one armature ---

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


# --- step 4: the scarf ---

def surface_tree(objects):
    verts, polys = [], []
    for obj in objects:
        offset = len(verts)
        verts.extend(world_coords(obj))
        polys.extend([offset + i for i in p.vertices] for p in obj.data.polygons)
    return BVHTree.FromPolygons(verts, polys)


def farthest_hit(tree, origin, direction, reach):
    """The distance to the farthest surface along a ray from `origin`, within `reach`, or 0."""
    farthest, travelled, start = 0.0, 0.0, origin.copy()
    while travelled < reach:
        hit, _, _, distance = tree.ray_cast(start, direction, reach - travelled)
        if hit is None:
            break
        travelled += distance
        farthest = travelled
        travelled += 1e-4
        start = origin + direction * travelled
    return farthest


def back_surface(tree, x, z):
    """The y of the body's outermost back surface at (x, z), or None if nothing is there."""
    hit, _, _, _ = tree.ray_cast(Vector((x, 1.0, z)), Vector((0.0, -1.0, 0.0)), 2.0)
    return None if hit is None else hit.y


def neck_axis(armature):
    """A function z -> point on the line through neck_01's and Head's heads."""
    low = armature.data.bones["neck_01"].head_local
    high = armature.data.bones["Head"].head_local

    def at(z):
        t = (z - low.z) / (high.z - low.z)
        return Vector((0.0, low.y + t * (high.y - low.y), z))

    return at


def loop_sections(tree, axis):
    """Four corners (inner bottom, outer bottom, outer top, inner top) for each of the loop's
    segments, going round from the back. Each segment sits CLEARANCE outside the farthest surface
    of `tree` (the neck) within MAX_REACH of the axis, over the band's bottom, middle and top."""
    heights = (LOOP_BOTTOM, (LOOP_BOTTOM + LOOP_TOP) / 2, LOOP_TOP)
    sections = []
    for k in range(LOOP_SEGMENTS):
        angle = (k + 0.5) * 2 * math.pi / LOOP_SEGMENTS  # 0 is straight back (+Y); a face is centred there
        out = Vector((math.sin(angle), math.cos(angle), 0.0))
        reach = max(farthest_hit(tree, axis(z), out, MAX_REACH) for z in heights)
        if reach == 0.0:
            raise BuildError("found no neck to wrap the scarf round")
        inner = reach + CLEARANCE
        outer = inner + LOOP_DEPTH
        sections.append([axis(LOOP_BOTTOM) + out * inner, axis(LOOP_BOTTOM) + out * outer,
                         axis(LOOP_TOP) + out * outer, axis(LOOP_TOP) + out * inner])
    return sections


def clears(tree, top, direction):
    """True when a ribbon bone from `top` along `direction` stays CLEARANCE off the body."""
    for i in range(1, 9):
        point = top + direction * (SCARF_BONE_LENGTH * i / 8)
        for x in (-RIBBON_WIDTH / 2, 0.0, RIBBON_WIDTH / 2):
            body = back_surface(tree, x, point.z)
            if body is not None and point.y - RIBBON_THICKNESS / 2 - body < CLEARANCE:
                return False
    return True


def scarf_joints(tree, start):
    """The five joints of the scarf chain from `start`: each bone hangs straight down unless that
    would put the ribbon into the body, in which case it leans back just enough (1° steps)."""
    joints = [start]
    for _ in SCARF_BONES:
        for tilt in range(MAX_TILT + 1):
            a = math.radians(tilt)
            direction = Vector((0.0, math.sin(a), -math.cos(a)))
            if clears(tree, joints[-1], direction):
                break
        else:
            raise BuildError(f"the scarf cannot clear the body within {MAX_TILT}°")
        joints.append(joints[-1] + direction * SCARF_BONE_LENGTH)
    return joints


def ribbon_weights(s):
    """Weights of a ribbon cross-section `s` metres down the chain: linear between the centres of
    neighbouring scarf bones, all on the first bone above its centre and on the last below its centre."""
    centre = s / SCARF_BONE_LENGTH - 0.5
    if centre <= 0:
        return {SCARF_BONES[0]: 1.0}
    if centre >= len(SCARF_BONES) - 1:
        return {SCARF_BONES[-1]: 1.0}
    k = int(centre)
    t = centre - k
    weights = {SCARF_BONES[k]: 1.0 - t, SCARF_BONES[k + 1]: t}
    return {name: w for name, w in weights.items() if w > 0}


def add_scarf_bones(armature, joints):
    bpy.context.view_layer.objects.active = armature
    with active(armature):
        bpy.ops.object.mode_set(mode="EDIT")
        bones = armature.data.edit_bones
        parent = bones["neck_01"]
        for i, name in enumerate(SCARF_BONES):
            bone = bones.new(name)
            bone.head, bone.tail = joints[i], joints[i + 1]
            bone.roll = 0.0
            bone.parent = parent
            bone.use_connect = i > 0
            bone.use_deform = True
            parent = bone
        bpy.ops.object.mode_set(mode="OBJECT")


def build_scarf(armature, neck, back):
    """Adds the scarf bones and the scarf mesh (a neck loop of 8 segments shaped round the `neck`
    meshes, and a ribbon RIBBON_WIDTH wide and RIBBON_LENGTH long that clears the `back` meshes)
    and returns the mesh object."""
    sections = loop_sections(surface_tree(neck), neck_axis(armature))

    # The ribbon hangs from the middle of the loop's back face, its front against the loop.
    back_left, back_right = sections[-1], sections[0]
    middle = (back_left[1] + back_left[2] + back_right[1] + back_right[2]) / 4
    start = Vector((0.0, middle.y + RIBBON_THICKNESS / 2, middle.z))
    joints = scarf_joints(surface_tree(back), start)
    add_scarf_bones(armature, joints)

    verts, faces, weights, uvs = [], [], [], {}

    # neck loop: 8 sections of 4 corners, joined into a closed band; it moves with the neck
    for k, corners in enumerate(sections):
        for corner in corners:
            verts.append(corner)
            weights.append({"neck_01": 1.0})
    for k in range(LOOP_SEGMENTS):
        k1 = (k + 1) % LOOP_SEGMENTS
        for c in range(4):
            c1 = (c + 1) % 4
            face = (k * 4 + c, k1 * 4 + c, k1 * 4 + c1, k * 4 + c1)
            faces.append(face)
            uvs[len(faces) - 1] = [(k / LOOP_SEGMENTS, c / 4), ((k + 1) / LOOP_SEGMENTS, c / 4),
                                   ((k + 1) / LOOP_SEGMENTS, (c + 1) / 4), (k / LOOP_SEGMENTS, (c + 1) / 4)]

    # ribbon: a thin box with a cross-section every half bone
    across = Vector((1.0, 0.0, 0.0))
    downs = [(joints[i + 1] - joints[i]).normalized() for i in range(len(SCARF_BONES))]
    backs = [across.cross(d) for d in downs]  # +Y when hanging straight down
    rows = len(SCARF_BONES) * RIBBON_ROWS_PER_BONE
    first = len(verts)
    for r in range(rows + 1):
        s = RIBBON_LENGTH * r / rows
        bone = min(int(s / SCARF_BONE_LENGTH + 1e-9), len(SCARF_BONES) - 1)
        centre = joints[bone] + downs[bone] * (s - bone * SCARF_BONE_LENGTH)
        on_joint = abs(s - round(s / SCARF_BONE_LENGTH) * SCARF_BONE_LENGTH) < 1e-9
        if on_joint and 0 < bone and r < rows:
            back = (backs[bone - 1] + backs[bone]).normalized()
        else:
            back = backs[bone]
        w, t = across * (RIBBON_WIDTH / 2), back * (RIBBON_THICKNESS / 2)
        for corner in (-w - t, w - t, w + t, -w + t):  # front left, front right, back right, back left
            verts.append(centre + corner)
            weights.append(ribbon_weights(s))
    for r in range(rows):
        a, b = first + r * 4, first + (r + 1) * 4
        for c in range(4):
            c1 = (c + 1) % 4
            faces.append((a + c, a + c1, b + c1, b + c))
            uvs[len(faces) - 1] = [(c / 4, r / rows), ((c + 1) / 4, r / rows),
                                   ((c + 1) / 4, (r + 1) / rows), (c / 4, (r + 1) / rows)]
    last = first + rows * 4
    for cap in ((first, first + 3, first + 2, first + 1), (last, last + 1, last + 2, last + 3)):
        faces.append(cap)
        uvs[len(faces) - 1] = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]

    me = bpy.data.meshes.new(SCARF_MESH)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    uv = me.uv_layers.new(name="UVMap")
    for p in me.polygons:
        for corner, loop in enumerate(p.loop_indices):
            uv.data[loop].uv = uvs[p.index][corner]
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)  # both parts are closed, so outward is defined
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(SCARF_MESH, me)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = armature
    groups = {name: obj.vertex_groups.new(name=name) for name in ("neck_01",) + SCARF_BONES}
    for index, vertex_weights in enumerate(weights):
        for name, weight in vertex_weights.items():
            groups[name].add([index], weight, "REPLACE")
    obj.modifiers.new("Armature", "ARMATURE").object = armature
    return obj


# --- step 5: palette slots ---

def peasant_luma():
    """A function (u, v) -> Rec. 709 luma of T_Peasant_BaseColor's stored (sRGB) value there."""
    image = bpy.data.images.get(PEASANT_TEXTURE)
    if image is None or image.size[0] == 0:
        raise BuildError(f"{PEASANT_TEXTURE} did not load from the outfit pack")
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    luma = pixels.reshape(height, width, 4)[:, :, :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)

    def at(u, v):  # Blender UVs and image rows both start at the bottom
        return float(luma[int((v % 1.0) * height) % height, int((u % 1.0) * width) % width])

    return at


def face_slots(obj, part, luma):
    """The slot of each face of `obj`, by the table in this file's docstring."""
    me = obj.data
    materials = [m.name if m else "" for m in me.materials]
    uv = me.uv_layers[0].data
    slots = []
    for p in me.polygons:
        material = materials[p.material_index] if materials else ""
        if part == "Abarax_Head":
            slot = SKIN
        elif part in ("Abarax_Brows", "Abarax_Hair"):
            slot = HAIR
        elif part == "Abarax_Eyes":
            slot = EYES
        elif part == SCARF_MESH:
            slot = ROSE
        elif material == SKIN_MATERIAL:
            slot = SKIN
        elif part == "Male_Peasant_Legs":
            slot = PANTS
        elif part == "Male_Peasant_Feet":
            slot = BOOTS
        elif part == "Male_Peasant_Body" and material == CLOTH_MATERIAL:
            u = sum(uv[i].uv.x for i in p.loop_indices) / p.loop_total
            v = sum(uv[i].uv.y for i in p.loop_indices) / p.loop_total
            slot = SEC if luma(u, v) < SPLIT_LUMA else MAIN
        elif part in ("Male_Peasant_Body", "Male_Peasant_Arms") and material == CLOTH_MATERIAL:
            slot = MAIN
        else:
            raise BuildError(f"{part}: no slot for a face using '{material}'")
        slots.append(slot)
    return slots


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


def read_slots(obj):
    """Each face's slot from the slots layer: the slot most of its corners are nearest to (on a tie,
    the first corner's), so a face only ever gets a slot one of its corners had."""
    me = obj.data
    layer = me.uv_layers[SLOTS_UV].data
    slots = []
    for p in me.polygons:
        corners = [min(max(round(layer[i].uv.x * PALETTE_SIZE - 0.5), 0), SLOT_COUNT - 1) for i in p.loop_indices]
        slots.append(max(corners, key=corners.count))
    return slots


# --- step 6: triangles ---

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


def ratios(objects):
    """Each mesh's decimation ratio. The scarf is built at its final size and is not decimated:
    collapsing would first merge its flat ribbon rows, leaving the scarf bones nothing to bend. The
    other meshes share one ratio, (TARGET_TRIANGLES - scarf) / (total - scarf), but never go below
    MIN_TRIANGLES each."""
    fixed = sum(triangles(o) for o in objects if o.name == SCARF_MESH)
    rest = sum(triangles(o) for o in objects if o.name != SCARF_MESH)
    shared = (TARGET_TRIANGLES - fixed) / rest
    return {o.name: 1.0 if o.name == SCARF_MESH else min(1.0, max(shared, MIN_TRIANGLES / triangles(o)))
            for o in objects}


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


# --- step 7: one material, no images ---

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


# --- step 8: export ---

def export(path):
    """Writes the scene as a GLB. The exporter prints an "ERROR ... is not available" line for each
    optional compression library (Draco, MeshOptimizer) the bpy wheel lacks; neither is used here,
    so those lines are dropped and anything else it prints is passed on."""
    path.parent.mkdir(parents=True, exist_ok=True)
    printed = io.StringIO()
    with quiet_gltf(), contextlib.redirect_stdout(printed):
        result = _export(path)
    for line in printed.getvalue().splitlines():
        if line.strip() and "is not available because library could not be found" not in line:
            print(line)
    if result != {"FINISHED"} or not path.is_file():
        raise BuildError(f"could not export {path}")


def _export(path):
    return bpy.ops.export_scene.gltf(
        filepath=str(path), check_existing=False, export_format="GLB",
        export_yup=True, use_selection=False, export_apply=False,
        export_texcoords=True, export_normals=True, export_tangents=False,
        export_vertex_color="NONE", export_all_vertex_colors=False, export_attributes=False,
        export_materials="EXPORT", export_image_format="NONE",
        export_skins=True, export_influence_nb=4, export_all_influences=False, export_def_bones=False,
        export_rest_position_armature=True, export_leaf_bone=False,
        export_animations=False, export_morph=False,
        export_cameras=False, export_lights=False, export_extras=False)


# --- the build ---

def build(ubc, outfits, out):
    reset_scene()
    logging.getLogger("glTFImporter_errors").addFilter(_DropMissingImages())

    # 1. import
    base, base_armatures = import_gltf(Path(ubc) / BASE_GLTF, BASE_PARTS)
    outfit, outfit_armatures = import_gltf(Path(outfits) / OUTFIT_GLTF, OUTFIT_PARTS)
    hair, hair_armatures = import_gltf(Path(ubc) / HAIR_GLTF, HAIR_PARTS)
    parts = {}
    for found, table in ((base, BASE_PARTS), (outfit, OUTFIT_PARTS), (hair, HAIR_PARTS)):
        for name, obj in found.items():
            part = table[name][1]
            obj.name = obj.data.name = part
            parts[part] = obj
    luma = peasant_luma()

    # 2. keep only the base body's head
    keep_head(parts["Abarax_Head"])

    # 3. one armature. The outfit and the hairstyle are skinned to the same skeleton (the
    # base's 65 bone names, the regular-male proportions); the base's own armature differs from it
    # only in the arms and legs (2-3 cm wider), which the head does not use. So the outfit's
    # armature is the one kept: the head, neck and spine bones the head hangs on are identical.
    keep = outfit_armatures[0]
    head_chain = ("root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head")
    for other in base_armatures + hair_armatures:
        if not same_rest(keep, other, head_chain):
            raise BuildError(f"{other.name}'s spine, neck or head differs from the outfit's")
    if not same_rest(keep, hair_armatures[0], [b.name for b in keep.data.bones]):
        raise BuildError("the hairstyle's skeleton differs from the outfit's")
    adopt([parts[p] for p in sorted(parts)], keep)
    for other in base_armatures + hair_armatures:
        data = other.data
        bpy.data.objects.remove(other, do_unlink=True)
        bpy.data.armatures.remove(data)
    keep.name = keep.data.name = ARMATURE

    for part in sorted(parts):
        tidy_layers(parts[part])
        weld(parts[part])

    # 4. the scarf
    parts[SCARF_MESH] = build_scarf(
        keep, neck=[parts["Abarax_Head"]],
        back=[parts[p] for p in ("Abarax_Head", "Abarax_Hair", "Male_Peasant_Body", "Male_Peasant_Legs")])

    # 5. palette slots
    objects = [parts[p] for p in sorted(parts)]
    for obj in objects:
        write_slots(obj, face_slots(obj, obj.name, luma))

    # 6. triangulate, then decimate
    for obj in objects:
        triangulate(obj)
    shares = ratios(objects)
    for obj in objects:
        decimate(obj, shares[obj.name])
        write_slots(obj, read_slots(obj))  # collapsing interpolates corners; put each face back on its slot
        finish_mesh(obj)

    # 7. one material, no images
    one_material(objects)

    # 8. export
    export(Path(out))

    total = sum(triangles(o) for o in objects)
    print(f"build_abarax: {out}: {total} triangles, {len(keep.data.bones)} bones")
    for obj in objects:
        slots = sorted(set(read_slots(obj)))
        print(f"  {obj.name}: {triangles(obj)} triangles (ratio {shares[obj.name]:.3f}), slots {slots}")


def main(argv=None):
    if argv is None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(prog="build_abarax.py", description=__doc__.split("\n\n")[0])
    parser.add_argument("--ubc", required=True, help="the ubc pack's extract folder (fetch.py path ubc)")
    parser.add_argument("--outfits", required=True, help="the outfits pack's extract folder (fetch.py path outfits)")
    parser.add_argument("--out", required=True, help="the .glb to write")
    args = parser.parse_args(argv)
    try:
        build(args.ubc, args.outfits, args.out)
    except BuildError as error:
        print(f"build_abarax.py: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
