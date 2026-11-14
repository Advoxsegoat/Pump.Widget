#!/usr/bin/env python3
"""Builds Abarax's model with bpy: the head of Quaternius's base character and the Fantasy Outfits
peasant on one skeleton, plus a scarf with four bones of its own and the things the owner's pencil portrait
(docs/art/owner/abarax-portrait-sketch-2026-11-14.jpg) draws on him: a top-knot with the sides cut close, a
forelock and the small tie at his left temple, a ring in his right lobe, and from his left ear a link, a ring,
two beads and a barred feather on two bones of their own. The model has palette slots in UV2 instead of
textures, one material, and at most 4,000 triangles.

    tools/.venv/bin/python -I tools/anim/build_abarax.py --ubc <dir> --outfits <dir> --out <glb>

<dir> are the folders `python3 -I tools/assets/fetch.py path ubc|outfits` prints. They hold
downloaded data: this script only reads two .gltf files (with their .bin) and one PNG from them.
The same inputs always give the same bytes.

Palette slots are stored as UV2.x = (slot + 0.5) / 16 (UV2.y = 0.5). Vertex colours are dropped.

    slot  name   taken from
    0     skin   the head kept from the base body, and outfit faces using MI_Regular_Male
    1     hair   the top-knot and the cut hair, the forelock, and the base's `Face` mesh (MI_Hair_1: brows and
                 stubble); in the feather, its dark bars, a bead and the cord
    2     eyes   the base's `Face.001` mesh (MI_Eyes)
    3     main   Male_Peasant_Body and Male_Peasant_Arms faces using MI_Peasant
    4     sec    Male_Peasant_Body faces whose T_Peasant_BaseColor luminance, sampled at the
                 face's UV centroid, is below SPLIT_LUMA
    5     pants  Male_Peasant_Legs
    6     boots  Male_Peasant_Feet
    7     rose   the scarf, and the tie at his left temple
    8     gold   the rings (his right lobe's, and the feather's), the link, a bead and the feather's pale bars

Bones: the 65 joints the base and the outfit share, plus scarf_01 to scarf_04 (scarf_01's parent is
neck_01; each bone is 0.175 m long and they hang down the back), plus feather_01 and feather_02 (feather_01
hangs from the Head at his left lobe and carries the link, the ring, the beads and the cord; feather_02 hangs
from it and carries the feather). The new bones come last, so the 69 before them keep their places.

Made in code, like the scarf, and not decimated: Abarax_Forelock, Abarax_Feather, Abarax_EarRing, Abarax_Stubble
(the chin's and jaw's stubble, a skin of the head's faces, and the mole), and the bun
of Abarax_Topknot. The rest of Abarax_Topknot is the upper skull's faces of the decimated head, drawn a little
outside it: 3-4 mm thick on the sides and the nape (cut close), 11 mm on top (the hair pulled back to the bun).

Blender works Z up with this character facing -Y, so "back" below is +Y. The exporter writes
glTF's Y up, facing +Z.
"""
import argparse
import logging
import math
import sys
from pathlib import Path

import bpy  # first: the bpy module is what makes bmesh and mathutils importable

import bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))  # python -I leaves this folder off sys.path
from bpy_common import (  # noqa: E402
    BuildError, DropMissingImages, active, adopt, decimate, export_glb, finish_mesh, import_gltf, keep_head,
    one_material, read_slots as read_slots_of, reset_scene, same_rest, tidy_layers, triangles, triangulate, weld,
    world_coords, write_slots)

# --- inputs (inside the extract folders) ---

BASE_GLTF = Path("Universal Base Characters[Standard]", "Base Characters", "Godot - UE", "Superhero_Male_FullBody.gltf")
OUTFIT_GLTF = Path("Modular Character Outfits - Fantasy[Standard]", "Exports", "glTF (Godot-Unreal)", "Outfits",
                   "Male_Peasant.gltf")
PEASANT_TEXTURE = "T_Peasant_BaseColor"  # the image the outfit import loads for MI_Peasant

