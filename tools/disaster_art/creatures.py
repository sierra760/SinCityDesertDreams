# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Original Nevada canyon giant and seven-person crowd, with authored looping skeletons.

Generated geometry is editable, closed, UV-mapped, and uses vertex-color finishes.
All source geometry is in metres, facing Blender +Y. No external art is used.
"""
import math

import bpy
from mathutils import Vector, Matrix

import disaster_art.common as c

TAU = math.tau


def _blend(a, b, t):
    t = max(0.0, min(1.0, t))
    t = t*t*(3-2*t)
    return {a: 1-t, b: t}


def _loft(name, rows, material, sides=12, axis='z'):
    """Closed ring loft: (center, horizontal radius, other radius)."""
    verts = []
    for center, rx, ry in rows:
        for j in range(sides):
            a = TAU*j/sides
            offset = Vector((rx*math.cos(a), ry*math.sin(a), 0))
            if axis == 'y': offset = Vector((offset.x, 0, -offset.y))
            verts.append(Vector(center)+offset)
    faces = [tuple(reversed(range(sides)))]
    for i in range(len(rows)-1):
        for j in range(sides):
            a=i*sides+j; b=i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.append(tuple(range(len(verts)-sides,len(verts))))
    return c.mesh(name, verts, faces, material)


def _plate(name, center, width, height, depth, material, bone, rig):
    """A closed pointed shield; broad planar facets catch the desert light."""
    x,y,z=center
    verts=[(x-width*.5,y,z-height*.25),(x-width*.35,y,z+height*.40),
           (x,y-depth*.18,z+height*.55),(x+width*.35,y,z+height*.40),
           (x+width*.5,y,z-height*.25),(x,y,z-height*.55),
           (x,y+depth,z)]
    faces=[(5,4,3,2,1,0)]
    faces.extend((i,(i+1)%6,6) for i in range(6))
    obj=c.mesh(name,verts,faces,material,False)
    c.rigid_skin(obj,rig,bone)
    return obj


def _bone_rot(rig, name, desired, parent_desired=None):
    """Convert desired world bone rotation to editable local Euler channels."""
    bone=rig.data.bones[name]
    rest=bone.matrix_local.to_3x3()
    if bone.parent:
        parent_rest=bone.parent.matrix_local.to_3x3()
        local_rest=parent_rest.inverted() @ rest
        local=local_rest.inverted() @ parent_desired.inverted() @ desired
    else: local=rest.inverted() @ desired
    return tuple(local.to_euler('XYZ'))


def _aim(rig,name,direction):
    bone=rig.data.bones[name]
    rest=bone.matrix_local.to_3x3()
    q=(bone.tail_local-bone.head_local).normalized().rotation_difference(Vector(direction).normalized())
    return q.to_matrix() @ rest


def monster():
    """Original Tsawhawbitts-inspired canyon giant, not a cultural reconstruction.

    Travel Nevada's Jarbidge account supplies the giant and carrying basket.
    Anatomy, clothing, surface styling, and animation are original interpretations.
    """
    c.timeline(8,30)
    bpy.context.scene['name']='Tsawhawbitts'
    bpy.context.scene['legend_reference']='https://travelnevada.com/ghost-town/journey-to-jarbidge/'
    bpy.context.scene['art_interpretation']='Original stylized giant and carrying basket; appearance is not a cultural reconstruction.'
    c.group('Tsawhawbitts_AuthoredMotion')
    c.add_material('canyon_skin',(.285,.20,.145),.94)
    c.add_material('weathered_skin',(.26,.135,.08),.94)
    c.add_material('shaggy_hair',(.043,.037,.030),.96)
    c.add_material('rough_cloth',(.11,.18,.17),.98)
    c.add_material('basket_reed',(.40,.265,.115),.96)
    c.add_material('basket_edge',(.62,.43,.20),.92)
    c.add_material('mouth_shadow',(.008,.006,.004),.99)
    # The shared dark finish completes the eight-material model.
    bones=[('root',(0,0,0),(0,0,7),None),
           ('pelvis',(0,0,24),(0,0,32),'root'),
           ('chest',(0,0,32),(0,1,44),'pelvis'),
           ('neck',(0,1,44),(0,3,49),'chest'),
           ('head',(0,3,49),(0,9,52),'neck'),
           ('jaw',(0,4,46),(0,10,46),'head'),
           ('basket',(0,-7,32),(0,-11,43),'chest')]
    for side,s in [('L',-1),('R',1)]:
        bones += [(f'thigh.{side}',(s*5.4,0,24),(s*6,3.6,12),'root'),
                  (f'shin.{side}',(s*6,3.6,12),(s*6,-.8,3),'thigh.'+side),
                  (f'foot.{side}',(s*6,-.8,3),(s*6,5,2.8),'shin.'+side),
                  (f'upperarm.{side}',(s*10,0,41),(s*15,1,30),'chest'),
                  (f'forearm.{side}',(s*15,1,30),(s*16,4,21),'upperarm.'+side),
                  (f'hand.{side}',(s*16,4,21),(s*16,5,16.5),'forearm.'+side)]
        for digit in range(4):
            x=s*16+(digit-1.5)*1.45
            z=17.3+(0,.3,.1,-.7)[digit]
            bones.append((f'finger{digit}.{side}',(x,5,z),(x,5.7,z-3.3),'hand.'+side))
        bones.append((f'thumb.{side}',(s*13.1,4.1,20),(s*11.9,5.9,17.5),'hand.'+side))
    rig=c.make_rig('Tsawhawbitts_Canyon_Giant_Rig',bones)
    c.GROUP=None
    def rigid(obj,bone): c.rigid_skin(obj,rig,bone); return obj
    # Broad ribcage, dropped belly and massive shoulder girdle form one sculpt.
    torso=_loft('Canyon giant torso',[
        ((0,0,22),6.5,4.7),((0,0,26),8,5.6),((0,0,31),8.7,6.1),
        ((0,.2,36),10.6,6.8),((0,0,41),11.1,6.6),
        ((0,.1,45),8.3,5.6),((0,1.3,48),4.7,4.0)],'canyon_skin',16)
    masses=[torso]
    for s in [-1,1]:
        masses.append(c.ellipsoid('Shoulder sculpt',(s*9.5,0,40),(10,11,12),'canyon_skin',.025,14,9))
    torso=c.unify(masses,'Unified giant torso and shoulders','canyon_skin',.7,1900)
    c.skin_weights(torso,rig,lambda v:_blend('pelvis','chest',(v.z-27)/10) if v.z<39 else _blend('chest','neck',(v.z-43)/5))
    # Practical rough shorts; irregular cuffs carry no decorative cultural motifs.
    cloth=_loft('Rough woven waist garment',[
        ((0,0,21.2),11.0,8.0),((0,0,26.4),10.5,7.6),((0,0,29),8.15,5.9)],'rough_cloth',16)
    rigid(cloth,'pelvis')
    for side,s in [('L',-1),('R',1)]:
        leg=c.tube('Powerful articulated leg '+side,[(s*5.4,0,24),(s*5.8,1.5,20),
            (s*6,3.6,14),(s*6,3.6,12),(s*6,1.5,8),(s*6,-.8,3)],
            [4.1,4.0,3.7,3.4,3.1,2.3],'canyon_skin',14)
        c.skin_weights(leg,rig,lambda v,side=side:_blend('shin.'+side,'thigh.'+side,(v.z-9)/7))
        pants=_loft('Rough shorts leg '+side,[
            ((s*5.8,2.5,17.5),5.35,5.25),((s*5.6,1.4,21.4),5.45,5.4),
            ((s*5.4,0,25),5.1,5.3)],'rough_cloth',12)
        for v in pants.data.vertices:
            if v.co.z<18: v.co.z+=.5*math.sin(v.co.x*1.5+v.co.y)
        rigid(pants,'thigh.'+side)
        # Flatten the complete barefoot sculpture at z=0; toes remain rounded.
        masses=[c.ellipsoid('Giant heel',(s*6,-.8,2.9),(6.6,6.4,5.7),'canyon_skin',0,12,8),
            c.ellipsoid('Giant sole',(s*6,2.6,1.7),(7.7,10.6,3.4),'canyon_skin',0,14,8)]
        foot=c.unify(masses,'Grounded broad foot '+side,'canyon_skin',.4,380)
        bottom=min(v.co.z for v in foot.data.vertices)
        for v in foot.data.vertices:v.co.z-=bottom
        rigid(foot,'foot.'+side)
        for toe in range(5):
            x=s*6+(toe-2)*1.22;length=2.7-.22*abs(toe-1)
            rigid(c.ellipsoid('Rounded toe '+side,(x,6.0,1.1),(1.65,length,1.8),'canyon_skin',0,8,5),'foot.'+side)
        arm=c.tube('Continuous muscular forelimb '+side,[(s*8.4,0,41),(s*12,.4,37),
            (s*15,1,30),(s*15.5,2.5,26),(s*16,4,21)],
            [4.1,4.6,3.2,3.75,2.55],'canyon_skin',14)
        c.skin_weights(arm,rig,lambda v,side=side:_blend('upperarm.'+side,'chest',(v.z-38)/5) if v.z>38 else _blend('forearm.'+side,'upperarm.'+side,(v.z-26)/8))
        palm=rigid(c.ellipsoid('Huge broad palm '+side,(s*16,4.8,18.8),(7.4,4.6,7.4),'canyon_skin',.025,14,9),'hand.'+side)
        for digit in range(4):
            x=s*16+(digit-1.5)*1.45;z=17.3+(0,.3,.1,-.7)[digit]
            points=[(x,5,z),(x,5.3,z-1.8),(x,6,z-3.4),(x,6.7,z-4.2)]
            finger=c.tube('Grasping finger '+side+str(digit),points,[1.03,.97,.79,.5],'canyon_skin',9)
            rigid(finger,f'finger{digit}.{side}')
            rigid(c.ellipsoid('Finger knuckle '+side+str(digit),(x,3.6,z-.2),(1.75,1.2,1.65),'weathered_skin',0,8,5),f'finger{digit}.{side}')
            nail=c.ellipsoid('Weathered fingernail '+side+str(digit),(x,6.7,z-3.82),(1.10,.3,1.0),'basket_edge',0,8,4)
            rigid(nail,f'finger{digit}.{side}')
        thumb=c.tube('Opposing thumb '+side,[(s*13.1,4.1,20),(s*11.9,5,18.7),(s*11.6,6.6,17.1)],
                     [1.36,1.16,.63],'canyon_skin',10)
        rigid(thumb,'thumb.'+side)
        # Creases and tapered forearm hair give large limbs directional detail.
        for k in range(3):
            lock=c.tube('Forearm hair lock '+side,[(s*(15+k*.6),.0,29-k*.9),
                (s*(15.3+k*.7),.35,26-k),(s*(15.4+k*.7),1,23.8-k*.7)],
                [1.1,.8,.09],'shaggy_hair',5)
            rigid(lock,'forearm.'+side)
    # Thick neck supports a human-like face with a broad brow, jaw and blunt nose.
    neck=rigid(c.ellipsoid('Thick giant neck',(0,2,46.7),(10.8,10,11),'canyon_skin',.015,14,9),'neck')
    faceparts=[c.ellipsoid('Cranium',(0,3.3,53.1),(13.5,12.1,15.6),'canyon_skin',.025,16,10),
        c.ellipsoid('Left cheek',(-3.5,7,49.7),(6.4,5.7,7),'canyon_skin',0,12,8),
        c.ellipsoid('Right cheek',(3.5,7,49.7),(6.4,5.7,7),'canyon_skin',0,12,8),
        c.ellipsoid('Blunt brow nose',(0,9.1,51.6),(4.4,5.5,6.2),'canyon_skin',0,12,8)]
    face=c.unify(faceparts,'Sculpted canyon giant face','canyon_skin',.48,1150)
    rigid(face,'head')
    jaw=rigid(c.ellipsoid('Expressive lower jaw',(0,7.3,45.9),(9.4,7.2,5.7),'canyon_skin',.02,14,8),'jaw')
    rigid(c.ellipsoid('Shadow inside mouth',(0,9.7,47.4),(7.9,1.3,2.75),'mouth_shadow',0,12,7),'jaw')
    for i in range(6):
        tooth=c.box('Uneven squared upper tooth',((i-2.5)*1.05,10.8,48.0),(.91,.9,1.2-(i%2)*.2),'basket_edge',.15)
        rigid(tooth,'head')
    for s in [-1,1]:
        rigid(c.ellipsoid('Deep eye socket',(s*3.45,8.57,53.6),(4.3,2.0,2.5),'weathered_skin',0,12,7),'head')
        rigid(c.ellipsoid('Canyon amber eye',(s*3.45,9.40,53.55),(2.20,.92,1.07),'basket_edge',0,12,6),'head')
        rigid(c.ellipsoid('Searching dark pupil',(s*3.45,9.83,53.55),(.63,.23,.82),'dark',0,10,6),'head')
        brow=c.tube('Massive overhanging brow',[(s*1.0,9.35,53.95),(s*3.25,9.15,54.75),(s*5.2,8.0,55.0)],
                    [1.05,1.4,.68],'shaggy_hair',7)
        rigid(brow,'head')
        rigid(c.ellipsoid('Natural rounded ear',(s*6.8,3.6,52.3),(2.25,2.6,4.2),'canyon_skin',0,10,7),'head')
        rigid(c.ellipsoid('Ear inset',(s*7.38,4.45,52.3),(.55,1.2,2.2),'weathered_skin',0,8,5),'head')
        rigid(c.ellipsoid('Nostril',(s*1.15,11.4,50.4),(1.0,.5,.60),'dark',0,8,4),'head')
        # Small skin folds use the same matte skin palette, not drawn symbols.
        for k in range(2):
            fold=c.tube('Weathered cheek fold',[(s*(4.6+k*.45),8.65,51.0-k*.85),
                (s*(5.3+k*.3),7.8,49.7-k*.6)],[.20,.06],'weathered_skin',5)
            rigid(fold,'head')
    # A continuous cap and broad mantle underlie layered tapering locks.
    rigid(c.ellipsoid('Dense shaggy crown',(0,2.2,56.4),(14.8,13.2,11.5),'shaggy_hair',.06,14,9),'head')
    rigid(c.ellipsoid('Shaggy shoulder mantle',(0,-2.5,44.2),(25.2,13.6,12.3),'shaggy_hair',.045,16,9),'chest')
    for k in range(8):
        x=(k-3.5)*1.5; lift=1.7*(1-abs(x)/7)
        points=[(x,6.8,56.8+lift),(x-.35,4.9,59.5+lift*.8),
                (x-.7,1.5,61.2-abs(x)*.16),(x-.9,-2.5,59.1-abs(x)*.10)]
        rigid(c.tube('Swept crown hair ridge',points,[.28,.72,.88,.10],'shaggy_hair',5),'head')
    for i in range(17):
        a=TAU*i/17; x=6.2*math.cos(a);y=2.0+5.2*math.sin(a)
        # The forehead is clear; side/back locks run below the skull.
        front=math.sin(a)>.55
        length=4.2 if front else 11+(i%3)*1.35
        start=(x*.85,2+(y-2)*.80,58.3-.8*math.cos(a*3))
        mid=(x*1.09,y-.5,55.2)
        end=(x*1.16,y-1.4,58.3-length)
        lock=c.tube('Layered head hair lock',[start,mid,end],[1.8,1.8,.08],'shaggy_hair',5)
        rigid(lock,'head')
    for s in [-1,1]:
        for k in range(6):
            x=s*(4.5+k*1.6);y=(-.2 if k%2 else -2.0)
            lock=c.tube('Layered mantle lock',[(x,y,46.5),(x+s*.6,y-.15,43),
                 (x+s*.8,y+.1,38.5+(k%3))],[2.2,2.05,.10],'shaggy_hair',6)
            rigid(lock,'chest')
        # Beard corners frame the mouth while keeping the jaw readable.
        for k in range(3):
            lock=c.tube('Short irregular beard lock',[(s*(2.4+k*1.15),7.8,45.6),
                (s*(2.4+k*1.3),8.0,43.1),(s*(2.2+k*1.3),7.5,40.7+k*.45)],
                [1.25,1.2,.07],'shaggy_hair',6)
            rigid(lock,'jaw')
    # Open empty carrying basket: closed thick vessel with a woven outer surface.
    rows=[(22,6.3,4.5),(27,7.8,5.6),(34,9.5,6.4),(42,10.8,7.0),(47.5,11.7,7.4)]
    by=-18.0; sides=28;verts=[]
    for inner in [False,True]:
        for z,rx,ry in rows:
            if inner: z=max(z,23);rx-=.66;ry-=.66
            for j in range(sides):
                a=TAU*j/sides;verts.append((rx*math.cos(a),by+ry*math.sin(a),z))
    faces=[]; nr=len(rows);off=nr*sides
    for k in range(nr-1):
        for j in range(sides):
            a=k*sides+j;b=k*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides));faces.append((off+a+sides,off+b+sides,off+b,off+a))
    for j in range(sides):
        a=(nr-1)*sides+j;b=(nr-1)*sides+(j+1)%sides
        faces.append((a,b,off+b,off+a))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple(off+j for j in range(sides)))
    rigid(c.mesh('Empty thick-walled carrying basket',verts,faces,'basket_reed'),'basket')
    def dimensions(z):
        for a,b in zip(rows,rows[1:]):
            if a[0]<=z<=b[0]:
                t=(z-a[0])/(b[0]-a[0]);return a[1]*(1-t)+b[1]*t,a[2]*(1-t)+b[2]*t
        return rows[-1][1],rows[-1][2]
    # A low-sided tube makes each reed closed; alternating radii show over/under.
    for k in range(10):
        z=23+k*2.60;rx,ry=dimensions(z);points=[]
        for j in range(21):
            a=TAU*j/20;woven=.22*math.cos(j*math.pi)
            points.append(((rx+woven)*math.cos(a),by+(ry+woven)*math.sin(a),z))
        rigid(c.tube('Horizontal woven reed '+str(k),points,[.27]*len(points),'basket_edge' if k%3==0 else 'basket_reed',4),'basket')
    for j in range(16):
        a=TAU*j/16;points=[]
        for k in range(7):
            z=22.6+k*4.0;rx,ry=dimensions(z);r=.20*(-1 if k%2 else 1)
            points.append(((rx+r)*math.cos(a),by+(ry+r)*math.sin(a),z))
        rigid(c.tube('Vertical split reed '+str(j),points,[.25]*len(points),'basket_edge',4),'basket')
    for z in [22.5,47.4]:
        rx,ry=dimensions(z);points=[(rx*math.cos(TAU*j/24),by+ry*math.sin(TAU*j/24),z) for j in range(25)]
        rigid(c.tube('Bound basket rim',points,[.63 if z>40 else .43]*len(points),'basket_edge',6),'basket')
    for s in [-1,1]:
        strap=c.tube('Broad carrying strap',[(s*7,-13.5,43.5),(s*7,-3,46),
            (s*7,3.3,43.8),(s*6.7,6.5,38),(s*6,6.6,32),(s*6.8,3,27),(s*7,-16.0,26)],
            [.70,.80,.8,.8,.8,.75,.65],'basket_reed',6)
        c.skin_weights(strap,rig,lambda v:_blend('pelvis','chest',(v.z-27)/8))
        # Mounted plain rectangular join, no decorative patterns.
        rigid(c.box('Strap leather join',(s*6.8,7.0,35.5),(2.0,.65,2.9),'weathered_skin',.16),'chest')
    root_rest=rig.data.bones['root'].matrix_local.to_3x3()
    def pose(t):
        a=TAU*2*t;search=math.sin(TAU*t);sway=.34*math.sin(a)
        bob=.32*(1-math.cos(2*a));shift=Vector((sway,0,bob))
        grab=(.5-.5*math.cos(TAU*t))**3
        result={'root':{'location':tuple(root_rest.inverted()@shift)},
            'pelvis':{'rotation_euler':(0,.02*math.sin(a),.023*math.sin(a))},
            'chest':{'rotation_euler':(.025*math.sin(2*a),-.045*math.sin(a),-.045*math.sin(a))},
            'neck':{'rotation_euler':(.03*math.sin(TAU*t),0,.045*search)},
            'head':{'rotation_euler':(.06*math.sin(TAU*t+.4),.10*search,.10*search)},
            'jaw':{'rotation_euler':(-.055-.15*grab,0,0)},
            'basket':{'rotation_euler':(.018*math.sin(a-.65),.025*math.sin(a-.9),.018*math.sin(a-.4))}}
        for side,s in [('L',-1),('R',1)]:
            phase=a+(math.pi if s==1 else 0)
            hip=Vector((s*5.4,0,24))+shift
            ankle=Vector((s*6,-.8+2.8*math.cos(phase),3+1.8*max(0,math.sin(phase))**1.5))
            rest_knee=Vector((s*6,3.6,12));rest_hip=Vector((s*5.4,0,24));rest_ankle=Vector((s*6,-.8,3))
            l1=(rest_knee-rest_hip).length;l2=(rest_ankle-rest_knee).length
            d=(ankle-hip).length;direction=(ankle-hip).normalized()
            along=(l1*l1-l2*l2+d*d)/(2*d);height=math.sqrt(max(0,l1*l1-along*along))
            bend=Vector((0,1,0));bend=(bend-direction*bend.dot(direction)).normalized()
            knee=hip+direction*along+bend*height
            thigh_rot=_aim(rig,'thigh.'+side,knee-hip);shin_rot=_aim(rig,'shin.'+side,ankle-knee)
            foot_rot=rig.data.bones['foot.'+side].matrix_local.to_3x3()
            result['thigh.'+side]={'rotation_euler':_bone_rot(rig,'thigh.'+side,thigh_rot,root_rest)}
            result['shin.'+side]={'rotation_euler':_bone_rot(rig,'shin.'+side,shin_rot,thigh_rot)}
            result['foot.'+side]={'rotation_euler':_bone_rot(rig,'foot.'+side,foot_rot,shin_rot)}
            reach=grab if s==1 else .28*grab
            result['upperarm.'+side]={'rotation_euler':(.19*math.cos(phase+.3)+.75*reach,.08*math.sin(phase),s*.09*reach)}
            result['forearm.'+side]={'rotation_euler':(.12+.09*math.sin(phase+.7)+.70*reach,0,-s*.08*reach)}
            result['hand.'+side]={'rotation_euler':(.07*math.sin(phase+1)+.12*reach,0,s*.12*reach)}
            for digit in range(4):
                curl=.12+.95*reach+.055*math.sin(a+digit*.38)
                result[f'finger{digit}.{side}']={'rotation_euler':(-curl,0,0)}
            result['thumb.'+side]={'rotation_euler':(-.12-.26*reach,s*.18*reach,0)}
        return result
    c.animate_rig(rig,pose,step=3)
    bpy.context.scene.frame_set(0)
    return rig


def riot():
    """Seven styled marchers; each owns a complete offset skeleton and gestures."""
    c.timeline(8,30)
    c.group('Crowd_AuthoredMotion')
    c.add_material('crowd_rust',(.58,.18,.085),.9)
    c.add_material('crowd_skin_dark',(.31,.17,.105),.92)
    materials=['teal','crowd_rust','white','blue','stone','teal','crowd_rust']
    # Explicit staggered cluster; distinct builds, hats, signs, and held gestures.
    specs=[(-2.1,1.5,1.0,-.10),(.1,2.3,1.07,.06),(2.4,1.2,.96,.12),
           (-3.25,-1.2,1.03,-.18),(-.9,-.9,.94,.04),(1.5,-1.4,1.06,-.06),(3.7,-1.0,.98,.19)]
    bones=[]; persons=[]
    for i,(ox,oy,scale,yaw) in enumerate(specs):
        prefix='citizen'+str(i)+'.'
        rot=Matrix.Rotation(yaw,3,'Z')
        def w(v,ox=ox,oy=oy,scale=scale,rot=rot): return Vector((ox,oy,0))+rot@Vector(v)*scale
        joints={'hips':(0,0,.92),'chest':(0,0,1.37),'neck':(0,0,1.51),'head':(0,0,1.75)}
        for side,s in [('L',-1),('R',1)]:
            joints['hip'+side]=(s*.15,0,.94); joints['knee'+side]=(s*.16,.13,.52)
            joints['ankle'+side]=(s*.16,0,.14);joints['toe'+side]=(s*.16,.21,.12)
            joints['shoulder'+side]=(s*.255,0,1.40)
            raised=(side=='R' and i in (0,2,3,5)) or (side=='L' and i in (1,6))
            joints['elbow'+side]=(s*(.40 if raised else .38),.02,1.65 if raised else 1.08)
            joints['wrist'+side]=(s*(.34 if raised else .39),.08,1.94 if raised else .85)
            joints['hand'+side]=(s*(.34 if raised else .39),.10,2.035 if raised else .765)
        bones += [(prefix+'root',w((0,0,0)),w((0,0,.3)),None),
            (prefix+'spine',w(joints['hips']),w(joints['chest']),prefix+'root'),
            (prefix+'head',w(joints['neck']),w((0,0,1.9)),prefix+'spine')]
        for side,s in [('L',-1),('R',1)]:
            bones += [(prefix+'thigh'+side,w(joints['hip'+side]),w(joints['knee'+side]),prefix+'root'),
                (prefix+'shin'+side,w(joints['knee'+side]),w(joints['ankle'+side]),prefix+'thigh'+side),
                (prefix+'foot'+side,w(joints['ankle'+side]),w(joints['toe'+side]),prefix+'shin'+side),
                (prefix+'arm'+side,w(joints['shoulder'+side]),w(joints['elbow'+side]),prefix+'spine'),
                (prefix+'forearm'+side,w(joints['elbow'+side]),w(joints['wrist'+side]),prefix+'arm'+side),
                (prefix+'hand'+side,w(joints['wrist'+side]),w(joints['hand'+side]),prefix+'forearm'+side)]
        persons.append((prefix,w,joints,scale,yaw,rot))
    rig=c.make_rig('Seven_Independent_Citizen_Skeletons',bones)
    c.GROUP=None
    for i,(prefix,w,j,scale,yaw,rot) in enumerate(persons):
        shirt=materials[i]; skin='crowd_skin_dark' if i in (1,4,6) else 'skin'
        def rigid(obj,bone): c.rigid_skin(obj,rig,prefix+bone); return obj
        def ball(name,loc,size,mat,bone,segments=8,rings=4):
            obj=c.ellipsoid('Citizen '+str(i)+' '+name,w(loc),tuple(s*scale for s in size),mat,0,segments,rings)
            obj.rotation_euler.z=yaw
            return rigid(obj,bone)
        def tube(name,points,radii,mat,bone,sides=8):
            return rigid(c.tube('Citizen '+str(i)+' '+name,[w(v) for v in points],[r*scale for r in radii],mat,sides),bone)
        torso=_loft('Citizen '+str(i)+' tailored jacket',[(w((0,0,z)),rx*scale,ry*scale)
            for z,rx,ry in [(.87,.215,.15),(1.0,.22,.145),(1.28,.265,.145),(1.43,.25,.135),(1.49,.12,.095)]],shirt,10)
        rigid(torso,'spine')
        # Dark hem/belt, separate collar and small placket make a readable garment.
        ball('trouser pelvis',(0,0,.92),(.40,.27,.22),'blue','spine')
        tube('jacket placket',[(.015,.151,1.0),(.015,.153,1.40)],[.015,.015],'white','spine',5)
        ball('neck',(0,0,1.52),(.16,.17,.19),skin,'head')
        ball('human head',(0,.018,1.725),(.285,.265,.355),skin,'head',12,8)
        ball('nose',(0,.157,1.727),(.079,.105,.084),skin,'head',8,6)
        for s in [-1,1]:
            ball('ear',(s*.145,.008,1.729),(.066,.063,.109),skin,'head',8,6)
            ball('eye',(s*.06,.142,1.773),(.025,.022,.026),'dark','head',8,4)
        hairmat='dark'
        if i in (1,4):
            ball('curly hair silhouette',(0,-.035,1.844),(.325,.285,.20),hairmat,'head')
            for h in range(5):
                a=h*TAU/5
                ball('curled hair lock',(.12*math.cos(a),-.02+.095*math.sin(a),1.872),(.095,.10,.09),hairmat,'head',8,5)
        elif i==3:
            ball('long hair',(0,-.07,1.71),(.32,.23,.44),hairmat,'head')
            ball('hair swept back',(0,-.015,1.867),(.31,.27,.13),hairmat,'head')
        else:
            ball('cap crown',(0,-.005,1.891),(.32,.29,.15),shirt if i!=2 else 'stone','head')
            visor=c.box('Citizen '+str(i)+' cap visor',w((0,.15,1.88)),(.32*scale,.27*scale,.035*scale),shirt if i!=2 else 'stone',.013*scale)
            visor.rotation_euler.z=yaw;rigid(visor,'head')
        for side,s in [('L',-1),('R',1)]:
            hip=j['hip'+side]; knee=j['knee'+side]; ankle=j['ankle'+side]
            tube('trouser thigh '+side,[hip,knee],[.125,.099],'blue','thigh'+side,10)
            ball('fabric knee '+side,knee,(.207,.211,.23),'blue','shin'+side)
            tube('trouser calf '+side,[knee,ankle],[.098,.073],'blue','shin'+side,10)
            shoe=c.box('Citizen '+str(i)+' boot '+side,w((s*.16,.09,.083)),(.19*scale,.37*scale,.16*scale),'dark',.028*scale)
            shoe.rotation_euler.z=yaw;rigid(shoe,'foot'+side)
            shoulder=j['shoulder'+side];elbow=j['elbow'+side];wrist=j['wrist'+side]
            ball('rounded jacket shoulder '+side,shoulder,(.225,.23,.225),shirt,'arm'+side)
            tube('rolled sleeve '+side,[shoulder,elbow],[.113,.092],shirt,'arm'+side,10)
            ball('sleeve elbow '+side,elbow,(.185,.19,.185),shirt,'forearm'+side)
            end=Vector(elbow).lerp(Vector(wrist),.37)
            tube('sleeve cuff '+side,[elbow,end],[.092,.086],shirt,'forearm'+side)
            tube('bare forearm '+side,[end,wrist],[.075,.052],skin,'forearm'+side)
            ball('clenched hand '+side,j['hand'+side],(.145,.125,.177),skin,'hand'+side)
            ball('thumb '+side,Vector(j['hand'+side])+Vector((-s*.059,.035,-.015)),(.075,.07,.12),skin,'hand'+side,8,5)
        # Signs are rigid skinned to raised hands: pole, frame, and handmade symbols.
        if i in (0,2,6):
            side='L' if i==6 else 'R'; hand=Vector(j['hand'+side])
            bottom=hand-Vector((0,0,.20));top=hand+Vector((0,0,.77))
            tube('placard pole',[bottom,top],[.022,.022],'stone','hand'+side,6)
            center=hand+Vector((0,0,.67))
            board=c.box('Citizen '+str(i)+' placard board',w(center),(.75*scale,.055*scale,.48*scale),'white',.025*scale)
            board.rotation_euler.z=yaw;rigid(board,'hand'+side)
            # An original three-bar civic mark, legible at city scale without fonts.
            for k in range(3):
                mark=c.box('Citizen '+str(i)+' placard graphic',w(center+Vector((0,.035,.13-k*.125))),
                    ((.50 if k!=1 else .35)*scale,.022*scale,.045*scale),('crowd_rust' if shirt=='white' else shirt),.009*scale)
                mark.rotation_euler.z=yaw;rigid(mark,'hand'+side)
        if i in (1,5):
            # Distinct cross-body bag; strap and closed satchel stay on the torso.
            tube('crossbody strap',[(-.21,.154,1.42),(.19,.162,.94)],[.024,.024],'dark','spine',6)
            bag=c.box('Citizen '+str(i)+' satchel',w((.225,.13,1.02)),(.24*scale,.15*scale,.29*scale),'stone',.028*scale)
            bag.rotation_euler.z=yaw;rigid(bag,'spine')
    def crowd_pose(t):
        result={}
        for i,(prefix,w,j,scale,yaw,rot) in enumerate(persons):
            a=TAU*4*t+i*.83
            root_rest=rig.data.bones[prefix+'root'].matrix_local.to_3x3()
            shift=Vector((.018*math.sin(a),0,.012*(1-math.cos(2*a))))*scale
            result[prefix+'root']={'location':tuple(root_rest.inverted()@shift)}
            result[prefix+'spine']={'rotation_euler':(.04*math.sin(a),.05*math.sin(a*.5+i),.055*math.sin(a))}
            result[prefix+'head']={'rotation_euler':(.065*math.sin(a*.5+.4),.045*math.cos(a*.5),.09*math.sin(TAU*t+i))}
            for side,s in [('L',-1),('R',1)]:
                phase=a+(math.pi if s==1 else 0)
                hip=w(j['hip'+side])+shift
                ankle=w(j['ankle'+side])+rot@Vector((0,.12*math.cos(phase),.09*max(0,math.sin(phase))))*scale
                knee_rest=w(j['knee'+side]); hip_rest=w(j['hip'+side]);ankle_rest=w(j['ankle'+side])
                l1=(knee_rest-hip_rest).length;l2=(ankle_rest-knee_rest).length
                direction=(ankle-hip).normalized(); d=(ankle-hip).length
                # Reach stays within the two-bone chain; any roundoff remains bounded.
                along=(l1*l1-l2*l2+d*d)/(2*d);h=math.sqrt(max(0,l1*l1-along*along))
                bend=rot@Vector((0,1,0));bend=(bend-direction*bend.dot(direction)).normalized()
                knee=hip+direction*along+bend*h
                thigh_name=prefix+'thigh'+side;shin_name=prefix+'shin'+side;foot_name=prefix+'foot'+side
                thigh_rot=_aim(rig,thigh_name,knee-hip);shin_rot=_aim(rig,shin_name,ankle-knee)
                foot_rot=rig.data.bones[foot_name].matrix_local.to_3x3()
                result[thigh_name]={'rotation_euler':_bone_rot(rig,thigh_name,thigh_rot,root_rest)}
                result[shin_name]={'rotation_euler':_bone_rot(rig,shin_name,shin_rot,thigh_rot)}
                result[foot_name]={'rotation_euler':_bone_rot(rig,foot_name,foot_rot,shin_rot)}
                raised=j['wrist'+side][2]>1.5
                result[prefix+'arm'+side]={'rotation_euler':((.10 if raised else .27)*math.sin(phase),.05*math.cos(a*.5+i),.07*math.sin(a*.5+i))}
                result[prefix+'forearm'+side]={'rotation_euler':(.13*math.sin(a+i) if raised else .10+.08*math.sin(phase+.7),0,.065*math.sin(a*.5+i))}
                result[prefix+'hand'+side]={'rotation_euler':(.045*math.sin(a+i),.03*math.sin(a*.5),0)}
        return result
    c.animate_rig(rig,crowd_pose,step=3)
    bpy.context.scene.frame_set(0)
    return rig
