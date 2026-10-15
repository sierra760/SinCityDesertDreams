#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate original static farm geometry, provenance and shared stock enclosures."""
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'tools'))
from model_art.agriculture import lot_definitions
ASSETS=ROOT/'game/assets/desert-dreams-3d'


def read_glb(path):
    data=path.read_bytes()
    assert struct.unpack_from('<III',data)==(0x46546c67,2,len(data)), 'GLB header'
    size,kind=struct.unpack_from('<II',data,12)
    assert kind==0x4e4f534a, 'JSON chunk'
    gltf=json.loads(data[20:20+size])
    offset=20+size
    n,kind=struct.unpack_from('<II',data,offset)
    assert kind==0x004e4942, 'binary chunk'
    return gltf,data[offset+8:offset+8+n]


def load_records():
    path=ROOT/'docs/art/agriculture.json'
    assert path.exists(), 'missing agricultural asset provenance and sixteen models'
    return json.loads(path.read_text())['lots']


def catalog_entry(code):
    rows=json.loads((ASSETS/'catalog.json').read_text())['entries']
    matches=[r for r in rows if r['code']==code]
    assert len(matches)==1, f'{code}: missing or duplicate farm catalog'
    return matches[0]


def positions(gltf,binary,index):
    accessor=gltf['accessors'][index]
    assert accessor['componentType']==5126 and accessor['type']=='VEC3', 'position format'
    view=gltf['bufferViews'][accessor['bufferView']]
    start=view.get('byteOffset',0)+accessor.get('byteOffset',0)
    stride=view.get('byteStride',12)
    return [struct.unpack_from('<fff',binary,start+i*stride) for i in range(accessor['count'])]


def node_bounds(gltf,binary,node):
    vertices=[]
    for primitive in gltf['meshes'][node['mesh']]['primitives']:
        vertices.extend(positions(gltf,binary,primitive['attributes']['POSITION']))
    return [[min(v[i] for v in vertices) for i in range(3)], [max(v[i] for v in vertices) for i in range(3)]]


def bounds_key(bounds):
    return tuple(round(v,3) for xyz in bounds for v in xyz)


def box_bounds(center,size):
    return [[center[i]-size[i]/2 for i in range(3)],[center[i]+size[i]/2 for i in range(3)]]


