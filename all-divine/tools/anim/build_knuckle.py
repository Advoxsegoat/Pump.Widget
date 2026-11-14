#!/usr/bin/env python3
"""Builds the Knuckle of the Hand's model with bpy: the head of Quaternius's base character (Abarax's base, so the
skeleton and its rest pose are his), a buzzed hairstyle and a beard, and the Fantasy Outfits ranger with its hood
and pauldron, on one skeleton of 65 bones (no scarf). The model has palette slots in UV2 instead of textures, one
material, and at most 4,000 triangles with every part in it: a tier hides the parts it goes without in the game
(ActorDef.hidden_parts), never in the file.

    tools/.venv/bin/python -I tools/anim/build_knuckle.py --ubc <dir> --outfits <dir> --out <glb>

<dir> are the folders `python3 -I tools/assets/fetch.py path ubc|outfits` prints. They hold downloaded data: this
script only reads four .gltf files (with their .bin) and one PNG from them. The same inputs always give the same
bytes. The build steps it shares with build_abarax.py are in bpy_common.py.

The meshes, and what each is made of:

    Knuckle_Head      the head kept from the base body, its brows (`Face`) and its eyes (`Face.001`)
    Knuckle_Hair      Hair_Buzzed
    Knuckle_Beard     Hair_Beard
    Knuckle_Body      Male_Ranger_Body and its two belts
    Knuckle_Legs      Male_Ranger_Legs
    Knuckle_Arms      Male_Ranger_Arms (the outfit's bracers are left out)
    Knuckle_Boots     Male_Ranger_Feet_Boots
    Knuckle_Hood      Male_Ranger_Head_Hood
    Knuckle_Pauldron  Male_Ranger_Acc_Pauldron
    Knuckle_Blade     a sword made here (make_blade), not taken from a pack: a straight single-edged blade 0.75 m from
                      its guard to its tip and 10.5 cm broad, with the guard, grip and pommel, in the right hand. It is skinned to hand_r
                      alone, so it follows every clip as the hand does, and only the blade Knuckle shows it.

Palette slots are stored as UV2.x = (slot + 0.5) / 16 (UV2.y = 0.5), as Abarax's are. Vertex colours are dropped.
A ranger face is sorted by the colour of T_Ranger_BaseColor at its UV centroid (the stored sRGB value, in HSV):
"metal" below METAL_SATURATION (the steel buckles and plates, grey at saturation about 0.1), else "cloth" at a hue
of CLOTH_HUE degrees or more (the greens, 60-180 degrees at saturation 0.5-0.8), else "leather" (the browns, 0-50
degrees). Then:

    slot  name   taken from
    0     skin   the head kept from the base body, and outfit faces using MI_Regular_Male (the hands)
    1     hair   the hairstyle, the beard and the brows
    2     eyes   the eyes
    3     main   the cloth of the body and the arms
    4     sec    the leather of the body, the arms and the legs, and all but the metal of the hood and the pauldron
    5     pants  the cloth of the legs
    6     boots  the boots but their metal
    7     hood   the cloth of the hood
    8     metal  the metal of every ranger part, and the sword's guard and pommel
    9     steel  the sword's blade (the other palettes leave it unused: they hide the blade); the grip is `sec`

Blender works Z up with this character facing -Y. The exporter writes glTF's Y up, facing +Z.
"""
import argparse
import colorsys
import logging
import sys
from pathlib import Path

import bpy  # first: the bpy module is what makes bmesh importable

import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))  # python -I leaves this folder off sys.path
from bpy_common import (  # noqa: E402
    BuildError, DropMissingImages, adopt, decimate, export_glb, finish_mesh, import_gltf, keep_head, one_material,
    read_slots, reset_scene, same_rest, tidy_layers, triangles, triangulate, weld, write_slots)

# --- inputs (inside the extract folders) ---

BASE_GLTF = Path("Universal Base Characters[Standard]", "Base Characters", "Godot - UE", "Superhero_Male_FullBody.gltf")
HAIR_DIR = Path("Universal Base Characters[Standard]", "Hairstyles", "Rigged to Head Bone", "glTF (Godot -Unreal)")
OUTFIT_GLTF = Path("Modular Character Outfits - Fantasy[Standard]", "Exports", "glTF (Godot-Unreal)", "Outfits",
                   "Male_Ranger.gltf")