# Objects as the importer names them (from the glTF nodes) -> (mesh data name the pack uses, our name).
BASE_PARTS = {
    "SuperHero_Male": ("Sphere.005_Retopology.004", "Abarax_Head"),
    "Eyebrows": ("Face", "Abarax_Brows"),
    "Eyes": ("Face.001", "Abarax_Eyes"),
}
OUTFIT_PARTS = {name: (name, name) for name in
                ("Male_Peasant_Arms", "Male_Peasant_Body", "Male_Peasant_Feet", "Male_Peasant_Legs")}
SCARF_MESH = "Abarax_Scarf"
TOPKNOT_MESH, FORELOCK_MESH, FEATHER_MESH, EARRING_MESH, STUBBLE_MESH = (
    "Abarax_Topknot", "Abarax_Forelock", "Abarax_Feather", "Abarax_EarRing", "Abarax_Stubble")
ARMATURE = "Armature"

# --- palette slots ---

SKIN, HAIR, EYES, MAIN, SEC, PANTS, BOOTS, ROSE, GOLD = range(9)
SLOT_COUNT = 9
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

TARGET_TRIANGLES = 3900  # the whole model; the budget is 1,500-4,000
MAX_TRIANGLES = 4000
# What the portrait parts (the cut hair and bun, forelock, feather, ring) come to; the other meshes share what is left
# of TARGET_TRIANGLES. The build checks the whole against MAX_TRIANGLES and says what the parts came to.
PORTRAIT_TRIANGLES = 400
MIN_TRIANGLES = 12  # per mesh

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


# The build steps shared with build_knuckle.py (importing, the head, one armature, slots, triangles, one
# material) are in bpy_common.py.

def read_slots(obj):
    return read_slots_of(obj, SLOT_COUNT)


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


# --- the portrait: what the owner's drawing has on him ---

# His left is +X (he faces -Y with Z up, and the GLB keeps +X). All measured on the kept head: the ear's vertices run
# x 0.079-0.091, y 0.006-0.032, z 1.668-1.715, so the lobe hangs at about (0.082, 0.016, 1.666).
LOBE_LEFT = (0.082, 0.016, 1.666)
LOBE_RIGHT = (-0.087, 0.016, 1.659)  # the ring's centre: it hangs round the lobe, a little below it
FEATHER_BONES = ("feather_01", "feather_02")
# feather_01 carries the link, ring, beads and cord and leans 12 degrees out from straight down; feather_02 carries the
# feather and leans 66 degrees out: the collar (1.559 m at x 0.08, the sleeve 1.53 m out to x 0.2) is in the way of
# anything that hangs further down, so the feather points out past the jaw as the drawing's does and the spring swings it.
CHAIN_LENGTH, CHAIN_TILT = 0.07, 12.0
FEATHER_LENGTH, FEATHER_TILT = 0.15, 66.0
# The feather's blade: the distance along its bone of each cross-section, its half width there, and how far its right edge
# lags (so the bars slant across it, as the drawing's do).
FEATHER_ROWS = (0.004, 0.034, 0.064, 0.094, 0.124, 0.150)
FEATHER_HALF_WIDTHS = (0.004, 0.021, 0.030, 0.029, 0.019, 0.003)
FEATHER_SLANT = 0.012
FEATHER_BULGE = 0.004  # the quill's ridge stands this far out of the vane, on both sides
# The head's hairline, as the height z above which the hair grows at a given y (front -0.04 and forward: 1.768; the
# temple, y 0: 1.742; the back of the head, from y 0.08: the nape at 1.65). The ear is kept clear. A face is hair only when
# all its corners are above the line (the decimated head's faces are 2-3 cm wide).
HAIRLINE = ((-0.04, 1.768), (0.0, 1.742), (0.05, 1.700), (0.08, 1.650))
EAR_CLEAR = {"x": 0.06, "y": (-0.03, 0.06), "z": 1.735}
CUT_CLOSE, PULLED_BACK = 0.004, 0.011  # the hair's thickness on the sides and nape, and on top
CUT_CLOSE_BELOW, PULLED_BACK_ABOVE = 1.75, 1.79  # blended between these heights
# The bun: a knot tied at the back of the head, as in the drawing (where its top shows over the skull from ahead): a lathe
# round an axis that stands off the skull backward and up from BUN_BASE (a point just inside the back of the skull, high on
# it), a ring of (radius, distance along the axis) at a time and a point at the end, all times BUN_SCALE. At scale 1 it is
# 12.6 cm across; the drawing's is about 7 cm (scale 0.55).
BUN_BASE = (0.0, 0.092, 1.755)
BUN_AXIS = (0.0, 0.75, 0.66)
BUN_SCALE = 0.72
BUN_PROFILE = ((0.034, 0.0), (0.038, 0.026), (0.054, 0.045), (0.063, 0.070), (0.057, 0.100), (0.037, 0.125))
BUN_END = 0.135
BUN_SEGMENTS = 10
# The forelock: a lock from the hairline toward the bridge of the nose: (x, z, half width) along it.
FORELOCK_PATH = ((0.018, 1.778, 0.009), (0.024, 1.757, 0.0085), (0.020, 1.736, 0.007), (0.010, 1.718, 0.005),
                 (0.003, 1.706, 0.0015))
