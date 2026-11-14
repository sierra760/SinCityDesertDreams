# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Mirage Menagerie: the walk-through Zoo (building 218) and its four animals.

Run: Blender --background --python tools/blender_exploration/build_zoo.py

Original procedural geometry authored here; no imported artwork or meshes.
Geometry is written in Godot axes (metres, +Y up, +Z toward the street front)
and rotated into Blender axes (+Z up) when each object is made; the game
applies the 1/16 tile scale. The lot is a walled 64 m square with an open
gate on +Z, a plus-shaped promenade and four railed enclosures. Objects whose
names end in -colonly are its collision shells: the ground slab, the walls,
the gate, the rails, the fountain basin and the snack stand. The animals are
separate GLBs whose named parts pivot at their joints; the game animates them.

The runtime pen bounds, plaque points and animal roaming paths live in
game/scripts/view/zoo_animal.gd and must match the layout below.
"""
import sys, json, math, hashlib, struct
from pathlib import Path
import bpy
from mathutils import Matrix, Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_resort_interiors as g

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT/'assets/zoo'
DEST = ROOT/'game/assets/desert-dreams-3d'
ANIMALS = ROOT/'game/assets/desert-dreams-zoo'
FONT = ROOT/'game/assets/fonts/biorhyme/BioRhyme-Medium.ttf'
CODE = 218
NAME = 'mirage-menagerie-walkthrough-zoo'
TO_BLENDER = g.TO_BLENDER

# ------------------------------------------------------------------ layout
GRADE = .2            # walking surface (top of the collision slab)
WALL = 30.8           # wall centre line on all four sides
WALL_T = .7
WALL_H = 2.6
PATH = 4.5            # promenade half width; also the gate's half opening
RAIL = 5.0            # rail line, |x| or |z|
RAIL_H = 1.15
INNER = WALL-WALL_T/2 # wall inner face
PEN_CENTRE = (RAIL+INNER)/2
PLAQUE_Z = 17.95      # plaque along the north-south promenade, |z|
# Pen quadrants (sign of x, sign of z) and their residents.
PENS = {'saguaroo':(1,1),'flamingoat':(-1,1),'periscope_tortoise':(-1,-1),'tumbleweasel':(1,-1)}
# Lot trees, planted at run time with the lot's vegetation zone species:
# (x, z) in lot metres, crown height and radius in tiles. Each stands in a pen
# clear of that pen's furnishings and its animal's path.
TREES = [(-27.3,27.3,.8,.15),(-20.0,-28.3,.85,.15),(-28.3,-13.5,.75,.14),(9.5,-9.5,.75,.14),(28.2,-28.2,.8,.14)]
TITLES = {'saguaroo':'SAGUAROO','flamingoat':'FLAMINGOAT','periscope_tortoise':'PERISCOPE TORTOISE','tumbleweasel':'TUMBLEWEASEL'}

# Shared, content-addressed surfaces already in the catalog (no new images).
SURFACE_FILES = {
    'desert-sand':'2f1cf594f7a43cda14a41dab3d5db8e47e749510ed35d4268adbd6475f10a658',
    'stucco':'a1c75451fc556750dbcca3f594da4e88e9d16f22eca4c60b8aeb043140e552fd',
    'limestone':'73fa088e2d4f6935e0812915b3317b83c8ce19b53ab1305dfc88b63be07afac4',
    'terrazzo-paving':'ac6c102e99f7919f31caac8978878bbe7eccb26b6018da5e2820accd509e651a',
}
# finish: (colour, roughness, metallic, emission, surface, metres per repeat)
LOT_FINISHES = {
    'sand': ('d6b88a',.95,0,0,'desert-sand',8.0),
    'adobe': ('d39b6c',.85,0,0,'stucco',4.0),
    'stone': ('e2d3b4',.8,0,0,'limestone',3.0),
    'path': ('e9dcc4',.55,0,0,'terrazzo-paving',6.0),
    'rock': ('b39a7a',.9,0,0,'limestone',2.5),
    'dirt': ('a7764b',.95,0,0,None,0),
    'grass': ('7a9443',.9,0,0,None,0),
    'water': ('2f8f93',.08,0,0,None,0),
    'foliage': ('4c7a3a',.8,0,0,None,0),
    'cactus': ('5b8e46',.7,0,0,None,0),
    'wood': ('6e4a2c',.75,0,0,None,0),
    'twig': ('b48a56',.9,0,0,None,0),
    'teal': ('2e8a83',.45,.2,0,None,0),
    'copper': ('b9733d',.35,.8,0,None,0),
    'awning_ivory': ('f1e6cf',.7,0,0,None,0),
    'awning_coral': ('e0795d',.7,0,0,None,0),
    'sign_teal': ('1f6c69',.5,0,0,None,0),
    'sign_ivory': ('f4ecd8',.5,0,0,None,0),
    'sign_neon_amber': ('ffbf5e',.4,0,.3,None,0),
    'warm_light': ('ffe3b0',.3,0,.25,None,0),
}

# ------------------------------------------------------------------ helpers
class Part(g.Asset):
    """Geometry for one animated piece, written in the animal's own axes."""

def ellipsoid(a,finish,center,radii,seg=10,rings=6,yaw=0.0,pitch=0.0,roll=0.0,smooth=True,floor=None):
    verts=[];faces=[]
    verts.append((0,-radii[1],0))
    for i in range(1,rings):
        t=math.pi*i/rings
        for j in range(seg):
            u=2*math.pi*j/seg
            verts.append((radii[0]*math.sin(t)*math.cos(u),-radii[1]*math.cos(t),radii[2]*math.sin(t)*math.sin(u)))
    verts.append((0,radii[1],0))
    top=len(verts)-1
    for j in range(seg):faces.append((0,1+(j+1)%seg,1+j))
    for i in range(rings-2):
        r0=1+i*seg;r1=r0+seg
        for j in range(seg):faces.append((r0+j,r0+(j+1)%seg,r1+(j+1)%seg,r1+j))
    last=1+(rings-2)*seg
    for j in range(seg):faces.append((last+j,last+(j+1)%seg,top))
    points=g.xform(verts,center,yaw,pitch,roll)
    # A grounded dome: the part below `floor` is pressed flat onto it.
    if floor is not None:points=[Vector((v.x,max(v.y,floor),v.z)) for v in points]
    a.add(finish,points,faces,smooth)

