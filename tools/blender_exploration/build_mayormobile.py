# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Author the mayor's original, boxy luxury trail SUV. Blender, no external art.

Run Blender --background --python tools/blender_exploration/build_mayormobile.py.
The editable master stays in assets/mayormobile; only the GLB is runtime art.
"""
import hashlib
import importlib.util
import json
import math
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('vehicle_authoring', Path(__file__).with_name('build_vehicles.py'))
art = importlib.util.module_from_spec(spec)
spec.loader.exec_module(art)
SOURCE = ROOT / 'assets/mayormobile'
EXPORT = ROOT / 'game/assets/desert-dreams-exploration/mayormobile.glb'
RECORD = ROOT / 'docs/art/mayormobile.json'
RADIUS = .42


def build():
    art.reset()
    art.material('Juniper green', (.045, .15, .105), .48, .29)
    art.material('Satin brass', (.63, .48, .24), .72, .32)
    root = art.pivot('MayormobileModel')
    box = lambda name, at, size, mat, bevel=0: art.box(name, at, size, mat, root, bevel)
    cyl = lambda name, at, radius, depth, mat, axis='Z', vertices=20: art.cylinder(name, at, radius, depth, mat, root, axis, vertices)
    # Flat hood, upright four-door cabin and slab sides, with true open arches.
    body = box('Pressed utility body', (0, -.02, .80), (1.84, 4.30, .65), 'Juniper green', .07)
    for side in [-1, 1]:
        for y in [-1.36, 1.34]:
            cutter = cyl('Temporary arch', (side*.89, y, RADIUS), .48, .62, 'Dark grille', 'X', 24)
            mod = body.modifiers.new('Open wheel arch', 'BOOLEAN')
            mod.operation = 'DIFFERENCE'; mod.object = cutter
            bpy.context.view_layer.objects.active = body
            bpy.ops.object.modifier_apply(modifier=mod.name)
            bpy.data.objects.remove(cutter, do_unlink=True)
            # A physical arch lip follows the tire, never a solid fender block.
            for i in range(13):
                a = i*math.pi/12
                b = (i+1)*math.pi/12
                if i == 12: break
                art.rod('Flared arch lip', (side*.958, y+math.cos(a)*.49, RADIUS+math.sin(a)*.49),
                        (side*.958, y+math.cos(b)*.49, RADIUS+math.sin(b)*.49), .055, 'Rubber charcoal', root)
    box('High flat hood', (0, 1.43, 1.145), (1.79, 1.34, .12), 'Juniper green', .035)
    box('Upright cabin', (0, -.59, 1.53), (1.78, 2.94, 1.04), 'Juniper green', .045)
    box('Ivory hardtop', (0, -.59, 2.065), (1.86, 3.02, .095), 'Warm cream', .035)
    # Glazing is inset within generous painted frames and explicit B/C pillars.
    box('Upright windscreen', (0, .891, 1.65), (1.58, .018, .60), 'Teal canopy', .018)
    box('Rear tailgate glass', (0, -2.073, 1.66), (1.52, .018, .55), 'Teal canopy', .018)
    for side in [-1, 1]:
        for y, length in [(.23, .98), (-.86, .94), (-1.69, .50)]:
            box('Framed side pane', (side*.898, y, 1.66), (.016, length, .58), 'Teal canopy', .015)
        box('Long side protection strip', (side*.932, -.05, 1.17), (.035, 3.96, .055), 'Rubber charcoal', .008)
        box('Trail running board', (side*.981, -.01, .39), (.22, 1.62, .09), 'Dark grille', .025)
        box('Brass sill edge', (side*1.09, -.01, .42), (.018, 1.50, .025), 'Satin brass', .004)
        for rear, front in [(-.35, .76), (-1.47, -.40)]:
            box('Door handle', (side*.938, rear+.22, 1.27), (.045, .18, .04), 'Warm alloy', .008)
            for y in [rear, front]:
                box('Door vertical shut line', (side*.924, y, .99), (.013, .012, .31), 'Dark grille')
            for z in [.85, 1.29]:
                box('Exposed utility hinge', (side*.944, front-.025, z), (.045, .085, .04), 'Juniper green', .008)
        art.rod('Mirror support', (side*.88, .71, 1.44), (side*1.01, .78, 1.48), .024, 'Dark grille', root)
        box('Squared mirror shell', (side*1.015, .77, 1.53), (.15, .21, .19), 'Juniper green', .025)
        box('Mirror silver face', (side*1.015, .659, 1.53), (.112, .012, .14), 'Warm alloy', .012)
        box('Hood corner signal', (side*.78, 1.83, 1.235), (.17, .13, .065), 'Amber lamp', .018)
        cyl('Round headlamp bezel', (side*.64, 2.164, .98), .185, .035, 'Warm alloy', 'Y', 24)
        cyl('Round headlamp lens', (side*.64, 2.188, .98), .146, .024, 'Ivory lamp', 'Y', 24)
        box('Tail lamp housing', (side*.72, -2.183, .88), (.23, .06, .28), 'Dark grille', .025)
        box('Rear red lens', (side*.72, -2.221, .91), (.18, .025, .18), 'Red lamp', .016)
        box('Rear amber lens', (side*.72, -2.223, .79), (.18, .025, .055), 'Amber lamp', .008)
        box('Roof rail foot', (side*.67, -.60, 2.135), (.065, 2.68, .045), 'Dark grille', .015)
    box('Recessed black grille', (0, 2.15, .94), (.79, .04, .34), 'Dark grille', .02)
    for z in [.83, .92, 1.01, 1.10]: box('Grille horizontal bar', (0, 2.177, z), (.73, .023, .025), 'Warm alloy', .006)
    cyl('Mayor sun seal', (0, 2.200, .97), .07, .012, 'Satin brass', 'Y', 16)
    for y in [-2.23, 2.23]:
        box('Trail bumper', (0, y, .56), (1.94, .16, .18), 'Dark grille', .045)
        box('Brass bumper insert', (0, y+(.084 if y>0 else -.084), .58), (.96, .012, .04), 'Satin brass', .006)
    box('Front bash plate', (0, 2.105, .38), (1.15, .12, .19), 'Warm alloy', .025)
    for side in [-1, 1]:
        box('Tow eye mount', (side*.58, 2.28, .52), (.10, .09, .09), 'Satin brass', .02)
    # Rear spare is separate static geometry, not a fifth animated road wheel.
    cyl('Rear spare tire', (0, -2.30, 1.18), .43, .30, 'Rubber charcoal', 'Y', 28)
    cyl('Spare wheel rim', (0, -2.46, 1.18), .28, .035, 'Warm alloy', 'Y', 20)
    cyl('Spare green cover', (0, -2.486, 1.18), .21, .025, 'Juniper green', 'Y', 20)
    cyl('Spare brass center', (0, -2.506, 1.18), .065, .017, 'Satin brass', 'Y', 16)
    # Four articulated wheels: steer at the axle, roll under Spin about local X.
    for side in [-1, 1]:
        for front in [True, False]:
            y = 1.34 if front else -1.36
            wheel = art.pivot(('WheelFront' if front else 'WheelRear')+('Left' if side<0 else 'Right'), (side*.85, y, RADIUS), root)
            spin = art.pivot('Spin', parent=wheel)
            art.torus('Rounded all-terrain tire', (0, 0, 0), .33, .09, 'Rubber charcoal', spin, major_segments=24, minor_segments=8)
            art.cylinder('Tire core', (0, 0, 0), .35, .23, 'Rubber charcoal', spin, 'X', 24)
            for outside in [-1, 1]:
                art.cylinder('Deep alloy rim', (outside*.125, 0, 0), .265, .03, 'Warm alloy', spin, 'X', 20)
                art.cylinder('Dark rim inset', (outside*.145, 0, 0), .218, .014, 'Dark grille', spin, 'X', 20)
                art.cylinder('Brass hub', (outside*.16, 0, 0), .083, .025, 'Satin brass', spin, 'X', 16)
                for j in range(5):
                    a = j*math.tau/5
                    art.rod('Five spoke alloy', (outside*.155, math.sin(a)*.07, math.cos(a)*.07),
                            (outside*.155, math.sin(a)*.22, math.cos(a)*.22), .027, 'Warm alloy', spin, 6)
            for j in range(24):
                a = j*math.tau/24
                tread = art.box('Trail tread', (0, math.sin(a)*.408, math.cos(a)*.408), (.20, .065, .020), 'Rubber charcoal', spin)
                tread.rotation_euler.x = -a
    # Centre the authored envelope about both horizontal axes, keeping tire contact.
    low, high = art.bounds(root)
    for child in root.children:
        child.location.y -= (low[1]+high[1])*.5
        child.location.z -= low[2]
    art.merge_by_pivot_material(root)
    return root


def main():
    SOURCE.mkdir(parents=True, exist_ok=True)
    root = build()
    bpy.context.preferences.filepaths.save_version = 0
    bpy.context.scene.unit_settings.system = 'METRIC'
    low, high = art.bounds(root)
    triangles = sum(len(p.vertices)-2 for o in art.objects_under(root) if o.type=='MESH' for p in o.data.polygons)
    assert triangles < 12000, triangles
    assert abs(low[2]) < .00001
    for angle in [-.45, 0, .45]:
        for node in root.children:
            if node.name.startswith('WheelFront'): node.rotation_euler.z = angle
        lo, hi = art.bounds(root)
        assert max(abs(lo[0]), abs(hi[0])) < 1.15
    for node in root.children:
        if node.name.startswith('WheelFront'): node.rotation_euler.z = 0
    bpy.ops.object.select_all(action='DESELECT')
    for obj in art.objects_under(root): obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=str(EXPORT), export_format='GLB', use_selection=True,
                              export_yup=True, export_animations=False, export_apply=True)
    art.normalize_glb_pivots(EXPORT)
    # Studio and editable master are retained locally alongside four previews.
    art.PREVIEW = SOURCE
    art.preview(root, 'mayormobile')
    scene = bpy.context.scene
    for name, at in [('rear',(0,-9,3)),('rear-quarter',(-6,-8,4.5)),('side',(9,0,3))]:
        scene.camera.location = at; art.look_at(scene.camera,(0,0,1))
        scene.render.filepath = str(SOURCE / ('mayormobile-'+name+'.png'))
        bpy.ops.render.render(write_still=True)
    master = SOURCE / 'mayormobile.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(master))
    record = dict(tool='tools/blender_exploration/build_mayormobile.py',
                  description='Original juniper-green four-door luxury trail SUV, ivory roof, brass mayoral sun seal, rear spare and four articulated all-terrain wheels.',
                  runtime=str(EXPORT.relative_to(ROOT)), runtime_sha256=hashlib.sha256(EXPORT.read_bytes()).hexdigest(),
                  master=str(master.relative_to(ROOT)), master_sha256=hashlib.sha256(master.read_bytes()).hexdigest(),
                  triangles=triangles, units='meters', runtime_scale=.0625,
                  bounds_blender=[low, high], envelope_godot_m=[2.30, 2.20, 5.10],
                  owned_geometry=True, external_textures=False,
                  animation={'wheel_radius_m':RADIUS,'wheels':[dict(node=n, radius_m=RADIUS, axis='X', steer=n.startswith('WheelFront')) for n in ['WheelFrontLeft','WheelFrontRight','WheelRearLeft','WheelRearRight']]})
    RECORD.write_text(json.dumps(record,indent=2)+'\n')
    print('MAYORMOBILE_COMPLETE', triangles, low, high)


if __name__ == '__main__': main()
