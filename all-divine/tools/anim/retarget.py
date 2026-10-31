#!/usr/bin/env python3
"""Retargets a BVH motion-capture clip (CMU joint names) onto Abarax's skeleton with bpy and writes it as
a GLB: Abarax's model with one animation, the clip.

    tools/.venv/bin/python -I tools/anim/retarget.py --bvh <in.bvh> --map tools/anim/bonemap_cmu.json \\
        --target assets/characters/abarax/abarax.glb --tpose <UAL1_Standard.glb> --tpose-clip A_TPose \\
        --out <out.glb> --name <clip>

--tpose is the glTF that holds the T-pose reference clip: the Quaternius pack's UAL1_Standard.glb, found with
`python3 -I tools/assets/fetch.py path ual1`. It is downloaded data: this script only reads its skeleton and
the first frame of the clip. The same inputs always give the same bytes. The GLB can be named as a source in
clips.cfg like the Quaternius ones.

Every rotation is compared in world space, so the two skeletons' bone axes, and the joints one has and the
other lacks, do not matter (CMU's Neck1, say, has no target: Head's world rotation already includes it).

    delta(source bone, t)  = world(source bone, t) x world(source bone, rest)^-1
    world(target bone, t)  = delta(source bone, t) x world(target bone, reference)

The reference is the target in the T-pose: its rest pose with, on each bone, the world rotation change the
first frame of --tpose-clip makes to the same bone of --tpose's skeleton (a bone only the target has, like
the scarf, turns with its parent). A BVH's rest pose has every joint turned by nothing, so there
world(source bone, rest) is the identity and delta is the joint's world rotation. A target bone that no BVH
joint drives (the fingers, the scarf, any bone the map lacks, any bone whose joint the BVH lacks) keeps its
reference pose relative to its parent, so it rides along with it.

The BVH's root joint (Hips) drives the target bone the map gives it (pelvis) in position too. Its path is
scaled by the target's hip height over the BVH's: the pelvis's rest height above the ground (z = 0 of the
armature) over the root's rest height above the lowest point of the BVH skeleton (an End Site counts). The
pelvis starts where it rests in the ground plane (only the root's travel from its first frame is applied
there); its height is the root's absolute height times the scale. A BVH's position channels are taken as
absolute, as in the CMU files from cgspeed (root OFFSET 0 0 0, the height in the channels).

BVH coordinates are Y up with the character facing +Z (its left is +X): glTF's, which Blender's importer turns
into Z up facing -Y. Euler channels compose in the order they are listed: Zrotation Yrotation Xrotation is
Rz Ry Rx. The clip is baked: one key per BVH frame on every bone, at the BVH's frame rate.
"""
import argparse
import contextlib
import io
import json
import math
import sys
from pathlib import Path

import bpy  # first: the bpy module is what makes mathutils importable

from mathutils import Matrix, Vector

# glTF/BVH axes (Y up, +Z in front) -> Blender's (Z up, -Y in front): (x, y, z) -> (x, -z, y)
TO_BLENDER = Matrix(((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)))
FROM_BLENDER = TO_BLENDER.transposed()
IDENTITY = Matrix.Identity(3)
AXES = {"X": Vector((1.0, 0.0, 0.0)), "Y": Vector((0.0, 1.0, 0.0)), "Z": Vector((0.0, 0.0, 1.0))}


class RetargetError(Exception):
    pass


# --- the bone map ---

def load_bonemap(path):
    """{BVH joint name: target bone name} from a JSON object. A target bone can be named only once."""
    try:
        data = json.loads(Path(path).read_text())
    except OSError as error:
        raise RetargetError(f"cannot read {path}: {error.strerror}")
    except ValueError as error:
        raise RetargetError(f"{path} is not JSON: {error}")
    if not isinstance(data, dict) or not data:
        raise RetargetError(f"{path}: expected a JSON object of BVH joint -> target bone")
    for source, target in data.items():
        if not isinstance(target, str) or not target:
            raise RetargetError(f"{path}: {source!r} must map to a bone name")
    seen = {}
    for source, target in data.items():
        if target in seen:
            raise RetargetError(f"{path}: {seen[target]!r} and {source!r} both map to {target!r}")
        seen[target] = source
    return dict(data)


