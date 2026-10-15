# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Original farm modules authored to the shared metre-space placement contract."""
import hashlib
import json
from pathlib import Path
import random

KEYS = ('farm_shed', 'shade_shelter', 'water_trough', 'water_tank', 'grain_bin',
        'hay_bale', 'vegetable_strip', 'alfalfa_strip', 'grain_strip',
        'fence_post', 'fence_rail', 'fence_gate')


def _vertices(asset):
    return [v for vertices, _, _ in asset.parts.values() for v in vertices]


def _ground_and_roof(asset, eave, peak):
    """Remove the old lot's plinth offset; lower only the roof above its eave."""
    vertices = _vertices(asset)
    old_peak = max(v.y for v in vertices) - .12
    for v in vertices:
        y = max(0, v.y - .12)
        v.y = y if y <= eave else eave + (y - eave) * (peak - eave) / (old_peak - eave)


def make_module(key, entry, g, original):
    a = g.Asset('parcel_' + key)
    w, h, d = entry['nominal_size']
    bounds = entry['placement_bounds']
    if key == 'farm_shed':
        original.barn(a, 0, 0, w=w, d=d, h=h)
        _ground_and_roof(a, h, bounds[4])
        # Preserve the 10x7m walls. Trim only projecting roof-edge caps to the envelope.
        for v in _vertices(a):
            v.x = max(bounds[0], min(bounds[3], v.x))
            v.z = max(bounds[2], min(bounds[5], v.z))
    elif key in ('shade_shelter', 'water_trough'):
        shelter = key == 'shade_shelter'
        wall_height = h - .7 if shelter else h
        original.pen_obstacle(a, {'kind': 'shelter' if shelter else 'trough',
                                'center': [0, wall_height / 2, 0], 'size': [w, wall_height, d]})
        _ground_and_roof(a, wall_height, h) if shelter else None
        if not shelter:
            for v in _vertices(a): v.y = max(0, v.y - .12)
        else:
            for v in _vertices(a):
                v.x = max(bounds[0], min(bounds[3], v.x))
                v.z = max(bounds[2], min(bounds[5], v.z))
    elif key == 'water_tank':
        original.tank(a, 0, 0, r=w / 2 - .12, h=h - .3)
        # The original helper ends with a six-sided outlet pipe. Repose it across
        # the front of the cylinder, inside this independent equipment footprint.
        for v in a.parts['metal'][0][-12:]:
            v.x = -.35 + v.x * .35
            v.z += d / 2 - .07
        original.box(a, 'concrete', (0, .06, 0), (w, .12, d))
    elif key == 'grain_bin':
        radius = w / 2 - .08
        g.cylinder(a, 'metal', (0, (h - .75) / 2, 0), radius, h - .75, seg=16)
        g.cylinder(a, 'roof', (0, h - .375, 0), w / 2, .75, seg=16, top=0)
        for y in (.35, 1, 1.65, 2.3, 2.95):
            g.torus(a, 'metal', (0, y, 0), radius + .02, .035, seg=16, ring=4)
        for x in (-.22, .22): g.rod(a, 'dark', (x, .1, d / 2 - .04), (x, h - .8, d / 2 - .04), .025)
        for y in (.3, .7, 1.1, 1.5, 1.9, 2.3, 2.7, 3.1):
            original.pipe(a, -.22, d / 2 - .04, .22, d / 2 - .04, y, .025)
    elif key == 'hay_bale':
        # Compact rectangular bale with its own tied straps, grounded on all four corners.
        original.box(a, 'hay', (0, (h - .02) / 2, 0), (w, h - .02, d - .04))
        for x in (-w / 3, w / 3):
            original.box(a, 'wood', (x, h - .015, 0), (.035, .03, d))
            for z in (-d / 2 + .015, d / 2 - .015):
                original.box(a, 'wood', (x, h / 2, z), (.035, h, .03))
    elif key.endswith('_strip'):
        style = 'vegetables' if key == 'vegetable_strip' else key.removesuffix('_strip')
        original.bed(a, 0, 0, length=d, width=w, style=style, rng=random.Random(style))
        # A separate 1m seedling unit: preserve X/Z spacing and soil thickness;
        # shorten only the plant canopy above the irrigation bed to its crop height.
        top = max(v.y for v in _vertices(a))
        for v in _vertices(a):
            y = max(0, v.y - .12)
            v.y = y if y <= .15 else .15 + (y - .15) * (h - .15) / (top - .27)
    elif key == 'fence_post':
        original.box(a, 'wood', (0, (h - .06) / 2, 0), (w, h - .06, d))
        original.box(a, 'cream', (0, h - .03, 0), (w, .06, d))
    else:
        # The helper's end posts remain fully inside each repeatable segment.
        original.fence(a, {'a': [-w / 2 + .09, 0], 'b': [w / 2 - .09, 0],
                           'height': h - .04, 'thickness': d,
                           'gate': key == 'fence_gate', 'end_posts_only': key == 'fence_gate'})
        for v in _vertices(a):
            v.y = max(0, v.y - .12)
            v.z = max(-d / 2, min(d / 2, v.z))
        # Caps and latch stand proud of the timber; no coplanar material flicker.
        for v in a.parts['wood'][0]: v.z *= .875
        # All rails terminate in the posts; gate diagonals and latch remain closed.
    a.colliders.clear()
    low, high = bounds[:3], bounds[3:]
    a.collider('Module envelope', [(low[i] + high[i]) / 2 for i in range(3)],
               [high[i] - low[i] for i in range(3)])
    return a