def ribbed(a,finish,profile,center=(0,0,0),ribs=8,depth=.09,seg=24,pitch=0.0,yaw=0.0):
    """A cactus column: a lathe whose radius swells into vertical ribs."""
    verts=[];faces=[];rings=[]
    for r,h in profile:
        if r<=1e-6:
            rings.append([len(verts)]);verts.append((0,h,0));continue
        ring=[]
        for i in range(seg):
            t=2*math.pi*i/seg;rr=r*(1+depth*math.cos(ribs*t))
            ring.append(len(verts));verts.append((rr*math.cos(t),h,rr*math.sin(t)))
        rings.append(ring)
    for ra,rb in zip(rings,rings[1:]):
        if len(ra)==1:
            for i in range(seg):faces.append((ra[0],rb[(i+1)%seg],rb[i]))
        elif len(rb)==1:
            for i in range(seg):faces.append((ra[i],ra[(i+1)%seg],rb[0]))
        else:
            for i in range(seg):faces.append((ra[i],ra[(i+1)%seg],rb[(i+1)%seg],rb[i]))
    a.add(finish,g.xform(verts,center,yaw,pitch),faces,True)

def rod(a,finish,p,q,r,seg=8):
    g.rod(a,finish,p,q,r,seg)

def box(a,finish,center,size,yaw=0.0):
    g.box(a,finish,center,size,yaw)

def solid(a,name,finish,center,size,yaw=0.0):
    box(a,finish,center,size,yaw);a.collider(name,center,size,yaw)

def cactus_arm(a,finish,base,side,reach,rise,r,seg=8):
    """An elbowed saguaro arm from `base`, out by `reach` then up by `rise`."""
    elbow=(base[0]+side*reach,base[1],base[2])
    rod(a,finish,base,elbow,r,seg)
    ellipsoid(a,finish,elbow,(r*1.02,r*1.02,r*1.02),seg,4)
    tip=(elbow[0],elbow[1]+rise,elbow[2])
    rod(a,finish,elbow,tip,r,seg)
    ellipsoid(a,finish,tip,(r,r*1.1,r),seg,4)

def mirrored(sx,sz,x,z):
    return (sx*x,sz*z)

# ------------------------------------------------------------------ the lot
def lot():
    a=g.Asset(NAME)
    # Ground slab: visible sand on top, solid to the walking grade.
    box(a,'sand',(0,GRADE/2,0),(63.0,GRADE,63.0))
    a.collider('Zoo ground',(0,GRADE/2,0),(63.0,GRADE,63.0))
    # Promenade: through the gate to the back, and across.
    box(a,'path',(0,GRADE+.012,.35),(PATH*2+.8,.024,62.3))
    box(a,'path',(0,GRADE+.012,0),(61.5,.024,PATH*2+.8))
    walls(a);gate(a);plaza(a);snack_stand(a)
    for species,(sx,sz) in PENS.items():
        rails(a,sx,sz);plaque(a,species,sx,sz)
        {'saguaroo':saguaroo_pen,'flamingoat':flamingoat_pen,
         'periscope_tortoise':tortoise_pen,'tumbleweasel':tumbleweasel_pen}[species](a,sx,sz)
    benches(a);lamps(a)
    return a

def walls(a):
    top=GRADE+WALL_H
    half_gate=PATH+1.25
    runs=[((0,-WALL),(63.0,WALL_T)),((-WALL,0),(WALL_T,63.0)),((WALL,0),(WALL_T,63.0))]
    front_len=WALL+WALL_T/2-half_gate
    for sx in (-1,1):runs.append(((sx*(half_gate+front_len/2),WALL),(front_len,WALL_T)))
    for (x,z),(w,d) in runs:
        solid(a,'Zoo wall','adobe',(x,GRADE+WALL_H/2,z),(w,WALL_H,d))
        box(a,'stone',(x,top+.09,z),(w+.12,.18,d+.12))
        box(a,'stone',(x,GRADE+.15,z),(w+.08,.3,d+.08))
    # Teal tile band on the street face.
    for sx in (-1,1):
        box(a,'teal',(sx*(half_gate+front_len/2),GRADE+1.9,WALL+WALL_T/2+.02),(front_len,.22,.04))

def gate(a):
    # Two adobe pylons and a stepped arch beam over the open promenade.
    for sx in (-1,1):
        x=sx*(PATH+.65)
        solid(a,'Zoo gate pylon','adobe',(x,GRADE+3.6,WALL),(1.3,7.2,1.3))
        box(a,'stone',(x,GRADE+7.3,WALL),(1.5,.2,1.5))
        box(a,'stone',(x,GRADE+.2,WALL),(1.45,.4,1.45))
        g.cylinder(a,'copper',(x,GRADE+7.75,WALL),.32,.7,10)
        g.sphere(a,'warm_light',(x,GRADE+8.3,WALL),.36,8,5)
        # Pylon portholes: a cactus-green tile stripe up each face.
        for z in (WALL+.66,WALL-.66):
            box(a,'teal',(x,GRADE+3.6,z),(.22,5.6,.03))
    beam_y=GRADE+5.6
    box(a,'adobe',(0,beam_y,WALL),(PATH*2+2.6,1.3,1.1))
    box(a,'stone',(0,beam_y+.75,WALL),(PATH*2+2.9,.2,1.3))
    box(a,'stone',(0,beam_y-.72,WALL),(PATH*2+2.7,.14,1.2))
    for z in (WALL+.56,WALL-.56):
        box(a,'sign_teal',(0,beam_y,z),(PATH*2+1.6,1.0,.04))
    # A copper sunburst crest rising from the beam.
    for i in range(9):
        t=math.pi*(i+1)/10
        rod(a,'copper',(0,beam_y+.85,WALL),(1.6*math.cos(t),beam_y+.85+1.25*math.sin(t),WALL),.06,6)
    g.cylinder(a,'copper',(0,beam_y+.9,WALL),.42,.12,16,axis='z')
    a.collider('Zoo gate beam',(0,beam_y,WALL),(PATH*2+2.6,1.3,1.1))
    letters(a,'MIRAGE MENAGERIE',(0,beam_y+.02,WALL+.6),0.0,PATH*2+.9,.62,'sign_neon_amber')
    letters(a,'MIRAGE MENAGERIE',(0,beam_y+.02,WALL-.6),math.pi,PATH*2+.9,.62,'sign_neon_amber')

