# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Build the owned Desert Dreams player characters, rigs, clips, GLBs and previews.

Run with Blender 5.2+: blender -b --factory-startup --python this_file -- [--character man|woman]
Coordinates are metres, feet at Z=0, facing Blender +Y (glTF/Godot -Z).

The body is one smooth surface grown from a skin graph, with a sculpted head,
layered clothing shells, distance-weighted skinning to the eighteen-bone rig and
procedurally keyed idle, walk, run and jump cycles. Every construction part keeps
its name so the saved master stays editable.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector, Matrix


ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--character", choices=("man", "woman"), default="man")
parser.add_argument("--skip-render", action="store_true")
parser.add_argument("--stage", help="write master/GLB/previews under this directory instead of the project")
parser.add_argument("--debug-colors", action="store_true", help="give every construction part its own flat color")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
WOMAN = args.character == "woman"
MODEL = "pedestrian_woman" if WOMAN else "pedestrian"
if args.stage:
    STAGE = Path(args.stage).resolve()
    SOURCE = STAGE / "assets/blender-exploration"
    GLB = STAGE / ("game/assets/desert-dreams-exploration/" + MODEL + ".glb")
else:
    SOURCE = ROOT / "assets/blender-exploration"
    GLB = ROOT / ("game/assets/desert-dreams-exploration/" + MODEL + ".glb")
PREVIEWS = SOURCE / "previews"
for folder in (SOURCE, PREVIEWS, GLB.parent):
    folder.mkdir(parents=True, exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for datablocks in (bpy.data.meshes, bpy.data.armatures, bpy.data.actions, bpy.data.materials):
    for datablock in list(datablocks):
        if datablock.users == 0:
            datablocks.remove(datablock)

scene = bpy.context.scene
scene.render.fps = 24
scene.render.fps_base = 1.0
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
FPS = 24


def material(name, rgb, roughness=0.72, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    node = mat.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value = (*rgb, 1)
    node.inputs["Roughness"].default_value = roughness
    node.inputs["Metallic"].default_value = metallic
    return mat


# Shared desert palette; the two characters wear it in different combinations.
M = {
    "teal": material("01 Desert teal cloth", (0.075, 0.34, 0.35), 0.78),
    "teal_dark": material("02 Deep teal trim", (0.025, 0.19, 0.22), 0.78),
    "copper": material("03 Oxide copper cloth", (0.53, 0.24, 0.14), 0.78),
    "skin": material("04 Warm sand skin", (0.76, 0.50, 0.33), 0.62),
    "hair": material("05 Dark umber hair", (0.085, 0.062, 0.052), 0.55),
    "shoes": material("06 Worn walnut leather", (0.19, 0.115, 0.08), 0.45),
    "brass": material("07 Brushed brass hardware", (0.72, 0.51, 0.22), 0.38, 0.55),
    "cream": material("08 Sunbleached canvas", (0.86, 0.78, 0.60), 0.80),
    "eye": material("09 Eye white", (0.93, 0.91, 0.87), 0.30),
    "lips": material("10 Terracotta lips", (0.62, 0.30, 0.24), 0.50),
}

# ---------------------------------------------------------------------------
# Proportions. Everything below reads from P so the two bodies stay editable in
# one place. Heights keep the finished figure below the 1.84 m actor ceiling.
# ---------------------------------------------------------------------------
if WOMAN:
    P = dict(
        height=1.70, pelvis=0.905, waist=1.03, chest=1.26, shoulder_z=1.395, shoulder_x=0.175,
        neck_base=1.44, head_base=1.505, head_center=1.615, head_rx=0.098, head_ry=0.102, head_rz=0.115,
        elbow=(0.212, 1.145), wrist=(0.222, 0.925), hand=(0.224, 0.835),
        hip_x=0.098, knee=(0.100, 0.505), ankle=(0.102, 0.105),
        pelvis_r=(0.172, 0.112), waist_r=(0.128, 0.096), chest_r=(0.150, 0.118), shoulder_r=(0.082, 0.082),
        upper_arm_r=0.046, elbow_r=0.040, forearm_r=0.037, wrist_r=0.031,
        thigh_r=(0.082, 0.088), knee_r=0.062, shin_r=0.055, ankle_r=0.042,
        neck_r=0.046,
    )
else:
    P = dict(
        height=1.80, pelvis=0.955, waist=1.08, chest=1.33, shoulder_z=1.475, shoulder_x=0.196,
        neck_base=1.525, head_base=1.585, head_center=1.695, head_rx=0.104, head_ry=0.106, head_rz=0.122,
        elbow=(0.230, 1.205), wrist=(0.238, 0.975), hand=(0.240, 0.880),
        hip_x=0.102, knee=(0.105, 0.530), ankle=(0.108, 0.110),
        pelvis_r=(0.162, 0.112), waist_r=(0.146, 0.104), chest_r=(0.176, 0.124), shoulder_r=(0.090, 0.088),
        upper_arm_r=0.052, elbow_r=0.045, forearm_r=0.042, wrist_r=0.034,
        thigh_r=(0.086, 0.092), knee_r=0.066, shin_r=0.058, ankle_r=0.045,
        neck_r=0.052,
    )

# ---------------------------------------------------------------------------
# Rig
# ---------------------------------------------------------------------------
arm_data = bpy.data.armatures.new("PedestrianSkeleton")
rig = bpy.data.objects.new("Armature", arm_data)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")


def bone(name, head, tail, parent=None):
    b = arm_data.edit_bones.new(name)
    b.head = head
    b.tail = tail
    if parent:
        b.parent = arm_data.edit_bones[parent]
    return b


bone("Root", (0, 0, 0), (0, 0, P["pelvis"]))
bone("Hips", (0, 0, P["pelvis"]), (0, 0, P["waist"] + 0.03), "Root")
bone("Spine", (0, 0, P["waist"] + 0.03), (0, 0, P["chest"] + 0.03), "Hips")
bone("Chest", (0, 0, P["chest"] + 0.03), (0, 0, P["neck_base"]), "Spine")
bone("Neck", (0, 0, P["neck_base"]), (0, 0, P["head_base"]), "Chest")
bone("Head", (0, 0, P["head_base"]), (0, 0, P["head_center"] + P["head_rz"] * 0.8), "Neck")
for side, sign in (("Left", -1), ("Right", 1)):
    sx, sz = P["shoulder_x"], P["shoulder_z"]
    ex, ez = P["elbow"]
    wx, wz = P["wrist"]
    hx, hz = P["hand"]
    bone(side + "UpperArm", (sign * sx, 0, sz), (sign * ex, 0, ez), "Chest")
    bone(side + "Forearm", (sign * ex, 0, ez), (sign * wx, 0, wz), side + "UpperArm")
    bone(side + "Hand", (sign * wx, 0, wz), (sign * hx, 0.01, hz), side + "Forearm")
    kx, kz = P["knee"]
    ax, az = P["ankle"]
    bone(side + "Thigh", (sign * P["hip_x"], 0, P["pelvis"] - 0.02), (sign * kx, 0, kz), "Hips")
    bone(side + "Shin", (sign * kx, 0, kz), (sign * ax, 0, az), side + "Thigh")
    bone(side + "Foot", (sign * ax, 0, az), (sign * ax, 0.11, 0.035), side + "Shin")
bpy.ops.object.mode_set(mode="OBJECT")
rig.select_set(False)
rig.show_in_front = False

BONE_SEGMENTS = {b.name: (Vector(b.head_local), Vector(b.tail_local)) for b in arm_data.bones}

parts = []
PART_BONES = {}


def segment_distance(point, a, b):
    ab = b - a
    length2 = ab.length_squared
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, (point - a).dot(ab) / length2))
    return (point - (a + ab * t)).length