def _export(root, a, g, bpy):
    g.reset()
    objects = g.make_objects(a) + g.make_colliders(a)
    for obj in objects:
        if obj.name.endswith('-colonly'): continue
        uv = obj.data.uv_layers.new(name='FarmSurfaceUV')
        for polygon in obj.data.polygons:
            axis = max(range(3), key=lambda i: abs(polygon.normal[i]))
            for loop in polygon.loop_indices:
                p = obj.data.vertices[obj.data.loops[loop].vertex_index].co
                coords = (p.y, p.z) if axis == 0 else ((p.x, p.z) if axis == 1 else (p.x, p.y))
                uv.data[loop].uv = (coords[0] / 2, coords[1] / 2)
    for obj in bpy.context.scene.objects: obj.select_set(False)
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(root / 'assets/agriculture/parcel-kit' / (a.name + '.blend')))
    key = a.name.removeprefix('parcel_')
    path = root / 'game/assets/agriculture/parcel-kit' / (key + '.glb')
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                             export_yup=True, export_materials='EXPORT', export_animations=False,
                             export_cameras=False, export_lights=False, export_extras=False,
                             export_image_format='AUTO', export_apply=False)
    uri = 'res://assets/agriculture/parcel-kit/' + path.name
    sidecar = path.with_suffix('.glb.import')
    if not sidecar.exists():
        sidecar.write_text(g.SIDECAR.replace('{path}', uri).replace('gltf/embedded_image_handling=1', 'gltf/embedded_image_handling=2'))
    verts = _vertices(a)
    return dict(path=uri, model_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                triangles=a.triangles(), materials=sorted('farm_' + f for f in a.parts),
                bounds_metres=[[min(v[i] for v in verts) for i in range(3)], [max(v[i] for v in verts) for i in range(3)]],
                collider_count=1)


def build_kit(root: Path, geometry_module, original, only=None) -> None:
    """Export exactly the shared twelve-module contract; no old catalog writes."""
    import bpy
    from check_agriculture_parcels import budget, validate_module, read_glb
    path = root / 'game/assets/agriculture/parcel_modules.json'
    manifest = json.loads(path.read_text())
    assert set(manifest['modules']) == set(KEYS), 'shared module roster'
    for directory in ('assets/agriculture/parcel-kit', 'game/assets/agriculture/parcel-kit'):
        (root / directory).mkdir(parents=True, exist_ok=True)
    (root / 'assets/agriculture/parcel-kit/.gitignore').write_text('*\n')
    bpy.context.preferences.filepaths.save_version = 0
    original.materials()
    assert not only or set(only)<=set(KEYS), 'unknown selective module key'
    for key in KEYS:
        if only and key not in only: continue
        entry = manifest['modules'][key]
        asset = make_module(key, entry, geometry_module, original)
        assert asset.triangles() <= budget(key), (key, asset.triangles())
        entry.update(_export(root, asset, geometry_module, bpy))
        gltf, binary = read_glb(root / 'game' / entry['path'].removeprefix('res://'))
        validate_module(key, entry, gltf, binary)
        print('PARCEL_EXPORTED', key, entry['triangles'], entry['model_sha256'], flush=True)
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    provenance = dict(schema_version=1, units=manifest['units'], up=manifest['up'], forward=manifest['forward'],
                      scale=manifest['scale'], generator='tools/model_art/agricultural_parcels.py',
                      provenance='Original procedural farm geometry and packed original surface swatches; no imported meshes or artwork.',
                      modules=manifest['modules'])
    (root / 'docs/art/agriculture-parcels.json').write_text(json.dumps(provenance, indent=2) + '\n')