def plaza(a):
    # Round fountain at the crossing: basin, water, a tiered copper spout.
    g.lathe(a,'stone',[(0,GRADE),(2.6,GRADE),(2.75,GRADE+.55),(2.55,GRADE+.62),(2.3,GRADE+.62),(2.3,GRADE+.3),(0,GRADE+.3)],(0,0,0),24,smooth=False)
    g.cylinder(a,'water',(0,GRADE+.47,0),2.32,.02,24,smooth=False)
    g.lathe(a,'stone',[(0,GRADE+.3),(.45,GRADE+.3),(.32,GRADE+1.3),(.9,GRADE+1.45),(.95,GRADE+1.6),(.25,GRADE+1.65),(.18,GRADE+2.4),(0,GRADE+2.4)],(0,0,0),16)
    g.cylinder(a,'water',(0,GRADE+1.57,0),.88,.02,16,smooth=False)
    ellipsoid(a,'copper',(0,GRADE+2.65,0),(.3,.32,.3),12,7)
    a.collider_lathe('Zoo fountain',[(0,GRADE),(2.75,GRADE),(2.75,GRADE+.62),(0,GRADE+.62)],(0,0,0),12)
    # Four planters with a cactus each, at the plaza's corners on the path.
    for sx in (-1,1):
        for sz in (-1,1):
            x,z=sx*3.55,sz*3.55
            g.cylinder(a,'adobe',(x,GRADE+.3,z),.5,.6,10)
            g.cylinder(a,'dirt',(x,GRADE+.61,z),.44,.02,12)
            ribbed(a,'cactus',[(0,GRADE+.6),(.13,GRADE+.62),(.15,GRADE+1.2),(.12,GRADE+1.5),(0,GRADE+1.58)],(x,0,z),8,.1,12)
            a.collider('Zoo planter',(x,GRADE+.3,z),(1.0,.6,1.0))

def snack_stand(a):
    # Adobe stand closing the back of the promenade, its counter toward the plaza.
    z0=-INNER;depth=3.4;cz=z0+depth/2
    solid(a,'Zoo snack stand','adobe',(0,GRADE+1.6,cz-.15),(8.0,3.2,depth-.3))
    box(a,'stone',(0,GRADE+3.3,cz),(8.4,.2,depth+.2))
    box(a,'wood',(0,GRADE+1.05,z0+depth+.05),(5.2,.12,.7))
    box(a,'sign_teal',(0,GRADE+2.0,z0+depth-.27),(5.0,1.4,.04))
    for i in range(8):
        x=-3.75+i*1.07
        box(a,'awning_ivory' if i%2==0 else 'awning_coral',(x,GRADE+2.95,z0+depth+.45),(1.07,.08,1.4))
    letters(a,'SNACKS & SODA',(0,GRADE+2.0,z0+depth-.24),0.0,4.5,.5,'sign_ivory')
    a.collider('Zoo snack counter',(0,GRADE+.55,z0+depth+.05),(5.2,1.1,.7))
    box(a,'wood',(0,GRADE+.5,z0+depth+.05),(5.0,1.0,.55))

def rails(a,sx,sz):
    """Teal pipe rails on the pen's two promenade sides, on a stone curb."""
    for along in ('x','z'):
        lo,hi=RAIL,INNER
        mid=(lo+hi)/2;length=hi-lo
        if along=='z':   # rail parallel to z, at x=sx*RAIL
            c=(sx*RAIL,0,sz*mid);size=(.42,0,length)
        else:
            c=(sx*mid,0,sz*RAIL);size=(length,0,.42)
        box(a,'stone',(c[0],GRADE+.09,c[2]),(size[0],.18,size[2]))
        a.collider('Zoo rail',(c[0],GRADE+.75,c[2]),(max(size[0],.3) if along=='x' else .3,1.5,max(size[2],.3) if along=='z' else .3))
        count=int(length/2.55)+1
        for i in range(count+1):
            s=lo+length*i/count
            p=(sx*RAIL,sz*s) if along=='z' else (sx*s,sz*RAIL)
            g.cylinder(a,'teal',(p[0],GRADE+.18+RAIL_H/2,p[1]),.055,RAIL_H,6)
            g.cylinder(a,'copper',(p[0],GRADE+.21+RAIL_H,p[1]),.08,.06,6)
        for y in (GRADE+.62,GRADE+.18+RAIL_H-.05):
            if along=='z':rod(a,'teal',(sx*RAIL,y,sz*lo),(sx*RAIL,y,sz*hi),.04,6)
            else:rod(a,'teal',(sx*lo,y,sz*RAIL),(sx*hi,y,sz*RAIL),.04,6)

def plaque(a,species,sx,sz):
    """A lettered board on two posts above the rail, facing the promenade."""
    x=sx*(RAIL-.05);z=sz*PLAQUE_Z
    for dz in (-1.15,1.15):
        g.cylinder(a,'wood',(x,GRADE+1.0,z+dz),.07,1.8,8)
    box(a,'wood',(x,GRADE+1.85,z),(.16,1.0,2.7))
    box(a,'sign_teal',(x-sx*.09,GRADE+1.85,z),(.02,.86,2.56))
    letters(a,TITLES[species],(x-sx*.11,GRADE+1.87,z),-sx*math.pi/2,2.35,.36,'sign_ivory')

def benches(a):
    for sx in (-1,1):
        x=sx*(INNER-.8)
        for dz in (-2.2,2.2):
            box(a,'wood',(x,GRADE+.45,dz),(.55,.08,1.8))
            box(a,'wood',(x+sx*.22,GRADE+.8,dz),(.08,.5,1.8))
            for e in (-.75,.75):box(a,'stone',(x,GRADE+.22,dz+e),(.5,.44,.12))
            a.collider('Zoo bench',(x,GRADE+.5,dz),(.6,1.0,1.8))

def lamps(a):
    spots=[(sx*(PATH-.25),sz*z) for sx in (-1,1) for sz in (-1,1) for z in (9.5,26.0)]
    spots+=[(sx*z,sz*(PATH-.25)) for sx in (-1,1) for sz in (-1,1) for z in (11.0,24.5)]
    for x,z in spots:
        g.cylinder(a,'copper',(x,GRADE+1.6,z),.07,3.2,6)
        g.cylinder(a,'copper',(x,GRADE+.12,z),.18,.24,6)
        g.sphere(a,'warm_light',(x,GRADE+3.35,z),.24,8,4)

# Pen furnishings, in the pen's own quadrant: (sx*x, sz*z) for x, z > 0.
def pen_ground(a,finish,sx,sz):
    size=INNER-RAIL-.25;c=PEN_CENTRE
    box(a,finish,(sx*c,GRADE+.015,sz*c),(size,.03,size))