def validate_lot(record,entry,gltf,binary):
    code=record['code'];label=f'{code} {record["key"]}'
    expected=next((r for r in lot_definitions(ROOT) if r['code']==code),None)
    assert expected is not None, label+': roster identity'
    for key,value in expected.items():
        assert record.get(key)==value, label+(': enclosure contract' if key=='enclosure' else ': roster '+key)
    side=expected['footprint'][0];half=side*8
    assert entry['footprint']==[side,side] and entry['scale']==1/16 and entry['meters_per_tile']==16, label+': footprint scale'
    assert entry['pivot']==[0,0,0] and entry['yaw']==0, label+': transform'
    assert 0<entry['triangles']<=20000, label+': triangle budget'
    assert entry['triangles']==record['triangles'], label+': triangle provenance'
    assert all('uri' not in b for b in gltf.get('buffers',[])), label+': external geometry'
    assert all('uri' not in i and 'bufferView' in i for i in gltf.get('images',[])), label+': external/private image reference'
    assert all(s.get('wrapS',10497)==10497 and s.get('wrapT',10497)==10497 for s in gltf.get('samplers',[])), label+': plain repeat materials'
    assert not gltf.get('skins') and not gltf.get('animations'), label+': static farms contain no imported animals'
    assert all(m.get('name','').startswith('farm_') for m in gltf.get('materials',[])), label+': original farm materials'
    colliders=[n for n in gltf['nodes'] if n.get('name','').endswith('-colonly')]
    assert colliders, label+': missing collider'
    supports=[n for n in colliders if n['name'].startswith('Ground support')]
    assert len(supports)==1, label+': missing ground support'
    assert bounds_key(node_bounds(gltf,binary,supports[0]))==bounds_key([[-half+.025,0,-half+.025],[half-.025,.12,half-.025]]), label+': support bounds'
    visible=[];triangles=0
    for node in gltf['nodes']:
        if 'mesh' not in node:continue
        assert 'matrix' not in node and 'rotation' not in node and 'translation' not in node and 'scale' not in node, label+': geometry must bake transforms'
        bounds=node_bounds(gltf,binary,node)
        for axis in (0,2):
            assert bounds[0][axis]>=-half-.001 and bounds[1][axis]<=half+.001, label+': footprint geometry'
        assert bounds[0][1]>=-.001, label+': below-ground geometry'
        for primitive in gltf['meshes'][node['mesh']]['primitives']:
            accessor=gltf['accessors'][primitive['attributes']['POSITION']]
            for axis in (0,2):
                assert accessor['min'][axis]>=-half-.001 and accessor['max'][axis]<=half+.001, label+': footprint accessor bounds'
            assert all(math.isfinite(v) for xyz in positions(gltf,binary,primitive['attributes']['POSITION']) for v in xyz), label+': nonfinite vertex'
            if not node.get('name','').endswith('-colonly'):
                assert primitive.get('mode',4)==4, label+': triangle topology'
                triangles+=gltf['accessors'][primitive['indices']]['count']//3
        if not node.get('name','').endswith('-colonly'):visible.append(bounds)
    assert triangles==entry['triangles'], label+': actual triangle count'
    actual=[[min(b[0][i] for b in visible) for i in range(3)],[max(b[1][i] for b in visible) for i in range(3)]]
    assert bounds_key(actual)==bounds_key(record['bounds_metres']), label+': authored bounds'
    assert abs(entry['height']-actual[1][1]/16)<1e-6, label+': height units'
    assert len(colliders)==record['collider_count'], label+': collider count'
    if record['enclosure']:
        enclosure=record['enclosure'];assert sum(p['count'] for p in enclosure['pens'])==record['livestock']<=12, label+': enclosure count'
        physical=Counter(bounds_key(node_bounds(gltf,binary,n)) for n in colliders)
        required=[]
        for pen in enclosure['pens']:
            fences=pen['fences']
            assert all(fences[i]['b']==fences[(i+1)%len(fences)]['a'] for i in range(len(fences))), label+': enclosure is not closed'
            assert sum(f['gate'] for f in fences)==1, label+': closed service gate'
            assert {'shelter','trough'} <= {o['kind'] for o in pen['obstacles']}, label+': enclosure shelter/water'
            for f in fences:
                p,q=f['a'],f['b'];h=f['height'];thickness=f['thickness']
                required.append(box_bounds([(p[0]+q[0])/2,.12+h/2,(p[1]+q[1])/2],[max(abs(q[0]-p[0]),thickness),h,max(abs(q[1]-p[1]),thickness)]))
            for o in pen['obstacles']:
                x,y,z=o['center'];w,h,d=o['size']
                x0,z0,x1,z1=pen['bounds'];b=o['bounds']
                assert x0<=b[0]<b[2]<=x1 and z0<=b[1]<b[3]<=z1, label+': enclosure obstacle containment'
                if o['kind']=='shelter':
                    required.extend([box_bounds([x,h/2+.12,z-d/2],[w,h,.12]),box_bounds([x,h+.3,z],[w,.6,d])])
                    for xx in (x-w/2+.13,x+w/2-.13):
                        for zz in (z-d/2+.13,z+d/2-.13):required.append(box_bounds([xx,.12+h/2,zz],[.2,h,.2]))
                else:required.append(box_bounds(o['center'],o['size']))
        for bounds,count in Counter(bounds_key(b) for b in required).items():
            assert physical[bounds]>=count, label+': enclosure geometry/manifest mismatch'

    from check_agriculture_parcels import unique_visible_triangles, validate_shed_details
    unique_visible_triangles(gltf,binary)
    shed={267:(-10,12,7,5,2.8),268:(11,-10,6,6,2.5),273:(-6,-12,26,13,4.8),275:(9,8,8,8,3.2),279:(4.7,5,4,3,2.1),280:(12.7,13,4,3,2.1),281:(20.7,21,4,3,2.1)}
    if record['code'] in shed:validate_shed_details(gltf,binary,*shed[record['code']])


def check():
    records=load_records();expected=lot_definitions(ROOT)
    assert len(records)==16 and {r['key'] for r in records}=={r['key'] for r in expected}, 'ten developed/six state lot coverage'
    assert sum(r['state']=='active' for r in records)==10, 'developed coverage'
    assert len({r['code'] for r in records})==16, 'duplicate farm identity'
    plantings=json.loads((ASSETS/'landscaping.json').read_text())['entries']
    for record in records:
        code=record['code'];path=ASSETS/f'{code}-blender.glb'
        assert path.exists(), f'{code}: missing agricultural model'
        entry=catalog_entry(code)
        assert hashlib.sha256(path.read_bytes()).hexdigest()==entry['glb_sha256']==record['glb_sha256'], f'{code}: provenance hash'
        gltf,binary=read_glb(path);validate_lot(record,entry,gltf,binary)
        sidecar=path.with_suffix('.glb.import').read_text()
        for setting in (f'source_file="{entry["path"]}"','nodes/use_name_suffixes=true','meshes/generate_lods=true','gltf/embedded_image_handling=2'):
            assert setting in sidecar, f'{code}: import policy'
        profiles=[r for r in plantings if r['code']==code]
        assert len(profiles)==1 and profiles[0]['glb_sha256']==record['glb_sha256'] and profiles[0]['palms']==[], f'{code}: landscaping provenance'
    from check_agriculture_parcels import check as check_parcel_kit
    assert check_parcel_kit()==12, "modular farm kit coverage"
    return len(records),check_animals()