FORELOCK_RIDGE = 0.003
TIE_AT = (0.30, -0.035, 1.762)  # a ray from here along -X finds his left temple, where the tie sits
# The stubble: the faces of the decimated head whose corners all lie in one of these boxes (z from, z to, |x| from, |x| to,
# y from, y to: the chin's patch, then the jaw along both sides), laid 1.5 mm outside it; and the mole under his left eye:
# a ray from MOLE_AT along +Y finds the cheek, and a hexagon of MOLE_RADIUS goes on it.
STUBBLE_BOXES = ((1.575, 1.625, 0.0, 0.05, -0.2, -0.04), (1.575, 1.645, 0.03, 0.075, -0.07, 0.02))
STUBBLE_THICKNESS = 0.0015
MOLE_AT, MOLE_RADIUS = (0.04, -0.3, 1.673), 0.0055


class Made:
    """The verts, faces, one palette slot per face and one bone weighting per vertex of a mesh drawn in code (the
    scarf is the other; it predates this). Faces are given with the way they face and wound to match."""

    def __init__(self):
        self.verts, self.faces, self.slots, self.weights = [], [], [], []

    def vert(self, point, weights):
        self.verts.append(Vector(point))
        self.weights.append(weights)
        return len(self.verts) - 1

    def face(self, ids, slot, facing=None, away=None):
        """Adds a face; flips it if it faces against `facing` (a direction) or toward `away` (a point it is round)."""
        a, b, c = (self.verts[i] for i in ids[:3])
        normal = (b - a).cross(c - a)
        if facing is not None:
            wrong = normal.dot(facing) < 0
        else:
            centre = sum((self.verts[i] for i in ids), Vector()) / len(ids)
            wrong = normal.dot(centre - away) < 0
        self.faces.append(tuple(reversed(ids)) if wrong else tuple(ids))
        self.slots.append(slot)

    def box(self, centre, half_x, half_y, half_z, slot, weights):
        """A closed box: `half_*` are the vectors from its centre to its three pairs of faces."""
        ids = {}
        for i in (-1, 1):
            for j in (-1, 1):
                for k in (-1, 1):
                    ids[(i, j, k)] = self.vert(Vector(centre) + half_x * i + half_y * j + half_z * k, weights)
        for axis in range(3):
            for sign in (-1, 1):
                corners = []
                for u in (-1, 1):
                    for v in (-1, 1):
                        key = [0, 0, 0]
                        key[axis], key[(axis + 1) % 3], key[(axis + 2) % 3] = sign, u, v
                        corners.append(ids[tuple(key)])
                self.face([corners[0], corners[1], corners[3], corners[2]], slot, away=Vector(centre))

    def ring(self, centre, outer, inner, slot, weights, sides=6, normal_axis=1, thickness=0.003):
        """A flat ring (an annulus of `sides` sides) in the plane across `normal_axis` (default Y: seen from the front),
        two layers of faces `thickness` apart, one facing each way (nothing at the rim, which is too thin to see)."""
        normal = Vector((0.0, 0.0, 0.0))
        normal[normal_axis] = 1.0
        axes = [Vector((1.0, 0.0, 0.0)), Vector((0.0, 1.0, 0.0)), Vector((0.0, 0.0, 1.0))]
        u, v = (axes[(normal_axis + 1) % 3], axes[(normal_axis + 2) % 3])
        for layer in (-1, 1):
            ring = []
            for r in (outer, inner):
                ring.append([self.vert(Vector(centre) + normal * (layer * thickness / 2)
                                       + (u * math.cos(a) + v * math.sin(a)) * r, weights)
                             for a in (2 * math.pi * k / sides for k in range(sides))])
            for k in range(sides):
                k1 = (k + 1) % sides
                self.face([ring[0][k], ring[0][k1], ring[1][k1], ring[1][k]], slot, facing=normal * layer)

    def bead(self, centre, radius, slot, weights):
        """A bipyramid: an eight-faced bead."""
        top = self.vert(Vector(centre) + Vector((0.0, 0.0, radius * 1.2)), weights)
        bottom = self.vert(Vector(centre) - Vector((0.0, 0.0, radius * 1.2)), weights)
        mid = [self.vert(Vector(centre) + Vector((math.cos(a), math.sin(a), 0.0)) * radius, weights)
               for a in (math.pi / 2 * k for k in range(4))]
        for k in range(4):
            self.face([top, mid[k], mid[(k + 1) % 4]], slot, away=Vector(centre))
            self.face([bottom, mid[(k + 1) % 4], mid[k]], slot, away=Vector(centre))


