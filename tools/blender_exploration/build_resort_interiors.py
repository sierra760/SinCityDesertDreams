# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Gaming resort casino floors: four halls and the shared prop kit.

Run: Blender --background --python tools/blender_exploration/build_resort_interiors.py --
     [--skip-render] [--review-dir DIR] [--only NAME[,NAME...]]

Original procedural geometry authored here; no imported artwork or meshes.
Geometry is written in Godot axes (metres, +Y up, +Z toward the door) and
rotated into Blender axes (+Z up, front toward -Y) when each object is made.
GLBs export +Y up, so the game reads Godot axes back; the game applies the
1/16 tile scale. Materials are named resort_<finish>; the game replaces each
with the procedural resort finish in the resort's palette. Objects whose
names end in -colonly are simplified collision shells.
"""
import bpy, math, json, sys, argparse, hashlib
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT/'assets/resort-interiors'
EXPORT = ROOT/'game/assets/desert-dreams-resorts'
FONTS = ROOT/'game/assets/fonts'
REVIEW = Path('/tmp/scdd-resort-review')
FINISHES = ['floor','carpet','wall','ceiling','stone','wood','metal','glass','felt','lamp','sign','screen','rubber','cove','foliage']
TO_BLENDER = Matrix.Rotation(math.pi/2,4,'X')

# ---------------------------------------------------------------- themes
RESORTS = {
    251: {'key':'arcology_comstock','name':'Comstock Grand','floor':'The Assay Office','signature':'faro',
          'font':'fontdiner-swanky/FontdinerSwanky-Regular.ttf','chandelier':'chandelier_gaslamp',
          'games':{'blackjack':'Assay Twenty-One','roulette':'Winding Wheel Roulette','slots':'Silver Strike',
                   'money_wheel':"Prospector's Wheel",'video_poker':'Bonanza Draw','faro':'Faro at the Assay Office'},
          'palette':{'stone':'c9a878','metal':'b06b3a','wood':'4a2e1c','glass':'1f6e68','lamp':'ffd9a0',
                     'carpet':'5a1f1a','felt':'2e5e4e','accent':'b06b3a','ink':'2b1d14','paper':'f2e6cf'},
          'minimum':100},
    252: {'key':'arcology_junction','name':'Silver Junction','floor':'The Roundhouse','signature':'chuck_a_luck',
          'font':'biorhyme/BioRhyme-Medium.ttf','chandelier':'chandelier_lantern',
          'games':{'blackjack':'Dining Car Twenty-One','roulette':'Turntable Roulette','slots':'Timetable',
                   'money_wheel':'Roundhouse Wheel','video_poker':'Sleeper Car Draw','chuck_a_luck':'Birdcage'},
          'palette':{'stone':'dccdae','metal':'c49a50','wood':'5b3a21','glass':'4f8f6a','lamp':'ffe2b0',
                     'carpet':'1e4f4a','felt':'2b4a6f','accent':'4f8f6a','ink':'1f2a30','paper':'f4eedc'},
          'minimum':250},
    253: {'key':'arcology_boulder','name':'Boulder Crown','floor':'The Powerhouse','signature':'baccarat',
          'font':'biorhyme-expanded/BioRhymeExpanded-Regular.ttf','chandelier':'chandelier_turbine',
          'games':{'blackjack':'Intake Twenty-One','roulette':'Turbine Roulette','slots':'Powerhouse',
                   'money_wheel':'Penstock Wheel','video_poker':'High Scaler Draw','baccarat':'Spillway Baccarat'},
          'palette':{'stone':'b99b6b','metal':'b06b3a','wood':'1c1a17','glass':'2fa6a0','lamp':'f6f1e4',
                     'carpet':'1d5f63','felt':'1e8a86','accent':'2fa6a0','ink':'15201f','paper':'f2e8d5'},
          'minimum':500},
    254: {'key':'arcology_orbit','name':'Desert Orbit','floor':'Mission Control','signature':'trajectory',
          'font':'atomic-age/AtomicAge-Regular.ttf','chandelier':'chandelier_starburst',
          'games':{'blackjack':'Countdown Twenty-One','roulette':'Orbital Roulette','slots':'Launch Pad',
                   'money_wheel':'Gravity Wheel','video_poker':'Mission Draw','trajectory':'Static Fire'},
          'palette':{'stone':'f4ead6','metal':'c97a45','wood':'3b2a22','glass':'2e8c85','lamp':'fff1d0',
                     'carpet':'13203a','felt':'1f7f7a','accent':'c97a45','ink':'0f1a33','paper':'f7f0df'},
          'minimum':1000},
}
SIGNATURE_PROPS = {'faro':'faro_table','chuck_a_luck':'chuck_a_luck_cage','baccarat':'baccarat_table','trajectory':'trajectory_console'}
GAME_PROPS = {'blackjack':'blackjack_table','roulette':'roulette_table','slots':'slot_cabinet','money_wheel':'money_wheel','video_poker':'video_poker_terminal'}

# --------------------------------------------- hall program (same numbers as
# game/scripts/exploration/resorts/resort_interior_layouts.gd, hall metres)
HALF = 22.0; CEILING = 11.0; WALL = .6
VEST_HALF = 5.0; VEST_END = 30.0; VEST_CEILING = 4.5; OPENING = 3.6
PIT = (0.0,2.0)
ROWS = [(-19,-5),(-14,-5),(-19,6),(-14,6)]
def _tables():
    """Pit ring, video poker, double-sided slot rows and the signature dais."""
    t=[('blackjack',(-8,0,2),-math.pi/2,1.5,1,(1.3,.75)),('blackjack',(8,0,2),math.pi/2,1.5,1,(1.3,.75)),
       ('blackjack',(0,0,10),0.0,1.5,1,(1.3,.75)),('roulette',(0,.15,2),0.0,1.45,1,(1.6,.8)),
       ('money_wheel',(0,0,-6),math.pi,1.6,1,(1.5,.55)),
       ('video_poker',(12,0,-4),math.pi/2,1.05,4,(1.6,.35)),('video_poker',(12,0,4),math.pi/2,1.05,4,(1.6,.35))]
    for x,z in ROWS:
        t.append(('slots',(x-.35,0,z),-math.pi/2,1.05,6,(2.4,.35)))
        t.append(('slots',(x+.35,0,z),math.pi/2,1.05,6,(2.4,.35)))
    t.append(('signature',(0,.3,-11.5),0.0,1.75,1,(1.5,.8)))
    return t
TABLES = _tables()
COLUMNS = [(-11,-10),(11,-10),(-11,12),(11,12)]
CAGE = ((0,-20.25),(6,1.75),3.6)
BAR = ((17.6,-3),(.6,9),1.1)
BACK_BAR = ((21.6,-3),(.4,9),3.2)
DAIS = ((0,-11.5),(6,3.5),.3)
ROULETTE_DAIS = (3.2,.15)
LOUNGE = [('banquette',(16.0,0,21.45),math.pi),('banquette',(19.7,0,21.45),math.pi),
          ('banquette',(21.45,0,17.6),-math.pi/2),('banquette',(21.45,0,13.9),-math.pi/2)]
COCKTAILS = [(17.2,18.3),(18.6,15.0)]
PLANTERS = [(-7.5,20.3),(7.5,20.3),(-10,-20.3),(10,-20.3),(20.3,-16),(-20.3,-16)]
BANDSTAND = ((-18.5,18),(3,3),.5)
BAR_STOOLS = [-10,-8,-6,-4,-2,0,2,4]
LIGHTS = [((0,7.5,2),16,2.6),((0,6.5,-12),12,1.8),((17,4.5,-3),12,1.4),((-16.5,6.5,.5),15,1.8),((17.6,4.0,16.7),9,1.3),((0,4.2,17),11,1.3)]
CHANDELIER_SPOTS = [(0,2),(0,-11.5),(-16.5,.5),(17.6,16.7)]
SIGN_PLATES = {  # role: (centre, plate size, yaw) in hall metres; lettering is set in the game
    'floor':((0,4.05,22.61),(9.2,.82,.02),0.0),
    'resort':((0,6.2,21.985),(14.4,1.75,.03),math.pi),
    'cage':((0,4.3,-18.465),(6.2,1.0,.03),0.0),
    'bar':((21.195,3.75,-3),(8.2,.9,.03),-math.pi/2),
}
MAT_POSE = (0,0,26.5)

def floor_rects():
    """Footprints (x0,x1,z0,z1) that wall dressing must keep clear of."""
    rects=[]
    for game,(x,y,z),yaw,seat,count,(hx,hz) in TABLES:
        if abs(math.sin(yaw))>.5:hx,hz=hz,hx
        rects.append((x-hx,x+hx,z-hz,z+hz))
    for (cx,cz),(hx,hz),_ in (CAGE,BAR,BACK_BAR,BANDSTAND):rects.append((cx-hx,cx+hx,cz-hz,cz+hz))
    for name,(x,y,z),yaw in LOUNGE:
        hx,hz=(1.8,.55) if abs(math.sin(yaw))<.5 else (.55,1.8)
        rects.append((x-hx,x+hx,z-hz,z+hz))
    for x,z in PLANTERS:rects.append((x-.6,x+.6,z-.6,z+.6))
    return rects

def clear_of(x0,x1,z0,z1,extra=()):
    for r in list(floor_rects())+list(extra):
        if x0<r[1]+.1 and x1>r[0]-.1 and z0<r[3]+.1 and z1>r[2]-.1:return False
    return True

# ---------------------------------------------------------------- geometry
class Asset:
    """Per-finish polygon soup plus collision shells, in Godot axes."""
    def __init__(self,name):
        self.name=name;self.parts={};self.colliders=[]
    def add(self,finish,verts,faces,smooth=False):
        verts_acc,faces_acc,smooth_acc=self.parts.setdefault(finish,([],[],[]))
        offset=len(verts_acc);verts_acc.extend(Vector(v) for v in verts)
        faces_acc.extend(tuple(i+offset for i in f) for f in faces);smooth_acc.extend([smooth]*len(faces))
    def collider(self,name,center,size,yaw=0.0):
        v,f=box_geo(center,size,yaw);self.colliders.append((name,v,f))
    def collider_lathe(self,name,profile,center,seg=16):
        tmp=Asset('tmp');lathe(tmp,'stone',profile,center,seg,smooth=False)
        v,f,_=tmp.parts['stone'];self.colliders.append((name,v,f))
    def triangles(self):
        return sum(len(f)-2 for _,faces,_ in self.parts.values() for f in faces)

def xform(points,center=(0,0,0),yaw=0.0,pitch=0.0,roll=0.0):
    m=Matrix.Translation(Vector(center))@Matrix.Rotation(yaw,4,'Y')@Matrix.Rotation(pitch,4,'X')@Matrix.Rotation(roll,4,'Z')
    return [m@Vector(p) for p in points]

def box_geo(center,size,yaw=0.0,pitch=0.0,roll=0.0):
    hx,hy,hz=size[0]/2,size[1]/2,size[2]/2
    v=[(-hx,-hy,-hz),(hx,-hy,-hz),(hx,hy,-hz),(-hx,hy,-hz),(-hx,-hy,hz),(hx,-hy,hz),(hx,hy,hz),(-hx,hy,hz)]
    f=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(2,3,7,6),(1,2,6,5),(0,4,7,3)]
    return xform(v,center,yaw,pitch,roll),f

def box(a,finish,center,size,yaw=0.0,pitch=0.0,roll=0.0):
    v,f=box_geo(center,size,yaw,pitch,roll);a.add(finish,v,f)

def lathe(a,finish,profile,center=(0,0,0),seg=16,axis='y',yaw=0.0,smooth=True,phase=0.0,closed=False):
    """Revolve [(radius,height)] about the local Y axis (or X/Z). A closed
    profile joins its last ring back to its first instead of capping."""
    verts=[];rings=[]
    for r,h in profile:
        if r<=1e-6:
            rings.append([len(verts)]);verts.append((0,h,0))
        else:
            ring=[]
            for i in range(seg):
                t=2*math.pi*i/seg+phase;ring.append(len(verts));verts.append((r*math.cos(t),h,r*math.sin(t)))
            rings.append(ring)
    faces=[]
    for a_ring,b_ring in zip(rings,rings[1:]):
        if len(a_ring)==1 and len(b_ring)==1:continue
        if len(a_ring)==1:
            for i in range(seg):faces.append((a_ring[0],b_ring[(i+1)%seg],b_ring[i]))
        elif len(b_ring)==1:
            for i in range(seg):faces.append((a_ring[i],a_ring[(i+1)%seg],b_ring[0]))
        else:
            for i in range(seg):faces.append((a_ring[i],a_ring[(i+1)%seg],b_ring[(i+1)%seg],b_ring[i]))
    if closed:
        for i in range(seg):faces.append((rings[-1][i],rings[-1][(i+1)%seg],rings[0][(i+1)%seg],rings[0][i]))
    else:
        if len(rings[0])>1:faces.append(tuple(reversed(rings[0])))
        if len(rings[-1])>1:faces.append(tuple(rings[-1]))
    pre={'y':Matrix.Identity(4),'x':Matrix.Rotation(-math.pi/2,4,'Z'),'z':Matrix.Rotation(math.pi/2,4,'X')}[axis]
    pts=[pre@Vector(p) for p in verts]
    a.add(finish,xform(pts,center,yaw),faces,smooth)

def cylinder(a,finish,center,radius,height,seg=12,axis='y',yaw=0.0,top=None,smooth=True):
    r2=radius if top is None else top
    lathe(a,finish,[(radius,-height/2),(r2,height/2)],center,seg,axis,yaw,smooth)

def rod(a,finish,p,q,radius,seg=6):
    p,q=Vector(p),Vector(q);d=q-p;length=d.length
    if length<1e-6:return
    verts=[];faces=[]
    for h in (-length/2,length/2):
        for i in range(seg):
            t=2*math.pi*i/seg;verts.append(Vector((radius*math.cos(t),h,radius*math.sin(t))))
    for i in range(seg):faces.append((i,(i+1)%seg,seg+(i+1)%seg,seg+i))
    faces.append(tuple(reversed(range(seg))));faces.append(tuple(range(seg,2*seg)))
    rot=Vector((0,1,0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    m=Matrix.Translation((p+q)/2)@rot
    a.add(finish,[m@v for v in verts],faces,True)

def torus(a,finish,center,major,minor,seg=32,ring=8,axis='y',yaw=0.0,arc=2*math.pi,start=0.0):
    verts=[];faces=[];closed=abs(arc-2*math.pi)<1e-6
    count=seg if closed else seg+1
    for i in range(count):
        t=start+arc*i/seg
        for j in range(ring):
            u=2*math.pi*j/ring;r=major+minor*math.cos(u)
            verts.append((r*math.cos(t),minor*math.sin(u),r*math.sin(t)))
    for i in range(seg):
        n=(i+1)%count
        for j in range(ring):faces.append((i*ring+j,n*ring+j,n*ring+(j+1)%ring,i*ring+(j+1)%ring))
    if not closed:
        faces.append(tuple(range(ring)));faces.append(tuple(reversed(range(seg*ring,seg*ring+ring))))
    pre={'y':Matrix.Identity(4),'x':Matrix.Rotation(-math.pi/2,4,'Z'),'z':Matrix.Rotation(math.pi/2,4,'X')}[axis]
    a.add(finish,xform([pre@Vector(p) for p in verts],center,yaw),faces,True)

def sphere(a,finish,center,radius,seg=8,rings=5):
    profile=[(radius*math.sin(math.pi*i/rings),-radius*math.cos(math.pi*i/rings)) for i in range(rings+1)]
    profile[0]=(0,-radius);profile[-1]=(0,radius)
    lathe(a,finish,profile,center,seg)

def prism(a,finish,polygon,y0,y1,center=(0,0,0),yaw=0.0):
    """Extrude a counter-clockwise (seen from above) [(x,z)] polygon."""
    n=len(polygon);verts=[(x,y0,z) for x,z in polygon]+[(x,y1,z) for x,z in polygon]
    faces=[tuple(range(n)),tuple(reversed(range(n,2*n)))]
    for i in range(n):faces.append((i,n+i,n+(i+1)%n,(i+1)%n))
    a.add(finish,xform(verts,center,yaw),faces)

def arc_points(cx,cz,rx,rz,a0,a1,seg):
    return [(cx+rx*math.cos(a0+(a1-a0)*i/seg),cz+rz*math.sin(a0+(a1-a0)*i/seg)) for i in range(seg+1)]

def recalc(mesh):
    import bmesh
    bm=bmesh.new();bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    bm.to_mesh(mesh);bm.free()

# ---------------------------------------------------------------- props
def stool(a,center,height=.72,seg=12,yaw=0.0):
    lathe(a,'metal',[(0,0),(.22,0),(.22,.03),(.05,.07),(.035,.09),(.035,height-.08),(0,height-.07)],center,seg)
    lathe(a,'felt',[(0,height-.09),(.17,height-.09),(.2,height-.04),(.18,height+.02),(0,height+.03)],center,seg)

def prop_slot_cabinet(a):
    box(a,'rubber',(0,.06,0),(.78,.12,.7))
    box(a,'wood',(0,.5,-.02),(.76,.76,.62))
    box(a,'lamp',(0,.55,.295),(.6,.4,.02))
    for y in (.33,.77):box(a,'metal',(0,y,.3),(.64,.03,.03))
    # Button deck, coin tray with a lip, and the pull handle.
    box(a,'metal',(0,.93,.17),(.76,.06,.38))
    for i,x in enumerate((-.24,-.12,0,.12,.24)):box(a,'lamp' if i!=4 else 'felt',(x,.975,.25),(.08,.03,.06))
    box(a,'metal',(0,.76,.31),(.48,.05,.12))
    box(a,'metal',(0,.80,.365),(.48,.07,.02))
    box(a,'rubber',(0,.79,.31),(.42,.02,.08))
    box(a,'wood',(0,1.32,-.08),(.76,.72,.5))
    # Reel window: three lit symbol tiles behind a chrome and brass frame.
    box(a,'screen',(0,1.29,.172),(.58,.36,.02))
    for i,x in enumerate((-.18,0,.18)):
        box(a,'stone',(x,1.29,.184),(.15,.28,.006))
        if i==0:cylinder(a,'carpet',(x,1.29,.19),.045,.008,12,'z')
        elif i==1:
            for y in (1.25,1.33):box(a,'sign',(x,y,.19),(.11,.035,.008))
        else:box(a,'felt',(x,1.29,.19),(.075,.075,.008),0,0,math.pi/4)
    box(a,'metal',(0,1.29,.181),(.012,.33,.01))
    for y in (1.09,1.49):box(a,'metal',(0,y,.18),(.64,.04,.04))
    for x in (-.31,.31):box(a,'metal',(x,1.29,.18),(.04,.44,.04))
    # Lit header plate with the resort emblem.
    box(a,'metal',(0,1.68,.06),(.76,.26,.12))
    box(a,'lamp',(0,1.68,.125),(.68,.2,.012))
    box(a,'sign',(0,1.68,.135),(.12,.12,.01),0,0,math.pi/4)
    for x in (-.18,.18):box(a,'sign',(x,1.68,.135),(.12,.025,.01))
    box(a,'lamp',(0,1.86,-.05),(.66,.12,.38))
    box(a,'metal',(0,1.805,-.05),(.72,.02,.42))
    for x in (-.389,.389):box(a,'metal',(x,.95,0),(.02,1.7,.66))
    cylinder(a,'metal',(.43,1.22,.05),.045,.08,8,'x')
    rod(a,'metal',(.47,1.22,.05),(.47,1.56,.12),.016)
    sphere(a,'rubber',(.47,1.6,.13),.045,8,4)
    a.collider('Slot cabinet shell',(0,.95,0),(.78,1.9,.7))

def prop_slot_stool(a):
    stool(a,(0,0,0),.7,14)

def prop_bar_stool(a):
    stool(a,(0,0,0),.78,14)
    torus(a,'metal',(0,.3,0),.17,.012,14,4)

def kidney(a,radius,cz,seg=24,height=.9,rail='rubber',rx=None):
    rx=radius if rx is None else rx
    outer=arc_points(0,cz,rx,radius,0,math.pi,seg)
    felt=arc_points(0,cz,rx-.12,radius-.12,0,math.pi,seg)
    # Godot +Z is toward the player: arc runs from +X through +Z to -X.
    prism(a,'felt',[(x,z) for x,z in reversed(felt)],height-.05,height-.02)
    ring=[(x,z) for x,z in outer]+[(x,z) for x,z in reversed(felt)]
    prism(a,'wood',list(reversed(ring)),height-.2,height-.04)
    torus(a,rail,(0,height-.02,cz),(rx+radius)/2-.03,.06,seg,6,'y',0.0,math.pi,0.0) if abs(rx-radius)<1e-6 else None
    if abs(rx-radius)>1e-6:
        pts=arc_points(0,cz,rx-.03,radius-.03,0,math.pi,seg)
        for p,q in zip(pts,pts[1:]):rod(a,rail,(p[0],height-.02,p[1]),(q[0],height-.02,q[1]),.06,6)
    box(a,'wood',(0,height-.11,cz-.04),(2*rx,.2,.1))
    for x in (-.6*rx/1.3,.6*rx/1.3):
        cylinder(a,'metal',(x,(height-.2)/2,cz+.25),.07,height-.2,10)
        cylinder(a,'metal',(x,.02,cz+.25),.3,.04,14)

def chip_rack(a,center,width=.7):
    box(a,'metal',center,(width,.05,.18))
    x0=center[0]-width/2+.06
    finishes=('lamp','felt','sign','stone','carpet','lamp','felt','sign')
    count=int((width-.08)/.08)
    for i in range(count):
        cylinder(a,finishes[i%len(finishes)],(x0+i*.08,center[1]+.045,center[2]),.034,.05,10)

def card_shoe(a,center):
    box(a,'sign',center,(.2,.12,.32))
    box(a,'metal',(center[0],center[1]+.02,center[2]+.17),(.2,.08,.02),0,math.radians(-30))
    box(a,'stone',(center[0],center[1]+.07,center[2]+.05),(.15,.01,.1))

def prop_blackjack_table(a):
    kidney(a,1.3,-.55)
    chip_rack(a,(0,.915,-.47),.72)
    card_shoe(a,(.66,.96,-.42))
    box(a,'stone',(-.66,.905,-.42),(.16,.01,.22))
    for i in range(5):
        t=math.pi*(i+.5)/5;cylinder(a,'stone',(math.cos(t)*.9,.885,-.55+math.sin(t)*.9),.11,.012,14)
    for t in (math.radians(28),math.radians(58),math.radians(122),math.radians(152)):
        stool(a,(math.cos(t)*1.65,0,-.55+math.sin(t)*1.65),.72,10)
    a.collider('Blackjack table shell',(0,.46,0),(2.6,.92,1.5))

def prop_baccarat_table(a):
    kidney(a,1.3,-.5,28,.9,'rubber',1.5)
    for x in (-.5,.5):box(a,'metal',(x,.915,-.45),(.6,.05,.14))
    box(a,'wood',(0,.96,-.38),(.24,.12,.34))
    for i in range(3):cylinder(a,'stone',(-.6+i*.6,.885,.2),.16,.012,16)
    for i in range(6):
        t=math.pi*(i+.5)/6;cylinder(a,'stone',(math.cos(t)*1.15,.885,-.5+math.sin(t)*.95),.08,.012,12)
    for t in (math.radians(25),math.radians(55),math.radians(125),math.radians(155)):
        stool(a,(math.cos(t)*1.85,0,-.5+math.sin(t)*1.55),.72,10)
    a.collider('Baccarat table shell',(0,.46,0),(3.0,.92,1.6))

def prop_roulette_table(a):
    for x in (-1.4,1.4):
        for z in (-.6,.6):cylinder(a,'wood',(x,.4,z),.06,.8,8)
    box(a,'wood',(0,.82,0),(3.2,.14,1.5))
    box(a,'felt',(-.38,.9,0),(2.3,.03,1.3))
    for z in (-.7,.7):box(a,'rubber',(-.38,.91,z),(2.42,.06,.1))
    box(a,'rubber',(-1.55,.91,0),(.1,.06,1.5))
    # Layout: zero, then twelve columns of three numbers in alternating
    # colours, with dozens and even-money boxes along the front.
    box(a,'felt',(-1.36,.918,-.06),(.14,.004,.66))
    box(a,'stone',(-1.36,.917,-.06),(.16,.002,.68))
    for col in range(12):
        for row in range(3):
            n=col*3+row
            f='carpet' if (n+col)%2==0 else 'sign'
            box(a,f,(-1.2+col*.13,.918,-.3+row*.22),(.115,.004,.2))
    box(a,'stone',(-.485,.917,-.06),(1.6,.002,.7))
    for i in range(3):box(a,'stone',(-1.0+i*.52,.918,.38),(.48,.004,.12))
    for i in range(6):box(a,'stone' if i%2 else 'felt',(-1.07+i*.26,.918,.54),(.23,.004,.12))
    # Numbered wheel bowl: wooden rim, 37 pockets, number plates, turret.
    c=1.08
    lathe(a,'wood',[(0,.88),(.66,.88),(.7,1.0),(.66,1.06),(.58,1.03),(0,1.03)],(c,0,0),36)
    lathe(a,'metal',[(0,1.02),(.54,1.02),(.5,1.04),(.16,1.1),(.05,1.13),(.05,1.2),(0,1.21)],(c,0,0),36)
    for i in range(37):
        t=2*math.pi*i/37;f='sign' if i%2 else 'carpet'
        if i==0:f='felt'
        box(a,f,(c+math.cos(t)*.44,1.045,math.sin(t)*.44),(.06,.012,.07),-t)
        box(a,'stone',(c+math.cos(t)*.53,1.04,math.sin(t)*.53),(.035,.008,.05),-t)
    for i in range(4):box(a,'metal',(c,1.15,0),(.34,.015,.02),i*math.pi/4)
    sphere(a,'stone',(c+.3,1.05,.12),.018,6,3)
    a.collider('Roulette table shell',(0,.5,0),(3.2,1.0,1.6))

def prop_money_wheel(a):
    box(a,'wood',(0,.55,0),(3.0,1.1,1.0))
    box(a,'stone',(0,1.13,0),(3.06,.06,1.06))
    box(a,'metal',(0,.08,0),(3.04,.16,1.04))
    for x in (-.22,.22):box(a,'metal',(x,1.75,-.25),(.12,1.2,.14))
    c=Vector((0,2.38,.08));segs=54
    colors=['stone','felt','stone','carpet','stone','felt','stone','sign','stone','carpet']
    for i in range(segs):
        t0=2*math.pi*i/segs;t1=2*math.pi*(i+1)/segs;f=colors[i%len(colors)]
        if i in (0,27):f='lamp'
        pts=[(0,0),(1.22*math.cos(t0),1.22*math.sin(t0)),(1.22*math.cos(t1),1.22*math.sin(t1))]
        v=[(c.x+x,c.y+y,c.z-.03) for x,y in pts]+[(c.x+x,c.y+y,c.z+.03) for x,y in pts]
        a.add(f,v,[(0,2,1),(3,4,5),(1,2,5,4),(0,1,4,3),(0,3,5,2)])
    for i in range(segs):
        t=2*math.pi*i/segs;box(a,'metal',(c.x+1.1*math.cos(t),c.y+1.1*math.sin(t),c.z+.045),(.012,.2,.012),0,0,t-math.pi/2)
    torus(a,'metal',tuple(c),1.27,.06,36,5,'z')
    for i in range(24):
        t=2*math.pi*(i+.5)/24;sphere(a,'lamp',(c.x+1.38*math.cos(t),c.y+1.38*math.sin(t),c.z),.045,6,3)
    torus(a,'wood',tuple(c),1.42,.05,48,5,'z')
    lathe(a,'metal',[(0,-.09),(.2,-.09),(.22,.05),(.12,.1),(0,.11)],tuple(c),16,'z')
    box(a,'metal',(c.x,c.y+1.38,c.z+.1),(.1,.3,.04))
    v=[(c.x-.08,c.y+1.55,c.z+.12),(c.x+.08,c.y+1.55,c.z+.12),(c.x,c.y+1.3,c.z+.12)]
    a.add('lamp',v+[(x,y,z+.04) for x,y,z in v],[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)])
    for i in range(7):box(a,'sign',(-1.2+i*.4,1.17,.25),(.32,.012,.36))
    a.collider('Money wheel shell',(0,1.8,0),(3.0,3.6,1.1))

def prop_video_poker_terminal(a):
    box(a,'wood',(0,.45,-.02),(.78,.9,.62))
    box(a,'rubber',(0,.04,0),(.8,.08,.7))
    box(a,'metal',(0,.96,.13),(.76,.06,.34),0,math.radians(-14))
    for i in range(5):box(a,'lamp',(-.24+i*.12,.995,.18),(.08,.025,.05),0,math.radians(-14))
    box(a,'felt',(.3,.995,.06),(.1,.025,.05),0,math.radians(-14))
    # Slanted screen in a lit bezel.
    box(a,'metal',(0,1.25,-.06),(.74,.56,.18),0,math.radians(-24))
    box(a,'lamp',(0,1.25,.035),(.68,.5,.012),0,math.radians(-24))
    box(a,'screen',(0,1.25,.045),(.6,.42,.012),0,math.radians(-24))
    for i in range(5):box(a,'stone',(-.22+i*.11,1.2,.062),(.085,.13,.004),0,math.radians(-24))
    box(a,'metal',(0,.98,-.2),(.74,.1,.36))
    box(a,'lamp',(0,1.56,-.16),(.66,.08,.22))
    box(a,'sign',(0,1.62,-.16),(.6,.06,.2))
    a.collider('Video poker shell',(0,.75,-.02),(.8,1.5,.7))

def prop_faro_table(a):
    for x in (-1.0,1.0):
        for z in (-.55,.55):lathe(a,'wood',[(0,0),(.08,0),(.08,.05),(.04,.12),(.06,.35),(.035,.6),(.06,.8),(0,.8)],(x,0,z),8)
    box(a,'wood',(0,.84,0),(2.4,.08,1.4))
    box(a,'felt',(0,.89,0),(2.24,.02,1.24))
    for row,z in ((0,-.18),(1,.22)):
        for i in range(6):box(a,'stone',(-.72+i*.29+(.0 if row==0 else .0),.903,z),(.18,.006,.26))
    box(a,'stone',(1.0,.903,.02),(.18,.006,.26))
    box(a,'metal',(0,.94,-.45),(.18,.08,.26))
    box(a,'wood',(-.85,.93,-.45),(.6,.05,.28))
    for i in range(4):
        rod(a,'metal',(-1.13,.98,-.55+i*.07),(-.57,.98,-.55+i*.07),.006,4)
        for j in range(3):box(a,'lamp' if j%2 else 'sign',(-1.0+j*.12+i*.03,.98,-.55+i*.07),(.03,.03,.03))
    a.collider('Faro table shell',(0,.46,0),(2.4,.92,1.4))

def prop_chuck_a_luck_cage(a):
    for x in (-.8,.8):
        for z in (-.5,.5):cylinder(a,'wood',(x,.42,z),.05,.84,8)
    box(a,'wood',(0,.86,0),(1.8,.08,1.2))
    box(a,'felt',(0,.905,.12),(1.64,.02,.84))
    for i in range(6):box(a,'stone',(-.62+i*.248,.918,.3),(.2,.006,.28))
    for x in (-.55,.55):
        box(a,'metal',(x,1.6,-.35),(.06,1.4,.06))
        box(a,'metal',(x,.95,-.35),(.18,.06,.18))
    rod(a,'metal',(-.6,1.9,-.35),(.6,1.9,-.35),.025)
    c=Vector((0,1.9,-.35))
    for i in range(10):
        t=2*math.pi*i/10
        for s in (-1,1):
            rod(a,'metal',(c.x+.42*s,c.y+.4*math.cos(t),c.z+.4*math.sin(t)),(c.x,c.y+.07*math.cos(t),c.z+.07*math.sin(t)),.01,4)
    for s in (-1,1):torus(a,'metal',(c.x+.42*s,c.y,c.z),.4,.02,20,4,'x')
    for i,(dx,dy) in enumerate(((-.3,-.22),(-.36,.05),(-.26,.18))):box(a,'stone',(c.x+dx,c.y+dy,c.z),(.11,.11,.11),i*.4,i*.3)
    a.collider('Birdcage table shell',(0,.46,0),(1.8,.92,1.2))
    a.collider('Birdcage shell',(0,1.6,-.35),(1.3,1.0,.9))

def prop_trajectory_console(a):
    pts=arc_points(0,1.6,2.0,2.0,math.radians(-122),math.radians(-58),6)
    for p,q in zip(pts,pts[1:]):
        mid=((p[0]+q[0])/2,(p[1]+q[1])/2);yaw=-math.atan2(q[1]-p[1],q[0]-p[0])
        length=math.hypot(q[0]-p[0],q[1]-p[1])+.02
        box(a,'metal',(mid[0],.42,mid[1]),(length,.84,.6),yaw)
        box(a,'stone',(mid[0],.88,mid[1]+.02),(length,.06,.66),yaw,math.radians(-8))
        box(a,'lamp',(mid[0]+.02,.92,mid[1]+.12),(length*.5,.02,.08),yaw,math.radians(-8))
    box(a,'metal',(0,1.95,-.47),(2.5,1.5,.12))
    box(a,'screen',(0,1.98,-.405),(2.3,1.26,.02))
    for x in (-1.0,1.0):box(a,'metal',(x,.95,-.47),(.12,.9,.12))
    lathe(a,'metal',[(0,2.75),(.06,2.75),(.07,2.95),(.05,3.1),(0,3.22)],(0,0,-.47),10)
    for i in range(3):box(a,'lamp',(.08*math.cos(i*2.1),2.8,-.47+.08*math.sin(i*2.1)),(.02,.12,.06),-i*2.1)
    a.collider('Static fire console shell',(0,.45,-.05),(2.8,.9,1.1))
    a.collider('Static fire screen shell',(0,1.95,-.47),(2.5,1.5,.14))

def chandelier_stem(a,drop):
    rod(a,'metal',(0,4.0,0),(0,-drop,0),.05,8)
    lathe(a,'metal',[(0,-.02),(.3,-.02),(.32,.04),(0,.06)],(0,0,0),12)

def prop_chandelier_gaslamp(a):
    chandelier_stem(a,2.6)
    lathe(a,'metal',[(0,-3.3),(.08,-3.25),(.32,-2.9),(.36,-2.7),(.2,-2.55),(0,-2.5)],(0,0,0),14)
    sphere(a,'lamp',(0,-3.4,0),.12,8,4)
    for tier,(count,radius,y) in enumerate(((8,1.35,-2.75),(6,.8,-2.2))):
        torus(a,'metal',(0,y,0),radius*.62,.025,24,4)
        for i in range(count):
            t=2*math.pi*(i+.5*tier)/count;tip=(radius*math.cos(t),y+.18,radius*math.sin(t))
            rod(a,'metal',(0,y-.1,0),(tip[0]*.85,y-.12,tip[2]*.85),.022,5)
            rod(a,'metal',(tip[0]*.85,y-.12,tip[2]*.85),tip,.022,5)
            lathe(a,'metal',[(0,0),(.07,0),(.09,.06),(0,.06)],tip,8)
            sphere(a,'lamp',(tip[0],tip[1]+.18,tip[2]),.13,8,5)

def prop_chandelier_lantern(a):
    chandelier_stem(a,1.6)
    torus(a,'metal',(0,-1.6,0),1.5,.05,32,6)
    for i in range(4):box(a,'metal',(0,-1.6,0),(3.0,.05,.05),i*math.pi/4)
    lathe(a,'metal',[(0,-1.75),(.25,-1.7),(.25,-1.5),(0,-1.45)],(0,0,0),12)
    for i in range(6):
        t=2*math.pi*i/6;p=(1.5*math.cos(t),-1.6,1.5*math.sin(t));low=(p[0],-2.5,p[2])
        rod(a,'metal',p,(p[0],-2.15,p[2]),.015,4)
        lathe(a,'metal',[(0,0),(.22,0),(.22,.04),(0,.16)],(low[0],low[1]+.35,low[2]),6)
        lathe(a,'lamp',[(0,-.26),(.16,-.24),(.19,.0),(.16,.3),(0,.32)],(low[0],low[1],low[2]),6,'y',0,False)
        for j in range(6):
            u=2*math.pi*j/6;rod(a,'metal',(low[0]+.2*math.cos(u),low[1]-.24,low[2]+.2*math.sin(u)),(low[0]+.2*math.cos(u),low[1]+.33,low[2]+.2*math.sin(u)),.012,4)
        lathe(a,'metal',[(0,-.4),(.12,-.3),(.18,-.26),(0,-.25)],(low[0],low[1],low[2]),6)

def prop_chandelier_turbine(a):
    chandelier_stem(a,2.0)
    torus(a,'metal',(0,-2.8,0),2.6,.16,48,8)
    torus(a,'lamp',(0,-2.8,0),1.75,.08,40,6)
    torus(a,'metal',(0,-2.8,0),.9,.07,24,6)
    for i in range(16):
        t=2*math.pi*i/16;r=(2.45+1.0)/2
        box(a,'metal',(r*math.cos(t),-2.8,r*math.sin(t)),(1.45,.04,.42),-t,0,math.radians(32))
    for i in range(4):
        t=2*math.pi*i/4+math.pi/4;rod(a,'metal',(0,-2.0,0),(2.6*math.cos(t),-2.75,2.6*math.sin(t)),.03,5)
    lathe(a,'metal',[(0,-3.15),(.3,-3.0),(.36,-2.8),(.3,-2.6),(0,-2.5)],(0,0,0),16)
    sphere(a,'lamp',(0,-3.25,0),.16,10,5)

def prop_chandelier_starburst(a):
    chandelier_stem(a,2.2)
    sphere(a,'metal',(0,-2.6,0),.36,14,8)
    golden=math.pi*(3-math.sqrt(5));c=Vector((0,-2.6,0))
    for i in range(30):
        y=1-2*(i+.5)/30;r=math.sqrt(1-y*y);t=golden*i
        d=Vector((r*math.cos(t),y,r*math.sin(t)));length=1.1+.5*((i*7)%3)/2
        if d.y>.75:continue
        rod(a,'metal',c+d*.3,c+d*length,.018,4)
        sphere(a,'lamp',tuple(c+d*(length+.06)),.07,6,3)
    torus(a,'lamp',(0,-2.6,0),.5,.03,24,4)

def prop_banquette(a):
    box(a,'wood',(0,.13,0),(3.6,.26,1.08))
    box(a,'felt',(0,.36,.08),(3.5,.2,.86))
    for i in range(5):box(a,'felt',(-1.4+i*.7,.82,-.39),(.67,.72,.24))
    for i in range(5):sphere(a,'metal',(-1.4+i*.7,.86,-.26),.025,6,3)
    box(a,'wood',(0,1.22,-.42),(3.6,.08,.28))
    box(a,'wood',(0,.7,-.5),(3.6,1.06,.08))
    for x in (-1.77,1.77):box(a,'wood',(x,.6,0),(.06,.9,1.08))
    box(a,'metal',(0,.27,.54),(3.6,.04,.02))
    a.collider('Banquette shell',(0,.62,0),(3.6,1.24,1.1))

def prop_standard_sign(a):
    lathe(a,'metal',[(0,0),(.22,0),(.22,.03),(.05,.06),(0,.07)],(0,0,0),14)
    cylinder(a,'metal',(0,.6,0),.03,1.1,10)
    box(a,'metal',(0,1.42,-.005),(.92,.52,.04))
    box(a,'sign',(0,1.42,.025),(.86,.46,.02))

PROPS = {name[5:]:fn for name,fn in globals().items() if name.startswith('prop_')}

# ---------------------------------------------------------------- halls
def hall_shell(a,code):
    main='carpet' if code in (251,254) else 'floor'
    box(a,main,(0,-.3,0),(2*HALF+2*WALL,.6,2*HALF+2*WALL))
    box(a,'floor',(0,-.3,(HALF+WALL+VEST_END+WALL)/2),(2*VEST_HALF+2*WALL,.6,VEST_END+WALL-HALF-WALL))
    a.collider('Hall floor',(0,-.3,(VEST_END+WALL-HALF-WALL)/2),(2*HALF+2*WALL,.6,VEST_END+HALF+2*WALL))
    for s in (-1,1):
        box(a,'wall',(s*(HALF+WALL/2),CEILING/2,0),(WALL,CEILING,2*HALF+2*WALL))
        a.collider('Side wall',(s*(HALF+WALL/2),CEILING/2,0),(WALL,CEILING,2*HALF+2*WALL))
        width=HALF+WALL-VEST_HALF
        box(a,'wall',(s*(VEST_HALF+width/2),CEILING/2,HALF+WALL/2),(width,CEILING,WALL))
        a.collider('Front wall',(s*(VEST_HALF+width/2),CEILING/2,HALF+WALL/2),(width,CEILING,WALL))
        depth=VEST_END-HALF-WALL
        box(a,'wall',(s*(VEST_HALF+WALL/2),VEST_CEILING/2,HALF+WALL+depth/2),(WALL,VEST_CEILING,depth))
        a.collider('Vestibule wall',(s*(VEST_HALF+WALL/2),VEST_CEILING/2,HALF+WALL+depth/2),(WALL,VEST_CEILING,depth))
    box(a,'wall',(0,CEILING/2,-HALF-WALL/2),(2*HALF+2*WALL,CEILING,WALL))
    a.collider('Back wall',(0,CEILING/2,-HALF-WALL/2),(2*HALF+2*WALL,CEILING,WALL))
    box(a,'wall',(0,(OPENING+CEILING)/2,HALF+WALL/2),(2*VEST_HALF,CEILING-OPENING,WALL))
    a.collider('Lintel',(0,(OPENING+CEILING)/2,HALF+WALL/2),(2*VEST_HALF,CEILING-OPENING,WALL))
    depth=VEST_END-HALF-WALL
    box(a,'ceiling',(0,VEST_CEILING+.3,HALF+WALL+depth/2),(2*VEST_HALF,.6,depth))
    a.collider('Vestibule ceiling',(0,VEST_CEILING+.3,HALF+WALL+depth/2),(2*VEST_HALF,.6,depth))
    box(a,'wood',(0,VEST_CEILING/2,VEST_END+WALL/2),(2*VEST_HALF+2*WALL,VEST_CEILING,WALL))
    a.collider('Street doors',(0,VEST_CEILING/2,VEST_END+WALL/2),(2*VEST_HALF+2*WALL,VEST_CEILING,WALL))
    a.collider('Hall ceiling',(0,CEILING+.3,0),(2*HALF+2*WALL,.6,2*HALF+2*WALL))
    # Vestibule: street doors, transom, sconces, door mat and a lamp.
    for s in (-1,1):
        box(a,'wood',(s*.95,1.3,VEST_END-.05),(1.8,2.6,.1))
        box(a,'glass',(s*.95,1.6,VEST_END-.105),(1.3,1.5,.02))
        box(a,'metal',(s*.25,1.15,VEST_END-.13),(.06,.9,.06))
        box(a,'metal',(s*1.9,2.0,VEST_END-.13),(.16,1.0,.06))
        box(a,'lamp',(s*1.9,2.0,VEST_END-.17),(.1,.8,.03))
        box(a,'wood',(s*(VEST_HALF-.03),.6,26.3),(.06,1.2,7.2))
        box(a,'metal',(s*(VEST_HALF-.065),1.22,26.3),(.02,.04,7.2))
    box(a,'glass',(0,3.3,VEST_END-.06),(3.8,.7,.06))
    box(a,'metal',(0,2.66,VEST_END-.08),(3.9,.12,.1))
    box(a,'carpet',(0,.006,MAT_POSE[2]),(3.2,.012,2.0))
    box(a,'metal',(0,.008,MAT_POSE[2]),(3.3,.008,2.1))
    lathe(a,'lamp',[(0,-.35),(.45,-.3),(.55,-.12),(.5,0),(0,0)],(0,VEST_CEILING,26.3),16)
    # Signage plates (lettering is set at runtime in the resort font).
    for centre,size,yaw in SIGN_PLATES.values():
        box(a,'sign',centre,size,yaw)
        bx,by,bz=size;box(a,'metal',(centre[0]+(math.sin(yaw)*-.012),centre[1],centre[2]+(math.cos(yaw)*-.012)),(bx+.12,by+.12,.02),yaw)
    # Cage: counter, grille, fascia; Bar: counter, foot rail, back bar; dais.
    (cx,cz),(hx,hz),ch=CAGE
    front=cz+hz
    box(a,'wood',(cx,.55,front-.3),(2*hx,1.1,.6))
    box(a,'stone',(cx,1.13,front-.28),(2*hx+.1,.06,.68))
    box(a,'wood',(cx,ch/2,cz-.5),(2*hx,ch,2*hz-1.0))
    for i in range(25):rod(a,'metal',(cx-hx+.24+i*.48,1.16,front-.12),(cx-hx+.24+i*.48,3.0,front-.12),.018,5)
    for x in (-4,0,4):box(a,'stone',(x,2.05,front-.1),(.9,.02,.02))
    box(a,'metal',(cx,3.05,front-.12),(2*hx,.1,.1))
    box(a,'wood',(cx,4.3,front-.1),(2*hx,1.4,.2))
    box(a,'stone',(cx,3.15,cz),(2*hx,.1,2*hz))
    a.collider('Cage',(cx,ch/2,cz),(2*hx,ch,2*hz))
    (bx,bz),(bhx,bhz),bh=BAR
    box(a,'wood',(bx,bh/2-.03,bz),(2*bhx,bh-.06,2*bhz))
    box(a,'stone',(bx-.05,bh-.03,bz),(2*bhx+.25,.06,2*bhz+.1))
    for i in range(9):box(a,'metal',(bx-bhx-.005,.55,bz-bhz+1+i*2),(.02,.7,.05))
    rod(a,'metal',(bx-bhx-.3,.22,bz-bhz),(bx-bhx-.3,.22,bz+bhz),.03,8)
    for z in (bz-bhz+.5,bz,bz+bhz-.5):rod(a,'metal',(bx-bhx-.3,.22,z),(bx-bhx,.22,z),.02,5)
    a.collider('Bar counter',(bx,bh/2,bz),(2*bhx,bh,2*bhz))
    (kx,kz),(khx,khz),kh=BACK_BAR
    box(a,'wood',(kx,.5,kz),(2*khx,1.0,2*khz))
    box(a,'stone',(kx-.02,1.02,kz),(2*khx+.06,.04,2*khz))
    box(a,'glass',(kx+.3,2.05,kz),(.04,1.9,2*khz-.4))
    for y in (1.5,2.2):box(a,'wood',(kx-.1,y,kz),(.6,.04,2*khz-.2))
    for i in range(18):
        for y in (1.52,2.22):
            f='glass' if i%3 else 'lamp'
            cylinder(a,f,(kx-.12,y+.17,kz-khz+.6+i*.94),.05,.3,6)
    box(a,'wood',(kx,3.75,kz),(2*khx,1.1,2*khz))
    box(a,'lamp',(kx-.42,3.12,kz),(.04,.05,2*khz-.2))
    for z in (kz-khz+.1,kz+khz-.1):box(a,'wood',(kx,1.6,z),(2*khx,3.2,.2))
    a.collider('Back bar',(kx,kh/2,kz),(2*khx,kh,2*khz))
    (dx,dz),(dhx,dhz),dh=DAIS
    box(a,'stone',(dx,dh/2,dz),(2*dhx,dh,2*dhz))
    for s in (-1,1):box(a,'metal',(dx,dh-.01,dz+s*(dhz-.02)),(2*dhx,.03,.05))
    for s in (-1,1):box(a,'metal',(dx+s*(dhx-.02),dh-.01,dz),(.05,.03,2*dhz))
    a.collider('Dais',(dx,dh/2,dz),(2*dhx,dh,2*dhz))

def cornice(a,steps,cove=True):
    """Stepped cornice around the four walls and a cool cove strip under its lip."""
    for i,(y,depth,height) in enumerate(steps):
        for s in (-1,1):
            box(a,'stone',(s*(HALF-depth/2),y,0),(depth,height,2*HALF))
            box(a,'stone',(0,y,s*(HALF-depth/2)),(2*HALF-2*depth,height,depth))
    if cove:
        y,depth,height=steps[-1]
        inset=depth+.12;cy=y-height/2-.1
        for s in (-1,1):
            box(a,'cove',(s*(HALF-inset),cy,0),(.08,.14,2*HALF-2*inset))
            box(a,'cove',(0,cy,s*(HALF-inset)),(2*HALF-2*inset-.2,.14,.08))
            box(a,'stone',(s*(HALF-inset+.07),cy-.1,0),(.06,.06,2*HALF-2*inset))
            box(a,'stone',(0,cy-.1,s*(HALF-inset+.07)),(2*HALF-2*inset-.2,.06,.06))

def wall_bands(a,finish,y,height,depth=.05,skip_opening=False):
    inner=HALF-depth
    for s in (-1,1):
        box(a,finish,(s*(HALF-depth/2),y,0),(depth,height,2*HALF))
    box(a,finish,(0,y,-(HALF-depth/2)),(2*inner,height,depth))
    if skip_opening and y<OPENING+height:
        for s in (-1,1):box(a,finish,(s*(VEST_HALF+(inner-VEST_HALF)/2),y,HALF-depth/2),(inner-VEST_HALF,height,depth))
    else:box(a,finish,(0,y,HALF-depth/2),(2*inner,height,depth))

def wall_spots(depth,width,extra=()):
    """Bay positions on the four walls: (centre, yaw facing the room) for
    pilasters every 6 m and sconces between them, clear of furniture."""
    pilasters=[];sconces=[]
    for wall in ('w','e','b','f'):
        for k in range(-3,4):
            for u,kind in ((k*6.0,'p'),(k*6.0+3.0,'s')):
                if kind=='s' and k==3:continue
                hw=width/2 if kind=='p' else .4
                if wall=='w':rect=(-HALF,-HALF+depth,u-hw,u+hw);centre=(-HALF,u);yaw=math.pi/2
                elif wall=='e':rect=(HALF-depth,HALF,u-hw,u+hw);centre=(HALF,u);yaw=-math.pi/2
                elif wall=='b':rect=(u-hw,u+hw,-HALF,-HALF+depth);centre=(u,-HALF);yaw=0.0
                else:
                    if abs(u)<10:continue
                    rect=(u-hw,u+hw,HALF-depth,HALF);centre=(u,HALF);yaw=math.pi
                if wall=='b' and abs(u)<7.5:continue
                if not clear_of(*rect,extra=extra):continue
                (pilasters if kind=='p' else sconces).append((centre,yaw))
    return pilasters,sconces

def bays(a,code,extra=()):
    """Pilasters between bays with capitals and bases, and a sconce in each bay."""
    depth,width={251:(.45,1.1),252:(.5,1.4),253:(.6,1.0),254:(.14,.6)}[code]
    pilasters,sconces=wall_spots(depth,width,extra)
    for (x,z),yaw in pilasters:
        m=Matrix.Translation((x,0,z))@Matrix.Rotation(yaw,4,'Y')
        p=lambda u,v,w:tuple(m@Vector((u,v,w)))
        if code==251:
            box(a,'stone',p(0,4.8,depth/2),(width,9.6,depth),yaw)
            box(a,'metal',p(0,8.9,depth+.03),(width+.1,.3,.08),yaw)
            box(a,'stone',p(0,.3,depth/2+.04),(width+.16,.6,depth+.08),yaw)
            box(a,'metal',p(0,6.1,depth+.02),(width,.16,.06),yaw)
        elif code==252:
            box(a,'stone',p(0,5.5,depth/2),(width,11,depth),yaw)
            box(a,'metal',p(0,9.6,depth+.03),(width+.1,.3,.08),yaw)
            box(a,'metal',p(0,1.2,depth+.03),(width+.1,.12,.08),yaw)
        elif code==253:
            box(a,'stone',p(0,4.8,depth/2),(width,9.6,depth),yaw)
            for i,(w,h) in enumerate(((1.15,.25),(1.3,.25),(1.45,.25))):box(a,'stone',p(0,8.6+i*.25,depth/2+.02*i),(w,h,depth+.04*i),yaw)
            box(a,'wood',p(0,.6,depth/2+.03),(width+.06,1.2,depth+.06),yaw)
            box(a,'cove',p(0,7.0,depth+.01),(width-.2,.06,.04),yaw)
        else:
            box(a,'metal',p(0,5.0,depth/2),(width,10.0,depth),yaw)
            box(a,'glass',p(0,5.0,depth+.01),(width-.24,9.0,.04),yaw)
    for (x,z),yaw in sconces:
        m=Matrix.Translation((x,0,z))@Matrix.Rotation(yaw,4,'Y')
        p=lambda u,v,w:tuple(m@Vector((u,v,w)))
        box(a,'metal',p(0,3.4,.04),(.18,.32,.08),yaw)
        if code==251:
            rod(a,'metal',p(0,3.45,.06),p(0,3.6,.42),.025,5)
            sphere(a,'lamp',p(0,3.8,.42),.16,8,5)
        elif code==252:
            rod(a,'metal',p(0,3.5,.06),p(0,3.5,.4),.02,5)
            lathe(a,'lamp',[(0,-.2),(.12,-.18),(.14,.1),(0,.16)],p(0,3.42,.42),6)
        elif code==253:
            box(a,'cove',p(0,3.6,.12),(.14,.8,.06),yaw)
            box(a,'stone',p(0,3.6,.09),(.3,.95,.06),yaw)
        else:
            sphere(a,'lamp',p(0,3.5,.25),.12,8,5)
            for i in range(6):
                t=2*math.pi*i/6;rod(a,'metal',p(0,3.5,.25),p(.32*math.cos(t),3.5+.32*math.sin(t),.25),.008,4)
    return len(pilasters),len(sconces)

def flat_ceiling(a):
    box(a,'ceiling',(0,CEILING+.3,0),(2*HALF+2*WALL,.6,2*HALF+2*WALL))

def coffers(a,step,beam,height,inner=None):
    """Ceiling coffer grid: beams on a `step` grid, with an optional second,
    shallower step inside each coffer (stepped Deco coffers)."""
    n=int(HALF//step)
    for k in range(-n,n+1):
        u=k*step
        box(a,'ceiling',(u,CEILING-height/2,0),(beam,height,2*HALF-.1))
        for j in range(-n,n):
            box(a,'ceiling',((j+.5)*step,CEILING-height/2+.01,u),(step-beam,height-.02,beam))
        if inner:
            iw,ih=inner
            for j in range(-n,n):
                for s in (-1,1):
                    box(a,'ceiling',(u+s*(beam/2+iw/2),CEILING-ih/2,(j+.5)*step),(iw,ih,step-beam-.02))
                    box(a,'ceiling',((j+.5)*step,CEILING-ih/2+.005,u+s*(beam/2+iw/2)),(step-beam-2*iw-.04,ih-.01,iw))

def rosettes(a,code):
    """A ceiling medallion around each chandelier."""
    for x,z in CHANDELIER_SPOTS:
        lathe(a,'stone',[(0,CEILING-.42),(1.2,CEILING-.42),(1.55,CEILING-.34),(1.75,CEILING-.2),(1.75,CEILING-.01),(0,CEILING-.01)],(x,0,z),32)
        torus(a,'metal',(x,CEILING-.4,z),1.38,.05,32,4)
        torus(a,'metal' if code==251 else 'cove',(x,CEILING-.43,z),.6,.04,24,4)

def column_square(a,x,z,finish='stone',cap='metal'):
    box(a,finish,(x,CEILING/2,z),(1.2,CEILING,1.2))
    for y,w,h in ((.15,1.5,.3),(9.6,1.45,.25),(9.9,1.6,.3)):box(a,cap if y>1 else finish,(x,y,z),(w,h,w))
    a.collider('Column',(x,CEILING/2,z),(1.2,CEILING,1.2))

def palm(a,x,z,height=3.4,lean=0.0):
    """A potted fan palm: urn, soil, ringed trunk and arching fronds."""
    lathe(a,'stone',[(0,0),(.42,0),(.5,.12),(.6,.7),(.66,.82),(.6,.86),(0,.86)],(x,0,z),16)
    cylinder(a,'wood',(x,.84,z),.55,.04,16)
    top=Vector((x+lean,height,z))
    for i in range(6):
        y0=.86+(height-.86)*i/6;y1=.86+(height-.86)*(i+1)/6
        rod(a,'wood',(x+lean*i/6,y0,z),(x+lean*(i+1)/6,y1,z),.11-.01*i,6)
    for i in range(9):
        t=2*math.pi*i/9+.3;drop=.35+.25*(i%3)
        mid=top+Vector((math.cos(t)*.8,.25,math.sin(t)*.8));tip=top+Vector((math.cos(t)*1.55,-drop,math.sin(t)*1.55))
        for p,q,w in ((top,mid,.30),(mid,tip,.22)):
            d=q-p;yaw=math.atan2(d.x,d.z);pitch=-math.atan2(d.y,math.hypot(d.x,d.z))
            box(a,'foliage',tuple((p+q)/2),(w,.02,d.length),yaw,pitch)
    a.collider('Planter',(x,.45,z),(1.2,.9,1.2))

def stanchions(a):
    """Brass posts and velvet rope around the pit, open toward each approach."""
    cx,cz=PIT;r=11.0
    for centre in (45,135,225,315):
        angles=[math.radians(centre-28+7*i) for i in range(9)]
        posts=[(cx+r*math.sin(t),cz+r*math.cos(t)) for t in angles]
        for x,z in posts:
            lathe(a,'metal',[(0,0),(.17,0),(.17,.03),(.035,.06),(.025,.95),(.05,.98),(.04,1.04),(0,1.06)],(x,0,z),10)
        for (x0,z0),(x1,z1) in zip(posts,posts[1:]):
            mid=((x0+x1)/2,.78,(z0+z1)/2)
            rod(a,'carpet',(x0,.95,z0),mid,.025,5);rod(a,'carpet',mid,(x1,.95,z1),.025,5)

def floor_features(a,code):
    """Roulette dais and pit medallion, stanchions, bandstand, planters,
    lounge tables, the slot-aisle medallion and the dressing of the slot rows."""
    cx,cz=PIT;radius,height=ROULETTE_DAIS
    lathe(a,'stone',[(0,0),(radius,0),(radius,height),(0,height)],(cx,0,cz),48,smooth=False)
    torus(a,'metal',(cx,height,cz),radius-.04,.04,48,4)
    for r in ((radius-.9),(radius-1.5)):torus(a,'metal' if code!=254 else 'cove',(cx,height+.004,cz),r,.025,48,4)
    if code==254:
        for r in (radius+.4,radius+.75):torus(a,'metal',(cx,.015,cz),r,.03,64,4)
    a.collider_lathe('Roulette dais',[(0,0),(radius,0),(radius,height),(0,height)],(cx,0,cz),24)
    stanchions(a)
    # Slot-aisle floor medallion under its chandelier.
    x,z=CHANDELIER_SPOTS[2]
    cylinder(a,'floor',(x,.006,z),1.3,.012,32)
    torus(a,'metal',(x,.012,z),1.3,.03,32,4)
    torus(a,'metal',(x,.012,z),.7,.02,24,4)
    # Bandstand with a grand piano and a drum riser.
    (bx,bz),(bhx,bhz),bh=BANDSTAND
    box(a,'wood',(bx,bh/2,bz),(2*bhx,bh,2*bhz))
    box(a,'metal',(bx,bh-.02,bz+bhz-.03),(2*bhx,.04,.06))
    box(a,'metal',(bx+bhx-.03,bh-.02,bz),(.06,.04,2*bhz))
    box(a,'carpet',(bx,bh+.005,bz),(2*bhx-.4,.01,2*bhz-.4))
    a.collider('Bandstand',(bx,bh/2,bz),(2*bhx,bh,2*bhz))
    px,pz=bx-.6,bz+.6
    outline=[(-.75,-.9),(.75,-.9),(.75,.1)]+[(-.75+.75*(1+math.cos(t)),.1+.9*math.sin(t)) for t in [math.pi*i/8 for i in range(1,8)]]+[(-.75,.1)]
    prism(a,'rubber',outline,bh+.65,bh+.95,(px,0,pz),.4)
    prism(a,'rubber',outline,bh+.95,bh+1.0,(px,0,pz),.4)
    box(a,'rubber',(px,bh+1.35,pz),(1.5,.04,1.4),.4,math.radians(-28))
    for lx,lz in ((-.6,-.75),(.6,-.75),(0,.6)):
        q=Matrix.Translation((px,0,pz))@Matrix.Rotation(.4,4,'Y')@Vector((lx,0,lz))
        cylinder(a,'rubber',(q.x,bh+.33,q.z),.05,.66,8)
    q=Matrix.Translation((px,0,pz))@Matrix.Rotation(.4,4,'Y')@Vector((0,0,-1.05))
    box(a,'stone',(q.x,bh+.72,q.z),(1.2,.04,.16),.4)
    box(a,'rubber',(q.x,bh+.25,q.z-.25),(.7,.5,.35),.4)
    a.collider('Grand piano',(px,bh+.6,pz),(1.9,1.2,1.9),.4)
    rx,rz=bx+1.4,bz-1.3
    box(a,'carpet',(rx,bh+.15,rz),(2.0,.3,1.6))
    for dx,dz,r,h in ((-.4,.1,.32,.4),(.35,.3,.22,.3),(.5,-.35,.2,.25)):
        cylinder(a,'stone',(rx+dx,bh+.3+h/2,rz+dz),r,h,16)
        torus(a,'metal',(rx+dx,bh+.3+h,rz+dz),r,.015,16,4)
    rod(a,'metal',(rx-.6,bh+.3,rz-.4),(rx-.6,bh+1.4,rz-.4),.015,5)
    cylinder(a,'metal',(rx-.6,bh+1.42,rz-.4),.22,.01,16)
    a.collider('Drum riser',(rx,bh+.15,rz),(2.0,.3,1.6))
    for x,z in PLANTERS:palm(a,x,z,3.4,.15 if x>0 else -.15)
    for x,z in COCKTAILS:
        lathe(a,'metal',[(0,0),(.3,0),(.3,.03),(.04,.06),(.04,.7),(0,.7)],(x,0,z),12)
        cylinder(a,'stone',(x,.72,z),.42,.04,20)
        lathe(a,'metal',[(0,.74),(.06,.74),(.02,.78),(.015,.95),(0,.95)],(x,0,z),8)
        lathe(a,'lamp',[(0,.88),(.1,.88),(.14,1.04),(.06,1.06),(0,1.06)],(x,0,z),10,smooth=False)
        a.collider('Cocktail table',(x,.4,z),(.84,.8,.84))
    # Slot-row dressing on top of each double-sided row (local X along the row).
    for x,z in ROWS:
        m=Matrix.Translation((x,0,z))@Matrix.Rotation(math.pi/2,4,'Y')
        p=lambda u,v,w:tuple(m@Vector((u,v,w)))
        yaw=math.pi/2
        box(a,'wood',p(0,1.95,0),(4.9,.1,1.44),yaw)
        if code==251:
            for off in (-1.6,0.0,1.6):
                prism(a,'wood',[(-.6,-.35),(.6,-.35),(.46,.35),(-.46,.35)],2.0,2.5,p(off,0,0),yaw)
                box(a,'metal',p(off,2.52,0),(1.24,.05,.74),yaw)
                for w in (-.42,.42):
                    for side in (-1,1):cylinder(a,'rubber',p(off+w,2.05,side*.36),.13,.05,10,'z',yaw)
            for side in (-1,1):
                for zz in (.28,.32):rod(a,'metal',p(-2.5,.03,side*(.35+zz)),p(2.5,.03,side*(.35+zz)),.018,5)
        elif code==252:
            for u in (-2.35,2.35):
                rod(a,'metal',p(u,2.0,0),p(u,2.75,0),.04,8)
            for side in (-1,1):
                for h in (2.55,2.72):rod(a,'metal',p(-2.4,h,side*.55),p(2.4,h,side*.55),.022,6)
                for u in (-1.6,0,1.6):box(a,'metal',p(u,2.64,side*.3),(.05,.04,.55),yaw)
            box(a,'sign',p(0,2.85,0),(4.6,.24,.08),yaw)
        elif code==253:
            for i,(w,h) in enumerate(((4.9,.18),(4.3,.18),(3.4,.18))):box(a,'stone',p(0,2.09+.18*i,0),(w,h,1.1-.25*i),yaw)
            for side in (-1,1):box(a,'cove',p(0,2.02,side*.73),(4.8,.05,.03),yaw)
        else:
            torus(a,'glass',p(0,2.0,0),2.3,.05,24,5,'z',yaw,math.pi,0.0)
            for u in (-1.6,0,1.6):sphere(a,'lamp',p(u,2.2+.5*(1-abs(u)/2.3),0),.1,8,4)

def hall_comstock(a):
    flat_ceiling(a)
    coffers(a,3.0,.28,.32)
    rosettes(a,251)
    cornice(a,((10.75,.35,.5),(10.25,.6,.5)))
    wall_bands(a,'wood',.6,1.2,.06,True)
    wall_bands(a,'metal',1.22,.06,.08,True)
    for y in (3.2,6.1):wall_bands(a,'metal',y,.16,.05,y<OPENING+.2)
    wall_bands(a,'glass',9.15,.9,.04)
    wall_bands(a,'metal',8.66,.08,.06)
    bays(a,251)
    for x,z in COLUMNS:
        lathe(a,'stone',[(0,0),(.75,0),(.75,.5),(.55,.6),(0,.6)],(x,0,z),16)
        cylinder(a,'metal',(x,5.3,z),.42,9.4,16)
        for y in (2.0,5.0,8.0):torus(a,'metal',(x,y,z),.44,.05,16,4)
        lathe(a,'metal',[(0,10.0),(.45,10.0),(.85,10.6),(.85,10.75),(0,10.75)],(x,0,z),16)
        a.collider('Column',(x,CEILING/2,z),(1.2,CEILING,1.2))
    # The giant copper winding wheel suspended over the pit: rim, spokes, a
    # brass hub open around the chandelier stem, and its suspension rods.
    cx,cz=PIT;y=8.0;c=(cx,y,cz)
    torus(a,'metal',c,6.5,.3,72,10)
    torus(a,'metal',c,5.9,.12,64,6)
    for i in range(36):
        t=2*math.pi*i/36;box(a,'metal',(cx+6.82*math.cos(t),y,cz+6.82*math.sin(t)),(.16,.5,.4),-t)
    lathe(a,'metal',[(1.62,-.42),(2.05,-.38),(2.05,.38),(1.62,.42)],c,40,'y',0,True,0.0,True)
    for i in range(16):
        t=2*math.pi*i/16;sphere(a,'lamp',(cx+2.12*math.cos(t),y,cz+2.12*math.sin(t)),.09,6,4)
    torus(a,'stone',(cx,y-.42,cz),1.83,.07,40,5)
    torus(a,'stone',(cx,y+.42,cz),1.83,.07,40,5)
    for i in range(12):
        t=2*math.pi*i/12
        rod(a,'metal',(cx+2.0*math.cos(t),y,cz+2.0*math.sin(t)),(cx+5.95*math.cos(t),y,cz+5.95*math.sin(t)),.11,6)
        rod(a,'metal',(cx+2.0*math.cos(t),y+.25,cz+2.0*math.sin(t)),(cx+4.5*math.cos(t+.15),y,cz+4.5*math.sin(t+.15)),.05,5)
    for i in range(4):
        t=2*math.pi*i/4+math.pi/4;rod(a,'metal',(cx+6.5*math.cos(t),y,cz+6.5*math.sin(t)),(cx+6.5*math.cos(t),CEILING,cz+6.5*math.sin(t)),.06,6)
    # Assay scales on the cage counter.
    for x in (-3.0,3.0):
        lathe(a,'metal',[(0,1.16),(.18,1.16),(.06,1.2),(.03,1.62),(0,1.64)],(x,0,-18.75),10)
        rod(a,'metal',(x-.4,1.6,-18.75),(x+.4,1.6,-18.75),.012,5)
        for s in (-1,1):lathe(a,'metal',[(0,1.32),(.15,1.36),(.16,1.38),(0,1.38)],(x+s*.4,0,-18.75),10)

def hall_junction(a):
    cornice(a,((10.8,.3,.4),))
    box(a,'carpet',(18.0,.006,17.5),(7.6,.012,8.6))
    wall_bands(a,'stone',.6,1.2,.08,True)
    wall_bands(a,'metal',1.24,.05,.1,True)
    board=[(-17.1,-8.9,-22,-21.4),(-1.5,1.5,-22,-21.4)]
    bays(a,252,board)
    # Vaulted green-glass train shed: segmental barrel along Z on brass ribs,
    # purlins, diagonal bracing and tie rods.
    rise=4.0;span=HALF+WALL;radius=(span*span+rise*rise)/(2*rise);seg=18
    angles=[math.asin(span/radius)*(2*i/seg-1) for i in range(seg+1)]
    yc=CEILING+rise-radius
    pts=[(radius*math.sin(t),yc+radius*math.cos(t)) for t in angles]
    for p0,p1 in zip(pts,pts[1:]):
        mid=((p0[0]+p1[0])/2,(p0[1]+p1[1])/2);ln=math.hypot(p1[0]-p0[0],p1[1]-p0[1])
        box(a,'ceiling',(mid[0],mid[1]+.12,0),(ln+.02,.2,2*HALF+2*WALL),0,0,math.atan2(p1[1]-p0[1],p1[0]-p0[0]))
    for k in range(-7,8):
        z=k*3.0
        heavy=k%2==0
        for p0,p1 in zip(pts,pts[1:]):rod(a,'metal',(p0[0],p0[1]-.12,z),(p1[0],p1[1]-.12,z),.12 if heavy else .06,6)
        if heavy:
            for s in (-1,1):
                rod(a,'metal',(s*(HALF-.4),CEILING,z),(s*HALF*.45,CEILING+rise*.72,z),.07,5)
                rod(a,'metal',(s*HALF*.45,CEILING+rise*.72,z),(0,CEILING+rise-.25,z),.07,5)
            rod(a,'metal',(-(HALF-.4),CEILING+.2,z),(HALF-.4,CEILING+.2,z),.03,5)
    for idx in range(2,seg-1,3):
        x,y=pts[idx]
        rod(a,'metal',(x,y-.2,-HALF),(x,y-.2,HALF),.05,6)
        for k in range(-7,7,2):
            rod(a,'metal',(x,y-.2,k*3.0),(pts[idx+1][0],pts[idx+1][1]-.2,k*3.0+3.0),.025,4)
    for s in (-1,1):
        poly=list(pts)
        verts=[(x,y,s*(HALF+WALL/2)-WALL/2) for x,y in poly]+[(x,y,s*(HALF+WALL/2)+WALL/2) for x,y in poly]
        n=len(poly);faces=[tuple(range(n)),tuple(reversed(range(n,2*n)))]
        for i in range(n-1):faces.append((i,i+1,n+i+1,n+i))
        faces.append((n-1,0,n,2*n-1))
        a.add('wall',verts,faces)
    # Station clock over the cashier cage and the split-flap departure board.
    cylinder(a,'stone',(0,7.0,-HALF+.15),1.3,.12,40,'z')
    torus(a,'metal',(0,7.0,-HALF+.2),1.33,.07,40,6,'z')
    for i in range(12):
        t=2*math.pi*i/12;box(a,'sign',(1.1*math.cos(t),7.0+1.1*math.sin(t),-HALF+.23),(.08,.22,.02),0,0,t+math.pi/2)
    box(a,'sign',(.0,7.32,-HALF+.25),(.07,.7,.02))
    box(a,'sign',(.32,6.92,-HALF+.27),(.55,.06,.02),0,0,math.radians(-15))
    box(a,'metal',(0,5.55,-HALF+.2),(.2,.3,.3))
    box(a,'wood',(-13,5.4,-HALF+.12),(8.2,2.8,.24))
    box(a,'screen',(-13,5.4,-HALF+.25),(7.8,2.4,.02))
    for i in range(1,6):box(a,'sign',(-13,4.2+i*.4,-HALF+.265),(7.8,.025,.01))
    box(a,'metal',(-13,6.95,-HALF+.2),(8.4,.3,.3))
    for x,z in COLUMNS:column_square(a,x,z,'stone','metal')

def hall_boulder(a):
    flat_ceiling(a)
    coffers(a,4.0,.5,.45,(.35,.22))
    rosettes(a,253)
    cornice(a,((10.8,.3,.4),(10.35,.6,.5),(9.85,.9,.5)))
    for s in (-1,1):
        for y in (10.55,10.05):box(a,'cove',(s*(HALF-(.32 if y>10.3 else .62)),y-.27,0),(.04,.04,2*HALF-2))
    wall_bands(a,'wood',.5,1.0,.08,True)
    wall_bands(a,'stone',1.05,.1,.1,True)
    bays(a,253)
    # Cashier cage as an intake tower rising to the cornice.
    for i,(w,y0,y1,depth) in enumerate(((12.4,3.6,6.0,3.2),(10.4,6.0,8.0,2.6),(8.4,8.0,9.6,1.9))):
        front=-HALF+depth
        box(a,'stone',(0,(y0+y1)/2,-HALF+depth/2),(w,y1-y0,depth))
        low=max(y0,5.1)+.2
        for k in range(int(w//1.2)):
            x=-w/2+.6+k*1.2
            box(a,'cove' if k%2 else 'stone',(x,(low+y1-.2)/2,front+.05),(.12,y1-.2-low,.1))
    for x,z in COLUMNS:
        box(a,'stone',(x,CEILING/2,z),(1.2,CEILING,1.2))
        for i,(w,y) in enumerate(((1.4,9.2),(1.6,9.6),(1.8,10.0))):box(a,'stone',(x,y,z),(w,.4,w))
        box(a,'wood',(x,.6,z),(1.3,1.2,1.3))
        box(a,'cove',(x,7.0,z),(1.24,.06,1.24))
        a.collider('Column',(x,CEILING/2,z),(1.2,CEILING,1.2))

def hall_orbit(a):
    cornice(a,((10.8,.3,.4),))
    wall_bands(a,'glass',1.6,3.2,.06,True)
    wall_bands(a,'metal',3.25,.12,.08,True)
    wall_bands(a,'metal',.03,.06,.08,True)
    bays(a,254)
    # Planetarium dome: square ceiling ring, then a navy cap with orbit ribs.
    r0=HALF-.4;seg=40;rise=5.0
    ring_in=[(r0*math.cos(2*math.pi*i/seg),r0*math.sin(2*math.pi*i/seg)) for i in range(seg)]
    def to_square(x,z):
        m=max(abs(x),abs(z));return (x/m*(HALF+WALL),z/m*(HALF+WALL))
    for i in range(seg):
        p,q=ring_in[i],ring_in[(i+1)%seg];P,Q=to_square(*p),to_square(*q)
        poly=[p,q,Q,P]
        verts=[(x,CEILING,z) for x,z in poly]+[(x,CEILING+.6,z) for x,z in poly]
        a.add('ceiling',verts,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)])
    rings=10;cap=[]
    for j in range(rings+1):
        phi=(math.pi/2)*j/rings;cap.append((r0*math.cos(phi),CEILING+rise*math.sin(phi)))
    inner=[(r,y) for r,y in cap[:-1]]+[(0,CEILING+rise)]
    outer=[(0,CEILING+rise+.3)]+[(r+.3,y+.3) for r,y in reversed(cap[1:-1])]+[(r0+.3,CEILING+.3)]
    lathe(a,'ceiling',inner+outer,(0,0,0),seg,'y',0.0,True,0.0,True)
    for k in range(12):
        t=2*math.pi*k/12
        rib=[(r*math.cos(t),y-.08,r*math.sin(t)) for r,y in cap]
        for p,q in zip(rib,rib[1:]):rod(a,'metal',p,q,.06,4)
    for j in (3,6):
        r,y=cap[j];torus(a,'cove',(0,y-.1,0),r-.1,.04,48,4)
    torus(a,'metal',(0,CEILING-.05,0),r0,.12,seg,6)
    torus(a,'cove',(0,CEILING-.2,0),r0-.25,.05,seg,4)
    # Copper nose cone crowning the back bar, countdown clock over the cage.
    lathe(a,'metal',[(0,0),(.75,0),(.7,1.4),(.5,2.6),(.25,3.3),(0,3.6)],(21.5,4.3,-3),20)
    for z in (-11.5,5.5):lathe(a,'metal',[(0,0),(.45,0),(.4,.8),(.2,1.4),(0,1.6)],(21.5,4.3,z),14)
    box(a,'metal',(0,5.7,-HALF+.12),(7.4,1.9,.24))
    box(a,'screen',(0,5.7,-HALF+.25),(7.0,1.5,.02))
    for x,z in COLUMNS:
        cylinder(a,'stone',(x,CEILING/2,z),.6,CEILING,20)
        for y in (1.2,4.4,7.6):torus(a,'glass',(x,y,z),.62,.08,20,4)
        lathe(a,'metal',[(0,10.2),(.62,10.2),(.95,10.8),(0,10.8)],(x,0,z),20)
        a.collider('Column',(x,CEILING/2,z),(1.2,CEILING,1.2))

HALLS = {251:hall_comstock,252:hall_junction,253:hall_boulder,254:hall_orbit}

def build_hall(code):
    a=Asset('hall_%d'%code)
    hall_shell(a,code)
    HALLS[code](a)
    floor_features(a,code)
    return a

# ---------------------------------------------------------------- blender
MATS={}
def materials(palette=None,code=0):
    neutral={'floor':'d8c9a8','carpet':'5a1f1a','wall':'c9a878','ceiling':'e3d6bc','stone':'c9a878','wood':'4a2e1c',
             'metal':'b06b3a','glass':'1f6e68','felt':'2e5e4e','lamp':'ffd9a0','sign':'2b1d14','screen':'ffd9a0','rubber':'0d0d0d',
             'cove':'e8f4f2','foliage':'3a6b32'}
    colors=dict(neutral)
    if palette:
        colors.update({'floor':palette['stone'],'carpet':palette['carpet'],'wall':palette['stone'],'ceiling':palette['paper'],
                       'stone':palette['stone'],'wood':palette['wood'],'metal':palette['metal'],'glass':palette['glass'],
                       'felt':palette['felt'],'lamp':palette['lamp'],'sign':palette['ink'],'screen':palette['lamp']})
        # Review swatches follow the runtime finish choices per resort.
        colors['floor']={251:palette['stone'],252:palette['paper'],253:palette['glass'],254:palette['paper']}.get(code,palette['stone'])
        colors['ceiling']={251:palette['paper'],252:palette['glass'],253:palette['paper'],254:palette['ink']}.get(code,palette['paper'])
        colors['screen']=palette['lamp'] if code in (251,252) else palette['glass']
    for finish in FINISHES:
        name='resort_'+finish
        mat=bpy.data.materials.get(name) or bpy.data.materials.new(name)
        rgb=tuple(int(colors[finish][i:i+2],16)/255 for i in (0,2,4))
        lin=tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in rgb)
        mat.diffuse_color=(*lin,1);mat.use_nodes=True
        bs=mat.node_tree.nodes.get('Principled BSDF')
        bs.inputs['Base Color'].default_value=(*lin,1)
        bs.inputs['Roughness'].default_value={'metal':.3,'glass':.1,'floor':.3,'felt':.95,'carpet':.95}.get(finish,.6)
        bs.inputs['Metallic'].default_value=.75 if finish=='metal' else 0.0
        if finish in ('lamp','screen','cove'):
            bs.inputs['Emission Color'].default_value=(*lin,1);bs.inputs['Emission Strength'].default_value=3.0 if finish=='lamp' else 1.6
        else:bs.inputs['Emission Strength'].default_value=0.0
        MATS[finish]=mat

def reset():
    for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
    for m in list(bpy.data.meshes):bpy.data.meshes.remove(m)
    for c in list(bpy.data.curves):bpy.data.curves.remove(c)
    for l in list(bpy.data.lights):bpy.data.lights.remove(l)
    for c in list(bpy.data.cameras):bpy.data.cameras.remove(c)

def make_objects(asset,matrix=Matrix.Identity(4),collection=None):
    objects=[]
    collection=collection or bpy.context.scene.collection
    for finish in FINISHES:
        if finish not in asset.parts:continue
        verts,faces,smooth=asset.parts[finish]
        mesh=bpy.data.meshes.new(asset.name+' '+finish)
        mesh.from_pydata([TO_BLENDER@matrix@v for v in verts],[],faces);mesh.update()
        recalc(mesh)
        for poly,flag in zip(mesh.polygons,smooth):poly.use_smooth=flag
        mesh.materials.append(MATS[finish])
        obj=bpy.data.objects.new(asset.name+' '+finish,mesh);collection.objects.link(obj);objects.append(obj)
    return objects

def make_colliders(asset):
    objects=[];counts={}
    for name,verts,faces in asset.colliders:
        counts[name]=counts.get(name,0)+1
        label=name if counts[name]==1 else '%s %d'%(name,counts[name])
        mesh=bpy.data.meshes.new(label+'-colonly');mesh.from_pydata([TO_BLENDER@v for v in verts],[],faces);mesh.update();recalc(mesh)
        obj=bpy.data.objects.new(label+'-colonly',mesh);bpy.context.scene.collection.objects.link(obj);objects.append(obj)
    return objects

def export(asset):
    reset();materials()
    objects=make_objects(asset)+make_colliders(asset)
    bpy.context.scene['provenance']='Original procedural geometry authored for Sin City: Desert Dreams; no external assets'
    bpy.context.scene['units']='metres, Godot axes rotated to Blender +Z up, door toward -Y; game applies 1/16 tile scale'
    SOURCE.mkdir(parents=True,exist_ok=True);EXPORT.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(asset.name+'.blend')))
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    path=EXPORT/(asset.name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,
        export_materials='EXPORT',export_cameras=False,export_lights=False,export_extras=False)
    coords=[v for verts,_,_ in asset.parts.values() for v in verts]
    low=[min(v[i] for v in coords) for i in range(3)];high=[max(v[i] for v in coords) for i in range(3)]
    data={'triangles':asset.triangles(),'parts':len(asset.parts),'materials':sorted('resort_'+f for f in asset.parts),
          'colliders':len(asset.colliders),'min_godot':low,'max_godot':high,'size_godot':[h-l for h,l in zip(high,low)],
          'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    sidecar=EXPORT/(asset.name+'.glb.import')
    if not sidecar.exists():sidecar.write_text(SIDECAR.replace('{path}','res://assets/desert-dreams-resorts/'+asset.name+'.glb'))
    return data

SIDECAR='''[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="{path}"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={}
gltf/naming_version=2
gltf/embedded_image_handling=1
'''

# ---------------------------------------------------------------- review
def lettering_case(code):
    """Capitals, except Atomic Age, whose capital I reads poorly at a distance."""
    return (lambda text:text) if code==254 else (lambda text:text.upper())

def placement(game,at,yaw,count,half):
    """Prop transforms (Godot axes) for one table row, as the game places them."""
    poses=[];step=half[0]*2/count
    for i in range(count):
        off=(i-(count-1)/2)*step
        poses.append(Matrix.Translation(Vector(at))@Matrix.Rotation(yaw,4,'Y')@Matrix.Translation((off,0,0)))
    return poses

def text_object(body,font,center,yaw,size,color_mat,depth=.0):
    curve=bpy.data.curves.new('Lettering','FONT');curve.body=body;curve.font=font;curve.align_x='CENTER';curve.align_y='CENTER'
    curve.size=1.0;curve.extrude=depth
    obj=bpy.data.objects.new('Lettering',curve);bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.update()
    w,h=max(obj.dimensions.x,1e-3),max(obj.dimensions.y,1e-3)
    s=min(size[0]/w,size[1]/h);curve.size=s
    m=Matrix.Translation(Vector(center))@Matrix.Rotation(yaw,4,'Y')
    obj.matrix_world=TO_BLENDER@m
    curve.materials.append(color_mat);return obj

def review(code,parts_cache,only_views=None):
    theme=RESORTS[code];reset();materials(theme['palette'],code)
    hall=build_hall(code);make_objects(hall)
    for game,at,yaw,seat,count,half in TABLES:
        name=SIGNATURE_PROPS[theme['signature']] if game=='signature' else GAME_PROPS[game]
        for m in placement(game,at,yaw,count,half):
            make_objects(parts_cache[name],m)
            if game=='slots':make_objects(parts_cache['slot_stool'],m@Matrix.Translation((0,0,.95)))
    for name,at,yaw in LOUNGE:make_objects(parts_cache[name],Matrix.Translation(Vector(at))@Matrix.Rotation(yaw,4,'Y'))
    for z in BAR_STOOLS:make_objects(parts_cache['bar_stool'],Matrix.Translation((16.35,0,z)))
    for x,z in CHANDELIER_SPOTS:make_objects(parts_cache[theme['chandelier']],Matrix.Translation((x,CEILING,z)))
    font=bpy.data.fonts.load(str(FONTS/theme['font']))
    letters=bpy.data.materials.new('review lettering');letters.use_nodes=True
    bs=letters.node_tree.nodes.get('Principled BSDF')
    lamp=tuple(int(theme['palette']['lamp'][i:i+2],16)/255 for i in (0,2,4))
    bs.inputs['Base Color'].default_value=(*lamp,1);bs.inputs['Emission Color'].default_value=(*lamp,1);bs.inputs['Emission Strength'].default_value=2.0
    case=lettering_case(code)
    texts={'floor':case(theme['floor']),'resort':case(theme['name']),'cage':case('Cashier'),'bar':case('Bar & Lounge')}
    rooms={'floor':(9.0*.92,.75*.78),'resort':(14.0*.92,1.6*.78),'cage':(6*.92,.9*.78),'bar':(8*.92,.8*.78)}
    for role,(centre,size,yaw) in SIGN_PLATES.items():
        off=Vector((math.sin(yaw)*.02,0,math.cos(yaw)*.02))
        text_object(texts[role],font,Vector(centre)+off,yaw,rooms[role],letters)
    for game,at,yaw,seat,count,half in TABLES:
        if game=='slots':continue
        real=theme['signature'] if game=='signature' else game
        side=Matrix.Rotation(yaw,4,'Y')@Vector((half[0]+.55,0,half[1]*.2))
        base=Vector(at)+side
        make_objects(parts_cache['standard_sign'],Matrix.Translation(base)@Matrix.Rotation(yaw,4,'Y'))
        face=base+Matrix.Rotation(yaw,4,'Y')@Vector((0,1.42,.04))
        text_object('%s\n$%s %s'%(theme['games'][real],'{:,}'.format(theme['minimum']),case('minimum')),font,face,yaw,(.78,.42),letters)
    for (x,y,z),rng,energy in LIGHTS:
        light=bpy.data.lights.new('Lamp','POINT');light.energy=energy*rng*rng*14;light.shadow_soft_size=.6
        light.color=lamp;obj=bpy.data.objects.new('Lamp',light);bpy.context.scene.collection.objects.link(obj)
        obj.location=TO_BLENDER@Vector((x,y,z))
    sun=bpy.data.lights.new('Fill','SUN');sun.energy=.9;sun.color=(1,.92,.8)
    obj=bpy.data.objects.new('Fill',sun);bpy.context.scene.collection.objects.link(obj);obj.rotation_euler=(math.radians(28),0,math.radians(30))
    world=bpy.context.scene.world or bpy.data.worlds.new('Hall');bpy.context.scene.world=world;world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=(.35,.32,.28,1);world.node_tree.nodes['Background'].inputs[1].default_value=.35
    scene=bpy.context.scene
    scene.render.engine='BLENDER_EEVEE'
    try:scene.eevee.taa_render_samples=48
    except Exception:pass
    scene.render.resolution_x=1600;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX';scene.view_settings.look='None'
    cam=bpy.data.cameras.new('Review');cam.lens=22;cam.clip_start=.05;cam.clip_end=200
    co=bpy.data.objects.new('Review',cam);scene.collection.objects.link(co);scene.camera=co
    seat_eye=lambda tx,tz,yaw,d,ty=0: (Vector((tx,ty,tz))+Matrix.Rotation(yaw,4,'Y')@Vector((0,0,d+1.7))+Vector((0,2.5,0)),Vector((tx,ty+.85,tz)))
    sig=TABLES[-1]
    views={'front':((0,1.75,29.4),(0,3.2,8)),'pit':((9,5.0,15),(0,1.0,1)),'bar':((9,2.6,-9),(19,1.6,0)),
           'cage':((-3,2.2,-7),(0,2.6,-20)),'seated':seat_eye(-8,2,-math.pi/2,1.5),'dais':seat_eye(0,-11.5,0.0,1.75,.3),
           'slots':((-16.5,2.2,12),(-16.5,1.0,-4)),'lounge':((10,2.4,8),(19,1.0,18)),'wheel':((6,1.7,9),(0,8.0,2))}
    out=REVIEW/theme['key'];out.mkdir(parents=True,exist_ok=True)
    for view,(eye,target) in views.items():
        if only_views and view not in only_views:continue
        e=TO_BLENDER@Vector(eye);t=TO_BLENDER@Vector(target)
        co.location=e;co.rotation_euler=(t-e).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(out/(view+'.png'));bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/('review_%d.blend'%code)))

# ---------------------------------------------------------------- main
def main():
    global REVIEW
    parser=argparse.ArgumentParser()
    parser.add_argument('--skip-render',action='store_true')
    parser.add_argument('--review-dir',type=Path)
    parser.add_argument('--only',default='')
    parser.add_argument('--views',default='')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    if args.review_dir:REVIEW=args.review_dir
    bpy.context.preferences.filepaths.save_version=0
    only=[n for n in args.only.split(',') if n]
    catalog_path=EXPORT/'catalog.json'
    catalog=json.loads(catalog_path.read_text()) if catalog_path.exists() else {}
    catalog.update({'source_units':'metres','runtime_units':'tile = 16 metres','forward':'Godot +Z (the door)',
        'provenance':'Original procedural geometry and flat colours; no external artwork or models',
        'generator':'tools/blender_exploration/build_resort_interiors.py'})
    catalog.setdefault('models',{});catalog.setdefault('halls',{})
    cache={}
    for name,fn in PROPS.items():
        a=Asset(name);fn(a);cache[name]=a
        if not only or name in only:catalog['models'][name]=export(a);print('exported',name,catalog['models'][name]['triangles'])
    for code in RESORTS:
        name='hall_%d'%code
        if only and name not in only:continue
        a=build_hall(code);catalog['models'][name]=export(a);print('exported',name,catalog['models'][name]['triangles'])
        theme=RESORTS[code]
        catalog['halls'][str(code)]={'model':name,'resort':theme['key'],'floor':theme['floor'],
            'chandelier':theme['chandelier'],'signature':SIGNATURE_PROPS[theme['signature']]}
    catalog['models']=dict(sorted(catalog['models'].items()));catalog['halls']=dict(sorted(catalog['halls'].items()))
    catalog_path.write_text(json.dumps(catalog,indent=2)+'\n')
    if not args.skip_render:
        views=[v for v in args.views.split(',') if v]
        for code in RESORTS:
            if only and 'hall_%d'%code not in only and not any(o.startswith('review') for o in only):continue
            review(code,cache,views)
    print('RESORT_INTERIORS_COMPLETE')

if __name__=='__main__':main()