# --- BVH files ---

class Joint:
    """One joint of a BVH: `parent` is an index into Bvh.joints (None for the root), `offset` its rest
    position from the parent in the BVH's axes, `position`/`rotation` the columns of a frame that hold its
    channels, and `rotation_order` the axes of its rotation channels as listed, e.g. "ZYX"."""

    def __init__(self, name, parent, offset):
        self.name = name
        self.parent = parent
        self.offset = offset
        self.position = []  # [(axis, column)]
        self.rotation = []  # [(axis, column)]

    @property
    def rotation_order(self):
        return "".join(axis for axis, _ in self.rotation)


class Bvh:
    def __init__(self, joints, end_sites, frame_time, frames):
        self.joints = joints  # parents before children
        self.end_sites = end_sites  # [(parent joint index, offset)]
        self.frame_time = frame_time
        self.frames = frames  # [[float]], one row of channel values per frame

    def rest_positions(self):
        """Every joint's rest position (from the root's offset and the offsets down the tree), then every End Site's."""
        at = []
        for joint in self.joints:
            at.append(joint.offset + (at[joint.parent] if joint.parent is not None else Vector()))
        return at + [offset + at[parent] for parent, offset in self.end_sites]

    def hip_height(self):
        """The root's rest height above the lowest rest point of the skeleton."""
        at = self.rest_positions()
        return at[0].y - min(p.y for p in at)

    def root_position(self, frame):
        """The root's position in a frame: its position channels, and its offset for an axis without one."""
        root, row = self.joints[0], self.frames[frame]
        position = root.offset.copy()
        for axis, column in root.position:
            position["XYZ".index(axis)] = row[column]
        return position

    def world_rotations(self, frame):
        """{joint name: 3x3 world rotation} in a frame. In the rest pose every joint is turned by nothing,
        so this is also each joint's world rotation change from rest."""
        row = self.frames[frame]
        world = []
        for joint in self.joints:
            local = Matrix.Identity(3)
            for axis, column in joint.rotation:
                local = local @ Matrix.Rotation(math.radians(row[column]), 3, axis)
            world.append(world[joint.parent] @ local if joint.parent is not None else local)
        return {joint.name: w for joint, w in zip(self.joints, world)}


def parse_bvh(path):
    """Reads a BVH file. Position and rotation channels may come in any order; a joint with no position
    channel does not move from its offset. Raises RetargetError if the file is not a whole BVH."""
    try:
        tokens = Path(path).read_text(errors="replace").split()
    except OSError as error:
        raise RetargetError(f"cannot read {path}: {error.strerror}")
    at = 0

    def take():
        nonlocal at
        if at >= len(tokens):
            raise RetargetError(f"{path}: the file ends early")
        at += 1
        return tokens[at - 1]

    def expect(word):
        got = take()
        if got.upper() != word.upper():
            raise RetargetError(f"{path}: expected {word}, found {got}")

    def number():
        got = take()
        try:
            return float(got)
        except ValueError:
            raise RetargetError(f"{path}: expected a number, found {got}")

    def offset():
        expect("OFFSET")
        return Vector((number(), number(), number()))

    joints, end_sites, columns = [], [], [0]

    def read_joint(name, parent):
        expect("{")
        joint = Joint(name, parent, offset())
        index = len(joints)
        joints.append(joint)
        while True:
            word = take().upper()
            if word == "CHANNELS":
                for _ in range(int(number())):
                    channel = take()
                    kind, axis = channel[1:].lower(), channel[:1].upper()
                    if axis not in AXES or kind not in ("position", "rotation"):
                        raise RetargetError(f"{path}: unknown channel {channel}")
                    (joint.position if kind == "position" else joint.rotation).append((axis, columns[0]))
                    columns[0] += 1
            elif word == "JOINT":
                read_joint(take(), index)
            elif word == "END":
                expect("Site")
                expect("{")
                end_sites.append((index, offset()))
                expect("}")
            elif word == "}":
                return
            else:
                raise RetargetError(f"{path}: unexpected {word} in joint {name}")

    expect("HIERARCHY")
    expect("ROOT")
    read_joint(take(), None)
    expect("MOTION")
    expect("Frames:")
    count = int(number())
    expect("Frame")
    expect("Time:")
    frame_time = number()
    if count < 1 or frame_time <= 0:
        raise RetargetError(f"{path}: needs at least one frame and a positive frame time")
    width = columns[0]
    values = tokens[at:]
    if len(values) != count * width:
        raise RetargetError(f"{path}: {count} frames of {width} values need {count * width} numbers, "
                            f"found {len(values)}")
    try:
        numbers = [float(v) for v in values]
    except ValueError:
        raise RetargetError(f"{path}: the motion data has something that is not a number")
    frames = [numbers[i * width:(i + 1) * width] for i in range(count)]
    return Bvh(joints, end_sites, frame_time, frames)