def smoothstep(lo, hi, x):
    t = min(1.0, max(0.0, (x - lo) / (hi - lo)))
    return t * t * (3 - 2 * t)


def feather_joints():
    """The three joints of the feather's chain, from the left lobe: out of the lobe, to the end of feather_01 and to the
    feather's tip. Each leans out (+X) by its tilt from straight down."""
    start = Vector(LOBE_LEFT)
    down = lambda tilt: Vector((math.sin(math.radians(tilt)), 0.0, -math.cos(math.radians(tilt))))
    middle = start + down(CHAIN_TILT) * CHAIN_LENGTH
    return [start, middle, middle + down(FEATHER_TILT) * FEATHER_LENGTH]


def add_feather_bones(armature, joints):
    """feather_01 from the Head at the lobe, feather_02 below it; after the scarf's, so the bones before keep their place."""
    bpy.context.view_layer.objects.active = armature
    with active(armature):
        bpy.ops.object.mode_set(mode="EDIT")
        bones = armature.data.edit_bones
        parent = bones["Head"]
        for i, name in enumerate(FEATHER_BONES):
            bone = bones.new(name)
            bone.head, bone.tail = joints[i], joints[i + 1]
            bone.roll = 0.0
            bone.parent = parent
            bone.use_connect = i > 0
            bone.use_deform = True
            parent = bone
        bpy.ops.object.mode_set(mode="OBJECT")


