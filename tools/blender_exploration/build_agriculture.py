# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build only the sixteen original inland-West farm lots.

Blender --background --python tools/blender_exploration/build_agriculture.py -- --lots
Geometry is authored in metres, Godot +Y up/+Z front. No previous art is rebuilt.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import re
import sys
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
sys.path.insert(0,str(Path(__file__).resolve().parent))
from model_art.agriculture import lot_definitions
import build_resort_interiors as g
DEST=ROOT/'game/assets/desert-dreams-3d'
SOURCE=ROOT/'assets/agriculture'
PROVENANCE=ROOT/'docs/art/agriculture.json'
COLORS={'earth':'a98a59','soil':'65503a','dry':'bb9e6a','grass':'748147','leaf':'487546',
        'leaf_light':'7d994c','sage':'8e9880','hay':'cfb470','grain':'c8ad63','wood':'897052',
        'red':'a25540','cream':'e0d4ad','roof':'65767b','metal':'a0aaa5','dark':'303b32',
        'water':'4a8d97','shade':'445a44','glass':'b5d5cb','concrete':'b1aa94','fruit':'c36e3b'}


def materials():
    g.FINISHES=list(COLORS)
    for finish,color in COLORS.items():
        material=bpy.data.materials.get('farm_'+finish) or bpy.data.materials.new('farm_'+finish)
        material.use_nodes=True
        bs=material.node_tree.nodes.get('Principled BSDF')
        rgb=[int(color[i:i+2],16)/255 for i in (0,2,4)]
        linear=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
        bs.inputs['Base Color'].default_value=(*linear,1)
        material.diffuse_color=(*linear,1)
        bs.inputs['Roughness'].default_value=.32 if finish in ('metal','glass','water') else .85
        bs.inputs['Metallic'].default_value=.45 if finish=='metal' else 0
        if finish in ('glass','shade'):
            # Light translucent glazing exposes real benches; no opaque green boxes.
            bs.inputs['Alpha'].default_value=.18 if finish=='glass' else .52
            material.surface_render_method='DITHERED'
            material.use_backface_culling=False
        else:
            # Original, deterministic packed swatches. No external image URI survives export.
            image=bpy.data.images.get('farm_'+finish+'_surface')
            if image is None:
                image=bpy.data.images.new('farm_'+finish+'_surface',64,64,alpha=False)
                rng=random.Random(finish)
                pixels=[]
                for y in range(64):
                    for x in range(64):
                        noise=(rng.random()-.5)*.12
                        stripe=.04*math.sin(x*math.pi/4) if finish in ('wood','roof','metal','hay') else 0
                        pixels.extend([max(0,min(1,v+noise+stripe)) for v in rgb]+[1])
                image.pixels=pixels
                image.pack()
            texture=material.node_tree.nodes.new('ShaderNodeTexImage')
            texture.image=image;texture.extension='REPEAT'
            material.node_tree.links.new(texture.outputs['Color'],bs.inputs['Base Color'])
        g.MATS[finish]=material


def box(a, finish, center, size, **kwargs):
    g.box(a,finish,center,size,**kwargs)


def solid(a, name, finish, x,z,w,d,h,y=.12):
    box(a,finish,(x,y+h/2,z),(w,h,d))
    a.collider(name,(x,y+h/2,z),(w,h,d))


def roof(a,x,z,w,d,h,finish='roof',rise=1.5):
    points=[(-w/2,0,-d/2),(w/2,0,-d/2),(0,rise,-d/2),(-w/2,0,d/2),(w/2,0,d/2),(0,rise,d/2)]
    a.add(finish,g.xform(points,(x,h,z)),[(0,2,1),(3,4,5),(0,3,5,2),(1,2,5,4),(0,1,4,3)])
    g.rod(a,'metal',(x,h+rise+.04,z-d/2),(x,h+rise+.04,z+d/2),.065)
    for zz in (z-d/2,z+d/2):
        g.rod(a,'cream',(x-w/2,h,zz),(x,h+rise,zz),.065)
        g.rod(a,'cream',(x,h+rise,zz),(x+w/2,h,zz),.065)


