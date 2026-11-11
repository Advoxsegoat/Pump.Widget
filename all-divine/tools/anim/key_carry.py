#!/usr/bin/env python3
"""Writes the layers of the blade Knuckle's armed locomotion clips (assets/anim/layers/blade_{idle,walk,jog,sprint}.json).

    tools/.venv/bin/python -I tools/anim/key_carry.py          writes the four layer files (then rebuild the library)

The carry is the right arm held in a low guard: the hand a little out from the hip, and the sword, which lies along the hand's
thumb axis, pointing forward, outward and a little down where the camera sees it. CARRY turns the right arm's bones (degrees, YXZ
Euler x y z, in each bone's own frame) from where the idle clip has them on its first frame: that is the carry's pose, TARGET.
Each locomotion clip then keeps only a share of its own arm swing (SWING, 0 to 1) and takes the rest from the carry: its layer, a key
for every frame, is the turn that takes the clip's rotation of each bone to that mix (see ClipBuilder.apply_layer: the layer is
laid after the clip's own rotation). So the arm still moves with the stride, a little, and the sword stays where it shows.

It reads the base clips from the library (assets/anim/abarax/{idle,walk,jog,sprint}.tres, which have no layer) as text.
"""
import json
import math
import re
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
LAYERS = ROOT / "assets" / "anim" / "layers"
CLIPS = ROOT / "assets" / "anim" / "abarax"
RATE = 60  # layer keys are at the physics rate, one for every frame
# The turn of each bone from the idle clip's own first frame, degrees (YXZ Euler).
CARRY = {
    "upperarm_r": (0.0, 0.0, -30.0),
    "lowerarm_r": (0.0, 0.0, 0.0),
    "hand_r": (-50.0, 50.0, 0.0),
}
# How much of its own arm swing each clip keeps (the rest is the carry's pose).
SWING = {"idle": 0.1, "walk": 0.25, "jog": 0.25, "sprint": 0.25}


def quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return np.array([aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz])


def quat_inv(q):
    return np.array([-q[0], -q[1], -q[2], q[3]])


def slerp(a, b, t):
    d = float(np.dot(a, b))
    if d < 0.0:
        b, d = -b, -d
    if d > 0.9995:
        q = a + (b - a) * t
        return q / np.linalg.norm(q)
    theta = math.acos(d)
    return (math.sin((1 - t) * theta) * a + math.sin(t * theta) * b) / math.sin(theta)


def from_euler_yxz(x, y, z):
    """The quaternion of Godot's Basis.from_euler(Vector3(x, y, z), YXZ): R = Ry * Rx * Rz (radians)."""
    qy = np.array([0, math.sin(y / 2), 0, math.cos(y / 2)])
    qx = np.array([math.sin(x / 2), 0, 0, math.cos(x / 2)])
    qz = np.array([0, 0, math.sin(z / 2), math.cos(z / 2)])
    return quat_mul(quat_mul(qy, qx), qz)


def to_euler_yxz(q):
    """Godot's Basis.get_euler(YXZ) of the quaternion, radians (x, y, z)."""
    x, y, z, w = q
    r01 = 2 * (x * y - z * w)
    r02 = 2 * (x * z + y * w)
    r10 = 2 * (x * y + z * w)
    r11 = 1 - 2 * (x * x + z * z)
    r12 = 2 * (y * z - x * w)
    r22 = 1 - 2 * (x * x + y * y)
    pitch = math.asin(max(-1.0, min(1.0, -r12)))
    if abs(r12) < 0.99999:
        return pitch, math.atan2(r02, r22), math.atan2(r10, r11)
    return pitch, math.atan2(-r01, 1 - 2 * (y * y + z * z)), 0.0


def read_clip(name):
    """{bone: (times, quaternions)} of the rotation tracks of a library clip, and the clip's length."""
    text = (CLIPS / f"{name}.tres").read_text()
    length = float(re.search(r"^length = ([0-9.]+)", text, re.M).group(1))
    tracks = {}
    for m in re.finditer(r'tracks/\d+/path = NodePath\("Model/Armature/Skeleton3D:(\w+)"\)\ntracks/\d+/interp = \d+\ntracks/\d+/loop_wrap = \w+\ntracks/\d+/keys = PackedFloat32Array\(([^)]*)\)', text):
        bone = m.group(1)
        if bone not in CARRY:
            continue
        values = [float(v) for v in m.group(2).split(",")]
        if len(values) % 6:  # a position track (five values a key: t, transition, x, y, z)
            continue
        keys = np.array(values).reshape(-1, 6)
        tracks[bone] = (keys[:, 0], keys[:, 2:6])
    return tracks, length


def sample(track, time):
    times, quats = track
    time = min(max(time, 0.0), float(times[-1]))
    i = int(np.searchsorted(times, time, side="right")) - 1
    i = min(max(i, 0), len(times) - 2)
    span = float(times[i + 1] - times[i])
    t = 0.0 if span <= 0 else (time - float(times[i])) / span
    return slerp(quats[i], quats[i + 1], t)


def main():
    idle, _ = read_clip("idle")
    target = {bone: quat_mul(sample(idle[bone], 0.0), from_euler_yxz(*[math.radians(a) for a in CARRY[bone]])) for bone in CARRY}
    for clip, swing in SWING.items():
        tracks, length = read_clip(clip)
        frames = round(length * RATE)
        layer = {}
        for bone in CARRY:
            keys = []
            previous = None
            for f in range(frames + 1):
                own = sample(tracks[bone], f / RATE)
                wanted = slerp(target[bone], own, swing)
                turn = quat_mul(quat_inv(own), wanted)
                euler = np.degrees(to_euler_yxz(turn))
                if previous is not None:  # no jump of 360 degrees between neighbouring keys
                    euler = previous + (euler - previous + 180.0) % 360.0 - 180.0
                previous = euler
                keys.append([f, *[round(float(a), 3) for a in euler]])
            layer[bone] = keys
        (LAYERS / f"blade_{clip}.json").write_text(json.dumps(layer) + "\n")
        print(f"key_carry: blade_{clip}: {frames + 1} keys a bone")


if __name__ == "__main__":
    main()