def made_object(name, made, armature, bones):
    """The mesh object of `made` (see Made), skinned to `bones` of `armature`, with its palette slots written."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in made.verts], [], made.faces)
    me.uv_layers.new(name="UVMap")
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = armature
    groups = {bone: obj.vertex_groups.new(name=bone) for bone in bones}
    for index, weights in enumerate(made.weights):
        for bone, weight in weights.items():
            groups[bone].add([index], weight, "REPLACE")
    obj.modifiers.new("Armature", "ARMATURE").object = armature
    write_slots(obj, made.slots)
    return obj


def hairline(y):
    for (y0, z0), (y1, z1) in zip(HAIRLINE, HAIRLINE[1:]):
        if y <= y1:
            return z0 + (z1 - z0) * (max(y, y0) - y0) / (y1 - y0)
    return HAIRLINE[-1][1]


def topknot(head, armature):
    """The cut hair and the bun: the faces of `head` above the hairline, grown outward along their normals (thin at the
    sides and nape, thick on top), and a lathed bun on the crown. Weighted to the Head bone."""
    made = Made()
    head_only = {"Head": 1.0}
    bm = bmesh.new()
    bm.from_mesh(head.data)
    bm.normal_update()
    matrix = head.matrix_world
    def grows(p):
        line = hairline(p.y)
        if abs(p.x) > EAR_CLEAR["x"] and EAR_CLEAR["y"][0] < p.y < EAR_CLEAR["y"][1]:
            line = max(line, EAR_CLEAR["z"])
        return p.z >= line

    kept = {f.index: f for f in bm.faces if all(grows(matrix @ v.co) for v in f.verts)}
    for f in sorted(kept.values(), key=lambda f: f.index):
        ids = []
        for v in f.verts:
            p = matrix @ v.co
            thickness = CUT_CLOSE + (PULLED_BACK - CUT_CLOSE) * smoothstep(CUT_CLOSE_BELOW, PULLED_BACK_ABOVE, p.z)
            ids.append(made.vert(p + (matrix.to_3x3() @ v.normal).normalized() * thickness, head_only))
        made.faces.append(tuple(ids))  # the head's own winding faces outward already
        made.slots.append(HAIR)
    bm.free()
    # the bun: rings round BUN_AXIS, standing off the back of the skull
    axis = Vector(BUN_AXIS).normalized()
    across = Vector((1.0, 0.0, 0.0))
    up = axis.cross(across)
    base = Vector(BUN_BASE)
    rings = []
    for r, along in BUN_PROFILE:
        centre = base + axis * (along * BUN_SCALE)
        rings.append([made.vert(centre + (across * math.cos(a) + up * math.sin(a)) * (r * BUN_SCALE), head_only)
                      for a in (2 * math.pi * k / BUN_SEGMENTS for k in range(BUN_SEGMENTS))])
    middle = base + axis * (BUN_END * 0.45 * BUN_SCALE)
    for lower, upper in zip(rings, rings[1:]):
        for k in range(BUN_SEGMENTS):
            k1 = (k + 1) % BUN_SEGMENTS
            made.face([lower[k], lower[k1], upper[k1], upper[k]], HAIR, away=middle)
    top = made.vert(base + axis * (BUN_END * BUN_SCALE), head_only)
    for k in range(BUN_SEGMENTS):
        made.face([rings[-1][k], rings[-1][(k + 1) % BUN_SEGMENTS], top], HAIR, away=middle)
    return made_object(TOPKNOT_MESH, made, armature, ["Head"])


def forelock(head, armature):
    """One lock on the forehead, a ridged ribbon laid just off the head's front, and the tie at his left temple."""
    made = Made()
    head_only = {"Head": 1.0}
    tree = surface_tree([head])
    rows = []
    for x, z, half in FORELOCK_PATH:
        hit, normal, _, _ = tree.ray_cast(Vector((x, -0.3, z)), Vector((0.0, 1.0, 0.0)), 0.6)
        if hit is None:
            raise BuildError("found no forehead for the forelock")
        lift = 0.006 + 0.004 * smoothstep(1.74, 1.775, z)  # clear of the hair's own thickness up at the hairline
        centre = hit + normal * lift
        rows.append([made.vert(centre - Vector((half, 0.0, 0.0)), head_only),
                     made.vert(centre + normal * FORELOCK_RIDGE, head_only),
                     made.vert(centre + Vector((half, 0.0, 0.0)), head_only)])
    for a, b in zip(rows, rows[1:]):
        for k in range(2):
            made.face([a[k], a[k + 1], b[k + 1], b[k]], HAIR, facing=Vector((0.0, -1.0, 0.0)))
    hit, normal, _, _ = tree.ray_cast(Vector(TIE_AT), Vector((-1.0, 0.0, 0.0)), 0.6)
    if hit is None:
        raise BuildError("found no left temple for the tie")
    made.box(hit + normal * 0.007, Vector((0.005, 0.0, 0.0)), Vector((0.0, 0.009, 0.0)), Vector((0.0, 0.0, 0.006)),
             ROSE, head_only)
    return made_object(FORELOCK_MESH, made, armature, ["Head"])