def barn(a,x,z,w=10,d=7,h=3.5,finish='red'):
    solid(a,'Farm shed',finish,x,z,w,d,h)
    roof(a,x,z,w+.5,d+.5,h+.12)
    # Board-and-batten siding on every wall and finished rear/side windows.
    for xx in range(int(w)+1):
        for zz in (z-d/2-.02,z+d/2+.02):
            box(a,'wood',(x-w/2+xx,h/2+.12,zz),(.055,h,.06))
    for zz in range(int(d)+1):
        for xx in (x-w/2-.02,x+w/2+.02):
            box(a,'wood',(xx,h/2+.12,z-d/2+zz),(.06,h,.055))
    for xx in (x-w/2+.1,x+w/2-.1):
        for zz in (z-d/2-.06,z+d/2+.06):
            box(a,'cream',(xx,h/2+.12,zz),(.16,h,.12))
    detail_scale=min(1,(h+.12-.15-.1)/2.5)
    box(a,'cream',(x,.1+1.25*detail_scale,z+d/2+.06),(2.9,2.5*detail_scale,.14))
    box(a,'wood',(x,.125+1.175*detail_scale,z+d/2+.15),(2.55,2.35*detail_scale,.06))
    g.rod(a,'cream',(x-1.2,.18,z+d/2+.2),(x+1.2,.18+2.27*detail_scale,z+d/2+.2),.045)
    window_height=min(1.4,h-.45)
    window_top=min(2.9,h+.12-.15)
    window_center=window_top-window_height/2
    for sign in (-1,1):
        box(a,'cream',(x+sign*w/2,window_center,z),(.1,window_height-.1,1.7))
        box(a,'dark',(x+sign*(w/2+.06),window_center,z),(.06,window_height-.35,1.45))
    box(a,'cream',(x,window_center,z-d/2-.08),(1.9,window_height,.1))
    box(a,'dark',(x,window_center,z-d/2-.15),(1.65,window_height-.25,.04))


def tuft(a,x,z,h=.55,finish='leaf',radius=.3,y=.14):
    # Four tapered leaves, two-sided exported material, each rooted in the soil.
    for angle in (0,math.pi/2,math.pi,math.pi*1.5):
        dx,dz=math.cos(angle),math.sin(angle)
        a.add(finish,[(x-.06*dz,y,z+.06*dx),(x+.06*dz,y,z-.06*dx),
                     (x+dx*radius,y+h*.65,z+dz*radius),(x+dx*radius*.45,y+h,z+dz*radius*.45)],[(0,1,2),(0,2,3)])


def bed(a,x,z,length,width=.85,style='vegetables',rng=None):
    rng=rng or random.Random(0)
    box(a,'soil',(x,.18,z),(width,.12,length))
    box(a,'dark',(x+.3,.255,z),(.045,.035,length))
    count=max(1,int(length/.65))
    for j in range(count):
        zz=z-length/2+.3+j*.65
        if style=='grain':
            tuft(a,x,zz,.95,'grain',.19,.25)
            box(a,'hay',(x,.94,zz),(.12,.5,.12))
        else:
            for dx in (-.19,.18):
                tuft(a,x+dx,zz,.35+rng.random()*.16,'leaf' if j%3 else 'leaf_light',.26,.25)
                if style=='vegetables' and j%3==0:
                    g.sphere(a,'cream',(x+dx,.31,zz),.12,seg=6,rings=3)


def pipe(a,x0,z0,x1,z1,y=.3,r=.06):
    g.rod(a,'metal',(x0,y,z0),(x1,y,z1),r)


def crate(a,x,z,stack=1):
    for n in range(stack):
        yy=.12+n*.65
        box(a,'wood',(x,yy+.08,z),(1,.12,.8))
        for h in (.2,.4,.6):
            for zz in (z-.4,z+.4):box(a,'hay',(x,yy+h,zz),(1,.13,.06))
            for xx in (x-.5,x+.5):box(a,'hay',(xx,yy+h,z),(.06,.13,.8))
        for xx in (x-.44,x+.44):
            for zz in (z-.34,z+.34):box(a,'wood',(xx,yy+.34,zz),(.09,.64,.09))


def bale(a,x,z,y=.12):
    g.cylinder(a,'hay',(x,y+.65,z),.65,1.5,seg=14,axis='x',smooth=False)
    for xx in (x-.5,x+.5):g.torus(a,'wood',(xx,y+.65,z),.66,.025,seg=14,ring=4,axis='x')
    for rr in (.18,.36,.52):
        for xx in (x-.76,x+.76):g.torus(a,'grain',(xx,y+.65,z),rr,.018,seg=14,ring=3,axis='x')