RANGER_TEXTURE = "T_Ranger_BaseColor"  # the image the outfit import loads for MI_Ranger

# Objects as the importer names them (from the glTF nodes) -> (mesh data name the pack uses, the part it goes into).
BASE_PARTS = {
    "SuperHero_Male": ("Sphere.005_Retopology.004", "Knuckle_Head"),
    "Eyebrows": ("Face", "Knuckle_Head"),
    "Eyes": ("Face.001", "Knuckle_Head"),
}
HAIR_PARTS = {
    "Hair_Buzzed": {"Hair_Buzzed": ("Cylinder.002", "Knuckle_Hair")},
    "Hair_Beard": {"Hair_Beard": ("Plane.006", "Knuckle_Beard")},
}
OUTFIT_PARTS = {
    "Male_Ranger_Body": ("Male_Ranger_Body", "Knuckle_Body"),
    "Male_Ranger_Body_Belt_1": ("Male_Ranger_Body_Belt_1", "Knuckle_Body"),
    "Male_Ranger_Body_Belt_2": ("Male_Ranger_Body_Belt_1.001", "Knuckle_Body"),
    "Male_Ranger_Legs": ("Male_Ranger_Legs", "Knuckle_Legs"),
    "Male_Ranger_Arms": ("Male_Ranger_Arms", "Knuckle_Arms"),
    "Male_Ranger_Feet_Boots": ("Male_Ranger_Feet_Boots", "Knuckle_Boots"),
    "Male_Ranger_Head_Hood": ("Male_Ranger_Head_Hood", "Knuckle_Hood"),
    "Male_Ranger_Acc_Pauldron": ("Male_Ranger_Acc_Pauldron", "Knuckle_Pauldron"),
}
LEFT_OUT = ("Male_Ranger_Arms_Bracer",)  # in the outfit, not in the Knuckle
ARMATURE = "Armature"

# --- palette slots ---

SKIN, HAIR, EYES, MAIN, SEC, PANTS, BOOTS, HOOD, METAL, STEEL = range(10)
SLOT_COUNT = 10
SKIN_MATERIAL = "MI_Regular_Male"
CLOTH_MATERIAL = "MI_Ranger"
# On T_Ranger_BaseColor the steel is grey (saturation 0.05-0.2 at the faces' UV centroids), and everything else is
# well saturated (0.5-0.8): 0.3 lies in the empty band between them.
METAL_SATURATION = 0.3
# The ranger's greens sit at 60-180 degrees of hue and its browns and reds at 0-45: 50 is between them.
CLOTH_HUE = 50.0
# What each ranger part's faces are, by what they are made of (see the docstring's table).
RANGER_SLOTS = {
    "Knuckle_Body": {"cloth": MAIN, "leather": SEC, "metal": METAL},
    "Knuckle_Arms": {"cloth": MAIN, "leather": SEC, "metal": METAL},
    "Knuckle_Legs": {"cloth": PANTS, "leather": SEC, "metal": METAL},
    "Knuckle_Boots": {"cloth": BOOTS, "leather": BOOTS, "metal": METAL},
    "Knuckle_Hood": {"cloth": HOOD, "leather": SEC, "metal": SEC},
    "Knuckle_Pauldron": {"cloth": SEC, "leather": SEC, "metal": METAL},
}

# --- triangles ---

TARGET_TRIANGLES = 3800  # the whole model, every part in it; the budget is 1,500-4,000
MIN_TRIANGLES = 12  # per mesh
# How much of the shared ratio a part gets: the ranger's boots are a third of its triangles (9,172 of about 29,900)
# and a few pixels on screen, so they keep less, and the head, body and arms more.
WEIGHTS = {"Knuckle_Boots": 0.4}


# --- palette slots ---