DEBUG_INDEX = [0]


def register(obj, mat, bones):
    """Smooth shading, one material, skinning to the named bones with soft falloff."""
    if args.debug_colors:
        DEBUG_INDEX[0] += 1
        hue = (DEBUG_INDEX[0] * 0.381966) % 1.0
        import colorsys
        obj.data.materials.append(material("Debug %02d %s" % (DEBUG_INDEX[0], obj.name), colorsys.hsv_to_rgb(hue, 0.85, 0.95)))
        print("DEBUG_PART", DEBUG_INDEX[0], obj.name)
    else:
        obj.data.materials.append(M[mat])
    for poly in obj.data.polygons:
        poly.use_smooth = True
    PART_BONES[obj.name] = bones
    modifier = obj.modifiers.new("Skinned to PedestrianSkeleton", "ARMATURE")
    modifier.object = rig
    obj.parent = rig
    parts.append(obj)
    return obj


# Influence radius per bone: larger values spread a bone's pull further.
RADIUS = {
    "Hips": 0.20, "Spine": 0.24, "Chest": 0.24, "Neck": 0.07, "Head": 0.16,
    "LeftUpperArm": 0.075, "RightUpperArm": 0.075, "LeftForearm": 0.065, "RightForearm": 0.065,
    "LeftHand": 0.07, "RightHand": 0.07, "LeftThigh": 0.11, "RightThigh": 0.11,
    "LeftShin": 0.085, "RightShin": 0.085, "LeftFoot": 0.08, "RightFoot": 0.08,
}


def weigh(obj, bones):
    """Distance-weighted skinning, limited to four smooth influences per vertex."""
    groups = {name: obj.vertex_groups.new(name=name) for name in bones}
    matrix = obj.matrix_world
    for vertex in obj.data.vertices:
        point = matrix @ vertex.co
        scores = []
        for name in bones:
            a, b = BONE_SEGMENTS[name]
            d = segment_distance(point, a, b)
            scores.append((math.exp(-(d / RADIUS[name]) ** 2 * 2.2), name))
        scores.sort(reverse=True)
        chosen = [(w, n) for w, n in scores[:4] if w > scores[0][0] * 0.02]
        total = sum(w for w, _ in chosen)
        for w, name in chosen:
            groups[name].add([vertex.index], w / total, "REPLACE")


# ---------------------------------------------------------------------------
# Skin-graph shells: a vertex per joint with a cross-section radius, grown
# into one closed quad surface and subdivided once for smooth silhouettes.
# ---------------------------------------------------------------------------
def cut_faces(obj, open_ends=(), covered=()):
    """Open a shell with clean planar cuts, and drop faces hidden under clothing."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for origin, direction in open_ends:
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(origin), plane_no=Vector(direction).normalized(),
            clear_outer=True, clear_inner=False)
    if covered:
        doomed = [face for face in bm.faces if any(test(face.calc_center_median()) for test in covered)]
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()


def solidify(obj, thickness):
    """Give an open shell a visible fabric thickness, keeping its outer surface."""
    mod = obj.modifiers.new("Fabric", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = -1.0
    mod.use_rim = True
    mod.use_even_offset = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def skin_shell(name, nodes, edges, root, mat, bones, subdivisions=1, open_ends=(), smoothing=0.0, covered=(), thickness=0.0):
    mesh = bpy.data.meshes.new(name + "Mesh")
    names = list(nodes)
    mesh.from_pydata([nodes[n][0] for n in names], [(names.index(a), names.index(b)) for a, b in edges], [])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.use_smooth_shade = True
    skin.branch_smoothing = smoothing
    for index, n in enumerate(names):
        radius = nodes[n][1]
        if not isinstance(radius, tuple):
            radius = (radius, radius)
        obj.data.skin_vertices[0].data[index].radius = radius
        obj.data.skin_vertices[0].data[index].use_root = n == root
    subsurf = obj.modifiers.new("Smooth", "SUBSURF")
    subsurf.levels = subdivisions
    subsurf.render_levels = subdivisions
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier="Skin")
    bpy.ops.object.modifier_apply(modifier="Smooth")
    obj.select_set(False)
    if open_ends or covered:
        cut_faces(obj, open_ends, covered)
    if thickness:
        solidify(obj, thickness)
    return register(obj, mat, bones)


def sphere_cap(name, center, radii, planes, mat, bones, segments=32, rings=20, thickness=0.0):
    """An ellipsoid trimmed by planes with clean bisected edges; used for hair."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = radii
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for point, normal in planes:
        local_point = Vector(point) - Vector(center)
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=local_point, plane_no=Vector(normal).normalized(),
            clear_inner=True, clear_outer=False)
    bm.to_mesh(obj.data)
    bm.free()
    if thickness:
        solidify(obj, thickness)
    return register(obj, mat, bones)


