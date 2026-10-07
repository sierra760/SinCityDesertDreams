# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Export-only rigid-skin batching for authored fire; editable source stays separate.

Call consolidate_fire() after saving the original Blender master, before GLB export.
The returned single mesh retains disconnected original topology, UVs, point colors,
face materials, all independent flame motion in six phase-basis morph targets,
and one bone per motion group. Morph weights remain in the range zero to one.
"""
import math
import bpy
from mathutils import Matrix, Vector


def linear_keys(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for point in curve.keyframe_points: point.interpolation='LINEAR'


def consolidate_fire(verify=True, remove_sources=True, single_surface=True):
    scene=bpy.context.scene
    scene.frame_set(scene.frame_start)
    source=[o for o in scene.objects if o.type=='MESH']
    assert source and all(not o.modifiers for o in source), 'Expected authored unskinned fire meshes'
    parents=list(dict.fromkeys(o.parent for o in source))
    assert None not in parents and all(p.type=='EMPTY' and p.parent is None for p in parents), 'Unexpected fire hierarchy'
    assert all(not o.animation_data for o in source), 'Animated child requires a separate bone'
    group_names={p:'Motion_%02d'%i for i,p in enumerate(parents)}
    # Bind bones retain translation only, avoiding inverse bind shear under the
    # independently scaled/rotated flame roots. Animated poses use full source LRS.
    rest={p:Matrix.Translation(p.matrix_world.translation) for p in parents}
    relative={o:o.parent.matrix_world.inverted()@o.matrix_world for o in source}
    verts=[];faces=[];material_names=[];materials=[];face_material=[];smooth=[]
    colors=[];uvs=[];ranges={};shape_specs=[]
    for obj in source:
        start=len(verts);transform=rest[obj.parent]@relative[obj]
        keydata=obj.data.shape_keys
        basis=keydata.key_blocks[0].data if keydata else obj.data.vertices
        verts.extend(transform@v.co for v in basis)
        ranges[obj]=(start,len(verts))
        for face in obj.data.polygons:
            faces.append(tuple(start+i for i in face.vertices));smooth.append(face.use_smooth)
            mat=obj.data.materials[face.material_index]
            if mat.name not in material_names:material_names.append(mat.name);materials.append(mat)
            face_material.append(material_names.index(mat.name))
            uvs.extend(tuple(obj.data.uv_layers.active.data[j].uv) for j in face.loop_indices)
        col=obj.data.color_attributes['Mottle'];assert col.domain=='POINT'
        colors.extend(tuple(entry.color) for entry in col.data)
        if keydata:
            assert keydata.use_relative
            for key in list(keydata.key_blocks)[1:]:
                assert key.relative_key==keydata.key_blocks[0]
                delta=[transform.to_3x3()@(v.co-basis[j].co) for j,v in enumerate(key.data)]
                shape_specs.append((obj,key.name,'Flame_%02d_%s'%(len(shape_specs),key.name),delta))
    # The authored11flames use opposed sculpt deltas driven by three sine
    # frequencies with distinct phases. Fit/verify their actual sampled curves,
    # rather than assume the shape names encode frequency or phase.
    grid=list(range(scene.frame_start,scene.frame_end+1,4))
    assert grid[-1]==scene.frame_end and scene.frame_start==0
    samples={obj:[] for obj in source if obj.data.shape_keys}
    for frame in grid:
        scene.frame_set(frame)
        for obj in samples:
            keys=obj.data.shape_keys.key_blocks
            assert len(keys)==3, 'Expected exactly two opposed flame sculpts'
            samples[obj].append(keys[1].value-keys[2].value)
    target_deltas={(frequency,axis):[Vector((0,0,0)) for _ in verts]
                   for frequency in (4,5,6) for axis in ('sin','cos')}
    waveform_error=0;opposition_error=0;phase_records=[]
    for obj,values in samples.items():
        matching=[spec for spec in shape_specs if spec[0]==obj]
        assert len(matching)==2
        delta_a,delta_b=matching[0][3],matching[1][3]
        opposition_error=max(opposition_error,max((a+b).length for a,b in zip(delta_a,delta_b)))
        candidates=[]
        for frequency in (4,5,6):
            angles=[math.tau*frequency*frame/scene.frame_end for frame in grid]
            n=len(values)-1
            sine=2*sum(v*math.sin(a) for v,a in zip(values[:-1],angles[:-1]))/n
            cosine=2*sum(v*math.cos(a) for v,a in zip(values[:-1],angles[:-1]))/n
            error=max(abs(v-sine*math.sin(a)-cosine*math.cos(a)) for v,a in zip(values,angles))
            candidates.append((error,frequency,sine,cosine))
        error,frequency,sine,cosine=min(candidates)
        waveform_error=max(waveform_error,error)
        phase_records.append({'flame':obj.name,'cycles':frequency,'sin_coefficient':sine,'cos_coefficient':cosine,'waveform_error':error})
        start,end=ranges[obj]
        for i in range(start,end):
            target_deltas[(frequency,'sin')][i]=delta_a[i-start]*sine
            target_deltas[(frequency,'cos')][i]=delta_a[i-start]*cosine
    assert opposition_error<.00001, ('Non-opposed sculpt deformation',opposition_error)
    assert waveform_error<.00001, ('Unrepresented flame timing',waveform_error)
    # B'=B-sum(D); target deltas2D with weights(1+sin/cos)/2. This
    # preserves signed independent flame deflection with nonnegative weights.
    for values in target_deltas.values():
        for i,delta in enumerate(values):verts[i]-=delta
    data=bpy.data.meshes.new('Fire consolidated source geometry')
    data.from_pydata(verts,[],faces);data.update()
    mesh=bpy.data.objects.new('FireSkinnedMesh',data);scene.collection.objects.link(mesh)
    material_records=[]
    for material in materials:
        bs=material.node_tree.nodes.get('Principled BSDF')
        material_records.append({'name':material.name,
            'emission_strength':float(bs.inputs['Emission Strength'].default_value),
            'emission_color':list(bs.inputs['Emission Color'].default_value[:3]),
            'roughness':float(bs.inputs['Roughness'].default_value)})
    if single_surface:
        # Godot's authored fire shader reads baked albedo from COLOR and
        # glTF UV2.x/y as emission strength / (1-roughness): the exporter
        # flips Blender UV V. The shader decodes ROUGHNESS=1-UV2.y. Its palette lookup
        # preserves the source material's constant (unmottled) emission color.
        material=bpy.data.materials.new('FireVertexPalette')
        material.use_nodes=True
        bs=material.node_tree.nodes.get('Principled BSDF')
        color=material.node_tree.nodes.new('ShaderNodeVertexColor');color.layer_name='Mottle'
        material.node_tree.links.new(color.outputs['Color'],bs.inputs['Base Color'])
        bs.inputs['Roughness'].default_value=.85
        data.materials.append(material)
    else:
        for material in materials:data.materials.append(material)
    for i,face in enumerate(data.polygons):
        face.material_index=0 if single_surface else face_material[i]
        face.use_smooth=smooth[i]
    uv=data.uv_layers.new(name='UVMap')
    for i,value in enumerate(uvs):uv.data[i].uv=value
    mask=data.uv_layers.new(name='FireMaterial')
    for i,face in enumerate(data.polygons):
        material=material_records[face_material[i]]
        for loop in face.loop_indices:
            mask.data[loop].uv=(material['emission_strength'],material['roughness'])
    data.uv_layers.active_index=0
    col=data.color_attributes.new(name='Mottle',type='FLOAT_COLOR',domain='POINT')
    for i,value in enumerate(colors):col.data[i].color=value
    mesh.shape_key_add(name='Basis',from_mix=False)
    for (frequency,axis),deltas in target_deltas.items():
        key=mesh.shape_key_add(name='Frequency_%d_%s'%(frequency,axis),from_mix=False)
        for i,v in enumerate(verts):key.data[i].co=v+deltas[i]*2
    armature=bpy.data.armatures.new('Fire export motion groups')
    rig=bpy.data.objects.new('FireMotionRig',armature);scene.collection.objects.link(rig)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')
    for parent in parents:
        bone=armature.edit_bones.new(group_names[parent])
        bone.head=rest[parent].translation;bone.tail=bone.head+Vector((0,1,0))
    bpy.ops.object.mode_set(mode='OBJECT')
    for parent in parents:
        group=mesh.vertex_groups.new(name=group_names[parent])
        for obj in source:
            if obj.parent==parent:
                start,end=ranges[obj];group.add(list(range(start,end)),1,'REPLACE')
    mod=mesh.modifiers.new('Baked authored motion','ARMATURE');mod.object=rig
    mesh.parent=rig
    # Sample all authored frames; SCENE export samples these at the same 30fps.
    previous_quaternion={}
    for frame in range(scene.frame_start,scene.frame_end+1):
        scene.frame_set(frame)
        for parent in parents:
            bone=rig.pose.bones[group_names[parent]];bone.rotation_mode='QUATERNION'
            bone.matrix=parent.matrix_world
            previous=previous_quaternion.get(parent)
            if previous is not None and bone.rotation_quaternion.dot(previous)<0:
                bone.rotation_quaternion.negate()
            previous_quaternion[parent]=bone.rotation_quaternion.copy()
            # Matrix is the source parent's LRS, with no parent-generated shear.
            for prop in ('location','rotation_quaternion','scale'):bone.keyframe_insert(data_path=prop,frame=frame)
    for frame in grid:
        for frequency,axis in target_deltas:
            angle=math.tau*frequency*frame/scene.frame_end
            wave=math.sin(angle) if axis=='sin' else math.cos(angle)
            key=data.shape_keys.key_blocks['Frequency_%d_%s'%(frequency,axis)]
            key.value=(1+wave)/2
            key.keyframe_insert(data_path='value',frame=frame)
    rig.animation_data.action.name='FireMotion_loop'
    data.shape_keys.animation_data.action.name='FireFlames_loop'
    linear_keys(rig.animation_data.action);linear_keys(data.shape_keys.animation_data.action)
    metrics={
        'source_meshes':len(source),
        'runtime_meshes':1,
        'materials':1 if single_surface else len(materials),
        'source_materials':len(materials),
        'material_palette':material_records,
        'material_encoding':('COLOR albedo; TEXCOORD_1.xy emission_strength and one_minus_roughness'
                             if single_surface else 'source materials'),
        'bones':len(parents),
        'morph_targets':len(target_deltas),
        'source_morph_targets':len(shape_specs),
        'independent_flames':len(samples),
        'waveform_reconstruction_error':waveform_error,
        'sculpt_opposition_error_m':opposition_error,
        'phase_basis':phase_records,
        'triangles':sum(len(f.vertices)-2 for f in data.polygons),
        'vertex_count':len(verts),
        'maximum_vertex_error_m':0,
        'maximum_integer_vertex_error_m':0,
        'maximum_half_frame_vertex_error_m':0,
        'verified_frames':0,
    }
    if verify:
        for sample in range(scene.frame_start*2,scene.frame_end*2+1):
            frame=sample/2
            scene.frame_set(int(frame),subframe=frame%1);bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
            final=mesh.evaluated_get(dg);final_mesh=final.to_mesh()
            for obj in source:
                original=obj.evaluated_get(dg);original_mesh=original.to_mesh();start,end=ranges[obj]
                for i,v in enumerate(original_mesh.vertices):
                    actual=final.matrix_world@final_mesh.vertices[start+i].co
                    expected=original.matrix_world@v.co
                    error=(actual-expected).length
                    category='maximum_half_frame_vertex_error_m' if sample%2 else 'maximum_integer_vertex_error_m'
                    metrics[category]=max(metrics[category],error)
                    if error>metrics['maximum_vertex_error_m']:
                        metrics['maximum_vertex_error_m']=error
                        metrics['worst']={'frame':frame,'source':obj.name,'vertex':i,'expected':list(expected),'actual':list(actual),'bone_matrix_error':max(abs(rig.pose.bones[group_names[obj.parent]].matrix[r][c]-obj.parent.matrix_world[r][c]) for r in range(4) for c in range(4))}
                original.to_mesh_clear()
            final.to_mesh_clear();metrics['verified_frames']+=1
        print('VALIDATE',metrics,flush=True)
        assert metrics['maximum_integer_vertex_error_m']<.0001, metrics
        # Quaternion interpolation replaces source Euler interpolation between
        # authored samples. Bound the difference to .016 source metres, or
        # .001 game-tile units after the runtime /16 conversion.
        assert metrics['maximum_half_frame_vertex_error_m']<.016, metrics
    if remove_sources:
        for obj in source:bpy.data.objects.remove(obj,do_unlink=True)
        for obj in parents:bpy.data.objects.remove(obj,do_unlink=True)
    scene.frame_set(scene.frame_start)
    bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True)
    bpy.context.view_layer.objects.active=mesh
    return metrics
