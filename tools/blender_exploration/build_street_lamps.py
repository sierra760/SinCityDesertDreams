# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Build the original Desert Dreams boulevard street lamps (masters, GLBs, previews).

Run with Blender 5.2+:
  blender --background --factory-startup --python-exit-code 1 \
      --python tools/blender_exploration/build_street_lamps.py [-- --skip-render]

Two mid-century boulevard lamps are modelled entirely from code: a slender
tapered graphite-bronze pole on a flared collar, a swan-neck arm and a flat
elliptical luminaire whose downward lens is its own face set.

* `street_lamp`        single arm, roadside.
* `street_lamp_double` two opposed arms, highway median.

Construction is in metres (Blender +Z up, arm toward Blender +Y), then every
vertex is scaled by 1/16 so the exported GLB is already in map-tile units
(1 tile = 16 m). glTF +Y up; the arm reaches toward glTF/Godot -Z. The origin
is the centre of the pole base at ground level (lowest vertex y = 0).

Exactly three materials: `street_lamp_pole`, `street_lamp_accent` and
`street_lamp_glow` (lens only, no emission; the game enables it at night).
Outputs: assets/street-lamps/<name>.blend, assets/street-lamps/previews/*.png,
game/assets/desert-dreams-street-lamps/<name>.glb and street-lamps.json.
"""

import json
import math
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/street-lamps"
PREVIEWS = SOURCE / "previews"
RUNTIME = ROOT / "game/assets/desert-dreams-street-lamps"
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SKIP_RENDER = "--skip-render" in ARGS
for folder in (SOURCE, PREVIEWS, RUNTIME):
    folder.mkdir(parents=True, exist_ok=True)

TILE = 16.0  # metres per map tile
POLE_SIDES = 10
ARM_SIDES = 6
HEAD_POINTS = 14
SHARP_ANGLE = math.radians(50.0)

# Dimensions in metres.
COLLAR_PROFILE = [(0.225, 0.0), (0.225, 0.05), (0.175, 0.11), (0.13, 0.24)]
POLE_BASE = (0.11, 0.20)   # radius, z (starts inside the collar)
POLE_TOP = (0.06, 8.00)
RING = (0.08, 7.56, 7.68)  # accent ring radius, bottom, top
ARM_RADIUS = (0.05, 0.04)  # at pole, at head
ARC_START_Z = 8.25
ARC_RADIUS = 0.75
REACH = 2.2                # pole axis to head centre
HEAD_HALF = (0.26, 0.60)   # half width (x), half length (along arm)
HEAD_BOTTOM = 8.70
LENS_SCALE = 0.86          # lens ellipse inside the bottom rim


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------
def make_material(name, color, metallic, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Emission Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 0.0
    mat.diffuse_color = (*color, 1.0)
    return mat


# ---------------------------------------------------------------------------
# Geometry helpers (bmesh, metres)
# ---------------------------------------------------------------------------
POLE, ACCENT, GLOW = 0, 1, 2


def ring_verts(bm, centre, radius_x, radius_y, count, frame=None, phase=0.0):
    """Ring of verts. Without a frame the ring is horizontal (x/y radii)."""
    out = []
    for i in range(count):
        t = phase + i * math.tau / count
        if frame is None:
            p = Vector((centre[0] + radius_x * math.cos(t), centre[1] + radius_y * math.sin(t), centre[2]))
        else:
            u, v = frame
            p = Vector(centre) + u * (radius_x * math.cos(t)) + v * (radius_y * math.sin(t))
        out.append(bm.verts.new(p))
    return out


def bridge(bm, lower, upper, mat):
    n = len(lower)
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
        f.material_index = mat


def cap_fan(bm, ring, centre, mat):
    c = bm.verts.new(Vector(centre))
    n = len(ring)
    for i in range(n):
        f = bm.faces.new((ring[i], ring[(i + 1) % n], c))
        f.material_index = mat
    return c


def cap_ngon(bm, ring, mat):
    f = bm.faces.new(ring)
    f.material_index = mat
    return f


def lathe(bm, profile, sides, mat, cap_bottom=True, cap_top=True):
    rings = [ring_verts(bm, (0, 0, z), r, r, sides) for r, z in profile]
    for a, b in zip(rings, rings[1:]):
        bridge(bm, a, b, mat)
    if cap_bottom:
        cap_ngon(bm, list(reversed(rings[0])), mat)
    if cap_top:
        cap_ngon(bm, rings[-1], mat)


def arm_path(direction, double):
    """Swan-neck centreline in the (y, z) plane; direction is +1 or -1 along Y.

    The single arm rises out of the pole top. On the median lamp the pole itself
    runs up to the start of the arcs, so the two arms only share their roots
    (hidden inside the pole) instead of a duplicated vertical stretch."""
    if double:
        pts = [(0.0, ARC_START_Z - 0.08)]
    else:
        pts = [(0.0, POLE_TOP[1] - 0.15), (0.0, ARC_START_Z)]
    for k in range(1, 5):
        t = k * (math.pi / 2) / 4
        pts.append((ARC_RADIUS - ARC_RADIUS * math.cos(t), ARC_START_Z + ARC_RADIUS * math.sin(t)))
    pts += [(1.40, 8.975), (REACH - 0.25, HEAD_BOTTOM + 0.19)]
    return [Vector((0.0, direction * y, z)) for y, z in pts]


def sweep(bm, path, radii, sides, mat):
    """Closed tube along a polyline with parallel-transported frames."""
    tangents = []
    for i, p in enumerate(path):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, len(path) - 1)]
        tangents.append((b - a).normalized())
    u = Vector((1, 0, 0))
    rings = []
    total = sum((path[i + 1] - path[i]).length for i in range(len(path) - 1))
    run = 0.0
    for i, (p, t) in enumerate(zip(path, tangents)):
        if i:
            run += (p - path[i - 1]).length
        u = (u - t * u.dot(t)).normalized()
        v = t.cross(u).normalized()
        r = radii[0] + (radii[1] - radii[0]) * (run / total)
        rings.append(ring_verts(bm, p, r, r, sides, frame=(u, v)))
    for a, b in zip(rings, rings[1:]):
        bridge(bm, a, b, mat)
    cap_ngon(bm, list(reversed(rings[0])), mat)
    cap_ngon(bm, rings[-1], mat)


def luminaire(bm, direction):
    """Flat elliptical saucer head; returns the lens centre (metres, Blender)."""
    cy = direction * REACH
    hx, hy = HEAD_HALF
    zb = HEAD_BOTTOM

    def ring(scale, z):
        return ring_verts(bm, (0.0, cy, z), hx * scale, hy * scale, HEAD_POINTS)

    rim = ring(1.0, zb)
    band = ring(1.0, zb + 0.06)
    shoulder = ring(0.80, zb + 0.15)
    bridge(bm, rim, band, ACCENT)        # thin teal band around the head
    bridge(bm, band, shoulder, POLE)
    cap_fan(bm, shoulder, (0.0, cy, zb + 0.20), POLE)
    lens = ring(LENS_SCALE, zb)
    bridge(bm, lens, rim, POLE)          # flat bottom rim (annulus), faces down
    cap_ngon(bm, list(reversed(lens)), GLOW)
    return Vector((0.0, cy, zb))


def build_lamp(name, directions, materials):
    bm = bmesh.new()
    lathe(bm, COLLAR_PROFILE, POLE_SIDES, POLE)
    double = len(directions) > 1
    pole_top = (POLE_TOP[0], ARC_START_Z) if double else POLE_TOP
    lathe(bm, [POLE_BASE, pole_top], POLE_SIDES, POLE)
    lathe(bm, [(RING[0], RING[1]), (RING[0], RING[2])], POLE_SIDES, ACCENT)
    lenses = []
    for d in directions:
        sweep(bm, arm_path(d, double), ARM_RADIUS, ARM_SIDES, POLE)
        lenses.append(luminaire(bm, d))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    # Manifold check: every edge has exactly two faces.
    bad = [e for e in bm.edges if len(e.link_faces) != 2]
    if bad:
        raise RuntimeError(f"{name}: {len(bad)} non-manifold edges")
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if e.calc_face_angle(0.0) > SHARP_ANGLE:
            e.smooth = False
    # Apply the tile scale directly to the vertices (no object transform).
    for v in bm.verts:
        v.co /= TILE

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    tri_count = len(bm.faces)
    lens_tris = sum(1 for f in bm.faces if f.material_index == GLOW)
    min_z = min(v.co.z for v in bm.verts)
    max_z = max(v.co.z for v in bm.verts)
    max_y = max(abs(v.co.y) for v in bm.verts)
    bm.free()
    for mat in materials:
        mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if abs(min_z) > 1e-6:
        raise RuntimeError(f"{name}: lowest vertex {min_z} is not at ground level")
    # glTF/Godot coordinates: (x, z, -y), tile units.
    lens_godot = [[round(p.x / TILE, 6), round(p.z / TILE, 6), round(-p.y / TILE, 6)] for p in lenses]
    info = {
        "lens": lens_godot,
        "height": round(max_z, 6),
        "reach": round(max_y, 6),
        "triangles": tri_count,
        "lens_triangles": lens_tris,
        "lens_radius": [round(HEAD_HALF[0] * LENS_SCALE / TILE, 6), round(HEAD_HALF[1] * LENS_SCALE / TILE, 6)],
    }
    return obj, info


# ---------------------------------------------------------------------------
# Preview studio (built after the master is saved; never exported)
# ---------------------------------------------------------------------------
def render_previews(name, obj, glow_mat):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("Preview world")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    scene.world = world

    bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
    floor = bpy.context.object
    floor.name = "Preview sand floor (not exported)"
    sand = bpy.data.materials.new("Preview sand")
    sand.use_nodes = True
    sand.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.62, 0.50, 0.36, 1)
    sand.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    floor.data.materials.append(sand)
    # A strip of asphalt where the road would be (lamp arm faces -Z in Godot = +Y here).
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0.25, 0.0005))
    road = bpy.context.object
    road.scale = (3, 0.34, 1)
    asphalt = bpy.data.materials.new("Preview asphalt")
    asphalt.use_nodes = True
    asphalt.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.09, 0.09, 0.1, 1)
    road.data.materials.append(asphalt)
    if name.endswith("double"):
        road.location.y = -0.25
        bpy.ops.object.duplicate()
        bpy.context.object.location.y = 0.25

    bpy.ops.object.light_add(type="SUN", location=(2, -2, 4))
    sun = bpy.context.object
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    sun.data.energy = 3.5
    sun.data.angle = math.radians(3)

    bpy.ops.object.camera_add()
    cam = bpy.context.object
    scene.camera = cam

    def aim(location, target, ortho=None, lens=50):
        cam.location = location
        cam.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
        if ortho:
            cam.data.type = "ORTHO"
            cam.data.ortho_scale = ortho
        else:
            cam.data.type = "PERSP"
            cam.data.lens = lens

    bsdf = glow_mat.node_tree.nodes["Principled BSDF"]
    # 1. Daylight street-level three-quarter view.
    bg.inputs["Color"].default_value = (0.55, 0.68, 0.85, 1)
    bg.inputs["Strength"].default_value = 0.9
    aim((0.95, -0.42, 0.30), (0, 0.04, 0.29), lens=45)
    scene.render.filepath = str(PREVIEWS / f"{name}-day-three-quarter.png")
    bpy.ops.render.render(write_still=True)
    # 2. Dusk aerial isometric view with the lens temporarily lit (preview only).
    bg.inputs["Color"].default_value = (0.10, 0.10, 0.20, 1)
    bg.inputs["Strength"].default_value = 0.6
    sun.data.energy = 0.6
    bsdf.inputs["Emission Color"].default_value = (1.0, 0.85, 0.55, 1)
    bsdf.inputs["Emission Strength"].default_value = 6.0
    bpy.ops.object.light_add(type="SPOT", location=(0, 0.1375 if not name.endswith("double") else 0, 0.53))
    pool_lights = [bpy.context.object]
    if name.endswith("double"):
        pool_lights[0].location.y = 0.1375
        bpy.ops.object.light_add(type="SPOT", location=(0, -0.1375, 0.53))
        pool_lights.append(bpy.context.object)
    for light in pool_lights:
        light.data.energy = 8
        light.data.color = (1.0, 0.85, 0.6)
        light.data.spot_size = math.radians(110)
        light.data.shadow_soft_size = 0.01
    aim((1.1, -1.1, 1.1), (0, 0, 0.25), ortho=0.95)
    scene.render.filepath = str(PREVIEWS / f"{name}-dusk-aerial.png")
    bpy.ops.render.render(write_still=True)


# ---------------------------------------------------------------------------
# Build both lamps
# ---------------------------------------------------------------------------
LAMPS = {"street_lamp": (1,), "street_lamp_double": (1, -1)}
report = {}
for lamp_name, directions in LAMPS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = [
        make_material("street_lamp_pole", (0.10, 0.10, 0.09), 0.6, 0.45),
        make_material("street_lamp_accent", (0.04, 0.32, 0.32), 0.3, 0.4),
        make_material("street_lamp_glow", (0.98, 0.90, 0.70), 0.0, 0.3),
    ]
    obj, info = build_lamp(lamp_name, directions, mats)
    report[lamp_name] = info
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / f"{lamp_name}.blend"), compress=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(RUNTIME / f"{lamp_name}.glb"), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=True, export_materials="EXPORT", export_animations=False,
        export_cameras=False, export_lights=False, export_extras=False)
    print("LAMP", lamp_name, json.dumps(info))
    if not SKIP_RENDER:
        render_previews(lamp_name, obj, mats[GLOW])

(RUNTIME / "street-lamps.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
print("WROTE", RUNTIME / "street-lamps.json")