def tank(a,x,z,r=1,h=2):
    g.cylinder(a,'metal',(x,.12+h/2,z),r,h,seg=16)
    a.collider('Storage tank',(x,.12+h/2,z),(r*2,h,r*2))
    for yy in (.3,h-.1):g.torus(a,'dark',(x,yy,z),r+.025,.035,seg=16,ring=4)
    g.cylinder(a,'metal',(x,h+.15,z),.3,.15,seg=12)
    pipe(a,x,z,x+r+1,z,.4)


def greenhouse(a,x,z,w,d,h=2.6):
    # Transparent complete walls/roof over individually grown crop benches.
    roof(a,x,z,w,d,h,'glass',1.2)
    for xx in (x-w/2,x+w/2):
        box(a,'glass',(xx,h/2+.12,z),(.035,h,d))
        box(a,'concrete',(xx,.25,z),(.16,.26,d))
    for zz in (z-d/2,z+d/2):
        box(a,'glass',(x,h/2+.12,zz),(w,h,.035))
        box(a,'concrete',(x,.25,zz),(w,.26,.16))
    # Every bay has a pitched steel rib and gutter.
    n=int(d/1.4)
    for j in range(n+1):
        zz=z-d/2+j*d/n
        for xx in (x-w/2,x+w/2):g.rod(a,'cream',(xx,.12,zz),(xx,h,zz),.045)
        g.rod(a,'cream',(x-w/2,h,zz),(x,h+1.2,zz),.045)
        g.rod(a,'cream',(x,h+1.2,zz),(x+w/2,h,zz),.045)
    for xx in (x-w/2,x+w/2):pipe(a,xx,z-d/2,xx,z+d/2,h,.05)
    for dx in (-w*.28,w*.28):
        box(a,'wood',(x+dx,.7,z),(w*.25,.15,d-1))
        for zz in (z-d*.35,z+d*.35):
            for ddx in (-w*.08,w*.08):box(a,'metal',(x+dx+ddx,.4,zz),(.07,.6,.07))
        for j in range(int(d/.6)-2):
            zz=z-d/2+.7+j*.6
            box(a,'soil',(x+dx,.82,zz),(w*.22,.15,.45))
            tuft(a,x+dx,zz,.55,'leaf',w*.1,.9)
    box(a,'roof',(x,h+1.24,z),(1.1,.08,d*.55)) # raised ridge vents
    a.collider('Greenhouse exterior',(x,(h+1.2)/2+.12,z),(w,h+1.2,d))



def hoop_house(a,x,z,w,d,shade=False):
    finish='shade' if shade else 'glass'
    # Low sidewall + curved eight-panel hoop cover, closed at both ends.
    profile=[(-w/2,.12),(-w/2,1.0)]
    profile += [(math.cos(math.pi-i*math.pi/8)*w/2,1+math.sin(i*math.pi/8)*2.4) for i in range(1,9)]
    profile += [(w/2,.12)]
    vertices=[(x+xx,yy,z+zz) for zz in (-d/2,d/2) for xx,yy in profile]
    n=len(profile)
    faces=[(i,i+1,n+i+1,n+i) for i in range(n-1)]
    faces += [tuple(reversed(range(n))),tuple(range(n,2*n))]
    a.add(finish,vertices,faces)
    for j in range(13):
        zz=z-d/2+j*d/12
        for (px,py),(qx,qy) in zip(profile,profile[1:]):
            g.rod(a,'metal',(x+px,py,zz),(x+qx,qy,zz),.035,seg=4)
    for xx in (x-w/2,x+w/2):
        pipe(a,xx,z-d/2,xx,z+d/2,1,.035)
        box(a,'wood',(xx,.2,z),(.1,.15,d))
    pipe(a,x,z-d/2,x,z+d/2,3.4,.04)
    for zz in (z-d/2-.02,z+d/2+.02):
        for xx in (x-.65,x+.65):g.rod(a,'cream',(xx,.12,zz),(xx,2.3,zz),.045)
        pipe(a,x-.65,zz,x+.65,zz,2.3,.045)
    for dx in (-1.6,1.6):
        box(a,'wood',(x+dx,.72,z),(1.45,.12,d-1))
        for zz in (z-d*.4,z,z+d*.4):
            for ddx in (-.55,.55):box(a,'metal',(x+dx+ddx,.4,zz),(.06,.64,.06))
        for j in range(25):
            zz=z-d/2+1+j*.84
            for ddx in (-.38,.38):
                box(a,'dark',(x+dx+ddx,.87,zz),(.48,.2,.5))
                tuft(a,x+dx+ddx,zz,.24,'leaf_light',.16,.97)
    a.collider('Nursery hoop house',(x,1.76,z),(w,3.28,d))