def ranger_material():
    """A function (u, v) -> "metal", "cloth" or "leather": what T_Ranger_BaseColor shows there (its stored sRGB value,
    in HSV, by METAL_SATURATION and CLOTH_HUE)."""
    image = bpy.data.images.get(RANGER_TEXTURE)
    if image is None or image.size[0] == 0:
        raise BuildError(f"{RANGER_TEXTURE} did not load from the outfit pack")
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    rgb = pixels.reshape(height, width, 4)[:, :, :3]

    def at(u, v):  # Blender UVs and image rows both start at the bottom
        r, g, b = (float(c) for c in rgb[int((v % 1.0) * height) % height, int((u % 1.0) * width) % width])
        hue, saturation, _ = colorsys.rgb_to_hsv(r, g, b)
        if saturation < METAL_SATURATION:
            return "metal"
        return "cloth" if hue * 360.0 >= CLOTH_HUE else "leather"

    return at


def face_slots(obj, source, part, material_at):
    """The slot of each face of `obj` (the pack's object `source`, going into `part`), by the docstring's table."""
    me = obj.data
    materials = [m.name.split(".")[0] if m else "" for m in me.materials]
    uv = me.uv_layers[0].data
    slots = []
    for p in me.polygons:
        material = materials[p.material_index] if materials else ""
        if source == "SuperHero_Male":
            slot = SKIN
        elif source == "Eyes":
            slot = EYES
        elif part in ("Knuckle_Hair", "Knuckle_Beard") or source == "Eyebrows":
            slot = HAIR
        elif material == SKIN_MATERIAL:
            slot = SKIN
        elif part in RANGER_SLOTS and material == CLOTH_MATERIAL:
            u = sum(uv[i].uv.x for i in p.loop_indices) / p.loop_total
            v = sum(uv[i].uv.y for i in p.loop_indices) / p.loop_total
            slot = RANGER_SLOTS[part][material_at(u, v)]
        else:
            raise BuildError(f"{source}: no slot for a face using '{material}'")
        slots.append(slot)
    return slots


# --- one mesh per part ---

def join(objects, name):
    """Joins `objects` (meshes on one armature) into the first of them, named `name`, and returns it."""
    keep = objects[0]
    if len(objects) > 1:
        with bpy.context.temp_override(object=keep, active_object=keep, selected_objects=objects,
                                       selected_editable_objects=objects):
            bpy.ops.object.join()
    keep.name = keep.data.name = name
    return keep


def ratios(objects):
    """Each mesh's decimation ratio: a shared ratio times the part's weight (WEIGHTS, else 1), the shared ratio being
    TARGET_TRIANGLES over the weighted total, but never below MIN_TRIANGLES each."""
    shared = TARGET_TRIANGLES / sum(WEIGHTS.get(o.name, 1.0) * triangles(o) for o in objects)
    return {o.name: min(1.0, max(shared * WEIGHTS.get(o.name, 1.0), MIN_TRIANGLES / triangles(o))) for o in objects}


# --- the sword ---

BLADE_BONE = "hand_r"
BLADE_PART = "Knuckle_Blade"
# Everything below is in the hand's own frame (the bone's: x out of the back of the hand, y along the fingers, z toward the
# thumb; at rest the right arm lies along -X, the palm down and the thumb forward): the sword lies along z, held across
# the palm as a fist closes on a hilt, its edge on the knuckles' side (+y) and its spine toward the wrist (-y).
GRIP_AXIS = (-0.006, 0.065)  # where the hilt's axis crosses the palm: (x, y), the middle of the fist
POMMEL_Z = (-0.085, -0.070)
GRIP_Z = (-0.070, 0.040)
GUARD_Z = (0.040, 0.052)
BLADE_LENGTH = 0.75  # from the guard's face to the tip
BLADE_WIDTH = 0.105  # spine to edge: a cleaver's breadth, over 3 px across at the game's 32 px a metre
BLADE_THICKNESS = 0.014  # at the spine
BLADE_BEVEL = 0.03  # how far from the edge the flat face turns into the edge's bevel
TIP_LENGTH = 0.075  # the last stretch, where the edge sweeps up to the spine
TIP_SPINE_GAP = 0.018  # the tip stands this far from the spine's line, toward the edge
BOX_HALF = {  # (x, y) half-sizes of each box part
    "pommel": (0.016, 0.016),
    "grip": (0.0145, 0.0135),
    "guard": (0.021, 0.062),
}