def stubble(head, armature):
    """The chin's patch and the jaw's stubble as a thin skin of the head's own faces, and the mole on his left cheek."""
    made = Made()
    head_only = {"Head": 1.0}
    bm = bmesh.new()
    bm.from_mesh(head.data)
    bm.normal_update()
    matrix = head.matrix_world

    def inside(p, box):
        z0, z1, x0, x1, y0, y1 = box
        return z0 <= p.z <= z1 and x0 <= abs(p.x) <= x1 and y0 <= p.y <= y1

    for f in bm.faces:
        corners = [matrix @ v.co for v in f.verts]
        if any(all(inside(p, box) for p in corners) for box in STUBBLE_BOXES):
            ids = [made.vert(p + (matrix.to_3x3() @ v.normal).normalized() * STUBBLE_THICKNESS, head_only)
                   for p, v in zip(corners, f.verts)]
            made.faces.append(tuple(ids))  # the head's own winding faces outward already
            made.slots.append(HAIR)
    bm.free()
    hit, normal, _, _ = surface_tree([head]).ray_cast(Vector(MOLE_AT), Vector((0.0, 1.0, 0.0)), 0.6)
    if hit is None:
        raise BuildError("found no cheek for the mole")
    middle = made.vert(hit + normal * (STUBBLE_THICKNESS + 0.001), head_only)
    ring = [made.vert(hit + normal * STUBBLE_THICKNESS + Vector((math.cos(a), 0.0, math.sin(a))) * MOLE_RADIUS, head_only)
            for a in (2 * math.pi * k / 6 for k in range(6))]
    for k in range(6):
        made.face([middle, ring[k], ring[(k + 1) % 6]], HAIR, facing=Vector((0.0, -1.0, 0.0)))
    if not made.faces:
        raise BuildError("found no chin for the stubble")
    return made_object(STUBBLE_MESH, made, armature, ["Head"])


def earring(armature):
    made = Made()
    made.ring(LOBE_RIGHT, 0.014, 0.008, GOLD, {"Head": 1.0})
    return made_object(EARRING_MESH, made, armature, ["Head"])


def feather(armature, joints):
    """From his left lobe: a link, a ring, two beads on a cord, then the barred feather (gold and the hair's brown: the bars are
    those two, so the feather shows dark against the cream of the shirt behind it and gold against the ground beyond)."""
    made = Made()
    first, second = {"feather_01": 1.0}, {"feather_02": 1.0}
    start, middle, tip = joints
    along = (middle - start).normalized()
    out = (tip - middle).normalized()
    at = lambda s: start + along * s
    side = Vector((0.0, 1.0, 0.0)).cross(along).normalized()  # across the chain, in the plane of X and Z
    made.box(at(0.007), along * 0.007, Vector((0.0, 0.002, 0.0)), side * 0.002, GOLD, first)
    made.ring(at(0.026), 0.0125, 0.0075, GOLD, first)
    made.bead(at(0.046), 0.0065, GOLD, first)
    made.bead(at(0.058), 0.0065, HAIR, first)
    made.box(at(0.066), along * 0.006, Vector((0.0, 0.0015, 0.0)), side * 0.0015, HAIR, first)
    # the blade: its width runs across `out`, in the plane of X and Z, and it faces front and back
    across = Vector((0.0, 1.0, 0.0)).cross(out)
    for layer, facing, bulge in ((0, Vector((0.0, -1.0, 0.0)), -1), (1, Vector((0.0, 1.0, 0.0)), 1)):
        rows = []
        for i, (s, half) in enumerate(zip(FEATHER_ROWS, FEATHER_HALF_WIDTHS)):
            weights = {"feather_01": 0.5, "feather_02": 0.5} if i == 0 else second
            left = middle + out * s - across * half
            right = middle + out * (s + FEATHER_SLANT * (half / max(FEATHER_HALF_WIDTHS))) + across * half
            ridge = middle + out * s + Vector((0.0, bulge * FEATHER_BULGE, 0.0))
            rows.append([made.vert(left + Vector((0.0, bulge * 0.001, 0.0)), weights), made.vert(ridge, weights),
                         made.vert(right + Vector((0.0, bulge * 0.001, 0.0)), weights)])
        for band, (a, b) in enumerate(zip(rows, rows[1:])):
            slot = GOLD if band % 2 == 0 else HAIR
            for k in range(2):
                made.face([a[k], a[k + 1], b[k + 1], b[k]], slot, facing=facing)
    return made_object(FEATHER_MESH, made, armature, ["feather_01", "feather_02"])


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
        elif part == "Abarax_Brows":
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