def fence(a,definition):
    p,q=definition['a'],definition['b']
    length=math.dist(p,q);n=1 if definition.get('end_posts_only') else max(1,math.ceil(length/2.6));h=definition['height'];thickness=definition['thickness']
    if not hasattr(a,'fence_posts'):a.fence_posts=set()
    for i in range(n+1):
        t=i/n;x=p[0]+(q[0]-p[0])*t;z=p[1]+(q[1]-p[1])*t
        post=(round(x,6),round(z,6),h,thickness)
        if post in a.fence_posts:continue
        a.fence_posts.add(post)
        box(a,'wood',(x,.12+h/2,z),(thickness,h,thickness))
        box(a,'cream',(x,h+.13,z),(.18,.06,.18))
    woven=definition.get('style')=='woven_wire'
    rails=(.25,.5,.75,1,1.25,1.5,1.65) if woven else (.58,1.12,1.65)
    for yy in rails:g.rod(a,'metal',(p[0],yy,p[1]),(q[0],yy,q[1]),.018 if woven else .035,seg=4 if woven else 6)
    if woven:
        for i in range(1,math.ceil(length/.55)):
            t=i/math.ceil(length/.55);x=p[0]+(q[0]-p[0])*t;z=p[1]+(q[1]-p[1])*t
            g.rod(a,'metal',(x,.25,z),(x,1.65,z),.012,seg=4)
    if definition['gate']:
        g.rod(a,'metal',(p[0],.4,p[1]),(q[0],1.65,q[1]),.045)
        g.rod(a,'metal',(p[0],1.65,p[1]),(q[0],.4,q[1]),.045)
        box(a,'dark',((p[0]+q[0])/2,1.15,p[1]),(.17,.17,.17))
    a.collider('Closed service gate' if definition['gate'] else 'Pen fence',
               ((p[0]+q[0])/2,.12+h/2,(p[1]+q[1])/2),
               (max(abs(q[0]-p[0]),thickness),h,max(abs(q[1]-p[1]),thickness)))


def pen_obstacle(a,o):
    x,yy,z=o['center'];w,h,d=o['size'];kind=o['kind']
    if kind=='shelter':
        roof(a,x,z,w,d,h+.12,'roof',.65)
        for xx in (x-w/2+.13,x+w/2-.13):
            for zz in (z-d/2+.13,z+d/2-.13):
                solid(a,'Shelter post','wood',xx,zz,.2,.2,h)
        box(a,'wood',(x,h/2+.12,z-d/2),(w,h,.12))
        a.collider('Shelter back',(x,h/2+.12,z-d/2),(w,h,.12))
        a.collider('Shelter roof',(x,h+.3,z),(w,.6,d))
    else:
        box(a,'concrete',(x,.22,z),(w,.2,d))
        for xx in (x-w/2+.1,x+w/2-.1):box(a,'concrete',(xx,.12+h/2,z),(.2,h,d))
        for zz in (z-d/2+.1,z+d/2-.1):box(a,'concrete',(x,.12+h/2,zz),(w,h,.2))
        box(a,'water' if kind=='trough' else 'hay',(x,h-.03,z),(w-.3,.06,d-.3))
        a.collider(kind,o['center'],o['size'])