# --- scene helpers ---

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


@contextlib.contextmanager
def quiet_gltf():
    """The glTF add-on logs at the level bpy.app.debug_value picks; 3 keeps only critical messages,
    so its info lines stay out of the output. The old value is put back afterwards."""
    previous = bpy.app.debug_value
    bpy.app.debug_value = 3
    try:
        yield
    finally:
        bpy.app.debug_value = previous


def import_armature(path):
    """Imports a glTF file into the (reset) scene and returns its one armature object."""
    path = Path(path)
    if not path.is_file():
        raise RetargetError(f"missing {path}")
    with quiet_gltf():
        result = bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic="BLENDER", disable_bone_shape=True,
                                           merge_vertices=False, import_shading="NORMALS")
    if result != {"FINISHED"}:
        raise RetargetError(f"could not import {path}")
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RetargetError(f"{path.name}: expected one armature, found {len(armatures)}")
    return armatures[0]


def bones_in_order(armature):
    """The armature's bones, every parent before its children."""
    ordered, seen = [], set()

    def visit(bone):
        if bone.name not in seen:
            if bone.parent is not None:
                visit(bone.parent)
            seen.add(bone.name)
            ordered.append(bone)

    for bone in armature.data.bones:
        visit(bone)
    return ordered


# --- the T-pose reference ---

def tpose_changes(path, clip):
    """{bone name: 3x3 world rotation change in the armature's space} that the first frame of `clip` makes
    to each bone of the armature in `path`, from its rest pose."""
    reset_scene()
    armature = import_armature(path)
    action = bpy.data.actions.get(clip)
    if action is None:
        have = ", ".join(sorted(a.name for a in bpy.data.actions)) or "none"
        raise RetargetError(f"{Path(path).name} has no clip {clip!r} (it has: {have})")
    if armature.animation_data is None:
        armature.animation_data_create()
    armature.animation_data.action = action
    if armature.animation_data.action_slot is None and len(action.slots):
        armature.animation_data.action_slot = action.slots[0]
    first = action.frame_range[0]
    bpy.context.scene.frame_set(math.floor(first), subframe=first - math.floor(first))
    return {pb.name: (pb.matrix @ pb.bone.matrix_local.inverted()).to_3x3() for pb in armature.pose.bones}


# --- the retargeting ---

def hip_target(bvh, bonemap):
    root = bvh.joints[0].name
    if root not in bonemap:
        raise RetargetError(f"the BVH's root joint {root} is not in the bone map, so nothing would carry its travel")
    return bonemap[root]