def box_faces(vertices, faces, slots, slot, x, y, z):
    """Adds a box of the half-sizes `x`, `y` (about GRIP_AXIS) and the z range `z` to `vertices` and `faces`."""
    cx, cy = GRIP_AXIS
    base = len(vertices)
    for zz in z:
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            vertices.append((cx + sx * x, cy + sy * y, zz))
    for ring in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
        faces.append(tuple(base + i for i in ring))
        slots.append(slot)


def blade_faces(vertices, faces, slots):
    """Adds the single-edged blade: a five-sided section (flat back, two flat sides, the edge's two bevels) from the
    guard to TIP_LENGTH short of the tip, then a taper to a small blunt end."""
    cx, cy = GRIP_AXIS
    half_w, half_t = BLADE_WIDTH / 2.0, BLADE_THICKNESS / 2.0
    z0 = GUARD_Z[1]
    z_tip = z0 + BLADE_LENGTH

    def section(scale, shift):
        # spine top, spine bottom, bottom shoulder, edge, top shoulder (+shift toward the edge, all but the tip pinched)
        pts = ((half_t, -half_w), (-half_t, -half_w), (-half_t, half_w - BLADE_BEVEL), (0.0, half_w),
               (half_t, half_w - BLADE_BEVEL))
        return [(cx + x * scale, cy + y * scale + shift) for x, y in pts]

    # The point is a small blunt end, not a needle: a needle's last pixels are too thin for the picture to draw, and the rim round a
    # body must not reach past it.
    rings = [(z0 - 0.004, section(1.0, 0.0)), (z_tip - TIP_LENGTH, section(1.0, 0.0)),
             (z_tip - TIP_LENGTH / 2.0, section(0.55, 0.022)), (z_tip, section(0.16, TIP_SPINE_GAP * 1.2 - half_w))]
    base = len(vertices)
    for z, pts in rings:
        vertices.extend((x, y, z) for x, y in pts)
    for r in range(len(rings) - 1):
        for i in range(5):
            j = (i + 1) % 5
            faces.append((base + r * 5 + i, base + r * 5 + j, base + (r + 1) * 5 + j, base + (r + 1) * 5 + i))
            slots.append(STEEL)
    last = base + (len(rings) - 1) * 5
    faces.append(tuple(last + i for i in range(5)))  # the blunt end
    slots.append(STEEL)


