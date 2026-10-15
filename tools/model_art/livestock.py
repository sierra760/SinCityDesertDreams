# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Original hoof-grounded quadrupeds, authored +Y up/+Z forward in metres.

All rest matrices are retained. Runtime rotations are deltas in each imported
bone's rest basis. Limits in the manifest are world-axis angles, converted by
rest_basis.inverse() * axis; Root is never translated or rotated.
"""
import hashlib
import json
import math
from pathlib import Path
import bpy
from mathutils import Matrix, Vector
from model_art.agriculture import lot_definitions, TURN_MARGIN
from model_art.livestock_enclosures import make_profiles

BONES=['Root','Body','Neck','Head','Tail']+[side+part for side in ('FrontLeft','FrontRight','RearLeft','RearRight') for part in ('Upper','Lower')]
# Intended runtime extremes, in degrees about authored world X (legs/neck)
# and Y (head/tail). Pose envelopes conservatively add all articulated reaches.
LIMITS={'Neck':[-12,80],'Head':[-20,20],'Tail':[-30,30],
        **{side+part:[-24,24] if part=='Upper' else [-32,0] for side in ('FrontLeft','FrontRight','RearLeft','RearRight') for part in ('Upper','Lower')}}
TO_BLENDER=Matrix.Rotation(math.pi/2,4,'X')


def build_animal(species,root,g):
    g.reset()
    sheep=species=='sheep';dairy=species=='dairy_cattle'
    mats={}
    palette={'coat':'e7dfc7' if sheep or dairy else 'a15f38','dark':'272b2a','muzzle':'49413c' if sheep else 'b98778',
             'horn':'d5c5a1','hoof':'3d3933','eye':'130f0b','glint':'eee4ce','ear':'b98172','udder':'c98d84','wool':'d8d0b7'}
    for name,color in palette.items():
        m=bpy.data.materials.new('livestock_'+name);m.use_nodes=True
        rgb=[int(color[i:i+2],16)/255 for i in (0,2,4)]
        m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb)+(1,)
        m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.82
        mats[name]=m
    H=.92 if sheep else 1.48
    body=(.38,.37,.70) if sheep else ((.48,.47,1.12) if dairy else (.56,.52,1.06))
    neckbase=(0,H-.10 if sheep else H-.20,.40 if sheep else .65)
    headbase=(0,H+.17,.88 if sheep else 1.17)
    headtip=(0,H+.12,1.19 if sheep else 1.64)
    tailbase=(0,H+.18,-.61 if sheep else -.98)
    tailtip=(0,H-.13,-.90 if sheep else -1.16)
    # Root has a true independent fixed rest, followed by the body hierarchy.
    rigdata=bpy.data.armatures.new('LivestockSkeleton')
    rig=bpy.data.objects.new('LivestockSkeleton',rigdata);bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig;rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    segments={}
    def bone(name,head,tail,parent=None):
        b=rigdata.edit_bones.new(name);b.head=TO_BLENDER@Vector(head);b.tail=TO_BLENDER@Vector(tail)
        if parent:b.parent=rigdata.edit_bones[parent]
        segments[name]=(Vector(head),Vector(tail))
    bone('Root',(0,0,0),(0,.25,0))
    bone('Body',(0,H,-.5),(0,H,.5),'Root')
    bone('Neck',neckbase,headbase,'Body');bone('Head',headbase,headtip,'Neck')
    bone('Tail',tailbase,tailtip,'Body')
    legx=.26 if sheep else .38;front=.46 if sheep else .76;rear=-.48 if sheep else -.78
    knee=.31 if sheep else .55
    for side,x,z in [('FrontLeft',legx,front),('FrontRight',-legx,front),('RearLeft',legx,rear),('RearRight',-legx,rear)]:
        bone(side+'Upper',(x,H-.12,z),(x,knee,z-.04), 'Body')
        bone(side+'Lower',(x,knee,z-.04),(x,.10,z+.02),side+'Upper')
    bpy.ops.object.mode_set(mode='OBJECT')
    objects=[]
    def mesh(name,verts,faces,mat,bone_name):
        data=bpy.data.meshes.new(name);data.from_pydata([TO_BLENDER@Vector(v) for v in verts],[],faces);data.materials.append(mats[mat]);data.update()
        obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj)
        obj.parent=rig;obj.vertex_groups.new(name=bone_name).add(list(range(len(verts))),1,'REPLACE')
        mod=obj.modifiers.new('Independent quadruped skin','ARMATURE');mod.object=rig
        for p in data.polygons:p.use_smooth=True
        objects.append(obj)
        return obj
    def ell(name,c,s,mat,b,seg=12,rings=7):
        verts=[(c[0],c[1]+s[1],c[2])]
        for j in range(1,rings):
            th=math.pi*j/rings
            for i in range(seg):
                ph=2*math.pi*i/seg
                verts.append((c[0]+s[0]*math.sin(th)*math.cos(ph),c[1]+s[1]*math.cos(th),c[2]+s[2]*math.sin(th)*math.sin(ph)))
        verts.append((c[0],c[1]-s[1],c[2]));bottom=len(verts)-1
        faces=[]
        for i in range(seg):faces.append((0,1+(i+1)%seg,1+i))
        for j in range(rings-2):
            a=1+j*seg;c0=a+seg
            for i in range(seg):faces.append((a+i,a+(i+1)%seg,c0+(i+1)%seg,c0+i))
        a=1+(rings-2)*seg
        for i in range(seg):faces.append((a+i,a+(i+1)%seg,bottom))
        return mesh(name,verts,faces,mat,b)
    def tube(name,p,q,r0,r1,mat,b,seg=8):
        p=Vector(p);q=Vector(q);axis=(q-p).normalized();u=axis.cross(Vector((1,0,0))).normalized()
        if u.length<.5:u=axis.cross(Vector((0,1,0))).normalized()
        v=axis.cross(u);verts=[tuple(c+r*(math.cos(i*2*math.pi/seg)*u+math.sin(i*2*math.pi/seg)*v)) for c,r in [(p,r0),(q,r1)] for i in range(seg)]
        faces=[tuple(reversed(range(seg))),tuple(range(seg,2*seg))]+[(i,(i+1)%seg,(i+1)%seg+seg,i+seg) for i in range(seg)]
        return mesh(name,verts,faces,mat,b)
    def torso():
        # Continuous original topology: rump, ribcage, tucked flank, withers.
        stations=[(-1.04,.12,.22),(-.92,.40,.40),(-.72,.50,.48),(-.45,.55,.52),(-.1,.56,.52),(.25,.53,.50),(.55,.47,.48),(.80,.34,.40),(.94,.12,.24)]
        if dairy:stations=[(z,w*.87,h*.91) for z,w,h in stations]
        if sheep:stations=[(z*.67,w*.70,h*.72) for z,w,h in stations]
        # Additional longitudinal rings give the coat organic boundaries.
        stations=[tuple((a[k]+b[k])/2 for k in range(3)) if mid else a for a,b in zip(stations[:-1],stations[1:]) for mid in (False,True)]+[stations[-1]]
        seg=28;verts=[];faces=[]
        for j,(z,w,h) in enumerate(stations):
            for i in range(seg):
                angle=2*math.pi*i/seg;cx=math.cos(angle);sy=math.sin(angle)
                # Flat topline and full lower ribcage, gently sculpted flanks.
                x=w*math.copysign(abs(cx)**.88,cx)
                y=H+h*math.copysign(abs(sy)**.80,sy)
                if sheep:
                    ripple=1+.035*math.sin(i*2.7+j*3.1)+.025*math.sin(i*4.9-j)
                    x*=ripple;y=H+(y-H)*ripple
                verts.append((x,y,z))
        for j in range(len(stations)-1):
            for i in range(seg):
                a=j*seg+i;b=j*seg+(i+1)%seg
                faces.append((a,b,b+seg,a+seg))
        faces.extend([tuple(reversed(range(seg))),tuple(range((len(stations)-1)*seg,len(stations)*seg))])
        obj=mesh('Continuous ribcage withers and rump',verts,faces,'coat','Body')
        if dairy:
            obj.data.materials.append(mats['dark'])
            # Coat is a material region on the actual skin: no floating overlays.
            for polygon in obj.data.polygons:
                center=sum((Vector(verts[i]) for i in polygon.vertices),Vector())/len(polygon.vertices)
                x,y,z=center
                patch=min(((z+.66)/.32)**2+((y-H-.14)/.37)**2,((z-.12)/.29)**2+((y-H+.04)/.45)**2,((z-.68)/.23)**2+((y-H-.12)/.35)**2)
                irregular=.22*math.sin(z*19+y*13)+.12*math.cos(z*29-y*8)
                if patch<1+irregular and abs(x)>.18:polygon.material_index=1
        if sheep:
            obj.data.materials.append(mats['wool'])
            for p in obj.data.polygons:
                if p.index%7 in (1,4):p.material_index=1
    torso()
    # Sculpted neck loft joins the chest and jaw without separate ball masses.
    def loft(name,stations,material,bone_name,seg=12):
        verts=[];faces=[]
        for center,width,height in stations:
            for i in range(seg):
                angle=2*math.pi*i/seg
                verts.append((center[0]+width*math.cos(angle),center[1]+height*math.sin(angle),center[2]))
        for j in range(len(stations)-1):
            for i in range(seg):
                a=j*seg+i;b=j*seg+(i+1)%seg;faces.append((a,b,b+seg,a+seg))
        faces.extend([tuple(reversed(range(seg))),tuple(range((len(stations)-1)*seg,len(stations)*seg))])
        return mesh(name,verts,faces,material,bone_name)
    if sheep:
        loft('Sloping wool neck',[((0,H,.40),.27,.30),((0,H+.10,.65),.23,.26),((0,H+.13,.86),.14,.17)],'coat','Neck')
        loft('Long ovine skull',[((0,H+.12,.82),.13,.17),((0,H+.13,.98),.16,.20),((0,H+.02,1.15),.12,.15),((0,H-.08,1.27),.10,.10)],'dark','Head')
        nose_y=H-.08;nose_z=1.27;eye_z=.97;eye_y=H+.18;ear_z=.85;ear_y=H+.26
    else:
        loft('Sloping muscular neck',[((0,H-.03,.60),.35 if not dairy else .29,.43),((0,H+.05,.9),.27,.37),((0,H+.09,1.19),.20,.25)],'coat','Neck')
        loft('Forehead cheek and long bovine jaw',[((0,H+.13,1.1),.18,.24),((0,H+.12,1.31),.23,.29),((0,H-.02,1.53),.19,.24),((0,H-.16,1.78),.21,.14)],'coat','Head')
        nose_y=H-.16;nose_z=1.80;eye_z=1.35;eye_y=H+.22;ear_z=1.14;ear_y=H+.36
    ell('Broad leathery nose',(0,nose_y,nose_z),(.115,.095,.10) if sheep else (.225,.135,.12),'muzzle','Head',12,6)
    for sign in (-1,1):
        eye_x=sign*(.145 if sheep else .21)
        ell('Inset almond eye',(eye_x,eye_y,eye_z),(.024,.027,.038),'eye','Head',8,5)
        ell('Nostril',(sign*(.07 if sheep else .13),nose_y+.02,nose_z+.09),(.025,.022,.014),'dark','Head',8,4)
        # Thin pointed leaves, attached at the skull and drooping at their tips.
        x0=.11 if sheep else .17;x1=.38 if sheep else .46
        verts=[(sign*x0,ear_y,ear_z),(sign*(x0+.12),ear_y+.035,ear_z-.07),(sign*x1,ear_y-.08,ear_z-.015),(sign*(x0+.15),ear_y-.04,ear_z+.085),(sign*(x0+.12),ear_y+.015,ear_z+.015)]
        mesh('Pointed lateral ear',verts,[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(0,3,2,1)],'coat','Head')
        mesh('Inner ear',[(x,y+.006,z) for x,y,z in verts],[(0,4,1),(1,4,2),(2,4,3),(3,4,0)],'ear','Head')
        if not sheep and not dairy:
            tube('Horn base',(sign*.17,H+.36,1.11),(sign*.29,H+.48,1.02),.065,.04,'horn','Head')
            tube('Swept horn tip',(sign*.29,H+.48,1.02),(sign*.32,H+.62,1.0),.04,.005,'horn','Head')
    for side in ('FrontLeft','FrontRight','RearLeft','RearRight'):
        upper=side+'Upper';lower=side+'Lower';p,k=segments[upper];_,foot=segments[lower]
        tube(side+' muscular upper',p,k,.10 if sheep else .15,.065 if sheep else .09,'coat',upper)
        ell(side+' knee',tuple(k),(.068,.085,.068) if sheep else (.095,.115,.095),'coat',lower,8,5)
        tube(side+' shin',k,foot,.065 if sheep else .085,.055 if sheep else .07,'dark' if sheep else 'coat',lower)
        # Flat sole, sloping coronet and two separated cloven toes.
        for dx in (-.031,.031) if sheep else (-.047,.047):
            w=.028 if sheep else .043;h=.13 if sheep else .18;d=.13 if sheep else .18
            x=foot.x+dx;z=foot.z
            verts=[(x-w,0,z-d*.35),(x+w,0,z-d*.35),(x+w,0,z+d),(x-w,0,z+d),
                   (x-w*.8,h,z-d*.3),(x+w*.8,h,z-d*.3),(x+w*.85,h*.75,z+d*.65),(x-w*.85,h*.75,z+d*.65)]
            mesh(side+' cloven hoof',verts,[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],'hoof',lower)
    tube('Tail shaft',tailbase,tailtip,.055,.027,'coat','Tail')
    if sheep:ell('Short fleece tail',tailtip,(.10,.14,.12),'coat','Tail',8,5)
    else:
        tube('Hanging tail',tailtip,(0,.45,-1.18),.027,.04,'coat','Tail')
        ell('Tail switch',(0,.4,-1.18),(.09,.16,.08),'dark','Tail',8,5)
    if dairy:
        ell('Udder',(0,H-.47,-.57),(.28,.22,.28),'udder','Body',12,6)
        for x in (-.12,.12):
            for z in (-.45,-.66):tube('Teat',(x,H-.60,z),(x,H-.78,z),.045,.025,'udder','Body',6)
    # Every piece carries weights before joining; all 13 joints retain their rest.
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();obj=bpy.context.object
    obj.name=species+' skinned anatomy'
    # Join duplicates modifiers; retain exactly one deformation modifier.
    for mod in list(obj.modifiers)[1:]:obj.modifiers.remove(mod)
    bpy.context.view_layer.update()
    verts=[tuple(TO_BLENDER.inverted()@v.co) for v in obj.data.vertices]
    bounds=[[min(v[i] for v in verts) for i in range(3)],[max(v[i] for v in verts) for i in range(3)]]
    # A conservative bound for ALL rotations at or inside the published limits:
    # each vertex <= sum of parent joint offsets + its last-joint distance.
    # Use horizontal radius of body/root plus full articulated chain reaches.
    radius=0
    for v in obj.data.vertices:
        p=TO_BLENDER.inverted()@v.co
        name=obj.vertex_groups[v.groups[0].group].name
        if name=='Body':reach=math.hypot(p.x,p.z)
        else:
            head=segments[name][0];reach=(p-head).length
            b=rigdata.bones[name]
            while b.parent and b.parent.name not in ('Root','Body'):
                reach+=(segments[b.name][0]-segments[b.parent.name][0]).length;b=b.parent
            reach+=math.hypot(segments[b.name][0].x,segments[b.name][0].z)
        radius=max(radius,reach)
    radius=math.ceil((radius+.025)*100)/100
    tris=sum(len(p.vertices)-2 for p in obj.data.polygons);assert tris<=4000,(species,tris)
    assert abs(bounds[0][1])<1e-6
    dest=root/'game/assets/agriculture';dest.mkdir(parents=True,exist_ok=True)
    source=root/'assets/agriculture';source.mkdir(parents=True,exist_ok=True)
    (source/'.gitignore').write_text('*\n');bpy.context.preferences.filepaths.save_version=0
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);obj.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.wm.save_as_mainfile(filepath=str(source/(species+'.blend')))
    path=dest/(species+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_animations=False,export_skins=True,export_apply=False,export_cameras=False,export_lights=False,export_extras=False)
    sidecar=path.with_suffix('.glb.import')
    if not sidecar.exists():sidecar.write_text(g.SIDECAR.replace('{path}','res://assets/agriculture/'+path.name).replace('gltf/embedded_image_handling=1','gltf/embedded_image_handling=2'))
    limits=dict(LIMITS)
    if sheep:limits['Neck']=[-12,55]
    return dict(model='res://assets/agriculture/'+path.name,model_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),scale=1/16,body_radius=radius,turn_margin=TURN_MARGIN,bounds_metres=bounds,triangles=tris,bones=BONES,pose_limits_degrees=limits,ground_y=0,forward='+Z',up='+Y',radius_method='sum of articulated joint reaches including visible head, ears, hooves and tail; valid for all joint angles')


def build_animals(root,g):
    species={key:build_animal(key,root,g) for key in ('beef_cattle','dairy_cattle','sheep')}
    rows=lot_definitions(root)
    profiles=make_profiles(root,rows,species)
    data=dict(schema_version=1,units='metres',meters_per_tile=16,species=species,profiles=profiles)
    (root/'game/assets/agriculture/enclosures.json').write_text(json.dumps(data,indent=2)+'\n')
    hashes={v['model']:v['model_sha256'] for v in list(species.values())+list(profiles.values())}
    radii={k:v['body_radius'] for k,v in species.items()}
    geometry={r['key'][3:]:r['enclosure']['pens'] for r in rows if r['enclosure']}
    (root/'game/scripts/view/agriculture_asset_hashes.gd').write_text('# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC\n# SPDX-License-Identifier: GPL-3.0-or-later\n# Generated by build_agriculture.py --animals; pinned imported-resource identities.\nextends RefCounted\nconst HASHES := '+json.dumps(hashes,indent=2)+'\nconst RADII := '+json.dumps(radii,indent=2)+'\nconst GEOMETRY := '+json.dumps(geometry,indent=2)+'\nconst SPECIES_METADATA := '+json.dumps(species,indent=2)+'\n')
    p=root/'docs/art/agriculture.json';provenance=json.loads(p.read_text());provenance['animals']=species
    p.write_text(json.dumps(provenance,indent=2)+'\n')
    print('AGRICULTURE_ANIMALS_COMPLETE',json.dumps({k:(v['triangles'],v['body_radius']) for k,v in species.items()}),flush=True)