def ellipsoid(name, center, radii, mat, bones, segments=16, rings=10, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = radii
    obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return register(obj, mat, bones)


def rounded_box(name, center, size, mat, bones, bevel=0.01, segments=3, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new("Rounded", "BEVEL")
    mod.width = min(bevel, min(size) * 0.45)
    mod.segments = segments
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return register(obj, mat, bones)


def torus_ring(name, center, major, minor, mat, bones, scale=(1, 1, 1), rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(location=center, major_radius=major, minor_radius=minor,
        major_segments=24, minor_segments=8)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return register(obj, mat, bones)


S = P
sx, sz = S["shoulder_x"], S["shoulder_z"]
ex, ez = S["elbow"]
wx, wz = S["wrist"]
hx, hz = S["hand"]
kx, kz = S["knee"]
ax, az = S["ankle"]
ALL = [n for n in RADIUS]
TORSO = ["Hips", "Spine", "Chest", "Neck"]
LEGS = ["Hips", "LeftThigh", "RightThigh", "LeftShin", "RightShin"]
GAP = 0.013
trouser_top = S["waist"] - 0.045 if WOMAN else S["waist"] - 0.085
cuff_z = kz - 0.19 if WOMAN else az + 0.03
shirt_hem = S["waist"] - 0.03 if WOMAN else S["waist"] - 0.07

# --- Body: the skin surface that shows at the neck, arms, hands and ankles.
# Faces hidden under clothing are removed so nothing pokes through the cloth.
sleeve_end = 0.30 if WOMAN else 0.52
sleeve_cuff_z = sz + (ez - sz) * sleeve_end


def under_cloth(c):
    if c.z <= cuff_z + 0.035 or c.z >= S["neck_base"] - 0.006:
        return False
    if c.z < S["pelvis"] + 0.06:
        return abs(c.x) < S["hip_x"] + S["thigh_r"][0] + 0.03
    if c.z > S["neck_base"] - 0.035 and math.hypot(c.x, c.y - 0.004) < 0.066:
        return False  # the neck column fills the collar opening
    if abs(c.x) > sx - 0.04 and c.z < sleeve_cuff_z + 0.02:
        return False  # the arm shows below the sleeve
    return abs(c.x) < sx + 0.05


body_covered = [under_cloth]
body_nodes = {
    "pelvis": ((0, 0, S["pelvis"]), S["pelvis_r"]),
    "waist": ((0, 0.005, S["waist"]), S["waist_r"]),
    "chest": ((0, 0, S["chest"]), S["chest_r"]),
    "collar": ((0, 0, S["shoulder_z"] - 0.01), (S["shoulder_x"] - 0.03, S["chest_r"][1] * 0.86)),
    "neck": ((0, 0.004, S["neck_base"] + 0.01), S["neck_r"]),
    "neck_top": ((0, 0.006, S["head_base"] + 0.04), S["neck_r"] * 0.96),
}
body_edges = [("pelvis", "waist"), ("waist", "chest"), ("chest", "collar"), ("collar", "neck"), ("neck", "neck_top")]
for side, sign in (("L", -1), ("R", 1)):
    body_nodes.update({
        side + "shoulder": ((sign * sx, 0, sz), S["shoulder_r"][0] * 0.74),
        side + "upper_arm": ((sign * (sx + ex) / 2, 0, (sz + ez) / 2 + 0.01), S["upper_arm_r"]),
        side + "elbow": ((sign * ex, 0, ez), S["elbow_r"]),
        side + "forearm": ((sign * (ex + wx) / 2, 0, (ez + wz) / 2), S["forearm_r"]),
        side + "wrist": ((sign * wx, 0, wz), S["wrist_r"]),
        side + "palm": ((sign * (wx - 0.002), 0.004, wz - 0.045), (S["wrist_r"] * 1.22, S["wrist_r"] * 0.62)),
        side + "fingers": ((sign * (hx - 0.006), 0.006, hz - 0.035), (S["wrist_r"] * 0.95, S["wrist_r"] * 0.5)),
        side + "thumb": ((sign * (wx - 0.030), 0.03, wz - 0.052), S["wrist_r"] * 0.42),
        side + "hip": ((sign * S["hip_x"], 0, S["pelvis"] - 0.03), S["thigh_r"]),
        side + "thigh": ((sign * (S["hip_x"] + kx) / 2, 0.004, (S["pelvis"] + kz) / 2), (S["thigh_r"][0] * 0.92, S["thigh_r"][1] * 0.92)),
        side + "knee": ((sign * kx, 0.004, kz), S["knee_r"]),
        side + "shin": ((sign * (kx + ax) / 2, 0.0, (kz + az) / 2), S["shin_r"]),
        side + "ankle": ((sign * ax, 0, az), S["ankle_r"]),
        side + "ankle_end": ((sign * ax, 0.004, 0.055), S["ankle_r"] * 0.9),
    })
    body_edges += [("collar", side + "shoulder"), (side + "shoulder", side + "upper_arm"), (side + "upper_arm", side + "elbow"),
        (side + "elbow", side + "forearm"), (side + "forearm", side + "wrist"), (side + "wrist", side + "palm"),
        (side + "palm", side + "fingers"), (side + "palm", side + "thumb"),
        ("pelvis", side + "hip"), (side + "hip", side + "thigh"), (side + "thigh", side + "knee"),
        (side + "knee", side + "shin"), (side + "shin", side + "ankle"), (side + "ankle", side + "ankle_end")]
skin_shell("Body skin", body_nodes, body_edges, "pelvis", "skin", ALL, subdivisions=1, smoothing=0.3, covered=body_covered)

# --- Clothing shells sit a little outside the body.
if WOMAN:
    # Cream blouse with cap sleeves, tucked into high-waist teal capris.
    shirt_nodes = {
        "hem": ((0, 0.004, shirt_hem - 0.02), (S["waist_r"][0] + GAP * 0.7, S["waist_r"][1] + GAP * 0.7)),
        "waist": ((0, 0.005, S["waist"] + 0.04), (S["waist_r"][0] + GAP, S["waist_r"][1] + GAP)),
        "chest": ((0, 0.004, S["chest"]), (S["chest_r"][0] + GAP, S["chest_r"][1] + GAP * 1.3)),
        "collar": ((0, 0, S["shoulder_z"] - 0.010), (S["shoulder_x"] - 0.03 + GAP * 1.6, S["chest_r"][1] * 0.86 + GAP * 1.8)),
        "neck": ((0, 0.004, S["neck_base"] + 0.008), S["neck_r"] + GAP * 1.4),
    }
    shirt_mat, trouser_mat = "cream", "teal"
else:
    # Teal camp shirt with short sleeves, worn loose over copper trousers.
    shirt_nodes = {
        "hem": ((0, 0.004, shirt_hem - 0.02), (S["waist_r"][0] + GAP * 1.8, S["waist_r"][1] + GAP * 1.8)),
        "waist": ((0, 0.005, S["waist"] + 0.04), (S["waist_r"][0] + GAP * 1.6, S["waist_r"][1] + GAP * 1.5)),
        "chest": ((0, 0.004, S["chest"]), (S["chest_r"][0] + GAP, S["chest_r"][1] + GAP * 1.2)),
        "collar": ((0, 0, S["shoulder_z"] - 0.010), (S["shoulder_x"] - 0.03 + GAP * 1.6, S["chest_r"][1] * 0.86 + GAP * 1.8)),
        "neck": ((0, 0.004, S["neck_base"] + 0.008), S["neck_r"] + GAP * 1.4),
    }
    shirt_mat, trouser_mat = "teal", "copper"
# Shoulder branches round the yoke; two subdivision levels soften the frames.
shirt_edges = [("hem", "waist"), ("waist", "chest"), ("chest", "collar"), ("collar", "neck")]
for side, sign in (("L", -1), ("R", 1)):
    shirt_nodes[side + "shoulder"] = ((sign * (sx - 0.012), 0, sz - 0.004), S["shoulder_r"][0] * 0.74 + GAP * 1.6)
    shirt_edges.append(("collar", side + "shoulder"))
# The hem is a planar cut hidden inside the trousers. The neck is a local
# circular opening so the shoulder tops stay closed; its edge sits under the
# collar band or scarf.
NECK_OPENING = 0.088
skin_shell("Shirt", shirt_nodes, shirt_edges, "chest", shirt_mat, TORSO + ["LeftUpperArm", "RightUpperArm"], subdivisions=2,
    open_ends=[((0, 0, shirt_hem), (0, 0, -1))],
    covered=[lambda c: c.z > S["neck_base"] - 0.012 and math.hypot(c.x, c.y - 0.004) < NECK_OPENING],
    smoothing=0.3)
for side, sign in (("Left", -1), ("Right", 1)):
    shoulder = Vector((sign * sx, 0, sz))
    elbow = Vector((sign * ex, 0, ez))
    direction = (elbow - shoulder).normalized()
    cuff = shoulder + (elbow - shoulder) * sleeve_end
    sleeve_nodes = {
        # The inner end tapers to a point inside the torso so no cap shows.
        "root": (tuple(shoulder - Vector((sign * 0.05, 0, 0.012))), 0.022),
        "shoulder": (tuple(shoulder + Vector((0, 0, 0.004))), S["shoulder_r"][0] * 0.74 + GAP * 1.5),
        "cuff": (tuple(cuff), S["upper_arm_r"] + GAP * 1.15),
        "end": (tuple(cuff + direction * 0.06), S["upper_arm_r"] + GAP * 1.2),
    }
    skin_shell(side + " sleeve", sleeve_nodes, [("root", "shoulder"), ("shoulder", "cuff"), ("cuff", "end")], "root",
        shirt_mat, ["Chest", side + "UpperArm"], subdivisions=1,
        open_ends=[(tuple(cuff + direction * 0.015), tuple(direction))], smoothing=0.2, thickness=0.006)

trouser_nodes = {
    "waist": ((0, 0.004, trouser_top + 0.03), (S["waist_r"][0] + GAP * 2.1 + (0.004 if WOMAN else 0.012),
        S["waist_r"][1] + GAP * 2.1 + (0.004 if WOMAN else 0.012))),
    "pelvis": ((0, 0, S["pelvis"] - 0.01), (S["pelvis_r"][0] + GAP, S["pelvis_r"][1] + GAP)),
}
trouser_edges = [("waist", "pelvis")]
open_ends = [((0, 0, trouser_top + 0.03), (0, 0, 1))]
for side, sign in (("L", -1), ("R", 1)):
    if side == "R":
        open_ends.pop()
    trouser_nodes.update({
        side + "hip": ((sign * S["hip_x"], 0, S["pelvis"] - 0.035), (S["thigh_r"][0] + GAP, S["thigh_r"][1] + GAP)),
        side + "thigh": ((sign * (S["hip_x"] + kx) / 2, 0.004, (S["pelvis"] + kz) / 2), (S["thigh_r"][0] * 0.92 + GAP, S["thigh_r"][1] * 0.92 + GAP)),
        side + "knee": ((sign * kx, 0.004, kz), S["knee_r"] + GAP),
        side + "cuff": ((sign * (kx if WOMAN else ax), 0.002, cuff_z + 0.03), (S["shin_r"] + GAP * 1.3 if WOMAN else S["ankle_r"] + GAP * 2.2)),
        side + "cuff_end": ((sign * (kx if WOMAN else ax), 0.002, cuff_z - 0.03), (S["shin_r"] + GAP * 1.3 if WOMAN else S["ankle_r"] + GAP * 2.2)),
    })
    trouser_edges += [("pelvis", side + "hip"), (side + "hip", side + "thigh"), (side + "thigh", side + "knee"),
        (side + "knee", side + "cuff"), (side + "cuff", side + "cuff_end")]
    open_ends.append(((0, 0, cuff_z), (0, 0, -1)))
skin_shell("Trousers", trouser_nodes, trouser_edges, "pelvis", trouser_mat, LEGS, subdivisions=1,
    open_ends=open_ends, smoothing=0.25, thickness=0.006 if WOMAN else 0.0)

# --- Belt and shirt details.
belt_z = trouser_top + 0.018
belt_r = (S["waist_r"][0] + GAP * 2.1 + (0.004 if WOMAN else 0.012), S["waist_r"][1] + GAP * 2.1 + (0.004 if WOMAN else 0.012))
belt = torus_ring("Leather belt", (0, 0.004, belt_z), 1.0, 0.014, "teal_dark" if WOMAN else "shoes", ["Hips"],
    scale=(belt_r[0] + 0.006, belt_r[1] + 0.006, 1.0))
rounded_box("Brass buckle", (0, belt_r[1] + 0.012, belt_z), (0.046, 0.016, 0.034), "brass", ["Hips"], bevel=0.004)
collar_z = S["neck_base"] - 0.012
band_r = 0.0875
if not WOMAN:
    torus_ring("Collar band", (0, 0.004, collar_z), 1.0, 0.0175, "cream", ["Chest", "Neck"], scale=(band_r, band_r, 1.0))
if not WOMAN:
    rounded_box("Shirt placket", (0, S["chest_r"][1] + GAP * 1.2 + 0.002, S["chest"] - 0.02), (0.02, 0.012, 0.30), "cream", ["Spine", "Chest"], bevel=0.003)
    for z in (S["chest"] - 0.10, S["chest"], S["chest"] + 0.10):
        ellipsoid("Brass button %.2f" % z, (0, S["chest_r"][1] + GAP * 1.2 + 0.009, z), (0.007, 0.004, 0.007), "brass", ["Spine", "Chest"], 10, 6)
    rounded_box("Chest pocket", (-0.095, S["chest_r"][1] + GAP * 1.2 + 0.002, S["chest"] + 0.02), (0.085, 0.010, 0.09), "teal_dark", ["Chest"], bevel=0.004)
else:
    rounded_box("Blouse front seam", (0, S["chest_r"][1] + GAP * 1.3 + 0.001, S["chest"] - 0.04), (0.012, 0.010, 0.24), "teal_dark", ["Spine", "Chest"], bevel=0.003)
    torus_ring("Copper neck scarf", (0, 0.004, collar_z), 1.0, 0.019, "copper", ["Chest", "Neck"],
        scale=(band_r, band_r, 1.0))
    rounded_box("Scarf knot", (0.055, 0.045, S["neck_base"] - 0.045), (0.036, 0.03, 0.05), "copper", ["Chest"], bevel=0.009, rotation=(0.2, 0.3, 0.5))

# --- Shoes: rounded leather forms with a low welt, planted on Z = 0.
for side, sign in (("Left", -1), ("Right", 1)):
    toe_length = 0.245 if WOMAN else 0.265
    rounded_box(side + " shoe", (sign * ax, 0.055, 0.042), (0.118 if WOMAN else 0.128, toe_length, 0.078), "shoes", [side + "Foot"], bevel=0.03, segments=4)
    rounded_box(side + " shoe welt", (sign * ax, 0.055, 0.009), (0.124 if WOMAN else 0.134, toe_length + 0.006, 0.018), "teal_dark", [side + "Foot"], bevel=0.007, segments=3)
    if WOMAN:
        rounded_box(side + " ankle strap", (sign * ax, 0.02, 0.09), (0.11, 0.1, 0.012), "shoes", [side + "Foot"], bevel=0.005)

# --- Head group, rigid to the Head bone.
H = ["Head"]
hc = Vector((0, 0.012, S["head_center"]))
rx, ry, rz = S["head_rx"], S["head_ry"], S["head_rz"]
ellipsoid("Head", tuple(hc), (rx, ry, rz), "skin", H, 32, 24)
# A gentle chin: slightly narrower than the skull and tucked under its curve.
ellipsoid("Nose", tuple(hc + Vector((0, ry - 0.003, -0.022))), (0.0135, 0.019, 0.020), "skin", H, 12, 8)
for side, sign in (("Left", -1), ("Right", 1)):
    ellipsoid(side + " ear", tuple(hc + Vector((sign * (rx - 0.002), -0.004, -0.014))), (0.011, 0.024, 0.034), "skin", H, 12, 8)
    eye_center = hc + Vector((sign * 0.031, ry - 0.0075, 0.014))
    ellipsoid(side + " eye", tuple(eye_center), (0.0165, 0.013, 0.0165), "eye", H, 16, 12)
    ellipsoid(side + " iris", tuple(eye_center + Vector((sign * -0.001, 0.0095, -0.001))), (0.0085, 0.005, 0.0085), "hair", H, 12, 8)
    rounded_box(side + " eyebrow", tuple(hc + Vector((sign * 0.033, ry - 0.001, 0.046))), (0.042, 0.007, 0.011), "hair", H, bevel=0.0025,
        rotation=(0.15, 0.0, sign * 0.10))
rounded_box("Mouth", tuple(hc + Vector((0, ry - 0.001, -0.062))), (0.036 if WOMAN else 0.040, 0.007, 0.011 if WOMAN else 0.008), "lips", H, bevel=0.0035)
if WOMAN:
    # Chin-length bob: crown cap with a tilted hairline, side/back curtain cut
    # behind the face, a swept fringe and a copper headband.
    sphere_cap("Bob crown", tuple(hc), (rx + 0.020, ry + 0.012, rz + 0.012),
        [(tuple(hc + Vector((0, 0, 0.012))), (0, -0.55, 1))], "hair", H, thickness=0.012)
    sphere_cap("Bob curtain", tuple(hc + Vector((0, -0.012, -0.030))), (rx + 0.026, ry + 0.010, rz + 0.030),
        [(tuple(hc + Vector((0, 0, -0.086))), (0, 0.10, 1)), (tuple(hc + Vector((0, ry * 0.42, 0))), (0, -1, 0))], "hair", H, thickness=0.012)
    ellipsoid("Swept fringe", tuple(hc + Vector((-0.018, ry * 0.58, 0.082))), (0.090, 0.046, 0.032), "hair", H, 20, 10, rotation=(0.0, 0.0, 0.16))
    for side, sign in (("Left", -1), ("Right", 1)):
        ellipsoid(side + " brass earring", tuple(hc + Vector((sign * (rx + 0.010), -0.004, -0.058))), (0.008, 0.008, 0.013), "brass", H, 10, 6)
    # The band lies in a plane tilted back from vertical, so it crosses the
    # crown behind the fringe and passes above the ears to the nape.
    tilt = 0.55
    band_normal = Vector((0, -math.sin(tilt), math.cos(tilt)))
    torus_ring("Copper headband", tuple(hc + band_normal * 0.040), 1.0, 0.0095, "copper", H,
        scale=(0.112, 0.112, 1.0), rotation=(tilt, 0, 0))
else:
    # Cropped hair: one cap with a tilted hairline and sideburns.
    sphere_cap("Hair crown", tuple(hc), (rx + 0.012, ry + 0.006, rz + 0.008),
        [(tuple(hc + Vector((0, 0, 0.010))), (0, -0.52, 1))], "hair", H, thickness=0.012)
    for side, sign in (("Left", -1), ("Right", 1)):
        rounded_box(side + " sideburn", tuple(hc + Vector((sign * (rx - 0.001), 0.010, 0.004))), (0.014, 0.036, 0.056), "hair", H, bevel=0.005)

# ---------------------------------------------------------------------------
# Weights, then join everything into one skinned mesh.
# ---------------------------------------------------------------------------
for obj in parts:
    weigh(obj, PART_BONES[obj.name])
for obj in bpy.context.selected_objects:
    obj.select_set(False)
for obj in parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
skinned_mesh = parts[0]
skinned_mesh.name = "PedestrianSkinnedMesh"
parts = [skinned_mesh]
# Keep a single armature modifier after the join.
for modifier in list(skinned_mesh.modifiers)[1:]:
    skinned_mesh.modifiers.remove(modifier)


def foot_height(side):
    """Lowest posed shoe vertex, in metres above the authored ground plane."""
    bpy.context.view_layer.update()
    group_index = skinned_mesh.vertex_groups[side + "Foot"].index
    evaluated = skinned_mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    low = min(
        (evaluated.matrix_world @ vertex.co).z
        for vertex in mesh.vertices
        if any(group.group == group_index and group.weight > 0.9 for group in vertex.groups)
    )
    evaluated.to_mesh_clear()
    return low


# ---------------------------------------------------------------------------
# Clips. Bone rotations are Euler XYZ in bone space: X bends forward/back,
# Z swings sideways, Y twists. The Root never moves; walking and running keep
# the lower shoe planted by solving the Hips height every frame.
# ---------------------------------------------------------------------------
CLIP_FRAMES = {"idle": 48, "walk": 24, "run": 14, "jump": 21}


def set_rot(bone_name, x=0, y=0, z=0):
    rig.pose.bones[bone_name].rotation_euler = (x, y, z)


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def idle(frame):
    t = (frame - 1) / CLIP_FRAMES["idle"]
    breath = math.sin(math.tau * t)
    shift = math.sin(math.tau * t * 0.5 - 0.6)
    set_rot("Hips", x=0.012 * breath, z=0.020 * shift)
    rig.pose.bones["Hips"].location.x = 0.014 * shift
    set_rot("Spine", x=0.020 * breath - 0.01, z=-0.018 * shift)
    set_rot("Chest", x=0.018 * breath)
    set_rot("Neck", x=-0.012 * breath, y=0.05 * math.sin(math.tau * t * 0.5 + 1.2))
    set_rot("Head", x=-0.02 - 0.010 * breath, y=0.06 * math.sin(math.tau * t * 0.5 + 1.2), z=0.012 * shift)
    for side, sign in (("Left", -1), ("Right", 1)):
        set_rot(side + "UpperArm", x=0.06 + 0.016 * math.sin(math.tau * t + sign * 0.8), z=sign * 0.07 + 0.012 * breath * sign)
        set_rot(side + "Forearm", x=0.18 + 0.02 * breath)
        set_rot(side + "Hand", x=0.06)
        set_rot(side + "Thigh", z=-sign * 0.02 * shift)
        set_rot(side + "Shin", x=-0.03)


def gait(frame, frames, swing, knee, lean, arm, elbow, bob_scale):
    t = (frame - 1) / frames
    phase = math.tau * t
    set_rot("Hips", x=lean * 0.35, y=0.10 * math.sin(phase) * swing / 0.43, z=0.055 * math.sin(phase))
    rig.pose.bones["Hips"].location.x = 0.012 * math.sin(phase) * bob_scale
    set_rot("Spine", x=lean, y=-0.07 * math.sin(phase) * swing / 0.43, z=-0.035 * math.sin(phase))
    set_rot("Chest", x=lean * 0.4, y=-0.05 * math.sin(phase) * swing / 0.43)
    set_rot("Neck", x=-lean * 0.6)
    set_rot("Head", x=-lean * 0.7 - 0.02, y=0.03 * math.sin(phase), z=0.02 * math.sin(phase))
    for side, sign in (("Left", 1), ("Right", -1)):
        stride = math.sin(phase) * sign
        # Swing phase begins at the rear of the stride; the knee folds most mid-swing.
        swing_t = ((t * sign + (0.25 if sign > 0 else 0.75)) % 1.0)
        lift = math.sin(math.pi * swing_t) ** 2 if swing_t < 1.0 else 0.0
        in_swing = 1.0 if 0.0 <= swing_t < 0.5 else 0.0
        fold = lift * in_swing
        strike = smoothstep(1.0 - abs(stride - 1.0) * 3.0)
        set_rot(side + "Thigh", x=swing * stride, z=-sign * 0.02)
        set_rot(side + "Shin", x=-(0.12 + knee * fold + 0.12 * strike))
        toe_off = smoothstep((-stride - 0.3) * 2.0) * (1.0 - in_swing)
        set_rot(side + "Foot", x=0.10 + 0.24 * toe_off - 0.18 * fold - 0.10 * strike)
        set_rot(side + "UpperArm", x=-arm * stride + 0.08, z=(-1 if side == "Left" else 1) * 0.10)
        set_rot(side + "Forearm", x=elbow + 0.18 * max(0.0, -stride))
        set_rot(side + "Hand", x=0.08)


def walk(frame):
    gait(frame, CLIP_FRAMES["walk"], swing=0.43, knee=0.62, lean=0.045, arm=0.30, elbow=0.30, bob_scale=1.0)


def run(frame):
    gait(frame, CLIP_FRAMES["run"], swing=0.70, knee=1.25, lean=0.17, arm=0.62, elbow=1.25, bob_scale=0.7)


def jump(frame):
    # Anticipation crouch, launch, tuck, then land in a soft knee bend.
    keys = [
        (1, 0.10, 0.28, -0.42, 0.18, -0.30, -0.25, 0.00),
        (4, 0.26, 0.60, -0.90, 0.30, -0.70, -0.55, 0.00),
        (7, -0.12, -0.10, -0.08, -0.25, 0.95, -0.30, 0.02),
        (10, -0.02, 0.55, -1.20, 0.35, 0.70, -0.65, 0.01),
        (14, 0.04, 0.20, -0.40, 0.15, 0.25, -0.45, 0.00),
        (18, 0.22, 0.48, -0.75, 0.25, -0.35, -0.50, 0.00),
        (21, 0.06, 0.12, -0.22, 0.10, -0.10, -0.25, 0.00),
    ]
    prev = keys[0]
    for key in keys:
        if key[0] >= frame:
            nxt = key
            break
        prev = key
    else:
        nxt = keys[-1]
    span = max(1, nxt[0] - prev[0])
    u = smoothstep((frame - prev[0]) / span) if nxt[0] != prev[0] else 1.0
    torso, thigh, shin, foot, arm, elbow, hips_y = [prev[i] + (nxt[i] - prev[i]) * u for i in range(1, 8)]
    set_rot("Hips", x=torso * 0.3)
    set_rot("Spine", x=torso)
    set_rot("Chest", x=torso * 0.5)
    set_rot("Head", x=-torso * 0.6)
    rig.pose.bones["Hips"].location.y = hips_y
    for side, sign in (("Left", -1), ("Right", 1)):
        set_rot(side + "Thigh", x=thigh, z=-sign * 0.03)
        set_rot(side + "Shin", x=shin)
        set_rot(side + "Foot", x=foot)
        set_rot(side + "UpperArm", x=arm, z=sign * 0.22)
        set_rot(side + "Forearm", x=-elbow)


def action(name, sampler, ground_feet=False):
    act = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = act
    frames = range(1, CLIP_FRAMES[name] + 1)
    for frame in frames:
        scene.frame_set(frame)
        for pb in rig.pose.bones:
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = (0, 0, 0)
            pb.location = (0, 0, 0)
        sampler(frame)
        for pb in rig.pose.bones:
            pb.keyframe_insert(data_path="rotation_euler", frame=frame, group=pb.name)
        rig.pose.bones["Hips"].keyframe_insert(data_path="location", frame=frame, group="Hips")
    rig.animation_data.action = None
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 1, act)
    strip.action_frame_start = 1
    strip.action_frame_end = CLIP_FRAMES[name]
    return act, track


clips = {
    "idle": action("idle", idle),
    "walk": action("walk", walk, ground_feet=True),
    "run": action("run", run, ground_feet=True),
    "jump": action("jump", jump),
}
for _, track in clips.values():
    track.mute = True

# Settle the lower shoe onto the ground for every frame of each clip. Solving
# against the finished action avoids stale evaluated poses. Airborne jump
# frames keep the launch height so the tucked feet visibly leave the ground.
AIRBORNE = range(8, 15)
for clip_name in ("idle", "walk", "run", "jump"):
    rig.animation_data.action = clips[clip_name][0]
    for _ in range(3):
        launch_height = None
        for frame in range(1, CLIP_FRAMES[clip_name] + 1):
            scene.frame_set(frame)
            hips = rig.pose.bones["Hips"]
            if clip_name == "jump" and frame in AIRBORNE:
                hips.location.y = launch_height
            else:
                gap = min(foot_height("Left"), foot_height("Right"))
                hips.location.y -= gap
                launch_height = hips.location.y
            hips.keyframe_insert(data_path="location", frame=frame, group="Hips")
rig.animation_data.action = None


def activate_pose(clip, frame):
    for _, track in clips.values():
        track.mute = True
    rig.animation_data.action = clips[clip][0]
    scene.frame_set(frame)
    bpy.context.view_layer.update()


# ---------------------------------------------------------------------------
# Preview studio (never exported), master save, GLB export and measurements.
# ---------------------------------------------------------------------------
bpy.ops.object.camera_add(location=(2.9, 5.4, 2.25))
camera = bpy.context.object
camera.name = "Preview three-quarter camera"
direction = Vector((0, 0, 1.0)) - camera.location
camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 2.55
scene.camera = camera

bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.011))
floor = bpy.context.object
floor.name = "Preview sand floor (not exported)"
floor.data.materials.append(material("Preview only warm ground", (.31, .25, .18)))
for name, location, energy, size in (
    ("Warm key", (2.1, 3.5, 5.1), 650, 3.5),
    ("Cool fill", (-3.6, 1.6, 3.4), 360, 4.0),
):
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    light.rotation_euler = (Vector((0, 0, 1)) - light.location).to_track_quat("-Z", "Y").to_euler()
scene.world.color = (.25, .22, .18)

scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.render.resolution_x = 1024
scene.render.resolution_y = 1024
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "AgX"
scene.render.image_settings.file_format = "PNG"

activate_pose("idle", 1)
scene.frame_end = CLIP_FRAMES["idle"]
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / (MODEL + ".blend")))

for obj in bpy.context.selected_objects:
    obj.select_set(False)
rig.select_set(True)
for obj in parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig
rig.animation_data.action = None
for _, track in clips.values():
    track.mute = False
bpy.ops.export_scene.gltf(filepath=str(GLB), export_format="GLB", use_selection=True,
    export_animations=True, export_animation_mode="NLA_TRACKS",
    export_merge_animation="NLA_TRACK", export_nla_strips=True,
    export_skins=True, export_yup=True, export_cameras=False, export_lights=False,
    export_materials="EXPORT", export_apply=False)

for clip, frame, filename in (
    ("idle", 1, "pedestrian-idle-three-quarter.png"),
    ("walk", 7, "pedestrian-walk-pose.png"),
    ("run", 4, "pedestrian-run-pose.png"),
):
    activate_pose(clip, frame)
    print("POSE_GROUND", clip, frame, foot_height("Left"), foot_height("Right"), tuple(rig.pose.bones["Hips"].location))
    scene.render.filepath = str(PREVIEWS / filename.replace("pedestrian", MODEL))
    if not args.skip_render:
        bpy.ops.render.render(write_still=True)