def make_blade(armature):
    """The sword as a mesh object on `armature`: made in the hand_r bone's frame (see the constants above), moved to
    where the bone rests, weighted wholly to hand_r, flat shaded (its bevels must not blur into its sides), with the
    palette slots of the docstring's table. Returns the object."""
    bone = armature.data.bones[BLADE_BONE]
    vertices, faces, slots = [], [], []
    box_faces(vertices, faces, slots, METAL, *BOX_HALF["pommel"], POMMEL_Z)
    box_faces(vertices, faces, slots, SEC, *BOX_HALF["grip"], GRIP_Z)
    box_faces(vertices, faces, slots, METAL, *BOX_HALF["guard"], GUARD_Z)
    blade_faces(vertices, faces, slots)
    to_world = armature.matrix_world @ bone.matrix_local
    mesh = bpy.data.meshes.new(BLADE_PART)
    mesh.from_pydata([tuple(to_world @ Vector(v)) for v in vertices], [], faces)
    mesh.update()
    obj = bpy.data.objects.new(BLADE_PART, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mesh.uv_layers.new(name="UVMap")
    group = obj.vertex_groups.new(name=BLADE_BONE)
    group.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    obj.parent = armature
    obj.modifiers.new("Armature", "ARMATURE").object = armature
    write_slots(obj, slots)
    mesh.shade_flat()
    triangulate(obj)  # the faces were written in order, so triangulating keeps each one's slot on its two halves
    return obj


# --- the build ---

def build(ubc, outfits, out):
    reset_scene()
    logging.getLogger("glTFImporter_errors").addFilter(DropMissingImages())

    # 1. import
    base, base_armatures = import_gltf(Path(ubc) / BASE_GLTF, BASE_PARTS)
    outfit, outfit_armatures = import_gltf(Path(outfits) / OUTFIT_GLTF, OUTFIT_PARTS)
    hairs = []
    hair_armatures = []
    for hair_name in sorted(HAIR_PARTS):
        found, armatures = import_gltf(Path(ubc) / HAIR_DIR / f"{hair_name}.gltf", HAIR_PARTS[hair_name])
        hairs.append((found, HAIR_PARTS[hair_name]))
        hair_armatures += armatures
    for name in LEFT_OUT:
        obj = bpy.data.objects.get(name)
        if obj is None:
            raise BuildError(f"the outfit has no {name} to leave out")
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(data)
    sources = []  # (source object name, the part it goes into, its object)
    for found, table in [(base, BASE_PARTS), (outfit, OUTFIT_PARTS)] + hairs:
        for name in sorted(found):
            sources.append((name, table[name][1], found[name]))
    material_at = ranger_material()

    # 2. keep only the base body's head
    keep_head(base["SuperHero_Male"])

    # 3. one armature: the outfit's, as Abarax's build keeps (the base's differs only in the arms and legs, which the
    # head does not use; the hairstyles' is the outfit's)
    keep = outfit_armatures[0]
    head_chain = ("root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head")
    for other in base_armatures + hair_armatures:
        if not same_rest(keep, other, head_chain):
            raise BuildError(f"{other.name}'s spine, neck or head differs from the outfit's")
    for other in hair_armatures:
        if not same_rest(keep, other, [b.name for b in keep.data.bones]):
            raise BuildError(f"{other.name}'s skeleton differs from the outfit's")
    adopt([obj for _, _, obj in sources], keep)
    for other in base_armatures + hair_armatures:
        data = other.data
        bpy.data.objects.remove(other, do_unlink=True)
        bpy.data.armatures.remove(data)
    keep.name = keep.data.name = ARMATURE

    # 4. palette slots, on each source before the sources of a part are joined
    for name, part, obj in sources:
        tidy_layers(obj)
        weld(obj)
        write_slots(obj, face_slots(obj, name, part, material_at))

    # 5. one mesh per part
    parts = {}
    for name, part, obj in sources:
        parts.setdefault(part, []).append(obj)
    objects = [join(parts[part], part) for part in sorted(parts)]

    # 6. triangulate, then decimate
    for obj in objects:
        triangulate(obj)
    shares = ratios(objects)
    for obj in objects:
        decimate(obj, shares[obj.name])
        write_slots(obj, read_slots(obj, SLOT_COUNT))  # collapsing interpolates corners; put each face back on its slot
        finish_mesh(obj)

    # 7. the sword (after the decimation: its triangles are not part of the budget the parts share), then one material,
    # no images
    objects.append(make_blade(keep))
    one_material(objects)

    # 8. export
    export_glb(Path(out), BuildError)

    total = sum(triangles(o) for o in objects)
    print(f"build_knuckle: {out}: {total} triangles, {len(keep.data.bones)} bones")
    for obj in objects:
        slots = sorted(set(read_slots(obj, SLOT_COUNT)))
        ratio = f" (ratio {shares[obj.name]:.3f})" if obj.name in shares else ""
        print(f"  {obj.name}: {triangles(obj)} triangles{ratio}, slots {slots}")


def main(argv=None):
    if argv is None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(prog="build_knuckle.py", description=__doc__.split("\n\n")[0])
    parser.add_argument("--ubc", required=True, help="the ubc pack's extract folder (fetch.py path ubc)")
    parser.add_argument("--outfits", required=True, help="the outfits pack's extract folder (fetch.py path outfits)")
    parser.add_argument("--out", required=True, help="the .glb to write")
    args = parser.parse_args(argv)
    try:
        build(args.ubc, args.outfits, args.out)
    except BuildError as error:
        print(f"build_knuckle.py: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