def boulder(a,x,z,r,h,finish='rock',yaw=0.0):
    ellipsoid(a,finish,(x,GRADE+h*.35,z),(r,h,r*.8),9,5,yaw,smooth=False,floor=GRADE)

def saguaroo_pen(a,sx,sz):
    pen_ground(a,'sand',sx,sz)
    m=lambda x,z:mirrored(sx,sz,x,z)
    # Sandstone outcrop and a few boulders at the back of the pen.
    for x,z,r,h in ((26.5,26.0,2.4,1.6),(23.5,27.4,1.6,1.1),(27.6,22.6,1.3,.9),(10.5,27.6,1.1,.7),(28.0,9.5,1.0,.6)):
        boulder(a,*m(x,z),r,h,yaw=x)
    for x,z,height in ((14.0,26.5,4.2),(27.4,15.5,3.4),(9.0,9.0,2.6)):
        cx,cz=m(x,z)
        ribbed(a,'cactus',[(0,GRADE),(.32,GRADE+.05),(.34,GRADE+height*.8),(.28,GRADE+height),(0,GRADE+height+.12)],(cx,0,cz),10,.09,14)
        cactus_arm(a,'cactus',(cx,GRADE+height*.45,cz),1,.65,height*.25,.2)
        cactus_arm(a,'cactus',(cx,GRADE+height*.6,cz),-1,.55,height*.2,.18)
    # A shade sail on two timber poles.
    c0=m(12.5,13.0);c1=m(19.0,13.0)
    for x,z in (c0,c1):
        rod(a,'wood',(x,GRADE,z),(x,GRADE+3.2,z),.09,8)
    g.box(a,'awning_coral',((c0[0]+c1[0])/2,GRADE+2.93,c0[1]+sz*1.6),(abs(c1[0]-c0[0])+.4,.04,3.23),0.0,sz*math.atan2(.45,3.2))

def flamingoat_pen(a,sx,sz):
    pen_ground(a,'grass',sx,sz)
    m=lambda x,z:mirrored(sx,sz,x,z)
    px,pz=m(20.0,20.5)
    g.lathe(a,'rock',[(5.6,GRADE+.02),(5.45,GRADE+.13),(4.95,GRADE+.17),(4.8,GRADE+.05)],(px,0,pz),24,smooth=False,closed=True)
    g.cylinder(a,'water',(px,GRADE+.11,pz),4.9,.02,24,smooth=False)
    # Reeds around the pond's far side.
    for i in range(14):
        t=math.pi*(.15+1.1*i/13)
        rx=px+sx*5.2*math.cos(t);rz=pz+sz*5.2*math.sin(t)
        h=1.1+.35*math.sin(i*1.7)
        rod(a,'foliage',(rx,GRADE+.05,rz),(rx+.12*math.cos(i),GRADE+h,rz+.1*math.sin(i)),.035,5)
        ellipsoid(a,'wood',(rx+.12*math.cos(i),GRADE+h,rz+.1*math.sin(i)),(.06,.16,.06),6,4)
    # A rocky climbing hill for the goat half, with a ledge.
    for x,z,r,h in ((26.0,10.5,3.0,2.4),(23.5,8.6,2.0,1.4),(28.0,13.6,1.7,1.6),(9.6,27.0,1.4,.9)):
        boulder(a,*m(x,z),r,h,yaw=z)
    # A pink-and-ivory striped feeding trough.
    tx,tz=m(10.5,12.0)
    box(a,'wood',(tx,GRADE+.35,tz),(2.4,.12,.8))
    box(a,'awning_coral',(tx,GRADE+.5,tz),(2.4,.25,.85))
    for e in (-1.0,1.0):box(a,'wood',(tx+e,GRADE+.16,tz),(.12,.32,.7))

def tortoise_pen(a,sx,sz):
    pen_ground(a,'grass',sx,sz)
    m=lambda x,z:mirrored(sx,sz,x,z)
    # A burrow mound with a dark doorway, a fallen log and some clover tufts.
    bx,bz=m(26.0,26.0)
    ellipsoid(a,'dirt',(bx,GRADE,bz),(3.4,1.5,3.0),14,6,floor=GRADE)
    ellipsoid(a,'wood',(bx-sx*1.8,GRADE+.55,bz-sz*1.6),(.75,.6,.18),10,5,yaw=math.pi/4*sx*sz)
    lx,lz=m(12.0,26.5)
    rod(a,'wood',(lx-3.0,GRADE+.4,lz),(lx+2.6,GRADE+.4,lz-sz*.6),.4,10)
    for i in range(10):
        cx,cz=m(10.0+1.7*i,9.5+((i*7)%5)*.9)
        ellipsoid(a,'foliage',(cx,GRADE+.1,cz),(.35,.22,.35),7,4)
    # A tall striped "lookout" pole so visitors know where to watch.
    ox,oz=m(9.0,9.0)
    g.cylinder(a,'wood',(ox,GRADE+1.6,oz),.08,3.2,8)
    for k in range(4):
        box(a,'awning_ivory' if k%2==0 else 'teal',(ox,GRADE+2.6+k*.15,oz),(.6,.15,.04),math.pi/4)

def tumbleweasel_pen(a,sx,sz):
    pen_ground(a,'sand',sx,sz)
    m=lambda x,z:mirrored(sx,sz,x,z)
    cx,cz=m(18.0,18.0)
    # A packed dirt racetrack ring with a striped infield.
    g.lathe(a,'dirt',[(7.4,GRADE+.025),(7.4,GRADE+.05),(5.0,GRADE+.05),(5.0,GRADE+.025)],(cx,0,cz),32,smooth=False,closed=True)
    for k in range(8):
        t0=2*math.pi*k/8;t1=t0+math.pi/8
        g.prism(a,'awning_ivory',[(0,0),(4.9*math.cos(t1),4.9*math.sin(t1)),(4.9*math.cos(t0),4.9*math.sin(t0))],GRADE+.025,GRADE+.045,(cx,0,cz))
    # A hollow log tunnel across the track and a finish-line flag post.
    lx,lz=cx+sx*6.2,cz
    for e in (-1,1):
        g.torus(a,'wood',(lx,GRADE+.95,lz+e*1.1),.95,.2,16,6,axis='z')
    g.lathe(a,'wood',[(.98,-1.1),(.98,1.1),(.78,1.1),(.78,-1.1)],(lx,GRADE+.95,lz),16,axis='z',smooth=False,closed=True)
    fx,fz=cx-sx*1.4,cz-sz*8.0
    rod(a,'copper',(fx,GRADE,fz),(fx,GRADE+2.2,fz),.05,6)
    for row in range(2):
        for col in range(3):
            finish='awning_ivory' if (row+col)%2==0 else 'sign_teal'
            box(a,finish,(fx,GRADE+2.08-row*.2,fz+sz*(.15+col*.2)),(.02,.2,.2))
    # Tumbleweeds blown into the corners.
    for x,z,r in ((25.2,28.6,.7),(27.0,25.0,.5),(9.0,27.5,.55),(28.0,9.0,.6)):
        tumbleweed(a,'twig',(m(x,z)[0],GRADE+r,m(x,z)[1]),r,int(x*z)%7)

