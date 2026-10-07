# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Build original editable Blender disaster models and authored looping animations.

blender --factory-startup --background --python-exit-code 1 --python this_file.py
Source metres, +Y forward/+Z up; runtime applies one /16 scale after glTF export.
"""
import argparse
import hashlib
import importlib
import json
import math
import os
import re
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from disaster_art import common as c

SOURCE = ROOT / 'assets/disaster-models'
RUNTIME = ROOT / 'game/assets/desert-dreams-disasters'
# Preview renders and manifests go to $SCDD_REVIEW_DIR (default: <repo>/tmp/review).
REVIEW = Path(os.environ.get('SCDD_REVIEW_DIR', ROOT / 'tmp/review')) / 'disaster-models'
KINDS = ['tornado', 'hurricane', 'monster', 'beam', 'riot', 'plane', 'fire']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def objects():
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def metrics():
    bpy.context.view_layer.update()
    meshes = objects()
    coords = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    low = [min(v[i] for v in coords) for i in range(3)]
    high = [max(v[i] for v in coords) for i in range(3)]
    rigs = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
    return {'source_metres_min': low, 'source_metres_max': high,
            'triangles': sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons),
            'editable_meshes': len(meshes),
            'materials': sorted({m.name for o in meshes for m in o.data.materials}),
            'godot_tile_size': [(high[0]-low[0])/16, (high[2]-low[2])/16, (high[1]-low[1])/16],
            'skeletons': len(rigs), 'bones': sum(len(o.data.bones) for o in rigs),
            'morph_meshes': sum(o.data.shape_keys is not None for o in meshes),
            'duration_seconds': bpy.context.scene.frame_end / bpy.context.scene.render.fps}


def evaluated_vertices():
    deps = bpy.context.evaluated_depsgraph_get()
    result = []
    for obj in sorted(objects(), key=lambda o: o.name):
        evaluated = obj.evaluated_get(deps)
        data = evaluated.to_mesh()
        result.extend(evaluated.matrix_world @ v.co for v in data.vertices)
        evaluated.to_mesh_clear()
    return result


def verify_geometry():
    import bmesh
    for obj in objects():
        assert obj.data.uv_layers and obj.data.color_attributes.get('Mottle'), obj.name
        bm = bmesh.new(); bm.from_mesh(obj.data)
        assert all(e.is_manifold for e in bm.edges), (obj.name, 'open edge')
        assert bm.calc_volume(signed=True) > 0, (obj.name, 'inward winding')
        bm.free()


def animation_envelope():
    scene = bpy.context.scene
    scene.frame_set(0); first = evaluated_vertices()
    low = Vector((math.inf,)*3); high = Vector((-math.inf,)*3)
    changed = 0.0
    for step in range(17):
        scene.frame_set(round(scene.frame_end * step / 16))
        verts = evaluated_vertices()
        assert len(verts) == len(first)
        for a, b in zip(first, verts):
            assert all(math.isfinite(v) for v in b)
            changed = max(changed, (a-b).length)
            for axis in range(3):
                low[axis] = min(low[axis], b[axis]); high[axis] = max(high[axis], b[axis])
    last = evaluated_vertices()
    seam = max((a-b).length for a,b in zip(first,last))
    assert seam < .002, ('loop seam metres', seam)
    assert changed > .15, ('no visible authored motion', changed)
    scene.frame_set(0)
    return {'animation_metres_min': list(low), 'animation_metres_max': list(high),
            'loop_seam_metres': seam, 'maximum_sampled_vertex_motion_metres': changed,
            'sampled_poses': 17}


def batch_runtime():
    # Shared rig children retain skin groups/modifiers when joined. Shape-key
    # meshes and animated objects keep their separate channels and topology.
    for parent in [o for o in bpy.context.scene.objects if o.type in {'EMPTY','ARMATURE'}]:
        parts = [o for o in parent.children if o.type == 'MESH' and
                 not o.animation_data and not o.data.shape_keys]
        if len(parts) < 2: continue
        bpy.ops.object.select_all(action='DESELECT')
        for obj in parts: obj.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        bpy.context.object.name = parent.name + 'Mesh'


def gltf_metrics(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack('<III', data[:12])
    assert magic == 0x46546c67 and version == 2 and length == len(data)
    size, chunk = struct.unpack('<II', data[12:20]); assert chunk == 0x4e4f534a
    gltf = json.loads(data[20:20+size])
    animations = gltf.get('animations', [])
    assert len(animations) == 1 and animations[0]['name'] == 'Incident_loop'
    paths = {x['target']['path'] for x in animations[0]['channels']}
    assert animations[0]['channels']
    triangles = 0
    for mesh in gltf['meshes']:
        for primitive in mesh['primitives']:
            assert {'POSITION','NORMAL','TEXCOORD_0','COLOR_0'} <= set(primitive['attributes'])
            triangles += gltf['accessors'][primitive['indices']]['count']//3
    assert triangles < 16000 and len(gltf['materials']) <= 8
    return {'runtime_triangles': triangles, 'runtime_meshes': len(gltf['meshes']),
            'runtime_materials': len(gltf['materials']),
            'animation_channels': len(animations[0]['channels']),
            'animation_paths': sorted(paths), 'runtime_skins': len(gltf.get('skins', []))}


def export(kind):
    c.reset()
    module = 'creatures' if kind in {'monster','riot'} else 'aircraft' if kind == 'plane' else 'weather'
    getattr(importlib.import_module('disaster_art.' + module), kind)()
    scene = bpy.context.scene
    scene.name = 'Incident_loop'
    scene.unit_settings.system = 'METRIC'
    scene['provenance'] = 'Original geometry, UVs, vertex-color materials, rigs and authored animation for Sin City: Desert Dreams'
    scene['units'] = 'Metres, +Y forward/+Z up; runtime applies /16 exactly once'
    scene['kind'] = kind
    scene.frame_set(0)
    verify_geometry()
    data = metrics()
    assert data['triangles'] < 16000 and len(data['materials']) <= 8, data
    data.update(animation_envelope())
    if kind == 'monster':
        data.update({'display_name': 'Tsawhawbitts',
                     'inspiration': 'Original stylized interpretation of the Jarbidge giant; appearance and animation are artistic inventions.',
                     'legend_reference': 'https://travelnevada.com/ghost-town/journey-to-jarbidge/'})
    master = SOURCE / (kind + '.blend')
    bpy.ops.wm.save_as_mainfile(filepath=str(master))
    if kind == 'fire':
        from disaster_art.fire_batch import consolidate_fire
        data['runtime_batch_verification'] = consolidate_fire()
        from disaster_art.fire_motion import bake_fire_motion
        data['vertex_animation'] = bake_fire_motion(RUNTIME)
        motion = data['vertex_animation']
        material_path = RUNTIME / 'fire.tres'
        material = material_path.read_text()
        for key, value in [('rows_per_frame', motion['rows_per_frame']),
                           ('atlas_height', motion['atlas_height']), ('playback_fps', motion['fps'])]:
            material = re.sub(r'(?m)^shader_parameter/' + key + r' = .+$',
                              'shader_parameter/' + key + ' = ' + str(float(value)), material)
        low = motion['all_frame_positions_min']; high = motion['all_frame_positions_max']
        bounds = [x-.02 for x in low] + [b-a+.04 for a,b in zip(low,high)]
        material = re.sub(r'(?m)^metadata/motion_bounds = .+$',
                          'metadata/motion_bounds = AABB(' + ', '.join(map(str,bounds)) + ')', material)
        material_path.write_text(material)
        data['presentation_material_sha256'] = sha(material_path)
        data['presentation_shader_sha256'] = sha(RUNTIME / 'fire.gdshader')
    else:
        batch_runtime()
    bpy.ops.object.select_all(action='SELECT')
    path = RUNTIME / (kind + '.glb')
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
        export_yup=True, export_materials='EXPORT', export_cameras=False, export_lights=False,
        export_animations=True, export_animation_mode='SCENE', export_anim_scene_split_object=False,
        export_nla_strips_merged_animation_name='Incident_loop', export_frame_range=True,
        export_force_sampling=True, export_morph=True, export_morph_animation=True)
    data.update(gltf_metrics(path))
    assert data['runtime_triangles'] == data['triangles']
    if kind in {'monster','riot'}: assert data['runtime_skins'] >= 1
    data.update({'master': str(master.relative_to(ROOT)), 'runtime': str(path.relative_to(ROOT)),
                 'master_sha256': sha(master), 'runtime_sha256': sha(path)})
    (SOURCE / (kind + '-metrics.json')).write_text(json.dumps(data, indent=2)+'\n')
    return data


def studio(kind, view='isometric', frames=False):
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE/(kind+'.blend')))
    record = json.loads((SOURCE/(kind+'-metrics.json')).read_text())
    low = Vector(record['animation_metres_min']); high = Vector(record['animation_metres_max'])
    center = (low+high)*.5; span = max(high-low)
    scene = bpy.context.scene
    scene.frame_set(round(scene.frame_end*.20))
    world = bpy.data.worlds.new('Desert studio'); scene.world = world; world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value=(.20,.25,.29,1)
    world.node_tree.nodes['Background'].inputs[1].default_value=.45
    for direction, energy, tint in [((-.8,1.1,1.6),14,(1,.83,.65)),((1,-.8,.9),12,(.62,.81,1))]:
        bpy.ops.object.light_add(type='AREA',location=center+Vector(direction)*span)
        lamp=bpy.context.object;lamp.data.energy=span*span*energy;lamp.data.size=span*.8
        lamp.data.color=tint;lamp.rotation_euler=(center-lamp.location).to_track_quat('-Z','Y').to_euler()
    direction=Vector((1.1,1.8,1.0)) if view=='isometric' else Vector((.55,2,.25))
    bpy.ops.object.camera_add(location=center+direction*span)
    camera=bpy.context.object;camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO';camera.data.ortho_scale=span*1.23;scene.camera=camera
    scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.resolution_x=800;scene.render.resolution_y=800;scene.render.resolution_percentage=100
    scene.render.film_transparent=True;scene.view_settings.view_transform='AgX'
    scene.render.image_settings.file_format='PNG'
    if frames:
        target=REVIEW/(kind+'-frames');target.mkdir(exist_ok=True)
        scene.render.resolution_x=512;scene.render.resolution_y=512;scene.cycles.samples=12
        end=scene.frame_end
        for index in range(96):
            scene.frame_set(round(index*end/96))
            scene.render.filepath=str(target/('%04d.png'%index));bpy.ops.render.render(write_still=True)
    else:
        scene.render.filepath=str(REVIEW/(kind+'-'+view+'.png'));bpy.ops.render.render(write_still=True)


def verify(kinds):
    records=json.loads((RUNTIME/'provenance.json').read_text())['models'];checks=[]
    for kind in kinds:
        record=records[kind];master=SOURCE/(kind+'.blend');runtime=RUNTIME/(kind+'.glb')
        assert sha(master)==record['master_sha256'] and sha(runtime)==record['runtime_sha256']
        if kind == 'fire':
            for key in ['position_texture', 'normal_texture']:
                texture = record['vertex_animation'][key]
                assert sha(RUNTIME / texture['path']) == texture['sha256']
            assert sha(RUNTIME / 'fire.tres') == record['presentation_material_sha256']
            assert sha(RUNTIME / 'fire.gdshader') == record['presentation_shader_sha256']
        bpy.ops.wm.open_mainfile(filepath=str(master));bpy.context.scene.frame_set(0)
        verify_geometry();actual=metrics();assert all(record[k]==v for k,v in actual.items()),(kind,actual)
        envelope=animation_envelope();gltf=gltf_metrics(runtime)
        assert all(record[k]==v for k,v in gltf.items())
        checks.append({'kind':kind,'master_reopened':True,'hashes_match':True,**actual,**envelope,**gltf})
    (REVIEW/'source-verification.json').write_text(json.dumps(checks,indent=2)+'\n')
    print('DISASTER_SOURCES_VERIFIED',len(checks))


def main():
    global REVIEW
    parser=argparse.ArgumentParser();parser.add_argument('--only',choices=KINDS,nargs='+')
    parser.add_argument('--review-dir',type=Path,help='where preview renders and verification output are written')
    parser.add_argument('--render-only',action='store_true');parser.add_argument('--skip-render',action='store_true')
    parser.add_argument('--verify',action='store_true');parser.add_argument('--frames',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    if args.review_dir:REVIEW=args.review_dir
    bpy.context.preferences.filepaths.save_version=0
    for path in [SOURCE,RUNTIME,REVIEW]:path.mkdir(parents=True,exist_ok=True)
    kinds=args.only or KINDS
    if args.verify:verify(kinds);return
    if not args.render_only:
        records=json.loads((RUNTIME/'provenance.json').read_text()).get('models',{}) if (RUNTIME/'provenance.json').exists() else {}
        for kind in kinds:records[kind]=export(kind)
        data={
            'authoring_tool':'Blender '+bpy.app.version_string,
            'source_units':'metres',
            'runtime_scale':.0625,
            'forward':'Godot -Z',
            'animation':'Incident_loop; authored transforms, skeletons and morphs',
            'provenance':'Original geometry, UVs, vertex-color materials, rigs and animation; no external artwork',
            'models':records,
        }
        (RUNTIME/'provenance.json').write_text(json.dumps(data,indent=2)+'\n')
    if not args.skip_render:
        for kind in kinds:
            for view in ['isometric','street']:studio(kind,view)
            if args.frames:studio(kind,frames=True)
    print('DISASTER_MODELS_COMPLETE',','.join(kinds))


if __name__=='__main__':main()