def accessor_values(gltf,binary,index):
    a=gltf['accessors'][index];v=gltf['bufferViews'][a['bufferView']]
    n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    fmt={5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']]
    size=struct.calcsize('<'+fmt*n);start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',size)
    return [struct.unpack_from('<'+fmt*n,binary,start+i*stride) for i in range(a['count'])]


def multiply(a,b):
    return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def transform(node):
    if 'matrix' in node:return [[node['matrix'][j*4+i] for j in range(4)] for i in range(4)]
    x,y,z,w=node.get('rotation',[0,0,0,1]);s=node.get('scale',[1,1,1]);t=node.get('translation',[0,0,0])
    a=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w),t[0]],
       [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w),t[1]],
       [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y),t[2]],[0,0,0,1]]
    for i in range(3):
        for j in range(3):a[i][j]*=s[j]
    return a


def validate_animal(species,record,gltf,binary):
    label=species+': '
    names=['Root','Body','Neck','Head','Tail']+[side+part for side in ('FrontLeft','FrontRight','RearLeft','RearRight') for part in ('Upper','Lower')]
    assert len(gltf.get('skins',[]))==1,label+'skin missing'
    skin=gltf['skins'][0];joints=skin['joints'];nodes=gltf['nodes']
    assert len(joints)==13 and {nodes[j].get('name') for j in joints}==set(names),label+'joint roster'
    assert not gltf.get('animations'),label+'no baked root motion'
    assert all('uri' not in b for b in gltf.get('buffers',[])) and all('uri' not in i for i in gltf.get('images',[])),label+'external resources'
    assert all(s.get('wrapS',10497)==10497 and s.get('wrapT',10497)==10497 for s in gltf.get('samplers',[])),label+'repeat'
    assert all(m.get('name','').startswith('livestock_') for m in gltf['materials']),label+'original material'
    parent={c:i for i,n in enumerate(nodes) for c in n.get('children',[])}
    def world(j):return multiply(world(parent[j]),transform(nodes[j])) if j in parent else transform(nodes[j])
    matrices={j:world(j) for j in joints};heads={j:tuple(matrices[j][i][3] for i in range(3)) for j in joints}
    lookup={nodes[j]['name']:j for j in joints}
    for name in names:
        if name=='Root':continue
        expected='Root' if name=='Body' else ('Neck' if name=='Head' else name.replace('Lower','Upper') if name.endswith('Lower') else 'Body')
        assert nodes[parent[lookup[name]]]['name']==expected,label+'joint hierarchy'
    inverse=accessor_values(gltf,binary,skin['inverseBindMatrices'])
    assert len(inverse)==13,label+'rest inverse count'
    for j,flat in zip(joints,inverse):
        matrix=multiply(matrices[j],[[flat[col*4+row] for col in range(4)] for row in range(4)])
        assert max(abs(matrix[i][k]-int(i==k)) for i in range(4) for k in range(4))<1e-5,label+'rest inverse bind mismatch'
    assert heads[lookup['Head']][2]>.8 and heads[lookup['Tail']][2]<-.5,label+'front axes'
    assert math.dist(heads[lookup['Root']],(0,0,0))<1e-5,label+'root rest'
    vertices=[];triangles=0;reach=0;used=set()
    for node in nodes:
        if 'mesh' not in node:continue
        assert node.get('skin')==0,label+'skin binding'
        assert all(k not in node for k in ('matrix','translation','rotation','scale')),label+'mesh rest transform'
        for p in gltf['meshes'][node['mesh']]['primitives']:
            attrs=p['attributes'];assert 'WEIGHTS_0' in attrs and 'JOINTS_0' in attrs,label+'weight attributes'
            pos=positions(gltf,binary,attrs['POSITION']);weights=accessor_values(gltf,binary,attrs['WEIGHTS_0']);indices=accessor_values(gltf,binary,attrs['JOINTS_0'])
            assert len(pos)==len(weights)==len(indices),label+'weight count'
            triangles+=gltf['accessors'][p['indices']]['count']//3
            vertices+=pos
            for v,w,ii in zip(pos,weights,indices):
                assert all(math.isfinite(c) for c in v+w) and abs(sum(w)-1)<1e-5 and min(w)>=0,label+'weight normalization / finite vertex'
                for weight,index in zip(w,ii):
                    if weight<1e-6:continue
                    assert index<len(joints),label+'weight joint index'
                    joint=joints[index];used.add(nodes[joint]['name'])
                    if nodes[joint]['name']=='Body':r=math.hypot(v[0],v[2])
                    else:
                        r=math.dist(v,heads[joint]);cursor=joint
                        while nodes[parent[cursor]]['name'] not in ('Body','Root'):
                            r+=math.dist(heads[cursor],heads[parent[cursor]]);cursor=parent[cursor]
                        r+=math.hypot(heads[cursor][0],heads[cursor][2])
                    reach=max(reach,r)
    assert used==set(names)-{'Root'},label+'unweighted independent joint'
    assert 0<triangles<=4000 and triangles==record['triangles'],label+'triangle budget/count'
    bounds=[[min(v[i] for v in vertices) for i in range(3)],[max(v[i] for v in vertices) for i in range(3)]]
    assert abs(bounds[0][1])<1e-5,label+'hoof grounding'
    assert bounds_key(bounds)==bounds_key(record['bounds_metres']),label+'actual exported bounds'
    assert math.isfinite(record['body_radius']) and reach+.01<=record['body_radius']<=5,label+'whole articulated body radius'
    assert record['scale']==1/16 and record['turn_margin']==.2,label+'units/turn clearance'
    assert record['bones']==names and record['forward']=='+Z' and record['up']=='+Y',label+'axes and bone metadata'
    return dict(triangles=triangles,computed_reach=reach,bounds=bounds)