def build(row):
    key=row['key'][3:];side=row['footprint'][0];s=side*16;half=s/2
    a=g.Asset(row['key'])
    solid(a,'Ground support','earth',0,0,s-.05,s-.05,.12,y=0)
    rng=random.Random(key)
    if row['state']!='active':
        dormant=row['state']=='dormant'
        width=s-4;depth=s-5
        box(a,'dry' if dormant else 'soil',(0,.13,-.5),(width,.02,depth))
        for i in range(int(width/1.3)):
            x=-width/2+.6+i*1.3
            box(a,'earth' if dormant else 'soil',(x,.2,-.5),(.65,.12,depth))
            if dormant:
                for j in range(max(3,int(depth/2))):tuft(a,x,-depth/2+j*2,.27,'grain',.18)
        pipe(a,-half+1,-half+1,half-1,-half+1,.3)
        for xx in (-half+1,half-1):
            for zz in (-half+1,half-1):solid(a,'Corner marker','wood',xx,zz,.13,.13,.7)
        if dormant:
            barn(a,half-3.3,half-3,4,3,2.1,'wood')
            box(a,'dark',(half-3.3,1.15,half-1.35),(2.5,1.8,.08))
            for xx in (half-4.3,half-2.3):g.rod(a,'wood',(xx,.3,half-1.25),(xx+.5,2,half-1.25),.08)
        else:
            for x in (-1,0,1):pipe(a,x,half-2,x+2,half-2,.25)
            crate(a,-half+2,half-2)
    elif key=='vegetables':
        for x in (-5.5,-3.8,-2.1,-.4,1.3,3):bed(a,x,-1,11,rng=rng)
        pipe(a,-6,-6.6,4,-6.6)
        for j in range(3):crate(a,5.5,1+j*1.1,1+(j%2))
        tank(a,5.6,-5, .65,1.5)
        box(a,'concrete',(0,.14,6),(13,.03,1.4))
    elif key=='alfalfa':
        for i in range(12):
            x=-13+i*1.65
            box(a,'grass' if i<7 else 'hay',(x,.17,-2),(1.3,.1,24))
            for j in range(28):tuft(a,x,-13+j*.8,.45 if i<7 else .13,'leaf_light' if i<7 else 'grain',.45)
        pipe(a,-14,-14,13,-14,.75,.1)
        for xx in (-12,-6,0,6,12):
            g.torus(a,'metal',(xx,.75,-14),.65,.045,seg=12,ring=4,axis='x')
            pipe(a,xx,-14,xx,-14,1.2)
        for x,z in ((10,10),(12,10),(10,12),(12,12),(9,7)):bale(a,x,z)
        barn(a,-10,12,7,5,2.8,'wood')
    elif key=='grain':
        for x in range(-13,9,2):bed(a,x,-2,24,.9,'grain',rng)
        x,z=11,9
        g.cylinder(a,'metal',(x,2.62,z),2.4,5,seg=20)
        g.cylinder(a,'roof',(x,5.62,z),2.5,1.2,seg=20,top=0)
        a.collider('Grain bin',(x,3,z),(5,6,5))
        for y in (.5,1.2,1.9,2.6,3.3,4,4.7):g.torus(a,'metal',(x,y,z),2.43,.055,seg=20,ring=4)
        for xx in (x-.3,x+.3):g.rod(a,'dark',(xx,.2,z+2.5),(xx,5,z+2.5),.035)
        for y in range(1,10):pipe(a,x-.3,z+2.5,x+.3,z+2.5,y*.5,.035)
        g.rod(a,'metal',(9,.3,4),(11,5.6,8),.16)
        barn(a,11,-10,6,6,2.5,'wood')
    elif key in ('greenhouse','nursery'):
        if key=='greenhouse':
            greenhouse(a,-1,-.5,9,12)
            tank(a,5.6,-4,.7,2)
            crate(a,5.5,4,2)
            pipe(a,4,-6,4,5,.35)
        else:
            for x in (-9,0,9):hoop_house(a,x,-2,6.5,23,shade=x==9)
            box(a,'concrete',(0,.14,12),(29,.03,3))
            for x in (-11,-9,-7,7,9,11):crate(a,x,12)
            tank(a,13,-12,.8,2.4)
    elif key=='market_garden':
        for x in (-12,-10,-8,-6,-4,-2,0,2):bed(a,x,-3,20,rng=rng)
        greenhouse(a,9,-8,7,10,2.4)
        barn(a,9,8,8,8,3.2,'cream')
        for x in (-11,-8,-5):crate(a,x,12,2)
        pipe(a,-13,-14,12,-14,.3)
        tank(a,12,0,.75,2)
    else:
        enclosure=row['enclosure']
        for p in enclosure['pens']:
            x0,z0,x1,z1=p['bounds']
            box(a,'dry',( (x0+x1)/2,.13,(z0+z1)/2),(x1-x0,.02,z1-z0))
            for f in p['fences']:fence(a,f)
            for o in p['obstacles']:pen_obstacle(a,o)
            # Sparse dry inland plants, never lush lawn in a dry stock pen.
            if key in ('cattle_range','sheep_pasture'):
                for i in range(150):
                    x=rng.uniform(x0+1,x1-1);z=rng.uniform(z0+1,z1-1)
                    if any(o['bounds'][0]-1<x<o['bounds'][2]+1 and o['bounds'][1]-1<z<o['bounds'][3]+1 for o in p['obstacles']):continue
                    tuft(a,x,z,.25+rng.random()*.35,'sage' if i%4==0 else 'grain',.3)
        if key=='dairy':
            barn(a,-6,-12,26,13,4.8,'cream')
            # Milking-barn roof vents, silo and silage bunker remain outside pen.
            for z in (-16,-12,-8):box(a,'roof',(-6,6.5,z),(1.1,.5,2))
            tank(a,15,-13,2.2,6.8)
            for x in (11,19):solid(a,'Silage retaining wall','concrete',x,-5,.3,6,1.6)
            box(a,'hay',(15,.6,-5),(7.5,1,5.5))
            box(a,'dark',(15,1.14,-5),(7.5,.08,5.5))
        if key=='feedlot':
            box(a,'concrete',(0,.14,0),(2.5,.04,44))
            for z in (-10,0,10):box(a,'cream',(0,.18,z),(.13,.015,2))
    return a