def pose_frames(armature, bvh, drives, hip_bone, reference, scale):
    """The pose of every bone in every frame, as [{bone name: (quaternion, location or None)}], where a
    bone's quaternion and location are its pose-bone values (rotation_quaternion and location) in Blender.

    `drives` is {target bone: BVH joint} for the joints the BVH has, `reference` {bone: world rotation change
    that puts it in the T-pose} (a bone it lacks has none), `scale` the factor for the root's travel."""
    bones = bones_in_order(armature)
    rest = {b.name: b.matrix_local.copy() for b in bones}
    rest_rotation = {n: m.to_3x3() for n, m in rest.items()}
    rest_rotation_inverse = {n: m.inverted() for n, m in rest_rotation.items()}
    relative = {b.name: (rest[b.parent.name].inverted() if b.parent else Matrix.Identity(4)) @ rest[b.name]
                for b in bones}
    relative_inverse = {n: m.inverted() for n, m in relative.items()}
    changes = {}  # the reference, for every bone: one the T-pose skeleton lacks (the scarf) turns as its parent does
    for bone in bones:
        changes[bone.name] = reference.get(bone.name, changes[bone.parent.name] if bone.parent else IDENTITY)
    reference = changes

    hip_rest = FROM_BLENDER @ rest[hip_bone].translation
    start = bvh.root_position(0)
    poses = []
    previous = {}
    for frame in range(len(bvh.frames)):
        world = bvh.world_rotations(frame)
        change = {}  # each bone's world rotation change from its rest pose
        matrix = {}  # each bone's pose matrix in the armature's space
        pose = {}
        for bone in bones:
            name, parent = bone.name, bone.parent.name if bone.parent else None
            if name in drives:
                source = TO_BLENDER @ world[drives[name]] @ FROM_BLENDER
                change[name] = source @ reference[name]
            elif parent is None:
                change[name] = reference[name]
            else:  # keeps its pose in the reference relative to its parent
                change[name] = change[parent] @ reference[parent].transposed() @ reference[name]
            parent_change = change[parent] if parent else IDENTITY
            parent_matrix = matrix[parent] if parent else Matrix.Identity(4)
            if name == hip_bone:
                at = bvh.root_position(frame)
                here = Vector((hip_rest.x + scale * (at.x - start.x), scale * at.y,
                               hip_rest.z + scale * (at.z - start.z)))
                wanted = Matrix.Translation(TO_BLENDER @ here) @ (change[name] @ rest_rotation[name]).to_4x4()
                basis = relative_inverse[name] @ parent_matrix.inverted() @ wanted
                rotation, location = basis.to_quaternion(), basis.translation.copy()
            else:
                local = rest_rotation_inverse[name] @ (parent_change.transposed() @ change[name]) @ rest_rotation[name]
                basis = local.to_4x4()
                rotation, location = local.to_quaternion(), None
            if name in previous:
                rotation.make_compatible(previous[name])  # the shorter way round from the last frame
            previous[name] = rotation
            matrix[name] = parent_matrix @ relative[name] @ basis
            pose[name] = (rotation, location)
        poses.append(pose)
    return poses


def key_poses(armature, poses, name, fps, fps_base):
    """Writes `poses` as the keys of a new action called `name`, one frame after another from frame 0, which
    becomes the armature's action. Every bone gets a key per frame on its quaternion, and the root-motion
    bone on its location as well."""
    scene = bpy.context.scene
    scene.render.fps, scene.render.fps_base = fps, fps_base
    scene.frame_start, scene.frame_end = 0, len(poses) - 1
    if armature.animation_data is None:
        armature.animation_data_create()
    action = bpy.data.actions.new(name)
    armature.animation_data.action = action
    frames = list(range(len(poses)))

    def keys(pose_bone, prop, index, values):
        curve = action.fcurve_ensure_for_datablock(armature, pose_bone.path_from_id(prop), index=index,
                                                   group_name=pose_bone.name)
        curve.keyframe_points.add(len(frames))
        flat = [0.0] * (2 * len(frames))
        flat[0::2], flat[1::2] = frames, values
        curve.keyframe_points.foreach_set("co", flat)
        for key in curve.keyframe_points:
            key.interpolation = "LINEAR"
        curve.update()

    for bone_name in poses[0]:
        pose_bone = armature.pose.bones[bone_name]
        pose_bone.rotation_mode = "QUATERNION"
        for index in range(4):
            keys(pose_bone, "rotation_quaternion", index, [pose[bone_name][0][index] for pose in poses])
        if poses[0][bone_name][1] is not None:
            for index in range(3):
                keys(pose_bone, "location", index, [pose[bone_name][1][index] for pose in poses])


# --- export ---

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
        raise RetargetError(f"could not export {path}")


