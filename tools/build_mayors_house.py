#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Scoped motor-court revision of the retained code-243 model.

Run python3 tools/build_mayors_house.py. Retains original bytes locally,
keeps the existing shared texture references/materials, and compacts the house
and porch into the back of its unchanged 32 m lot. A restrained set of roof
tiles, classical porch details and garden beds fit the original triangle budget.
The editable revised master and its source hashes are retained locally; the
art record identifies this exact runtime geometry.
"""
import math
import json
from pathlib import Path
import numpy as np
from fix_mirrored_textures import (ROOT, ASSETS, read_glb, write_glb, set_hashes,
                                  load_json, save_json, sha, LANDSCAPING, CATALOG)
from split_model_palms import parts_of, strip, accessor_array, triangle_count

SOURCE = ROOT/'assets/mayors-house'
MODEL = ASSETS/'243-blender.glb'
LAYOUT = ASSETS/'mayors-house.json'


def revise(original: bytes, layout: dict) -> bytes:
    doc, binary = read_glb(original)
    assert not any(n.get('name') == 'MayorHelipad' for n in doc['nodes']), 'input is already revised'
    parts = parts_of(doc, binary)
    gone = []
    tile_index=0
    for p in parts:
        size = p['hi']-p['lo']
        base = size[0]>31 and size[2]>31 and p['hi'][1]<.201
        garden = p['material'] in ('foliage.001','leaflight.001') and not base
        tile = False
        if p['material']=='tile_light':
            tile_index += 1
            tile = tile_index%4 != 0
        boundary = p['material']=='warm_light' and p['hi'][1]<.501 and max(size[0],size[2])>10
        path = p['material'].split(' • ')[0]=='warm_roof' and p['hi'][1]<.22
        if garden or tile or boundary or path: gone.append(p)
    doc,binary,_=strip(doc,binary,[{'parts':gone}])
    # Transform only retained house parts, never the supporting lot slab.
    transformed=set()
    for mesh in doc['meshes']:
        for prim in mesh['primitives']:
            idx=prim['attributes']['POSITION']
            if idx in transformed: continue
            transformed.add(idx)
            values=accessor_array(doc,binary,idx).copy()
            base=(values[:,1]<=.201).all() and np.ptp(values[:,0])>31 and np.ptp(values[:,2])>31
            # A collision primitive also holds the base slab; exempt its base
            # vertices by position, since the compacting transform is per vertex.
            mask=np.ones(len(values),bool)
            if base: mask[:]=False
            elif mesh is doc['meshes'][0]:
                mask=~((values[:,1]<=.201)&((np.abs(values[:,0])>15.7)|(np.abs(values[:,2])>15.7)))
            values[mask,0]*=.85
            values[mask,2]=values[mask,2]*.55-7.8
            values[mask,1]=.2+(values[mask,1]-.2)*.72
            a=doc['accessors'][idx];v=doc['bufferViews'][a['bufferView']]
            offset=v.get('byteOffset',0)+a.get('byteOffset',0)
            binary[offset:offset+values.nbytes]=values.tobytes()
            a['min']=values.min(0).tolist();a['max']=values.max(0).tolist()
            normal_idx=prim['attributes'].get('NORMAL')
            if normal_idx is not None and not base:
                ns=accessor_array(doc,binary,normal_idx).copy()
                ns[:,0]/=.85;ns[:,1]/=.72;ns[:,2]/=.55
                ns/=np.maximum(np.linalg.norm(ns,axis=1,keepdims=True),1e-9)
                na=doc['accessors'][normal_idx];nv=doc['bufferViews'][na['bufferView']]
                off=nv.get('byteOffset',0)+na.get('byteOffset',0)
                binary[off:off+ns.nbytes]=ns.tobytes()

    def accessor(values, typ, component=5126, target=34962):
        values=np.asarray(values, np.float32 if component==5126 else np.uint16)
        while len(binary)%4: binary.append(0)
        vi=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':len(binary),'byteLength':values.nbytes,'target':target})
        binary.extend(values.tobytes())
        a={'bufferView':vi,'componentType':component,'count':len(values),'type':typ}
        if typ=='VEC3':a.update(min=values.min(0).tolist(),max=values.max(0).tolist())
        doc['accessors'].append(a);return len(doc['accessors'])-1

    def quads(name, rectangles, material):
        positions=[];normals=[];uv=[];indices=[]
        for x,z,w,d,y in rectangles:
            n=len(positions)
            positions.extend([(x-w/2,y,z-d/2),(x-w/2,y,z+d/2),(x+w/2,y,z+d/2),(x+w/2,y,z-d/2)])
            normals.extend([(0,1,0)]*4);uv.extend([(0,0),(0,d*.25),(w*.25,d*.25),(w*.25,0)])
            indices.extend([n,n+1,n+2,n,n+2,n+3])
        p={'attributes':{'POSITION':accessor(positions,'VEC3'),'NORMAL':accessor(normals,'VEC3'),'TEXCOORD_0':accessor(uv,'VEC2')},'indices':accessor(indices,'SCALAR',5123,34963),'material':material}
        mi=len(doc['meshes']);doc['meshes'].append({'name':name,'primitives':[p]})
        ni=len(doc['nodes']);doc['nodes'].append({'name':name,'mesh':mi});doc['scenes'][0]['nodes'].append(ni)

    def geometry(name, positions, indices, material, collision=False):
        # Flat normals keep the small architectural profiles crisp. All new
        # surfaces reuse the original palette; the compiler merges by material.
        points=[];normals=[];uv=[];remapped=[];unique={}
        for start in range(0,len(indices),3):
            a,b,c=[np.asarray(positions[indices[start+j]],float) for j in range(3)]
            normal=np.cross(b-a,c-a)
            length=np.linalg.norm(normal)
            if length<1e-9: continue
            normal/=length
            for v in [a,b,c]:
                texture=(v[0]*.25,v[1]*.25)
                key=tuple(np.round(np.r_[v,normal,texture],6))
                if key not in unique:
                    unique[key]=len(points);points.append(v);normals.append(normal);uv.append(texture)
                remapped.append(unique[key])
        prim={'attributes':{'POSITION':accessor(points,'VEC3'),'NORMAL':accessor(normals,'VEC3'),'TEXCOORD_0':accessor(uv,'VEC2')},'indices':accessor(remapped,'SCALAR',5123,34963),'material':material}
        if collision:
            doc['meshes'][0]['primitives'].append(prim)
            return
        mi=len(doc['meshes']);doc['meshes'].append({'name':name,'primitives':[prim]})
        ni=len(doc['nodes']);doc['nodes'].append({'name':name,'mesh':mi});doc['scenes'][0]['nodes'].append(ni)

    def boxes(name, rows, material, collision=False):
        vertices=[];indices=[]
        for x,y,z,w,h,d in rows:
            first=len(vertices)
            vertices.extend([(x+dx*w/2,y+dy*h/2,z+dz*d/2) for dx,dy,dz in
                             [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]])
            for a,b,c in [(0,2,1),(0,3,2),(4,5,6),(4,6,7),(0,1,5),(0,5,4),(3,7,6),(3,6,2),(0,4,7),(0,7,3),(1,2,6),(1,6,5)]:
                indices.extend([first+a,first+b,first+c])
        geometry(name,vertices,indices,material,collision)

    def arches(name, rows, material):
        points=[];indices=[]
        for x,y,z,rx,ry,thickness in rows:
            first=len(points)
            for i in range(9):
                angle=math.pi*i/8
                for inset in [0,thickness]:points.append((x+(rx-inset)*math.cos(angle),y+(ry-inset)*math.sin(angle),z))
            for i in range(8):
                n=first+i*2;indices.extend([n,n+2,n+3,n,n+3,n+1])
        geometry(name,points,indices,material)

    mats={m['name']:i for i,m in enumerate(doc['materials'])}
    # Flush paving and paint. The existing lot collider supports them, avoiding
    # extra overlapping floor bodies and preserving a ground-level connection.
    quads('Mayor motor court',[(0,7.65,29.6,16.7,.205)],mats['paving_dark • concrete'])
    paint=[]
    # Three bays with long truck clearance and an open front apron.
    for x in [.2,4.3,8.9,13.6]:paint.append((x,4.8,.10,9.4,.215))
    paint.append((6.9,.1,13.5,.10,.215))
    # Square pad outline and an original H, all flat painted geometry.
    for x in [-13,-2]:paint.append((x,6,.12,11,.215))
    for z in [.5,11.5]:paint.append((-7.5,z,11,.12,.215))
    for x in [-8.8,-6.2]:paint.append((x,6,.32,4,.215))
    paint.append((-7.5,6,2.6,.32,.215))
    quads('Mayor bay and helipad paint',paint,mats['warm_light'])
    quads('Mayor walking path',[(0,-.45,4.8,.5,.218)],mats['warm_roof'])
    # A low, broad Spanish Revival residence: tiled hip roofs, layered stone
    # cornices, louvered teal shutters and an arcaded porch. All detail stays
    # behind the motor court's clear walking/vehicle/takeoff envelopes.
    cream=mats['warm_light'];teal=mats['teal.001'];dark=mats['teal_dark']
    trim=[]
    for y,h in [(5.65,.20),(9.99,.22),(10.16,.12)]:
        trim.extend([(0,y,-5.99,17.4,h,.24),(0,y,-13.77,17.4,h,.24),(-8.55,y,-9.88,.24,h,7.9),(8.55,y,-9.88,.24,h,7.9)])
    for x in [-8.34,8.34]:
        for z in [-6.01,-13.68]:trim.append((x,5.79,z,.32,8.5,.24))
    boxes('Mayor layered limestone cornices and pilasters',trim,cream)
    arches('Mayor shaded porch arcade',[(x,4.17,-3.44,r,.51,.15) for x,r in [(-3.4,1.53),(0,1.87),(3.4,1.53)]],cream)
    windows=[(x,7.40,1.73) for x in [-6.545,-2.21,2.21,6.545]]+[(x,3.22,1.73) for x in [-6.545,6.545]]
    shutters=[];slats=[];caps=[]
    for x,y,h in windows:
        caps.append((x,y+h/2+.06,-5.91,.77,.29,.105))
        for side in [-1,1]:
            sx=x+side*.87
            shutters.append((sx,y,-5.91,.36,h+.08,.12))
            for dy in [-.55,-.18,.18,.55]:slats.append((sx,y+dy,-5.825,.31,.045,.045))
    boxes('Mayor deep teal shutters',shutters,teal)
    louver_points=[];louver_indices=[]
    for x,y,z,w,h,d in slats:
        n=len(louver_points)
        louver_points.extend([(x-w/2,y-h/2,z),(x+w/2,y-h/2,z),(x+w/2,y+h/2,z),(x-w/2,y+h/2,z)])
        louver_indices.extend([n,n+1,n+2,n,n+2,n+3])
    geometry('Mayor shutter louvers',louver_points,louver_indices,dark)
    arches('Mayor limestone window crowns',caps,cream)
    # Low stone balustrades frame the wide, open entrance stair.
    rails=[]
    for side in [-1,1]:
        x=side*4.1
        rails.extend([(x,1.60,-3.16,2.65,.20,.27),(x,2.39,-3.16,2.72,.16,.30)])
        for dx in [-1.08,-.36,.36,1.08]:rails.append((x+dx,1.99,-3.16,.13,.65,.13))
    boxes('Mayor carved porch balustrades',rails,cream)
    boxes('Mayor balustrade physical faces',rails,cream,True)
    # Slender paired chimney stacks are seated through the pitched roof.
    stacks=[];chimney_caps=[]
    for x in [-5.4,5.4]:
        stacks.append((x,11.8,-11.55,.72,2.6,.80))
        chimney_caps.extend([(x,13.10,-11.55,.98,.16,1.02),(x,12.87,-11.55,.86,.10,.92)])
    boxes('Mayor stucco chimney stacks',stacks,mats['cream_wall'])
    boxes('Mayor terracotta chimney caps',chimney_caps,mats['terracotta'])
    # Garden beds use low shared-color forms, away from both pad and bays.
    beds=[]
    for x in [-12.2,12.2]:
        beds.extend([(x,.37,-3.0,4.0,.28,.18),(x,.37,-13.6,4.0,.28,.18),(x-1.91,.37,-8.3,.18,.28,10.6),(x+1.91,.37,-8.3,.18,.28,10.6)])
    boxes('Mayor walled parterre beds',beds,cream)
    # Small bronze lanterns and an original sun medallion dress the entrance.
    lamps=[];glass=[]
    for x in [-1.8,1.8]:
        lamps.extend([(x,3.25,-5.70,.34,.10,.30),(x,2.76,-5.70,.32,.09,.28),(x-.12,3.0,-5.59,.045,.40,.045),(x+.12,3.0,-5.59,.045,.40,.045)])
        glass.append((x,3.0,-5.65,.22,.37,.18))
    boxes('Mayor porch lantern frames',lamps,dark)
    boxes('Mayor porch lantern glass',glass,mats['glass_light.001'])
    # Relief disk and eight tapered rays, on the facade between upper windows.
    points=[(0,7.45,-5.84)];inds=[]
    for i in range(16):
        a=math.tau*i/16;points.append((.36*math.cos(a),7.45+.36*math.sin(a),-5.84))
    for i in range(16):inds.extend([0,1+i,1+(i+1)%16])
    for i in range(8):
        a=math.tau*i/8;n=len(points)
        points.extend([(.46*math.cos(a-.1),7.45+.46*math.sin(a-.1),-5.84),(.66*math.cos(a),7.45+.66*math.sin(a),-5.84),(.46*math.cos(a+.1),7.45+.46*math.sin(a+.1),-5.84)])
        inds.extend([n,n+1,n+2])
    geometry('Mayor bronze desert sun crest',points,inds,mats['wood_light'])
    doc,binary,_=strip(doc,binary,[])
    for name,point in [('MayorWalkStart',layout['walk'])]+[(s['marker'],s['position']) for s in layout['slots']]:
        node={'name':name,'translation':[point[0],layout['ground_m'],point[1]]}
        doc['scenes'][0]['nodes'].append(len(doc['nodes']));doc['nodes'].append(node)
    for index,point in enumerate(layout['trees']):
        doc['scenes'][0]['nodes'].append(len(doc['nodes']))
        doc['nodes'].append({'name':f'MayorTree_{index:02d}','translation':[point[0],layout['ground_m'],point[1]]})
    # Cream stone and paint are reflective finishes, not the generic neon
    # role associated with the old warm_light name. No material is added.
    doc['materials'][mats['warm_light']]['name']='mayor_cream_trim'
    doc['buffers'][0]['byteLength']=len(binary)
    return write_glb(doc,binary)


def main():
    SOURCE.mkdir(parents=True,exist_ok=True)
    original=SOURCE/'243-original.glb'
    if not original.exists(): original.write_bytes(MODEL.read_bytes())
    before=original.read_bytes();layout=load_json(LAYOUT)
    assert sha(before)=='ebdde1fbdf559b59df7e90c0777059a32a2c5dda411dc8d311230fb08e7a8dc0', 'original Mayor house does not match the recorded source; refusing to rewrite'
    after=revise(before,layout);doc,binary=read_glb(after)
    assert triangle_count(doc,binary)<=4874
    MODEL.write_bytes(after);set_hashes(243,after)
    catalog=load_json(CATALOG)
    for row in catalog['entries']:
        if row['code']==243:
            row['triangles']=triangle_count(doc,binary)
            row['height']=max(float(p['hi'][1]) for p in parts_of(doc,binary) if not p['collision'])/16.0
    save_json(CATALOG,catalog)
    landscaping=load_json(LANDSCAPING)
    for row in landscaping['entries']:
        if row['code']==243:
            # Two rows of three shared global vegetation anchors, matching the
            # approved parterre layout. The existing system selects the species.
            row['palms']=[[x/16.0,layout['ground_m']/16.0,z/16.0,.5,1.25/16.0] for x,z in layout['trees']]
    save_json(LANDSCAPING,landscaping)
    save_json(ROOT/'docs/art/mayors-house.json',{'code':243,'tool':'tools/build_mayors_house.py','original_sha256':sha(before),'runtime_sha256':sha(after),'triangles':triangle_count(doc,binary),'layout':'game/assets/desert-dreams-3d/mayors-house.json','description':'Spanish Revival cream residence with tiled hip roofs, shutters, limestone cornices, arcaded porch and balustrades; ground-level motor court; two side rows of three global elevation-based planting anchors; original shared material/texture sets retained.'})
    print(f'Mayor house: {triangle_count(doc,binary)} triangles, {len(doc["materials"])} materials, {len(after)} bytes')

if __name__=='__main__': main()
