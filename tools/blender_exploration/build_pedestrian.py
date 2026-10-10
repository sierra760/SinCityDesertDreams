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

# Snapshot retained identity sources even for an in-place rebuild.
import tempfile
import shutil
identity_backup = tempfile.TemporaryDirectory(prefix="scdd-player-identity-")
identity_paths = []
for original in (ROOT / "game/assets/desert-dreams-exploration" / (MODEL+".glb"), ROOT / "assets/blender-exploration" / (MODEL+".blend")):
    if original.exists():
        backup = Path(identity_backup.name) / original.name
        shutil.copyfile(original, backup)
        identity_paths.append(backup)

sys.path.insert(0, str(ROOT / "tools"))
from model_art.pedestrians import build_character
# Shared construction returns the editable rig, mesh, helpers and clip metadata
# used by this long-standing player export/preview wrapper.
shared = build_character(args.character, "detailed", {"debug_colors":args.debug_colors})
shared.pop("args")
globals().update(shared)

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

# Retained editable player masters are authoritative for accepted faces/outfits.
# Preserve their exact geometry while adding the newly authored animation.
from model_art.pedestrians import preserve_player_geometry
if len(identity_paths)==2 and not args.debug_colors:
    preserve_player_geometry(identity_paths[0], GLB, identity_paths[1], SOURCE / (MODEL + '.blend'))
identity_backup.cleanup()
