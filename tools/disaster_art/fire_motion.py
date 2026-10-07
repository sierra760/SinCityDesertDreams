# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Bake fire's authored runtime poses into shared vertex-animation textures.

Call after fire_batch.consolidate_fire() and before exporting the GLB. The saved
editable Blender master precedes both export conversions and keeps original UVs.
The standalone GLB retains its rig and morph clip; the game's optimized material
uses these atlases on a shared static copy of its mesh instead.
"""
import hashlib
import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix


def _sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _save_half_atlas(path, logical, scene):
    """Logical row0 is the first animation row at the image's visual top.

    Blender's image pixel API is bottom-up. Upload the logical rows reversed;
    verify that loading the actual saved EXR gives exactly that same orientation.
    The runtime must check its actual Image.get_pixel(0,0) against the returned
    landmark; Blender readback alone does not establish another loader's order.
    """
    height,width,_=logical.shape
    # Quantize explicitly before saving; this makes readback verification exact
    # and prevents an implicit color transform from hiding behind a loose bound.
    quantized=logical.astype(np.float16).astype(np.float32)
    pixels=np.ascontiguousarray(quantized[::-1])
    image=bpy.data.images.new(path.stem,width=width,height=height,alpha=True,float_buffer=True,is_data=True)
    image.colorspace_settings.name='Non-Color'
    image.pixels.foreach_set(pixels.ravel())
    settings=scene.render.image_settings
    saved={name:getattr(settings,name) for name in ('file_format','color_mode','color_depth','exr_codec')}
    try:
        settings.file_format='OPEN_EXR';settings.color_mode='RGBA';settings.color_depth='16';settings.exr_codec='ZIP'
        image.save_render(str(path),scene=scene)
    finally:
        # Set format first because Blender validates the supported bit depths.
        settings.file_format=saved['file_format']
        for name in ('color_mode','color_depth','exr_codec'):setattr(settings,name,saved[name])
    bpy.data.images.remove(image)
    loaded=bpy.data.images.load(str(path),check_existing=False)
    loaded.colorspace_settings.name='Non-Color'
    actual=np.empty(width*height*4,dtype=np.float32)
    loaded.pixels.foreach_get(actual);actual=actual.reshape(height,width,4)
    maximum_readback_error=float(np.max(np.abs(actual-pixels)))
    first_top=actual[-1,0].tolist();last_bottom=actual[0,0].tolist()
    bpy.data.images.remove(loaded)
    assert maximum_readback_error<=.000001, (path,maximum_readback_error)
    return {'path':path.name,'sha256':_sha(path),'bytes':path.stat().st_size,
            'half_float':True,'compression':'ZIP','color_space':'Non-Color',
            'readback_max_component_error':maximum_readback_error,
            'blender_pixel_api_top_left':first_top,
            'blender_pixel_api_bottom_left':last_bottom}


def bake_fire_motion(runtime_dir, bake_fps=60):
    scene=bpy.context.scene
    mesh=bpy.data.objects.get('FireSkinnedMesh')
    assert mesh is not None and mesh.type=='MESH'
    assert all(face.use_smooth for face in mesh.data.polygons), 'Split face normals require a loop-domain atlas'
    assert max(abs(mesh.matrix_world[i][j]-Matrix.Identity(4)[i][j]) for i in range(4) for j in range(4))<.000001, 'Expected identity runtime mesh transform'
    assert scene.frame_start==0
    vertex_count=len(mesh.data.vertices)
    width=1024;rows=math.ceil(vertex_count/width)
    source_fps=scene.render.fps
    duration=scene.frame_end/source_fps
    frames=round(duration*bake_fps)+1;height=rows*frames
    source_step=source_fps/bake_fps
    positions=np.zeros((height,width,4),dtype=np.float32)
    normals=np.zeros_like(positions)
    minimum=np.full(3,np.inf,dtype=np.float64);maximum=np.full(3,-np.inf,dtype=np.float64)
    position_error=0.0;normal_error=0.0;normal_length_error=0.0
    landmarks=[]
    for frame in range(frames):
        source_frame=frame*source_step
        scene.frame_set(int(source_frame),subframe=source_frame%1);bpy.context.view_layer.update()
        obj=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
        evaluated=obj.to_mesh()
        assert len(evaluated.vertices)==vertex_count, 'Animated topology changed'
        co=np.empty(vertex_count*3,dtype=np.float32)
        no=np.empty(vertex_count*3,dtype=np.float32)
        evaluated.vertices.foreach_get('co',co)
        evaluated.vertices.foreach_get('normal',no)
        obj.to_mesh_clear()
        co=co.reshape(-1,3);no=no.reshape(-1,3)
        # Source metres +Z up/+Y forward -> glTF/Godot +Y up/-Z forward.
        co=np.column_stack((co[:,0],co[:,2],-co[:,1]))
        no=np.column_stack((no[:,0],no[:,2],-no[:,1]))
        lengths=np.linalg.norm(no,axis=1)
        assert float(np.min(lengths))>.5, 'Degenerate evaluated vertex normal'
        no/=lengths[:,None]
        offset=frame*rows
        destination=positions[offset:offset+rows].reshape(-1,4)
        destination[:vertex_count,:3]=co;destination[:vertex_count,3]=1
        destination=normals[offset:offset+rows].reshape(-1,4)
        destination[:vertex_count,:3]=no;destination[:vertex_count,3]=1
        quantized=co.astype(np.float16).astype(np.float32)
        normal_quantized=no.astype(np.float16).astype(np.float32)
        position_error=max(position_error,float(np.max(np.linalg.norm(quantized-co,axis=1))))
        normal_error=max(normal_error,float(np.max(np.linalg.norm(normal_quantized-no,axis=1))))
        normal_length_error=max(normal_length_error,float(np.max(np.abs(np.linalg.norm(normal_quantized,axis=1)-1))))
        minimum=np.minimum(minimum,np.minimum(np.min(co,axis=0),np.min(quantized,axis=0)))
        maximum=np.maximum(maximum,np.maximum(np.max(co,axis=0),np.max(quantized,axis=0)))
        if frame in (0,1,60,120,180,240):
            landmarks.append({'frame':frame,'source_frame':source_frame,'vertex0_position':quantized[0].tolist(),
                              'vertex0_normal':normal_quantized[0].tolist(),
                              'last_vertex_position':quantized[-1].tolist()})
    assert position_error<=.016, ('Half-float position error',position_error)
    assert normal_error<=.001, ('Half-float normal error',normal_error)
    seam=float(np.max(np.linalg.norm(positions[:rows,:,:3]-positions[-rows:,:,:3],axis=2)))
    assert seam<.002, ('Loop position seam',seam)
    # Compare the shader's actual adjacent-frame HALF texture interpolation
    # against evaluated skin/morph geometry between every pair of baked frames.
    half_positions=positions.astype(np.float16).astype(np.float32)
    half_normals=normals.astype(np.float16).astype(np.float32)
    interpolation_error=0.0;normal_angle_error=0.0;minimum_normal_mix_length=1.0
    interpolation_worst={};normal_fallback_count=0
    for frame in range(frames-1):
        source_frame=(frame+.5)*source_step
        scene.frame_set(int(source_frame),subframe=source_frame%1);bpy.context.view_layer.update()
        obj=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());evaluated=obj.to_mesh()
        co=np.empty(vertex_count*3,dtype=np.float32);no=np.empty(vertex_count*3,dtype=np.float32)
        evaluated.vertices.foreach_get('co',co);evaluated.vertices.foreach_get('normal',no)
        obj.to_mesh_clear();co=co.reshape(-1,3);no=no.reshape(-1,3)
        co=np.column_stack((co[:,0],co[:,2],-co[:,1]))
        no=np.column_stack((no[:,0],no[:,2],-no[:,1]))
        no/=np.linalg.norm(no,axis=1)[:,None]
        first=half_positions[frame*rows:(frame+1)*rows].reshape(-1,4)[:vertex_count,:3]
        second=half_positions[(frame+1)*rows:(frame+2)*rows].reshape(-1,4)[:vertex_count,:3]
        actual=(first+second)*.5
        errors=np.linalg.norm(actual-co,axis=1);index=int(np.argmax(errors));error=float(errors[index])
        assert np.all(np.isfinite(errors))
        if error>interpolation_error:
            interpolation_error=error
            owner=mesh.data.vertices[index].groups[0].group
            interpolation_worst={'frame':source_frame,'atlas_frame':frame+.5,'vertex_index':index,
                'motion_group':mesh.vertex_groups[owner].name,
                'source_position':co[index].tolist(),'texture_interpolated_position':actual[index].tolist()}
        first=half_normals[frame*rows:(frame+1)*rows].reshape(-1,4)[:vertex_count,:3]
        second=half_normals[(frame+1)*rows:(frame+2)*rows].reshape(-1,4)[:vertex_count,:3]
        mixed=(first+second)*.5;lengths=np.linalg.norm(mixed,axis=1)
        minimum_normal_mix_length=min(minimum_normal_mix_length,float(np.min(lengths)))
        fallback=lengths<.0001;normal_fallback_count+=int(np.count_nonzero(fallback))
        mixed[fallback]=first[fallback];lengths=np.linalg.norm(mixed,axis=1)
        assert float(np.min(lengths))>.0001, 'Normal fallback remains degenerate'
        mixed/=lengths[:,None]
        cosine=np.clip(np.sum(mixed*no,axis=1),-1,1)
        normal_angle_error=max(normal_angle_error,float(np.max(np.degrees(np.arccos(cosine)))))
    output=Path(runtime_dir);output.mkdir(parents=True,exist_ok=True)
    position_file=_save_half_atlas(output/'fire-motion-positions.exr',positions,scene)
    normal_file=_save_half_atlas(output/'fire-motion-normals.exr',normals,scene)
    # glTF flips UV V. Encode 1-row in Blender so imported UV.y is an integer
    # within-frame row. X is already the texel center. UV2 material data stays.
    uv=mesh.data.uv_layers.get('UVMap')
    assert uv is not None and mesh.data.uv_layers.get('FireMaterial') is not None
    for loop in mesh.data.loops:
        index=loop.vertex_index
        uv.data[loop.index].uv=((index%width+.5)/width,1-index//width)
    scene.frame_set(0)
    return {'vertex_count':vertex_count,'atlas_width':width,'atlas_height':height,
            'rows_per_frame':rows,'frames':frames,'frame_count':frames,'fps':bake_fps,'source_fps':source_fps,
            'duration_seconds':duration,
            'position_space':'Godot axes (source.x, source.z, -source.y), source metres before runtime /16',
            'logical_row_order':'top-to-bottom; row=frame*rows_per_frame+vertex_index//atlas_width',
            'blender_pixel_order':'logical rows vertically reversed for bottom-up Blender pixel API',
            'uv0_encoding':'imported UV.x=(vertex_index%width+.5)/width; imported UV.y=vertex_index//width',
            'sampling':'nearest texels; explicitly interpolate adjacent frame positions and normalize interpolated normals',
            'smooth_vertex_normals':True,'all_frame_positions_min':minimum.tolist(),'all_frame_positions_max':maximum.tolist(),
            'max_half_position_error_source_metres':position_error,
            'max_half_normal_vector_error':normal_error,'max_half_normal_length_error':normal_length_error,
            'loop_position_seam_source_metres':seam,'landmarks':landmarks,
            'half_frame_interpolation':{'sample_count':frames-1,
                'max_position_error_source_metres':interpolation_error,
                'worst':interpolation_worst,'max_normal_angle_error_degrees':normal_angle_error,
                'minimum_mixed_normal_length':minimum_normal_mix_length,
                'normal_fallback_count':normal_fallback_count,
                'normal_fallback_rule':'normalize(first_frame_normal) if length(mix(normal0,normal1,t))<0.0001'},
            'frame0_vertex0_position':landmarks[0]['vertex0_position'],
            'frame120_vertex0_position':next(p['vertex0_position'] for p in landmarks if p['frame']==120),
            'bounds_include_half_quantized_positions':True,
            'position_texture':position_file,'normal_texture':normal_file}