def tumbleweed(a,finish,center,r,phase=0,count=16,width=.025):
    for k in range(count):
        t=(k+.5)/count;y=1-2*t;rr=math.sqrt(max(0,1-y*y))
        u=k*2.39996+phase
        p=Vector((rr*math.cos(u),y,rr*math.sin(u)))*r
        q=Vector((-p.x*.9+.2*r*math.sin(u),-p.y*.85,-p.z*.9+.2*r*math.cos(u)))
        rod(a,finish,tuple(Vector(center)+p),tuple(Vector(center)+q),width,4)

# ------------------------------------------------------------------ lettering
LETTERING=[]
def letters(a,text,center,yaw,width,size,finish):
    """Queue BioRhyme lettering facing local +Z rotated by `yaw` (Godot)."""
    LETTERING.append((text,center,yaw,width,size,finish))

def make_lettering():
    font=bpy.data.fonts.load(str(FONT),check_existing=True)
    out=[]
    for text,center,yaw,width,size,finish in LETTERING:
        curve=bpy.data.curves.new(text,'FONT');curve.body=text;curve.font=font
        curve.align_x='CENTER';curve.align_y='CENTER';curve.size=size;curve.extrude=0.0;curve.resolution_u=2
        o=bpy.data.objects.new('Lettering '+text,curve);bpy.context.scene.collection.objects.link(o)
        o.location=TO_BLENDER@Vector(center);o.rotation_euler=(math.pi/2,0,yaw)
        curve.materials.append(MATS[finish]);bpy.context.view_layer.update()
        if o.dimensions.x>width:o.scale*=width/o.dimensions.x
        bpy.ops.object.select_all(action='DESELECT')
        bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH')
        m=bpy.context.object;bpy.context.view_layer.update()
        m.data.transform(m.matrix_world);m.matrix_world=Matrix.Identity(4)
        out.append(m)
    LETTERING.clear()
    return out