def export(row,a):
    g.reset();materials()
    objects=g.make_objects(a)+g.make_colliders(a)
    for obj in objects:
        if obj.name.endswith('-colonly'):continue
        uv=obj.data.uv_layers.new(name='FarmSurfaceUV')
        for polygon in obj.data.polygons:
            normal=polygon.normal;axis=max(range(3),key=lambda i:abs(normal[i]))
            for loop in polygon.loop_indices:
                p=obj.data.vertices[obj.data.loops[loop].vertex_index].co
                coords=(p.y,p.z) if axis==0 else ((p.x,p.z) if axis==1 else (p.x,p.y))
                uv.data[loop].uv=(coords[0]/2,coords[1]/2)
    bpy.context.view_layer.update()
    for obj in bpy.context.scene.objects:obj.select_set(False)
    for obj in objects:obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(row['key']+'.blend')))
    path=DEST/f"{row['code']}-blender.glb"
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,
                              export_materials='EXPORT',export_animations=False,export_cameras=False,export_lights=False,
                              export_extras=False,export_image_format='AUTO',export_apply=False)
    sidecar=path.with_suffix('.glb.import')
    uri='res://assets/desert-dreams-3d/'+path.name
    # Basis Universal embeds small original swatches in the imported scene.
    # Extract mode would create untracked texture files beside each source GLB.
    settings=sidecar.read_text() if sidecar.exists() else g.SIDECAR.replace('{path}',uri)
    settings=settings.replace('gltf/embedded_image_handling=1','gltf/embedded_image_handling=2')
    sidecar.write_text(settings)
    verts=[v for vs,fs,sm in a.parts.values() for v in vs]
    bounds=[[min(v[i] for v in verts) for i in range(3)],[max(v[i] for v in verts) for i in range(3)]]
    height=bounds[1][1]/16
    digest=hashlib.sha256(path.read_bytes()).hexdigest()
    entry=dict(code=row['code'],path=uri,scale=1/16,pivot=[0,0,0],yaw=0,height=height,
               footprint=row['footprint'],triangles=a.triangles(),source_kind='authored_blender',glb_sha256=digest,meters_per_tile=16)
    assert a.triangles()<=20000, (row['key'],a.triangles())
    record=dict(row,glb_sha256=digest,triangles=a.triangles(),bounds_metres=bounds,
                collider_count=len(a.colliders),generator='tools/blender_exploration/build_agriculture.py',
                provenance='Original procedural geometry and original packed surface swatches; no imported meshes or artwork')
    return entry,record