def _export(path):
    # the model's settings are build_abarax.py's; the animation is baked at every frame of the action
    return bpy.ops.export_scene.gltf(
        filepath=str(path), check_existing=False, export_format="GLB",
        export_yup=True, use_selection=False, export_apply=False,
        export_texcoords=True, export_normals=True, export_tangents=False,
        export_vertex_color="NONE", export_all_vertex_colors=False, export_attributes=False,
        export_materials="EXPORT", export_image_format="NONE",
        export_skins=True, export_influence_nb=4, export_all_influences=False, export_def_bones=False,
        export_rest_position_armature=True, export_leaf_bone=False,
        export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
        export_frame_range=False, export_frame_step=1, export_optimize_animation_size=False,
        export_anim_slide_to_zero=False, export_morph=False,
        export_cameras=False, export_lights=False, export_extras=False)


# --- the tool ---

def retarget(bvh, bonemap, target, tpose, tpose_clip, out, name):
    """Retargets the BVH file `bvh` onto the armature of the GLB `target` through `bonemap` ({BVH joint:
    target bone}, see load_bonemap), with the first frame of the clip `tpose_clip` of the GLB `tpose` as the
    T-pose reference, and writes the GLB `out`: the target with one animation called `name`."""
    source = parse_bvh(bvh)
    hip_bone = hip_target(source, bonemap)
    source_hip = source.hip_height()
    if source_hip <= 0:
        raise RetargetError(f"{bvh}: the root is not above the rest of the skeleton in the rest pose")

    reference = tpose_changes(tpose, tpose_clip)

    reset_scene()
    armature = import_armature(target)
    names = {b.name for b in armature.data.bones}
    missing = sorted(t for t in bonemap.values() if t not in names)
    if missing:
        raise RetargetError(f"{Path(target).name} has no bone {', '.join(missing)}, which the bone map names")
    joints = {j.name for j in source.joints}
    drives = {t: s for s, t in bonemap.items() if s in joints}
    target_hip = armature.data.bones[hip_bone].head_local.z
    scale = target_hip / source_hip

    poses = pose_frames(armature, source, drives, hip_bone, reference, scale)
    fps = max(1, round(1.0 / source.frame_time))
    fps_base = 1.0 if abs(fps * source.frame_time - 1.0) < 1e-3 else fps * source.frame_time
    key_poses(armature, poses, name, fps, fps_base)
    if len(bpy.data.actions) != 1:  # the export writes every action: the clip must be the only one
        raise RetargetError(f"expected {name!r} to be the only action, found {len(bpy.data.actions)}")
    export(Path(out))

    kept = sorted(n for n in names if n not in drives)
    print(f"retarget: {out}: {len(poses)} frames at {fps / fps_base:g} fps, clip {name!r}")
    print(f"  hip height {target_hip:.4f} m / {source_hip:.4f} = scale {scale:.4f}")
    print(f"  driven bones: {len(drives)}; kept at the reference pose: {len(kept)}")
    ignored = sorted(j for j in joints if j not in bonemap)
    if ignored:
        print(f"  BVH joints not in the map (ignored): {', '.join(ignored)}")
    absent = sorted(s for s in bonemap if s not in joints)
    if absent:
        print(f"  mapped joints the BVH lacks: {', '.join(absent)}")


def main(argv=None):
    if argv is None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(prog="retarget.py", description=__doc__.split("\n\n")[0])
    parser.add_argument("--bvh", required=True, help="the BVH file to retarget (CMU joint names)")
    parser.add_argument("--map", required=True, help="the bone map JSON (tools/anim/bonemap_cmu.json)")
    parser.add_argument("--target", required=True, help="the GLB with the skeleton to retarget onto (abarax.glb)")
    parser.add_argument("--tpose", required=True, help="the GLB with the T-pose reference clip (UAL1_Standard.glb)")
    parser.add_argument("--tpose-clip", required=True, help="the clip in --tpose to take the reference from (A_TPose)")
    parser.add_argument("--out", required=True, help="the .glb to write")
    parser.add_argument("--name", required=True, help="the name of the animation in it")
    args = parser.parse_args(argv)
    try:
        retarget(args.bvh, load_bonemap(args.map), args.target, args.tpose, args.tpose_clip, args.out, args.name)
    except RetargetError as error:
        print(f"retarget.py: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