# ------------------------------------------------------------------ materials
MATS={}
SURFACE_MEAN={}
def linear(hexcolor):
    rgb=[int(hexcolor[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in rgb)

def surface_image(name):
    import numpy as np
    path=DEST/'surfaces'/(SURFACE_FILES[name]+'.jpg')
    image=bpy.data.images.load(str(path),check_existing=True)
    if name not in SURFACE_MEAN:
        px=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(px)
        rgb=px.reshape(-1,4)[:,:3]
        # Byte images report display-encoded values; average in linear light.
        lin=np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
        SURFACE_MEAN[name]=tuple(float(v) for v in lin.mean(0))
    return image

def make_material(name,spec):
    color,rough,metal,emission,surface,_=spec
    lin=linear(color)
    label=name if surface is None else '%s • %s'%(name,surface)
    mat=bpy.data.materials.new(label);mat.use_nodes=True;mat.diffuse_color=(*lin,1)
    nodes,links=mat.node_tree.nodes,mat.node_tree.links
    bs=nodes['Principled BSDF']
    bs.inputs['Base Color'].default_value=(*lin,1)
    bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
    if emission>0:
        bs.inputs['Emission Color'].default_value=(*lin,1);bs.inputs['Emission Strength'].default_value=emission
    if surface:
        image=surface_image(surface);mean=SURFACE_MEAN[surface]
        factor=tuple(min(1.0,lin[i]/max(mean[i],1e-4)) for i in range(3))+(1.0,)
        tex=nodes.new('ShaderNodeTexImage');tex.image=image;tex.extension='REPEAT';tex.interpolation='Linear'
        mix=nodes.new('ShaderNodeMix');mix.data_type='RGBA';mix.blend_type='MULTIPLY'
        mix.inputs[0].default_value=1.0;mix.inputs[7].default_value=factor
        links.new(tex.outputs['Color'],mix.inputs[6]);links.new(mix.outputs[2],bs.inputs['Base Color'])
        mat['surface_texture']=surface;mat['meters_per_repeat']=spec[5]
    return mat

def lot_materials():
    MATS.clear()
    for name,spec in LOT_FINISHES.items():MATS[name]=make_material(name,spec)
    g.MATS.clear();g.MATS.update(MATS)
    g.FINISHES[:]=list(LOT_FINISHES)

def box_uv(obj,period):
    uv=obj.data.uv_layers.new(name='SurfaceUV')
    for poly in obj.data.polygons:
        axis=max(range(3),key=lambda k:abs(poly.normal[k]))
        for index in poly.loop_indices:
            v=obj.data.vertices[obj.data.loops[index].vertex_index].co
            # Blender Z is up: vertical faces keep their courses horizontal.
            s,t=(v.y,v.z) if axis==0 else (v.x,v.z) if axis==1 else (v.x,v.y)
            uv.data[index].uv=(s/(period*2),t/(period*2))

# ------------------------------------------------------------------ export
def glb_doc(raw):
    n=struct.unpack_from('<I',raw,12)[0]
    return json.loads(raw[20:20+n]),raw[28+n:]

def write_glb(path,doc,binary):
    encoded=json.dumps(doc,separators=(',',':'),ensure_ascii=False).encode()
    encoded+=b' '*((-len(encoded))%4)
    binary=bytes(binary)+b'\0'*((-len(binary))%4)
    size=12+8+len(encoded)+8+len(binary)
    path.write_bytes(struct.pack('<III',0x46546c67,2,size)+struct.pack('<II',len(encoded),0x4e4f534a)
                     +encoded+struct.pack('<II',len(binary),0x004e4942)+binary)

def share_existing_images(path):
    """Point the runtime GLB at the existing shared surfaces; drop embedded copies."""
    doc,binary=glb_doc(path.read_bytes())
    known={sha:sha for sha in SURFACE_FILES.values()}
    for image in doc.get('images',[]):
        stem=image.get('name','').split('.')[0]
        assert stem in known,'unexpected image %s'%image.get('name')
        image.pop('bufferView');image.pop('mimeType',None)
        image['uri']='surfaces/%s.jpg'%stem
    used=set()
    def collect(value):
        if isinstance(value,dict):
            for k,v in value.items():
                if k=='bufferView':used.add(v)
                else:collect(v)
        elif isinstance(value,list):
            for v in value:collect(v)
    collect({k:v for k,v in doc.items() if k not in ('bufferViews','buffers')})
    packed=bytearray();views=[];remap={}
    for old in sorted(used):
        view=dict(doc['bufferViews'][old]);offset=view.get('byteOffset',0)
        while len(packed)%4:packed.append(0)
        view['byteOffset']=len(packed);packed.extend(binary[offset:offset+view['byteLength']])
        remap[old]=len(views);views.append(view)
    def renumber(value):
        if isinstance(value,dict):
            for k,v in value.items():
                if k=='bufferView':value[k]=remap[v]
                else:renumber(v)
        elif isinstance(value,list):
            for v in value:renumber(v)
    for k in list(doc):
        if k not in ('bufferViews','buffers'):renumber(doc[k])
    doc['bufferViews']=views;doc['buffers']=[{'byteLength':len(packed)}]
    write_glb(path,doc,packed)

def visible_triangles(path):
    doc,_=glb_doc(path.read_bytes())
    total=0
    for node in doc['nodes']:
        if node.get('name','').endswith('-colonly') or 'mesh' not in node:continue
        for p in doc['meshes'][node['mesh']]['primitives']:
            total+=doc['accessors'][p.get('indices',p['attributes']['POSITION'])]['count']//3
    return total

def export_selected(path,objects,embed=True):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,
        export_materials='EXPORT',export_cameras=False,export_lights=False,export_extras=False,
        export_image_format='JPEG',export_jpeg_quality=90,export_apply=False)

def export_lot():
    g.reset();lot_materials()
    a=lot()
    objects=g.make_objects(a)
    for o in objects:
        finish=o.name.removeprefix(NAME+' ')
        period=LOT_FINISHES[finish][5]
        if LOT_FINISHES[finish][4]:box_uv(o,period)
    objects+=make_lettering()
    objects+=g.make_colliders(a)
    coords=[v for vs,_,_ in a.parts.values() for v in vs]
    bad={f:(min(v.y for v in vs),max(max(abs(v.x),abs(v.z)) for v in vs)) for f,(vs,_,_) in a.parts.items()}
    assert min(v.y for v in coords)>=-1e-6 and all(abs(v.x)<=31.6 and abs(v.z)<=31.6 for v in coords),bad
    high=max(v.y for v in coords)
    bpy.context.scene['provenance']='Original procedural geometry authored for Sin City: Desert Dreams; no external assets'
    bpy.context.scene['units']='metres, Godot axes rotated to Blender +Z up, gate toward -Y; game applies 1/16 tile scale'
    SOURCE.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    master=SOURCE/'zoo.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(master))
    standalone=SOURCE/'zoo-standalone.glb'
    export_selected(standalone,objects)
    path=DEST/('%d-blender.glb'%CODE)
    export_selected(path,objects)
    share_existing_images(path)
    triangles=visible_triangles(path)
    for f,(vs,fs,_) in sorted(a.parts.items(),key=lambda kv:-sum(len(x)-2 for x in kv[1][1])):print('ZOO_FINISH',f,sum(len(x)-2 for x in fs))
    for o in objects:
        if o.name.startswith('Lettering') and o.type=='MESH':print('ZOO_LETTERS',o.name,sum(len(p.vertices)-2 for p in o.data.polygons))
    assert triangles<40000,triangles
    textured=sum(1 for spec in LOT_FINISHES.values() if spec[4])
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    entry={'code':CODE,'path':'res://assets/desert-dreams-3d/%d-blender.glb'%CODE,'scale':.0625,'pivot':[0,0,0],
        'yaw':0,'height':high/16,'footprint':[4,4],'triangles':triangles,'source_kind':'authored_blender',
        'glb_sha256':sha(path),'meters_per_tile':16}
    record={'code':CODE,'name':NAME,'master_blend_sha256':sha(master),'standalone_glb_sha256':sha(standalone),
        'runtime_glb_sha256':sha(path),'textured_materials':textured,'runtime_bytes':path.stat().st_size}
    return entry,record

# ------------------------------------------------------------------ animals
ANIMAL_COLORS = {
    'saguaroo': {'cactus':'5f9a48','rib':'467a36','belly':'d9c58e','flower':'ef6f9a','flower_core':'f7c948','eye':'15100c','glint':'fff6e0','foot':'7c5a3a','spine':'f4ecd2'},
    'flamingoat': {'fur':'f29ab4','fur_light':'fcd6e0','leg':'ec6f8e','horn':'e2d1a4','hoof':'3a2a26','eye':'15100c','glint':'fff6e0','nose':'b8566e'},
    'periscope_tortoise': {'shell':'6d8a45','scute':'d0a64e','belly':'d9c58e','skin':'a3b46e','brass':'c48a3a','lens':'2a8c8a','eye':'15100c','glint':'fff6e0'},
    'tumbleweasel': {'weed':'b98d58','weed_dark':'7d5932','fur':'9a6236','belly':'efd9b0','nose':'1a1210','eye':'15100c','glint':'fff6e0'},
}

def animal_materials(species):
    MATS.clear()
    for key,color in ANIMAL_COLORS[species].items():
        rough={'lens':.08,'brass':.35,'glint':.2,'eye':.2}.get(key,.75)
        metal={'brass':.8}.get(key,0)
        MATS[key]=make_material('zoo_%s_%s'%(species,key),(color,rough,metal,0,None,0))

def eyes(a,center,spread,r,forward=(0,0,1)):
    for s in (-1,1):
        c=(center[0]+s*spread,center[1],center[2])
        g.sphere(a,'eye',c,r,10,6)
        g.sphere(a,'glint',(c[0]+s*r*.15,c[1]+r*.45,c[2]+r*.65),r*.28,6,4)

def saguaroo():
    parts={}
    body=Part('Body');parts['Body']=((0,1.0,-.1),None,body)
    ribbed(body,'cactus',[(0,-.1),(.4,-.05),(.44,.35),(.38,.8),(.3,1.05),(0,1.12)],(0,0,0),8,.09,24,pitch=.32)
    ellipsoid(body,'belly',(0,.42,.24),(.28,.42,.12),10,6,pitch=.32)
    for i in range(16):
        t=i*2.4;h=.1+.06*i
        p=Vector((.42*math.cos(t),h,.42*math.sin(t)));p=Matrix.Rotation(.32,3,'X')@p
        if p.z<.15:rod(body,'spine',tuple(p),tuple(p*1.13),.012,4)
    head=Part('Head');parts['Head']=((0,2.06,.32),'Body',head)
    ellipsoid(head,'cactus',(0,.1,.1),(.22,.21,.3),12,7)
    ellipsoid(head,'cactus',(0,.02,.38),(.12,.1,.14),10,5)
    g.sphere(head,'eye',(0,.04,.52),.035,8,4)
    eyes(head,(0,.17,.3),.12,.055)
    for s in (-1,1):   # prickly-pear pad ears
        ellipsoid(head,'cactus',(s*.13,.47,-.02),(.11,.24,.05),10,6,roll=-s*.25)
        for k in range(3):rod(head,'spine',(s*.13,.38+.1*k,.02),(s*.13,.38+.1*k,.09),.01,4)
    for k in range(6):   # flower crown
        t=2*math.pi*k/6
        ellipsoid(head,'flower',(.11*math.cos(t),.33,.1*math.sin(t)-.02),(.08,.04,.08),8,4,yaw=t)
    g.sphere(head,'flower_core',(0,.36,-.02),.05,8,4)
    for s in (-1,1):
        arm=Part('Arm'+('L' if s<0 else 'R'));parts[arm.name]=((s*.33,1.72,.24),'Body',arm)
        cactus_arm(arm,'cactus',(0,0,0),s,.34,.38,.1)
        leg=Part('Leg'+('L' if s<0 else 'R'));parts[leg.name]=((s*.27,1.0,-.15),'Body',leg)
        ellipsoid(leg,'cactus',(s*.06,-.22,.02),(.22,.38,.33),12,7)
        rod(leg,'rib',(s*.08,-.5,-.05),(s*.1,-.86,-.04),.1,8)
        ellipsoid(leg,'foot',(s*.1,-.92,.2),(.13,.07,.42),10,5)
    tail=Part('Tail');parts['Tail']=((0,.98,-.48),'Body',tail)
    ribbed(tail,'cactus',[(0,0),(.2,.02),(.16,.6),(.08,1.05),(0,1.1)],(0,0,0),8,.08,16,pitch=-2.2)
    return parts

def flamingoat():
    parts={}
    body=Part('Body');parts['Body']=((0,1.55,0),None,body)
    ellipsoid(body,'fur',(0,0,0),(.32,.3,.56),14,8)
    for k in range(7):
        t=k*.9
        g.sphere(body,'fur_light',(.18*math.cos(t),.22+.03*math.sin(3*t),.35*math.sin(t)-.05),.14,8,5)
    neck=Part('Neck');parts['Neck']=((0,1.72,.42),'Body',neck)
    rod(neck,'fur',(0,0,0),(0,.36,.18),.11,10)
    g.sphere(neck,'fur_light',(0,.08,.02),.15,8,5)
    head=Part('Head');parts['Head']=((0,2.1,.62),'Neck',head)
    ellipsoid(head,'fur',(0,0,.08),(.15,.15,.24),12,7,pitch=.35)
    ellipsoid(head,'nose',(0,-.11,.28),(.08,.06,.07),8,4)
    eyes(head,(0,.07,.15),.1,.045)
    for s in (-1,1):
        g.torus(head,'horn',(s*.1,.17,-.04),.12,.035,14,6,axis='x',arc=4.6,start=-.6)
        ellipsoid(head,'fur_light',(s*.19,.05,-.02),(.11,.04,.06),8,4,roll=s*.4)
    g.cylinder(head,'fur_light',(0,-.22,.13),.04,.16,8,top=.01)
    tail=Part('Tail');parts['Tail']=((0,1.62,-.55),'Body',tail)
    g.sphere(tail,'fur_light',(0,.05,-.06),.12,8,5)
    for s in (-1,1):
        side='L' if s<0 else 'R'
        upper=Part('Leg'+side);parts[upper.name]=((s*.12,1.34,.05),'Body',upper)
        rod(upper,'leg',(0,0,0),(0,-.62,0),.035,8)
        g.sphere(upper,'leg',(0,-.62,0),.055,8,4)
        g.sphere(upper,'fur',(0,.02,0),.1,8,5)
        lower=Part('Shin'+side);parts[lower.name]=((s*.12,.72,.05),upper.name,lower)
        rod(lower,'leg',(0,0,0),(0,-.66,0),.03,8)
        box(lower,'hoof',(0,-.67,.05),(.1,.06,.16))
    return parts

def periscope_tortoise():
    parts={}
    shell=Part('Shell');parts['Shell']=((0,.28,0),None,shell)
    g.lathe(shell,'shell',[(0,0),(.95,0),(.98,.12),(.88,.38),(.66,.62),(.36,.78),(0,.82)],(0,0,0),20)
    for h,r in ((.12,.99),(.4,.88),(.64,.65)):
        g.torus(shell,'scute',(0,h,0),r,.035,24,5)
    for k in range(6):
        t=2*math.pi*k/6
        rod(shell,'scute',(.66*math.cos(t),.64,.66*math.sin(t)),(.92*math.cos(t),.32,.92*math.sin(t)),.03,5)
    g.cylinder(shell,'belly',(0,-.02,0),.9,.08,20)
    for i,(x,z) in enumerate(((.55,.48),(-.55,.48),(.55,-.48),(-.55,-.48))):
        leg=Part('Leg%d'%i);parts[leg.name]=((x,.22,z),'Shell',leg)
        g.cylinder(leg,'skin',(0,-.1,0),.16,.26,10,top=.14)
        ellipsoid(leg,'skin',(0,-.21,.04),(.18,.05,.22),10,4)
    tail=Part('Tail');parts['Tail']=((0,.22,-.92),'Shell',tail)
    g.cylinder(tail,'skin',(0,0,-.1),.07,.25,8,axis='z',top=.01)
    radii=(.17,.145,.12)
    names=('NeckA','NeckB','NeckC')
    for i,(n,r) in enumerate(zip(names,radii)):
        p=Part(n);pivot=(0,.55,.78) if i==0 else (0,.55,0)
        parts[n]=(pivot,None if i==0 else names[i-1],p)
        g.cylinder(p,'skin',(0,.3,0),r,.6,12)
        g.torus(p,'brass',(0,.59,0),r+.012,.025,14,5)
    parts['NeckA']=((0,.55,.78),'Shell',parts['NeckA'][2])
    head=Part('Head');parts['Head']=((0,.62,0),'NeckC',head)
    ellipsoid(head,'skin',(0,.1,.06),(.17,.15,.22),12,7)
    g.cylinder(head,'brass',(0,.13,.28),.11,.14,14,axis='z')
    g.cylinder(head,'lens',(0,.13,.355),.085,.02,14,axis='z')
    box(head,'brass',(0,.24,.12),(.2,.05,.24))
    eyes(head,(0,.18,.16),.11,.04)
    g.torus(head,'eye',(0,-.01,.19),.07,.012,10,4,axis='x',arc=math.pi,start=math.pi)
    return parts

def tumbleweasel():
    parts={}
    ball=Part('Ball');parts['Ball']=((0,.55,0),None,ball)
    g.sphere(ball,'weed_dark',(0,0,0),.4,10,6)
    tumbleweed(ball,'weed',(0,0,0),.55,0,34,.024)
    tumbleweed(ball,'weed_dark',(0,0,0),.5,1.3,14,.02)
    head=Part('Head');parts['Head']=((0,.86,.36),None,head)
    ellipsoid(head,'fur',(0,.06,.08),(.14,.13,.2),12,7)
    ellipsoid(head,'belly',(0,-.01,.16),(.1,.07,.14),10,5)
    g.sphere(head,'nose',(0,.06,.3),.035,8,4)
    eyes(head,(0,.13,.17),.08,.035)
    for s in (-1,1):
        ellipsoid(head,'fur',(s*.1,.19,.0),(.05,.06,.025),8,4)
        for k in (-1,1):rod(head,'belly',(s*.04,.04,.27),(s*.2,.04+k*.03,.29),.006,3)
    for s in (-1,1):g.sphere(head,'fur',(s*.11,-.13,.12),.05,8,4)
    tail=Part('Tail');parts['Tail']=((0,.7,-.48),None,tail)
    for k in range(5):
        t=k/4
        ellipsoid(tail,'fur' if k<4 else 'belly',(0,.12*t+.32*t*t,-.16*t),(.1+.03*k,.11+.02*k,.12+.02*k),10,6)
    return parts

BUILDERS={'saguaroo':saguaroo,'flamingoat':flamingoat,'periscope_tortoise':periscope_tortoise,'tumbleweasel':tumbleweasel}

def export_animal(species):
    g.reset();animal_materials(species)
    g.MATS.clear();g.MATS.update(MATS);g.FINISHES[:]=list(ANIMAL_COLORS[species])
    parts=BUILDERS[species]()
    # Neck segments chain their pivots relative to the parent; all other
    # pivots are given in the animal's own space.
    chained={'NeckB','NeckC','Head'} if species=='periscope_tortoise' else set()
    world={}
    def resolve(name):
        if name in world:return world[name]
        pivot,parent,_=parts[name]
        p=Vector(pivot)
        if name in chained and parent is not None:p=resolve(parent)+p
        world[name]=p;return p
    root=bpy.data.objects.new(species,None);bpy.context.scene.collection.objects.link(root)
    made={}
    triangles=0
    def make(name):
        if name in made:return made[name]
        pivot,parent,asset=parts[name]
        here=resolve(name)
        # Part geometry is authored around its own joint already.
        objs=g.make_objects(asset)
        # One object per part: join the per-finish meshes.
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:o.select_set(True)
        bpy.context.view_layer.objects.active=objs[0]
        if len(objs)>1:bpy.ops.object.join()
        obj=bpy.context.view_layer.objects.active;obj.name=name;obj.data.name=species+' '+name
        owner=root if parent is None else make(parent)
        # Parts carry no rest rotation: each sits at its joint's offset from
        # its parent's joint, which is exactly the local position the game reads.
        origin=Vector((0,0,0)) if parent is None else resolve(parent)
        obj.parent=owner;obj.matrix_parent_inverse=Matrix.Identity(4)
        obj.location=TO_BLENDER@(here-origin)
        made[name]=obj
        return obj
    for name in parts:make(name)
    for name,(_,_,asset) in parts.items():triangles+=asset.triangles()
    master=SOURCE/('%s.blend'%species)
    bpy.ops.wm.save_as_mainfile(filepath=str(master))
    ANIMALS.mkdir(parents=True,exist_ok=True)
    path=ANIMALS/('%s.glb'%species)
    export_selected(path,[root]+list(made.values()))
    sidecar=ANIMALS/(path.name+'.import')
    if not sidecar.exists():sidecar.write_text(g.SIDECAR.replace('{path}','res://assets/desert-dreams-zoo/'+path.name))
    return {'species':species,'path':'res://assets/desert-dreams-zoo/%s.glb'%species,
            'parts':sorted(parts),'triangles':triangles,'master_blend_sha256':hashlib.sha256(master.read_bytes()).hexdigest(),
            'glb_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'pivots':{n:[round(c,4) for c in resolve(n)] for n in parts}}

# ------------------------------------------------------------------ main
def main():
    entry,record=export_lot()
    catalog_path=DEST/'catalog.json';catalog=json.loads(catalog_path.read_text())
    catalog['entries']=[entry if e['code']==CODE else e for e in catalog['entries']]
    catalog_path.write_text(json.dumps(catalog,indent=2)+'\n')
    landscaping_path=DEST/'landscaping.json';landscaping=json.loads(landscaping_path.read_text())
    palms=[[round(x/16,6),round(GRADE/16,6),round(z/16,6),h,r] for x,z,h,r in TREES]
    for row in landscaping['entries']:
        if row['code']==CODE:row['glb_sha256']=entry['glb_sha256'];row['palms']=palms
    landscaping_path.write_text(json.dumps(landscaping,indent=2)+'\n')
    materials_path=ROOT/'docs/art/building-materials.json';materials=json.loads(materials_path.read_text())
    materials['models']=[record if r['code']==CODE else r for r in materials['models']]
    materials_path.write_text(json.dumps(materials,indent=2)+'\n')
    animals=[export_animal(species) for species in PENS]
    manifest={'title':'Mirage Menagerie animals','provenance':'Original procedural Blender geometry authored for Sin City: Desert Dreams; fictional species; no external assets.',
              'units':'metres, +Y up, +Z forward, feet on y=0; parts pivot at their joints','lot':record,'animals':animals}
    (ROOT/'docs/art/zoo.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('ZOO_LOT',entry['triangles'],entry['height'])
    for a in animals:print('ZOO_ANIMAL',a['species'],a['triangles'])

if __name__=='__main__':main()