def main():
    parser=argparse.ArgumentParser()
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--lots',action='store_true');group.add_argument('--animals',action='store_true')
    group.add_argument('--parcel-kit',action='store_true')
    parser.add_argument('--only',nargs='+',help='Only these lot codes or module keys; preserve every other asset byte')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    if args.parcel_kit:
        from model_art.agricultural_parcels import build_kit
        build_kit(ROOT,g,sys.modules[__name__],args.only)
        return
    if args.animals:
        from model_art.livestock import build_animals
        build_animals(ROOT,g)
        return
    rows=lot_definitions()
    if args.only:
        requested=set(args.only)
        rows=[row for row in rows if str(row['code']) in requested]
        assert {str(row['code']) for row in rows}==requested,'unknown selective lot code'
    catalog_path=DEST/'catalog.json';land_path=DEST/'landscaping.json'
    catalog=json.loads(catalog_path.read_text());land=json.loads(land_path.read_text())
    previous=json.loads(PROVENANCE.read_text()) if PROVENANCE.exists() else {'lots':[]}
    owned={r['code']:r['key'] for r in previous['lots']}
    codes={r['code'] for r in rows}
    for row in rows:
        exists=(DEST/f"{row['code']}-blender.glb").exists() or any(e['code']==row['code'] for e in catalog['entries'])
        assert not exists or owned.get(row['code'])==row['key'], 'refusing occupied farm code/path '+str(row['code'])
    SOURCE.mkdir(parents=True,exist_ok=True);(SOURCE/'.gitignore').write_text('*\n')
    bpy.context.preferences.filepaths.save_version=0
    entries=[];records=[]
    for row in rows:
        entry,record=export(row,build(row));entries.append(entry);records.append(record)
        print('FARM_EXPORTED',row['code'],row['key'],entry['triangles'],flush=True)
    replacement={e['code']:e for e in entries}
    catalog['entries']=[replacement.get(e['code'],e) for e in catalog['entries']]
    catalog['entries'] += [e for e in entries if not any(old['code']==e['code'] for old in catalog['entries'])]
    land_replacement={e['code']:dict(code=e['code'],glb_sha256=e['glb_sha256'],palms=[]) for e in entries}
    land['entries']=[land_replacement.get(e['code'],e) for e in land['entries']]
    land['entries'] += [e for code,e in land_replacement.items() if not any(old['code']==code for old in land['entries'])]
    catalog_path.write_text(json.dumps(catalog,indent=2)+'\n');land_path.write_text(json.dumps(land,indent=2)+'\n')
    replacements={row['code']:row for row in records}
    records=[replacements.get(row['code'],row) for row in previous['lots']]+[row for row in records if row['code'] not in owned]
    previous.update(version=1,meters_per_tile=16,scale=1/16,axes='+Y up / +Z front',lots=records)
    PROVENANCE.write_text(json.dumps(previous,indent=2)+'\n')
    # A selective static export also refreshes only its existing identity pins;
    # animal rigs, radii, navigation, enclosure shapes and other assets retain bytes.
    enclosure_path=ROOT/'game/assets/agriculture/enclosures.json'
    if enclosure_path.exists():
        data=json.loads(enclosure_path.read_text())
        changed={e['path']:e['glb_sha256'] for e in entries}
        for profile in data['profiles'].values():
            if profile['model'] in changed:profile['model_sha256']=changed[profile['model']]
        enclosure_path.write_text(json.dumps(data,indent=2)+'\n')
        pins_path=ROOT/'game/scripts/view/agriculture_asset_hashes.gd'
        if pins_path.exists():
            pins=pins_path.read_text();start=pins.index('const HASHES := ')+len('const HASHES := ');end=pins.index('\nconst RADII',start)
            hashes={v['model']:v['model_sha256'] for v in list(data['species'].values())+list(data['profiles'].values())}
            pins_path.write_text(pins[:start]+json.dumps(hashes,indent=2)+pins[end:])
        geometry_path=ROOT/'game/scripts/core/agricultural_parcel_geometry.gd'
        if geometry_path.exists():
            geometry=geometry_path.read_text()
            geometry=re.sub('const ENCLOSURE_SHA256 := "[^"]+"','const ENCLOSURE_SHA256 := "'+hashlib.sha256(enclosure_path.read_bytes()).hexdigest()+'"',geometry)
            geometry_path.write_text(geometry)
    print('AGRICULTURE_LOTS_COMPLETE',len(entries),flush=True)

if __name__=='__main__':main()
