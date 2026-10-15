# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read-only structural, collision, material and exported-model contract checks.

Run with Blender --background --python this_file.py. Original exterior support
graph and crossed-pane checks use the already reviewed six-resort checker.
Nothing is regenerated or written. Counts are verified against the actual GLB.
"""
import sys, json, struct, hashlib
from pathlib import Path
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_neighborhood_resorts as n
import check_six_resort_exteriors as check

def document(path):
    raw=path.read_bytes();length,kind=struct.unpack_from('<II',raw,12)
    assert kind==0x4e4f534a
    return json.loads(raw[20:20+length])

def exported_positions(path,doc,mesh):
    raw=path.read_bytes();start=28+struct.unpack_from('<I',raw,12)[0];points=set()
    for primitive in mesh['primitives']:
        accessor=doc['accessors'][primitive['attributes']['POSITION']]
        assert accessor['componentType']==5126 and accessor['type']=='VEC3'
        view=doc['bufferViews'][accessor['bufferView']]
        offset=start+view.get('byteOffset',0)+accessor.get('byteOffset',0)
        for i in range(accessor['count']):
            xyz=struct.unpack_from('<fff',raw,offset+i*view.get('byteStride',12))
            points.add(xyz)
    return points

def same_positions(actual,expected):
    # glTF's axis conversions introduce a few micrometres of float32 error.
    for source,target in ((actual,expected),(expected,actual)):
        tree=KDTree(len(target))
        for i,point in enumerate(target):tree.insert(point,i)
        tree.balance()
        if any(tree.find(point)[2]>.00005 for point in source):return False
    return True

def collider_bounds(asset,name):
    found=[vs for label,vs,_ in asset.colliders if label==name]
    assert len(found)==1,(asset.name,name,len(found))
    vs=found[0]
    return [[min(v[i] for v in vs) for i in range(3)],[max(v[i] for v in vs) for i in range(3)]]

def near(actual,expected):
    assert len(actual)==len(expected)
    assert all(abs(a-b)<.0001 for a,b in zip(actual,expected)),(actual,expected)

def presentation_geometry(theme):
    """Check exact repeated solids and actual exposed glazing, not broad bounds."""
    a=n.build_exterior(theme);issues=[];seen=set()
    for finish,_,_,verts,faces in a.shapes:
        key=(finish,tuple(sorted(tuple(round(c,5) for c in v) for v in verts)))
        if key in seen:issues.append('coincident duplicate '+finish+' at '+str(tuple(round(c,2) for c in verts[0])))
        seen.add(key)
    verts=[];faces=[];finishes=[]
    for finish,vs,fs,_ in [(f,*p) for f,p in a.parts.items()]:
        offset=len(verts);verts.extend(vs)
        for face in fs:
            for i in range(1,len(face)-1):
                faces.append(tuple(offset+face[j] for j in (0,i,i+1)));finishes.append(finish)
    bvh=BVHTree.FromPolygons(verts,faces,all_triangles=True)
    def visible(origin,direction,want,label):
        hit=bvh.ray_cast(Vector(origin),Vector(direction),100)
        actual=finishes[hit[2]] if hit[2] is not None else None
        if actual!=want:issues.append(label+' is hidden by '+str(actual))
    if theme['slug']=='boddy':
        for x in (-9,-5,5,9):
            for side in (-1,1):visible((x+side*.80,2.55,16),(0,0,-1),'ceiling','lace curtain')
    if theme['slug']=='woolier':
        panes=[vs for f,_,_,vs,_ in a.shapes if f=='glass' and min(v.y for v in vs)>5 and min(v.z for v in vs)>12]
        assert len(panes)==4
        for vs in panes:
            x=sum(v.x for v in vs)/len(vs);bottom=min(v.y for v in vs)
            visible((x,bottom+.02,16),(0,0,-1),'glass','upper boardinghouse pane')
            visible((x,bottom-.2,16),(0,0,-1),'stone','upper boardinghouse sill')
            for y,want in ((bottom+.02,'glass'),(bottom-.2,'stone')):
                eye=Vector((0,2.56,33.6));direction=(Vector((x,y,12.1))-eye).normalized()
                visible(eye,direction,want,'street-level boardinghouse '+want)
    if theme['slug']=='stockgrowers':
        for side in (-1,1):
            panes=[v for f,_,_,v,_ in a.shapes if f=='glass' and max(p.z for p in v)-min(p.z for p in v)>20]
            pane=next(v for v in panes if v[0].x*side>0)
            bottom=min(p.y for p in pane);top=max(p.y for p in pane)
            assert top-bottom>=.9,'clerestory must retain tall glazing'
            for z in (-8,-3,7):
                for y in (bottom+.04,(bottom+top)/2,top-.04):
                    visible((side*30,y,z),(-side,0,0),'glass','clerestory pane')
        # Attached wings must meet the barn; no narrow full-height outdoor slot.
        barn=collider_bounds(a,'Sale barn')
        wings=[vs for name,vs,_ in a.colliders if name=='Guest wing']
        for vs in wings:
            lo=min(v.x for v in vs);hi=max(v.x for v in vs)
            gap=lo-barn[1][0] if lo>0 else barn[0][0]-hi
            if gap>.001:issues.append('guest wing detached by '+str(round(gap,3))+'m')
    if theme['slug']=='stockgrowers':
        first=bvh.ray_cast(Vector((0,7,19.7)),Vector((0,-1,0)),5)
        second=bvh.ray_cast(first[0]+Vector((0,-.001,0)),Vector((0,-1,0)),5)
        if second[0] is not None and first[0].y-second[0].y<.08:
            issues.append('near-coplanar overlapping lobby/porch roof tops')
    return issues

def exterior(theme):
    slug=theme['slug'];half=theme['footprint'][0]*8
    original=check.s.build
    check.s.build=lambda name,asset=None:n.build_exterior(theme,asset)
    try:issues=check.check(slug)
    finally:check.s.build=original
    assert not issues,'\n'.join(issues)
    a=n.build_exterior(theme)
    coords=[v for vs,_,_ in a.parts.values() for v in vs]
    assert all(v.y>=0 and abs(v.x)<=half and abs(v.z)<=half for v in coords)
    # Decorative paving must not produce a grounded whole-lot terrain barrier.
    assert not any(max(v.x for v in vs)-min(v.x for v in vs)>half*1.8 and
                   max(v.z for v in vs)-min(v.z for v in vs)>half*1.8
                   for _,vs,_ in a.colliders)
    walk_floor=.6 if theme['code'] in (263,264) else 0.0
    if theme['code'] in (263,264):
        lo,hi=collider_bounds(a,'Porch deck')
        near([lo[1],hi[1]],[.5,.6])
    z=12 if theme['code']<264 else 20
    threshold=z+1.12
    assert threshold<half-.4
    # Outdoor capsule's central approach stays free of piers and pillars.
    for label,vs,_ in a.colliders:
        low=[min(v[i] for v in vs) for i in range(3)];high=[max(v[i] for v in vs) for i in range(3)]
        if low[1]>=walk_floor+2 or high[1]<=walk_floor+.0001:continue
        assert not (low[0]<.4 and high[0]>-.4 and low[2]<threshold+.4 and high[2]>threshold-.4),(slug,label)
    path=n.DEST/('%d-blender.glb'%theme['code']);doc=document(path)
    meshes={mesh.get('name'):mesh for mesh in doc['meshes']}
    for finish,(verts,faces,_) in a.parts.items():
        mesh=meshes[slug+' '+finish]
        count=sum(doc['accessors'][p['indices']]['count']//3 for p in mesh['primitives'])
        assert count==sum(len(f)-2 for f in faces),(slug,finish,'exported geometry is stale')
        expected={tuple(v) for v in verts}
        assert same_positions(exported_positions(path,doc,mesh),expected),(slug,finish,'exported vertex positions are stale')
    for sampler in doc.get('samplers',[]):
        assert sampler.get('wrapS',10497)==10497 and sampler.get('wrapT',10497)==10497
    assert doc.get('images'),(slug,'missing structural swatches')
    assert all((path.parent/image['uri']).is_file() for image in doc['images'])
    entries=json.loads((n.DEST/'catalog.json').read_text())['entries'];entry=next(row for row in entries if row['code']==theme['code'])
    assert entry['glb_sha256']==hashlib.sha256(path.read_bytes()).hexdigest()
    assert entry['triangles']==n.e.visible_triangles(path)<40000
    assert entry['footprint']==theme['footprint'] and entry['scale']==.0625
    lettering=[node for node in doc['nodes'] if node.get('name')=='Original outlined name']
    assert len(lettering)==1 and 'mesh' in lettering[0],(slug,'missing outlined sign')
    assert all(doc['accessors'][part['attributes']['POSITION']]['count']>0
               for part in doc['meshes'][lettering[0]['mesh']]['primitives'])
    if slug=='woolier':
        mats={mat['name']:mat for mat in doc['materials']}
        for name,hexcolor in [('flag_red','ce1126'),('flag_green','009b48'),('flag_white','ffffff')]:
            assert name in mats
            color=mats[name]['pbrMetallicRoughness'].get('baseColorFactor',[1,1,1,1])
            rgb=[int(hexcolor[i:i+2],16)/255 for i in (0,2,4)]
            near(color[:3],[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb])
        assert len(a.parts['flag_green'][1])==4,'saltire must be drawn on both faces'
        assert len(a.parts['flag_white'][1])==24,'cross must be drawn on both faces'
    print('NEIGHBORHOOD_GEOMETRY',slug,'clean',entry['triangles'],'triangles',len(a.colliders),'colliders',len(a.omitted),'omitted windows')

def hall(theme):
    a=n.build_hall(theme);small=theme['code']<264;half=12 if small else 18;ceiling=6 if small else 8
    assert set(a.parts)<=set(n.g.FINISHES[:15])
    low,high=collider_bounds(a,'Hall floor');near(low,[-half,-.32,-half]);near(high,[half,0,half])
    low,high=collider_bounds(a,'Closed vestibule door');near(low,[-3.3,0,half+5]);near(high,[3.3,3.8,half+5.3])
    low,high=collider_bounds(a,'Cash cage');near(low,[-(3 if small else 4),0,-half+.75]);near(high,[(3 if small else 4),2.5,-half+2.25])
    low,high=collider_bounds(a,'Bar counter');near(low,[half-2.5,0,-7]);near(high,[half-1.5,1.1,-1])
    low,high=collider_bounds(a,'Back bar');near(low,[half-.8,0,-7]);near(high,[half-.1,3,-1])
    if theme['code']==263:
        low,high=collider_bounds(a,'Family dining');near(low,[4.8,0,5.5]);near(high,[9.2,1,8.5])
    if theme['code']==264:
        low,high=collider_bounds(a,'Auction display');near(low,[11,0,8]);near(high,[15,1.2,12])
    if theme['code']==265:
        low,high=collider_bounds(a,'Fountain basin');near(low,[10.6,0,8.6]);near(high,[13.4,1,11.4])
    # The 6m entrance retains an unobstructed central path into the hall.
    for label,vs,_ in a.colliders:
        if label in ('Hall floor','Hall ceiling','Vestibule floor','Vestibule ceiling','Closed vestibule door','Vestibule lintel'):continue
        lo=[min(v[i] for v in vs) for i in range(3)];hi=[max(v[i] for v in vs) for i in range(3)]
        assert not (lo[0]<.4 and hi[0]>-.4 and lo[2]<half+4 and hi[2]>half-1 and lo[1]<1.9 and hi[1]>0),label
    path=n.HALL_DEST/(a.name+'.glb');doc=document(path)
    assert not doc.get('images'),'runtime dresser applies procedural finishes'
    assert set(mat['name'] for mat in doc['materials'])<=set('resort_'+f for f in n.g.FINISHES[:15])
    catalog=json.loads((n.HALL_DEST/'catalog.json').read_text());entry=catalog['models'][a.name]
    assert entry['sha256']==hashlib.sha256(path.read_bytes()).hexdigest()
    assert entry['triangles']==n.e.visible_triangles(path)<40000
    assert catalog['halls'][str(theme['code'])]['resort']==theme['key']
    print('NEIGHBORHOOD_HALL_CONTRACT',theme['code'],'clean',entry['triangles'],'triangles',len(a.colliders),'colliders')

def main():
    # No free-ended columns are permitted. Finials are short attached parts.
    check.FREE_ENDS=set();check.EXPECTED_OMITTED={};check.TOL=.008
    issues=[theme['slug']+': '+issue for theme in n.THEMES for issue in presentation_geometry(theme)]
    for issue in issues:print('PRESENTATION_DEFECT',issue)
    assert not issues, str(len(issues))+' presentation defects'
    for theme in n.THEMES:exterior(theme);hall(theme)
    print('NEIGHBORHOOD_MODELS 8/8 verified')

if __name__=='__main__':main()