def check_animals():
    from model_art.livestock_enclosures import make_profiles
    path=ROOT/'game/assets/agriculture/enclosures.json'
    assert path.exists(),'missing rigged livestock manifest'
    data=json.loads(path.read_text());assert data['schema_version']==1 and data['units']=='metres' and data['meters_per_tile']==16,'manifest schema'
    assert set(data['species'])=={'beef_cattle','dairy_cattle','sheep'},'species coverage'
    for species,record in data['species'].items():
        path=ROOT/'game/assets/agriculture'/(species+'.glb')
        assert hashlib.sha256(path.read_bytes()).hexdigest()==record['model_sha256'],species+': stale hash'
        assert record['model']=='res://assets/agriculture/'+species+'.glb',species+': path'
        gltf,binary=read_glb(path);validate_animal(species,record,gltf,binary)
        sidecar=path.with_suffix('.glb.import').read_text()
        assert 'gltf/embedded_image_handling=2' in sidecar and 'skins/use_named_skins=true' in sidecar,species+': import policy'
    expected=make_profiles(ROOT,lot_definitions(ROOT),data['species'])
    assert data['profiles']==expected,'runtime enclosure / exact shared authoring geometry and clearance'
    provenance=json.loads((ROOT/'docs/art/agriculture.json').read_text())
    assert provenance['animals']==data['species'],'animal provenance'
    for line in (ROOT/'game/export_presets.cfg').read_text().splitlines():
        if line.startswith('include_filter='):assert 'assets/agriculture/enclosures.json' in line,'manifest export filter'
    # GDScript identity pins use JSON-compatible dictionary literals.
    pins=(ROOT/'game/scripts/view/agriculture_asset_hashes.gd').read_text()
    hashes=json.loads(pins.split('const HASHES := ',1)[1].split('\nconst RADII',1)[0])
    assert hashes=={v['model']:v['model_sha256'] for v in list(data['species'].values())+list(data['profiles'].values())},'runtime identity pins'
    geometry=json.loads(pins.split('const GEOMETRY := ',1)[1].split('\nconst SPECIES_METADATA',1)[0])
    assert json.loads(pins.split('const SPECIES_METADATA := ',1)[1])==data['species'],'runtime species pins'
    assert geometry=={r['key'][3:]:r['enclosure']['pens'] for r in lot_definitions(ROOT) if r['enclosure']},'runtime geometry pins'
    return 3

if __name__=='__main__':
    lots,animals=check()
    print(f'Agriculture package clean: {lots} static lots, {animals} animal models')