camera.location = (2.9, -5.4, 2.25)
camera.rotation_euler = (Vector((0, 0, 1.0)) - camera.location).to_track_quat("-Z", "Y").to_euler()
activate_pose("idle", 1)
scene.render.filepath = str(PREVIEWS / (MODEL + "-back-three-quarter.png"))
if not args.skip_render:
    bpy.ops.render.render(write_still=True)
# A tight face study from the front, for checking features at close range.
camera.location = (0.9, 3.2, S["head_center"] + 0.35)
camera.rotation_euler = (Vector((0, 0, S["head_center"])) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.ortho_scale = 0.62
scene.render.filepath = str(PREVIEWS / (MODEL + "-face.png"))
if not args.skip_render:
    bpy.ops.render.render(write_still=True)
camera.data.ortho_scale = 2.55

pose_bounds = {}
for clip_name, (_, track) in clips.items():
    track.mute = True
    rig.animation_data.action = clips[clip_name][0]
    clip_min = Vector((float("inf"),) * 3)
    clip_max = Vector((float("-inf"),) * 3)
    contacts = []
    for frame in range(1, CLIP_FRAMES[clip_name] + 1):
        scene.frame_set(frame)
        if clip_name in ("walk", "run"):
            contacts.append(min(foot_height("Left"), foot_height("Right")))
        evaluated = skinned_mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = evaluated.to_mesh()
        for vertex in mesh.vertices:
            point = evaluated.matrix_world @ vertex.co
            clip_min = Vector((min(clip_min[i], point[i]) for i in range(3)))
            clip_max = Vector((max(clip_max[i], point[i]) for i in range(3)))
        evaluated.to_mesh_clear()
    if contacts:
        assert min(contacts) >= -0.002, (clip_name, min(contacts))
        assert max(contacts) <= 0.01, (clip_name, max(contacts))
    pose_bounds[clip_name] = {
        "min": list(clip_min), "max": list(clip_max),
        "max_stance_shoe_ground_gap": max(contacts) if contacts else None,
    }
rig.animation_data.action = clips["idle"][0]
scene.frame_set(1)

triangles = 0
min_corner = Vector((float("inf"),) * 3)
max_corner = Vector((float("-inf"),) * 3)
for obj in parts:
    obj.data.calc_loop_triangles()
    triangles += len(obj.data.loop_triangles)
    for vertex in obj.data.vertices:
        p = obj.matrix_world @ vertex.co
        min_corner = Vector((min(min_corner[i], p[i]) for i in range(3)))
        max_corner = Vector((max(max_corner[i], p[i]) for i in range(3)))
summary = {
    "generator": "tools/blender_exploration/build_pedestrian.py",
    "blender": bpy.app.version_string,
    "character": args.character,
    "source": "assets/blender-exploration/" + MODEL + ".blend",
    "glb": "game/assets/desert-dreams-exploration/" + MODEL + ".glb",
    "coordinate_contract": "metres; Blender +Y forward; glTF/Godot -Z forward; feet Z=0; runtime scale 1/16",
    "rig": rig.name,
    "bones": [bone.name for bone in arm_data.bones],
    "clips": dict(CLIP_FRAMES),
    "fps": FPS,
    "triangles": triangles,
    "vertices": len(skinned_mesh.data.vertices),
    "mesh_parts": len(parts),
    "shared_materials": [name for name in M if M[name].users > 0],
    "rest_bounds_blender_xyz": {"min": list(min_corner), "max": list(max_corner)},
    "sampled_pose_bounds_blender_xyz": pose_bounds,
    "previews": [] if args.skip_render else [MODEL + suffix for suffix in ("-idle-three-quarter.png", "-walk-pose.png", "-run-pose.png", "-back-three-quarter.png", "-face.png")],
}
(PREVIEWS / (MODEL + "-source.json")).write_text(json.dumps(summary, indent=2) + "\n")
assert triangles <= 14000, triangles
assert len(summary["shared_materials"]) <= 10
assert max_corner.x - min_corner.x <= .576, (min_corner.x, max_corner.x)
assert max_corner.y - min_corner.y <= .576, (min_corner.y, max_corner.y)
assert min_corner.z >= -.002 and max_corner.z <= 1.84, (min_corner.z, max_corner.z)
for clip_name, bounds in pose_bounds.items():
    assert bounds["min"][2] >= -.002, (clip_name, bounds["min"])
    assert bounds["max"][2] <= 1.90, (clip_name, bounds["max"])
print("PEDESTRIAN_SOURCE", json.dumps(summary, sort_keys=True))