# --- step 6: triangles ---

def ratios(objects):
    """Each mesh's decimation ratio. The scarf is built at its final size and is not decimated:
    collapsing would first merge its flat ribbon rows, leaving the scarf bones nothing to bend. The
    other meshes share one ratio, (TARGET_TRIANGLES - scarf - PORTRAIT_TRIANGLES) / (total - scarf), but never go
    below MIN_TRIANGLES each. (The portrait parts are made after this, from the decimated head.)"""
    fixed = sum(triangles(o) for o in objects if o.name == SCARF_MESH)
    rest = sum(triangles(o) for o in objects if o.name != SCARF_MESH)
    shared = (TARGET_TRIANGLES - fixed - PORTRAIT_TRIANGLES) / rest
    return {o.name: 1.0 if o.name == SCARF_MESH else min(1.0, max(shared, MIN_TRIANGLES / triangles(o)))
            for o in objects}


# --- the build ---

def build(ubc, outfits, out):
    reset_scene()
    logging.getLogger("glTFImporter_errors").addFilter(DropMissingImages())

    # 1. import
    base, base_armatures = import_gltf(Path(ubc) / BASE_GLTF, BASE_PARTS)
    outfit, outfit_armatures = import_gltf(Path(outfits) / OUTFIT_GLTF, OUTFIT_PARTS)
    parts = {}
    for found, table in ((base, BASE_PARTS), (outfit, OUTFIT_PARTS)):
        for name, obj in found.items():
            part = table[name][1]
            obj.name = obj.data.name = part
            parts[part] = obj
    luma = peasant_luma()

    # 2. keep only the base body's head
    keep_head(parts["Abarax_Head"])

    # 3. one armature. The outfit is skinned to the base's skeleton (the 65 bone names, the
    # regular-male proportions); the base's own armature differs from it only in the arms and legs
    # (2-3 cm wider), which the head does not use. So the outfit's armature is the one kept: the
    # head, neck and spine bones the head hangs on are identical.
    keep = outfit_armatures[0]
    head_chain = ("root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head")
    for other in base_armatures:
        if not same_rest(keep, other, head_chain):
            raise BuildError(f"{other.name}'s spine, neck or head differs from the outfit's")
    adopt([parts[p] for p in sorted(parts)], keep)
    for other in base_armatures:
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
        back=[parts[p] for p in ("Abarax_Head", "Male_Peasant_Body", "Male_Peasant_Legs")])

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

    # 7. the portrait: bones, then the parts, made from the decimated head and finished like the rest
    joints = feather_joints()
    add_feather_bones(keep, joints)
    made = [topknot(parts["Abarax_Head"], keep), forelock(parts["Abarax_Head"], keep), feather(keep, joints),
            earring(keep), stubble(parts["Abarax_Head"], keep)]
    for obj in made:
        triangulate(obj)
        finish_mesh(obj)
    objects += made
    if sum(triangles(o) for o in objects) > MAX_TRIANGLES:
        raise BuildError(f"{sum(triangles(o) for o in objects)} triangles: over {MAX_TRIANGLES}")

    # 8. one material, no images
    one_material(objects)

    # 9. export
    export_glb(Path(out), BuildError)

    total = sum(triangles(o) for o in objects)
    print(f"build_abarax: {out}: {total} triangles, {len(keep.data.bones)} bones")
    for obj in objects:
        slots = sorted(set(read_slots(obj)))
        print(f"  {obj.name}: {triangles(obj)} triangles (ratio {shares.get(obj.name, 1.0):.3f}), slots {slots}")


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
