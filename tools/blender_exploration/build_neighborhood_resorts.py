# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Four original neighborhood resort buildings and enclosed casino pockets.

Blender --background --python tools/blender_exploration/build_neighborhood_resorts.py
Only IDs 262..265 are written. Coordinates are metres, +Y up, +Z streetfront;
the existing runtime applies 1/16 scale. Editable masters stay locally excluded.
"""
import bpy, sys, math, json, hashlib, argparse
from pathlib import Path
from mathutils import Matrix, Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_resort_interiors as g
import build_six_resort_exteriors as e

ROOT = Path(__file__).resolve().parents[2]
THEMES = json.loads((ROOT/'tools/neighborhood_resorts.json').read_text())['resorts']
SOURCE = ROOT/'assets/six-resorts/neighborhood'
DEST = ROOT/'game/assets/desert-dreams-3d'
HALL_DEST = ROOT/'game/assets/desert-dreams-resorts'
FONTS = {'fontdiner':'fontdiner-swanky/FontdinerSwanky-Regular.ttf',
         'biorhyme':'biorhyme/BioRhyme-Medium.ttf',
         'biorhyme_expanded':'biorhyme-expanded/BioRhymeExpanded-Regular.ttf'}
CURSIVE = Path('/System/Library/Fonts/Supplemental/Apple Chancery.ttf')
SURFACES = {
    'boddy':dict(stone=('scored-stucco',4),wood=('neighborhood-timber',2.4),floor=e.TERRAZZO,roof=e.GRAVEL),
    'woolier':dict(stone=('brick',2.4),wood=('neighborhood-timber',2.4),floor=e.TERRAZZO,roof=('corrugated-steel',3)),
    'stockgrowers':dict(stone=('rusticated-sandstone',3),wood=('neighborhood-timber',2.4),floor=e.TERRAZZO,roof=('corrugated-steel',3)),
    'fremont':dict(stone=('granite',4),wood=('scored-stucco',4),floor=e.TERRAZZO,roof=e.GRAVEL),
}
e.SURFACES.update(SURFACES)

def original_timber():
    """Deterministic grain/board swatch, no external photograph or copied image."""
    import numpy as np
    count=512; yy,xx=np.mgrid[0:count,0:count].astype(float)/count
    # Periodic vertical grain and fine growth rings; four dark joined boards.
    grain=np.sin(math.tau*(xx*47+.17*np.sin(math.tau*yy*3)))
    fine=np.sin(math.tau*(xx*131+.08*np.sin(math.tau*yy*7)))
    bands=np.cos(math.tau*xx*4)
    seam=np.exp(-((np.sin(math.tau*xx*2))/.028)**2)
    shade=.65+.075*grain+.035*fine+.08*bands-.28*seam
    pixels=np.ones((count,count,4),dtype=np.float32)
    for i,base_color in enumerate((.72,.47,.27)):pixels[:,:,i]=np.clip(shade*base_color,.04,.85)
    # Write sRGB bytes directly so the measured linear mean matches exported tint.
    import struct,zlib
    rgb_bytes=(pixels[:,:,:3]*255+.5).astype(np.uint8)
    def chunk(kind,payload):
        return struct.pack('>I',len(payload))+kind+payload+struct.pack('>I',zlib.crc32(kind+payload)&0xffffffff)
    scanlines=b''.join(b'\0'+row.tobytes() for row in rgb_bytes)
    png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',count,count,8,2,0,0,0))
    png+=chunk(b'IDAT',zlib.compress(scanlines,9))+chunk(b'IEND',b'')
    (e.TEXTURES/'neighborhood-timber.png').write_bytes(png)
    meta_path=e.TEXTURES/'manifest.json';meta=json.loads(meta_path.read_text())
    rgb=rgb_bytes.astype(float)/255;linear=np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
    record={'file':'neighborhood-timber.png','periods':1,'mean_linear':list(linear.mean(axis=(0,1))),
            'source':'Original deterministic vertical timber grain and board joints',
            'generator':'tools/blender_exploration/build_neighborhood_resorts.py'}
    meta['textures']=[row for row in meta['textures'] if row['file']!=record['file']]+[record]
    meta_path.write_text(json.dumps(meta,indent=2)+'\n')
    e.TEXTURE_META.update({row['file']:row for row in meta['textures']})

def box(a,f,p,s,**kw): g.box(a,f,p,s,**kw)
def rod(a,f,p,q,r=.06): g.rod(a,f,p,q,r,8)
def solid(a,name,p,s,f='stone'):
    box(a,f,p,s); a.collider(name,p,s)
def mass(a,name,p,s,f='stone'):
    solid(a,name,p,s,f)
    if abs(p[1]-s[1]/2-.6)<.001:
        solid(a,name+' footing',(p[0],.3,p[2]),(s[0],.6,s[2]),'stone')
def cylinder(a,f,p,r,h,seg=20,axis='y'): g.cylinder(a,f,p,r,h,seg,axis)

def base(a,half):
    # Never a whole-lot grounded collider: terrain supports belong to buildings.
    box(a,'floor',(0,.025,0),(half*2-.5,.02,half*2-.5))
    for z in range(-int(half)+2,int(half),4):
        box(a,'stone',(0,.041,z),(half*2-.5,.008,.025))

def door(a,z,top=4.55):
    box(a,'sign',(0,2.6,z+.025),(5.6,4,.05))
    box(a,'glass',(0,2.6,z+.08),(5.25,3.85,.06))
    for x in (-2.65,0,2.65):box(a,'metal',(x,2.6,z+.13),(.10,4,.10))
    for x in (-.23,.23):
        rod(a,'metal',(x,2.2,z+.18),(x,2.85,z+.18),.025)
        for yy in (2.2,2.85):rod(a,'metal',(x,yy,z+.10),(x,yy,z+.18),.028)
    box(a,'metal',(0,top,z+.15),(5.6,.12,.18))
    # Safe positive-bottom apron stops before the threshold capsule.
    box(a,'floor',(0,.18,z+.28),(6.1,.30,.56))
    box(a,'floor',(0,.47,z+.10),(5.9,.26,.20))
    for x in (-3.6,3.6):
        box(a,'metal',(x,3.05,z+.08),(.18,.85,.16))
        box(a,'lamp',(x,3.05,z+.18),(.13,.62,.06))

def window(a,x,y,z,w,h,side,shutters=False,lace=False):
    e.window(a,x,y,z,w,h,side)
    d=1 if side in ('front','right') else -1
    # Curtain/shutter panels belong outside pane region so no crossed windows.
    for off in (-w/2-.35,w/2+.35):
        if shutters:
            if side in ('front','back'):
                box(a,'felt',(x+off,y,z+d*.04),(.45,h,.12))
                for yy in (y-h*.35,y,y+h*.35):box(a,'wood',(x+off,yy,z+d*.11),(.45,.045,.08))
            else:
                box(a,'felt',(x+d*.04,y,z+off),(.12,h,.45))
                for yy in (y-h*.35,y,y+h*.35):box(a,'wood',(x+d*.11,yy,z+off),(.08,.045,.45))
    if lace:
        if not hasattr(a,'lace_windows'):a.lace_windows=set()
        a.lace_windows.add((x,y,z))
        a.window_decoration=window_decoration

def window_decoration(a,x,y,z,w,h,side):
    """Ivory fabric relief on opaque panes; included with its own window parts."""
    if (x,y,z) not in getattr(a,'lace_windows',set()):return
    d=1 if side=='front' else -1
    for side_x in (-1,1):
        xx=x+side_x*(w/2-.25)
        box(a,'ceiling',(xx,y,z+d*.095),(.34,h*.9,.04))
        for i in range(7):
            cylinder(a,'ceiling',(xx-side_x*.16,y+h*.4-i*h*.125,z+d*.11),.09,.028,8,'z')

def flowerbox(a,x,y,z,w=2):
    box(a,'wood',(x,y,z),(w,.38,.48))
    # Wall-mounted wrought brackets carry the box, rather than hovering.
    for xx in (x-w*.35,x+w*.35):
        box(a,'metal',(xx,y-.12,z-.26),(.08,.28,.24))
    for xx in (x-w*.3,x,x+w*.3):
        rod(a,'foliage',(xx,y+.18,z),(xx,y+.58,z),.025)
        for off in (-.13,.13):g.sphere(a,'foliage',(xx+off,y+.4,z),.13,8,4)
        g.sphere(a,'carpet',(xx,y+.62,z),.13,8,4)

def porch(a,w,z,roof_y,depth=2.8,roof_back=None,roof_finish='wood'):
    solid(a,'Porch deck',(0,.55,z),(w,.10,depth),'wood')
    front=z+depth/2;back=z-depth/2 if roof_back is None else roof_back
    box(a,roof_finish,(0,roof_y,(front+back)/2),(w,.25,front-back))
    for x in (-w/2+.5,-w/4,w/4,w/2-.5):
        mass(a,'Porch post',(x,(roof_y+.6)/2,z+depth/2-.3),(.22,roof_y-.6,.22),'wood')
        for sign in (-1,1):rod(a,'wood',(x,roof_y-.75,z+depth/2-.3),(x+sign*.55,roof_y-.13,z+depth/2-.3),.07)
    box(a,'wood',(0,roof_y-.20,z+depth/2-.2),(w,.35,.23))

def awning(a,x,z,w):
    box(a,'carpet',(x,4.05,z),(w,.12,1.5),pitch=.15)
    box(a,'carpet',(x,3.86,z+.73),(w,.3,.06))
    for i in range(int(w/.25)):
        xx=x-w/2+.125+i*.25
        cylinder(a,'carpet',(xx,3.73,z+.74),.125,.04,8,'z')
    for side in (-1,1):rod(a,'metal',(x+side*(w/2-.1),3.35,z-.76),(x+side*(w/2-.1),3.98,z+.5),.035)

def boddy(a):
    mass(a,'Tavern',(0,3.25,0),(26,5.3,24))
    e.roof(a,0,0,26,24,5.9,'stone',.65)
    box(a,'wood',(0,4.7,12.18),(25,1.15,.35))
    door(a,12)
    for x in (-9,-5,5,9):
        window(a,x,2.55,12.035,2.1,2.15,'front',lace=True)
        awning(a,x,12.72,2.65);flowerbox(a,x,.65,12.35,2.3)
    for side in (-1,1):
        for z in (-8,-2,5):
            window(a,side*13.035,2.55,z,2.4,2.5,'right' if side>0 else 'left')
    for x in (-9,-4,4,9):window(a,x,2.55,-12.035,2.3,2.3,'back')
    # Chimney, kitchen hood, roof vents and rear service-door detail.
    mass(a,'Chimney',(-9,6.75,-7),(1.25,3.0,1.15),'stone')
    box(a,'metal',(-9,8.32,-7),(1.5,.18,1.4))
    for x in (4,8):
        box(a,'stone',(x,6.12,-6),(1.8,.25,1.8))
        box(a,'metal',(x,6.5,-6),(1.6,.7,1.6))
    box(a,'wood',(0,2.05,-12.045),(2.1,2.9,.09))
    box(a,'metal',(.72,2,-12.11),(.1,.25,.07))
    for x in (-10,10):
        solid(a,'Garden box',(x,.62,14.8),(3,.7,.9),'wood')
        for xx in (x-1,x+1):solid(a,'Garden box feet',(xx,.15,14.8),(.3,.3,.7),'wood')
        for xx in (x-.8,x,x+.8):g.sphere(a,'foliage',(xx,1.0,14.8),.5,10,5)

def flag(a):
    # Ikurrina: red field, green diagonal saltire, white upright cross.
    # Two independently surfaced faces preserve the same design from behind.
    x,y,z=-12.6,7.6,14.35;w,h=3.2,2.0
    mass(a,'Flagpole',(-14.2,4.7,14.35),(.09,8.2,.09),'metal')
    g.sphere(a,'metal',(-14.2,8.85,14.35),.10,10,5)
    box(a,'flag_red',(x,y,z),(w,h,.022))
    # Clip a stripe polygon to the rectangle before emitting both sides.
    def clip(poly,axis,edge,greater):
        out=[]
        for p,q in zip(poly,poly[1:]+poly[:1]):
            pin=p[axis]>=edge if greater else p[axis]<=edge
            qin=q[axis]>=edge if greater else q[axis]<=edge
            if pin:out.append(p)
            if pin!=qin:
                t=(edge-p[axis])/(q[axis]-p[axis]);out.append((p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1])))
        return out
    for diagonal in (-1,1):
        slope=diagonal*h/w;b=.19*math.sqrt(1+slope*slope)
        poly=[(-w,slope*-w-b),(w,slope*w-b),(w,slope*w+b),(-w,slope*-w+b)]
        for axis,edge,greater in [(0,-w/2,True),(0,w/2,False),(1,-h/2,True),(1,h/2,False)]:poly=clip(poly,axis,edge,greater)
        for face in (-1,1):
            pts=[(x+xx,y+yy,z+face*.013) for xx,yy in poly]
            a.add('flag_green',pts,[tuple(range(len(pts))) if face>0 else tuple(reversed(range(len(pts))))])
    for face in (-1,1):
        box(a,'flag_white',(x,y,z+face*.018),(w,.29,.004))
        box(a,'flag_white',(x,y,z+face*.020),(.29,h,.004))

def woolier(a):
    mass(a,'Boardinghouse',(0,4.8,0),(26,8.4,24),'stone')
    e.roof(a,0,0,26,24,9,'wood',.55)
    porch(a,25,13.25,5.0,3.0)
    box(a,'wood',(0,5.75,12.75),(22,1.0,.30))
    for x in (-8,8):box(a,'wood',(x,5.2,12.75),(.18,.4,.30))
    door(a,12)
    for x in (-9,-5,5,9):window(a,x,2.65,12.035,2,2.4,'front',shutters=True)
    for side in (-1,1):
        for y in (3,7):
            for z in (-8,-2,5,9):window(a,side*13.035,y,z,1.8,2.2,'right' if side>0 else 'left',shutters=True)
    for x in (-9,-4,4,9):
        window(a,x,7.7,12.035,1.8,1.9,'front',shutters=True)
        for y in (3,7):window(a,x,y,-12.035,1.8,2.2,'back',shutters=True)
    for x in (-10,10):
        flowerbox(a,x,1.0,14.6,2.5)
        for xx in (x-.8,x+.8):box(a,'wood',(xx,.70,14.6),(.20,.30,.30))
    # Sheep projecting sign supported by a bracket bolted into the porch fascia.
    rod(a,'metal',(10.5,5.2,12.8),(10.5,6.1,14.7),.055)
    box(a,'wood',(10.5,5.95,14.25),(2.7,1.2,.14))
    g.sphere(a,'ceiling',(10.5,5.96,14.38),.42,16,8)
    for xx in (10.22,10.52):rod(a,'sign',(xx,5.9,14.42),(xx,5.5,14.42),.035)
    g.sphere(a,'sign',(11.0,6.08,14.41),.19,12,6)
    for xx in (10.87,11.05):rod(a,'sign',(xx,6.2,14.4),(xx+.05,6.32,14.4),.035)
    mass(a,'Kitchen chimney',(-9,9.25,-8),(1.3,2.5,1.3),'stone')
    box(a,'metal',(-9,10.57,-8),(1.55,.18,1.55))
    flag(a)

def gable_roof(a,x,z,w,d,eave,ridge):
    # Closed gable shell, edge-seamed galvanized roof, no orphan ridge posts.
    e.facade_polygon(a,'wood',[(x-w/2,eave),(x+w/2,eave),(x,ridge)],z-d/2,.18)
    e.facade_polygon(a,'wood',[(x-w/2,eave),(x+w/2,eave),(x,ridge)],z+d/2,.18)
    rise=ridge-eave;angle=math.atan2(rise,w/2);length=math.hypot(w/2,rise)
    for side in (-1,1):
        box(a,'roof',(x+side*w/4,(eave+ridge)/2,z),(length+.5,.18,d+.8),roll=-side*angle)
        for zz in range(int(z-d/2),int(z+d/2)+1,2):
            rod(a,'metal',(x+side*(w/2+.1),eave+.10,zz),(x,ridge+.10,zz),.035)
    rod(a,'metal',(x,ridge+.10,z-d/2-.4),(x,ridge+.10,z+d/2+.4),.075)

def stockgrowers(a):
    mass(a,'Sale barn',(0,4.5,0),(28,7.8,30),'wood')
    gable_roof(a,0,0,28,30,8.4,10.8)
    # Raised glazed clerestory rests on the main roof ridge.
    mass(a,'Clerestory',(0,10.7,-1),(5.5,2.2,23),'wood')
    for side in (-1,1):
        box(a,'glass',(side*2.785,11.1,-1),(.08,1.1,21))
        for z in range(-10,11,3):box(a,'wood',(side*2.85,11.1,z),(.20,1.2,.16))
    gable_roof(a,0,-1,6,24,11.8,12.8)
    for side in (-1,1):
        mass(a,'Guest wing',(side*17.75,3.1,-1),(7.5,5,26),'stone')
        e.roof(a,side*17.75,-1,7.5,26,5.6,'wood',.45)
        for z in (-10,-5,0,5,10):window(a,side*21.535,2.9,z,2.2,2.5,'right' if side>0 else 'left')
        for x in (side*18,):
            window(a,x,2.9,12.035,3,2.4,'front');window(a,x,2.9,-14.035,3,2.4,'back')
        for y in (3,6):window(a,side*14.035,y,13.5,2,1.8,'right' if side>0 else 'left')
    mass(a,'Auction lobby',(0,3.25,17.4),(12,5.3,5.2),'wood')
    door(a,20)
    porch(a,15,20.75,5.9,2.5,roof_back=14.4,roof_finish='roof')
    box(a,'wood',(0,6.60,21.15),(19,1.2,.35))
    for x in (-6,6):box(a,'metal',(x,6.3,21.0),(.12,.8,.18))
    for x in (-10,10):
        # Embossed auction-circle motif seated on the barn front.
        box(a,'wood',(x,5.6,15.08),(2.3,2.3,.25))
        g.torus(a,'metal',(x,5.6,15.22),1.0,.075,24,6,'z')
        rod(a,'metal',(x-.6,5.0,15.22),(x+.6,6.2,15.22),.055)
        rod(a,'metal',(x-.6,6.2,15.22),(x+.6,5.0,15.22),.055)
    # Water tank: four grounded legs, diagonal braces, bearing platform and bands.
    cx,cz=-17,-18
    for dx in (-1.5,1.5):
        for dz in (-1.5,1.5):
            mass(a,'Tank trestle',(cx+dx,4.55,cz+dz),(.25,7.9,.25),'wood')
    for side in (-1,1):
        for aa,bb in [(-1.5,1.5),(1.5,-1.5)]:
            rod(a,'wood',(cx+aa,1.0,cz+side*1.5),(cx+bb,8.1,cz+side*1.5),.095)
            rod(a,'wood',(cx+side*1.5,1.0,cz+aa),(cx+side*1.5,8.1,cz+bb),.095)
    box(a,'wood',(cx,8.4,cz),(4.2,.35,4.2))
    cylinder(a,'wood',(cx,10.0,cz),1.85,3.0,28)
    for yy in (8.6,9.7,11.3):g.torus(a,'metal',(cx,yy,cz),1.86,.065,28,6)
    cylinder(a,'roof',(cx,11.6,cz),2.05,.25,28)
    rod(a,'metal',(cx,11.4,cz),(cx,12.0,cz),.05)

def fremont(a):
    mass(a,'Plain hotel',(0,8.85,-9),(27,16.5,21),'wood')
    e.roof(a,0,-9,27,21,17.1,'stone',.55)
    for yy in (3.2,7.2,11.2,15.2):
        for x in (-10,-5,0,5,10):
            window(a,x,yy,-19.535,2.4,2.6,'back')
            if yy>=11:window(a,x,yy,1.535,2.4,2.6,'front')
        for side in (-1,1):
            for z in (-16,-10,-4):window(a,side*13.535,yy,z,2.4,2.6,'right' if side>0 else 'left')
        box(a,'stone',(0,yy-1.6,-9),(27.4,.20,21.4))
    mass(a,'Former showroom',(0,4.6,10),(39,8,20),'wood')
    e.roof(a,0,10,39,20,8.6,'stone',.65)
    box(a,'stone',(0,8.05,20.18),(38.5,1.05,.7))
    # Honest marble salvage columns: footings, shafts, capitals touch fascia.
    for x in (-16,-10,10,16):
        mass(a,'Marble column footing',(x,.9,21.0),(1.5,.6,1.5),'stone')
        cylinder(a,'stone',(x,4.0,21.0),.47,5.6,20)
        a.collider('Marble column',(x,4.0,21.0),(.95,5.6,.95))
        for yy in (1.35,6.8):box(a,'stone',(x,yy,21.0),(1.1,.3,1.1))
        box(a,'stone',(x,7.1,21.0),(1.45,.3,1.45))
        box(a,'stone',(x,7.48,20.9),(1.45,.45,1.65))
    # Canopy rests on full columns and showroom; name plaque and Deco crown.
    box(a,'stone',(0,7.7,20.9),(37.5,.35,2.6))
    box(a,'stone',(0,8.55,20.9),(28,1.45,1.4))
    box(a,'carpet',(0,8.65,21.45),(27,1.25,.4))
    for i in range(-4,5):
        h=2.0-abs(i)*.28
        box(a,'metal',(i*1.0,9.25+h/2,20.9),(.7,h,.45))
    door(a,20)
    for side in (-1,1):
        for z in (3,9,16):window(a,side*19.535,4.35,z,3.5,4,'right' if side>0 else 'left')
        for x in (side*6,side*13):window(a,x,4.5,20.035,3.2,4.3,'front')
    # Chandelier relief framed above the closed central entry.
    box(a,'sign',(0,5.9,20.1),(5.7,2.0,.36))
    rod(a,'metal',(0,6.85,20.28),(0,5.7,20.28),.065)
    for x in (-1.65,-.85,.85,1.65):
        rod(a,'metal',(0,5.8,20.29),(x,5.65,20.29),.045)
        rod(a,'metal',(x,5.65,20.29),(x,6.35,20.29),.045)
        g.sphere(a,'lamp',(x,6.35,20.3),.13,10,5)

BUILDERS = dict(boddy=boddy,woolier=woolier,stockgrowers=stockgrowers,fremont=fremont)
def build_exterior(theme,asset=None):
    a=asset or e.ExteriorAsset(theme['slug']);base(a,theme['footprint'][0]*8)
    BUILDERS[theme['slug']](a);e.flush_windows(a);return a

def panel(a,f,center,size,name=None):
    box(a,f,center,size)
    if name:a.collider(name,center,size)

def hall_shell(a,half,ceiling):
    solid(a,'Hall floor',(0,-.16,0),(half*2,.32,half*2),'floor')
    solid(a,'Hall ceiling',(0,ceiling+.16,0),(half*2+.6,.32,half*2+.6),'ceiling')
    for sign in (-1,1):
        solid(a,'Side wall',(sign*(half+.15),ceiling/2,0),(.3,ceiling,half*2+.6),'wall')
    solid(a,'Back wall',(0,ceiling/2,-half-.15),(half*2,.0+ceiling,.3),'wall')
    for sign in (-1,1):
        width=half-3
        solid(a,'Front wall',(sign*(3+width/2),ceiling/2,half+.15),(width,ceiling,.3),'wall')
    solid(a,'Vestibule lintel',(0,(3.8+ceiling)/2,half+.15),(6,ceiling-3.8,.3),'wall')
    solid(a,'Vestibule floor',(0,-.16,half+2.5),(6,.32,5.0),'floor')
    solid(a,'Vestibule ceiling',(0,3.95,half+2.5),(6.6,.3,5.6),'ceiling')
    for sign in (-1,1):solid(a,'Vestibule side wall',(sign*3.15,1.9,half+2.5),(.3,3.8,5.0),'wall')
    solid(a,'Closed vestibule door',(0,1.9,half+5.15),(6.6,3.8,.3),'wood')
    box(a,'carpet',(0,.012,half+2.5),(4,.02,2.2))
    for sign in (-1,1):rod(a,'metal',(sign*.25,1.5,half+4.97),(sign*.25,2.3,half+4.97),.025)
    # Continuous wainscoting, cornice and coffer grid; all floor details flush.
    for sign in (-1,1):
        box(a,'wood',(sign*(half-.06),.72,0),(.10,1.4,half*2))
        box(a,'metal',(sign*(half-.10),1.45,0),(.08,.07,half*2))
        box(a,'wood',(sign*(half-.15),ceiling-.2,0),(.3,.4,half*2))
        box(a,'wood',(0,.72,sign*(half-.06)),(half*2,1.4,.10)) if sign<0 else None
        box(a,'wood',(0,ceiling-.2,sign*(half-.15)),(half*2,.4,.3))
    for x in range(-int(half)+3,int(half),6):
        box(a,'wood',(x,ceiling-.10,0),(.18,.20,half*2))
    for z in range(-int(half)+3,int(half),6):box(a,'wood',(0,ceiling-.10,z),(half*2,.20,.18))
    box(a,'carpet',(0,.003,0),(half*2-1.2,.006,half*2-1.2))
    # Thin upholstery panels are wall details, above capsule height.
    for side in (-1,1):
        for z in range(-int(half)+3,int(half)-2,6):
            if side<0 and abs(z+7)<3:continue # heritage picture
            box(a,'carpet',(side*(half-.03),2.7,z),(.10,1.6,2.3))
            box(a,'metal',(side*(half-.11),3.6,z),(.09,.06,2.5))
    # Backed physical sign plates; text quads sit .015m beyond these faces.
    box(a,'sign',(0,3.25,half+.065),(5.55,.7,.018))
    for x in (-2.4,2.4):box(a,'metal',(x,3.72,half+.085),(.05,.28,.08))
    box(a,'sign',(0,4.7,half-.015),(8.2,1.1,.02))
    box(a,'wood',(0,4.7,half+.005),(8.1,1.0,.05))
    box(a,'sign',(0,3.0,-half+2.255),(4.2,.7,.02))
    for x in (-1.8,1.8):box(a,'metal',(x,2.75,-half+2.245),(.055,.55,.08))
    box(a,'sign',(half-.775,3.4,-4),(.02,.7,5.2))
    for z in (-6.25,-1.75):box(a,'metal',(half-.39,3.4,z),(.86,.08,.06))

def picture_frame(a,p,yaw):
    # Border occupies 2.56m square; runtime image is 2.4m square at its face.
    temp=g.Asset('frame')
    for sign in (-1,1):
        box(temp,'metal',(sign*1.25,0,.035),(.12,2.62,.09))
        box(temp,'metal',(0,sign*1.25,.035),(2.38,.12,.09))
        # Short hidden standoffs join the picture border to the wall face.
        box(temp,'wood',(sign*1.25,0,-.09),(.10,.3,.22))
    transform=Matrix.Translation(Vector(p))@Matrix.Rotation(yaw,4,'Y')
    for f,(vs,fs,smooth) in temp.parts.items():a.add(f,[transform@v for v in vs],fs)

def cage(a,half,small):
    width=6 if small else 8; z=-half+1.5
    solid(a,'Cash cage',(0,1.25,z),(width,2.5,1.5),'wood')
    box(a,'stone',(0,1.08,z+.77),(width+.1,.12,.15))
    box(a,'sign',(0,1.75,z+.755),(width-.4,1.12,.03))
    for x in (-(width/2-.5),0,width/2-.5):
        box(a,'glass',(x,1.75,z+.785),(width/3-.25,.95,.025))
    for x in [i*.35 for i in range(-int(width/.7)+1,int(width/.7))]:
        rod(a,'metal',(x,1.22,z+.82),(x,2.3,z+.82),.014)
    box(a,'metal',(0,2.35,z+.81),(width-.3,.08,.07))

def bar(a,half):
    solid(a,'Bar counter',(half-2,.55,-4),(1,1.1,6),'wood')
    box(a,'stone',(half-2,1.12,-4),(1.1,.10,6.2))
    solid(a,'Back bar',(half-.45,1.5,-4),(.7,3,6),'wood')
    for y in (1.25,1.9,2.5):
        box(a,'metal',(half-.9,y,-4),(.18,.06,5.8))
        for i in range(10):
            zz=-6.5+i*.55
            cylinder(a,'glass' if i%3 else 'carpet',(half-.83,y+.18,zz),.07,.30,8)
            cylinder(a,'metal',(half-.83,y+.37,zz),.025,.10,8)
    # Glasses, trays and a coffee pot stay within the counter obstacle.
    for zz in (-5.5,-3,-2):
        cylinder(a,'metal',(half-2,1.24,zz),.13,.16,12)
    cylinder(a,'metal',(half-2,1.38,-6.2),.18,.40,14)
    rod(a,'metal',(half-1.84,1.4,-6.2),(half-1.67,1.45,-6.2),.05)

def lamp_sconce(a,x,z,y=3.5,side=1):
    box(a,'metal',(x,y,z),(.16,.6,.14))
    rod(a,'metal',(x,y-.1,z),(x-side*.25,y,z),.03)
    cylinder(a,'lamp',(x-side*.25,y+.10,z),.17,.25,14)

def build_hall(theme):
    small=theme['code']<264;half=12 if small else 18;ceiling=6 if small else 8
    a=g.Asset('hall_%s'%theme['code']);hall_shell(a,half,ceiling);cage(a,half,small);bar(a,half)
    for p,yaw in [((-7,3.8,half-.12),math.pi),((7,3.8,half-.12),math.pi),((-half+.12,3.8,-7),math.pi/2)]:picture_frame(a,p,yaw)
    for side in (-1,1):
        for z in (-half+4,0,half-4):lamp_sconce(a,side*(half-.18),z,3.6,side)
    if theme['slug']=='boddy':
        # Homelike molded panels, a snack shelf and hanging ceramic details.
        for x in (-7,7):
            box(a,'wood',(x,1.6,-half+.06),(3.5,2.8,.15))
            box(a,'carpet',(x,1.8,-half+.16),(3.1,2.2,.12))
            for yy in (.7,2.8):box(a,'metal',(x,yy,-half+.24),(3.2,.055,.04))
        box(a,'wood',(half-.65,2.85,1.5),(.6,.12,2.3))
        for zz in (.7,1.2,1.7,2.2):
            cylinder(a,'stone',(half-.65,3.00,zz),.15,.2,12)
            g.sphere(a,'carpet',(half-.65,3.15,zz),.10,10,5)
        # Framed floral reliefs are attached to the rear paneled wall, above heads.
        for x in (-7,7):
            box(a,'stone',(x,3.5,-half+.06),(2.3,1.2,.15))
            for dx in (-.65,0,.65):
                rod(a,'foliage',(x+dx,3.1,-half+.16),(x+dx,3.65,-half+.16),.02)
                for j in range(6):
                    t=math.tau*j/6
                    g.sphere(a,'carpet',(x+dx+.10*math.cos(t),3.68+.1*math.sin(t),-half+.18),.07,8,4)
                g.sphere(a,'metal',(x+dx,3.68,-half+.2),.04,8,4)
    elif theme['slug']=='woolier':
        solid(a,'Family dining',(7,.5,7),(4.4,1,3),'wood')
        box(a,'ceiling',(7,1.025,7),(4.5,.03,3.1))
        for xx in (5.5,6.5,7.5,8.5):
            for zz in (6,8):
                cylinder(a,'stone',(xx,1.06,zz),.23,.035,16)
                cylinder(a,'glass',(xx+.30,1.17,zz),.055,.22,10)
                rod(a,'metal',(xx-.33,1.06,zz-.12),(xx-.33,1.06,zz+.12),.015)
        for xx in (6.2,7.5):
            cylinder(a,'wood',(xx,1.16,7),.28,.22,16)
            cylinder(a,'metal',(xx,1.30,7),.30,.05,16)
        # Beams sit into side walls and upper ceiling; no floor columns.
        for z in (-8,0,8):box(a,'wood',(0,ceiling-.3,z),(half*2,.6,.5))
    elif theme['slug']=='stockgrowers':
        solid(a,'Auction display',(13,.6,10),(4,1.2,4),'wood')
        box(a,'stone',(13,1.23,10),(4.1,.06,4.1))
        box(a,'sign',(13,3.5,half-.08),(7,2.1,.06))
        box(a,'wood',(13,3.5,half-.015),(7,2.1,.11))
        for yy in (2.5,4.5):box(a,'metal',(13,yy,half-.15),(7.2,.08,.08))
        for xx in (10,12,14,16):box(a,'metal',(xx,3.5,half-.15),(.07,2,.07))
        # Auction board tally strokes and lot medallions are attached relief.
        for xx in (11,13,15):
            for yy in (3.05,3.65):
                for off in (-.24,-.08,.08,.24):rod(a,'ceiling',(xx+off,yy-.16,half-.20),(xx+off,yy+.16,half-.20),.018)
        for x in (-8,8):
            box(a,'wood',(x,4,-half+.04),(5,2.8,.16))
            g.torus(a,'metal',(x,4,-half+.18),.85,.065,28,6,'z')
            for sign in (-1,1):
                rod(a,'metal',(x,3.55,-half+.20),(x+sign*.58,4.55,-half+.20),.055)
                rod(a,'metal',(x+sign*.58,4.55,-half+.20),(x+sign*.92,4.8,-half+.20),.055)
        # Exposed upper truss/braces remain above 5.5m with no floor posts.
        for z in (-12,-4,4,12):
            for side in (-1,1):rod(a,'wood',(side*half,6,z),(side*(half-3),ceiling-.15,z),.13)
        # Flush auction ring around display; no unreported step or railing.
        g.torus(a,'metal',(13,.007,10),2.8,.012,48,4)
        for z in (-12,-4,4,12):box(a,'wood',(0,ceiling-.25,z),(half*2,.5,.35))
    else:
        solid(a,'Fountain basin',(12,.5,10),(2.8,1,2.8),'stone')
        cylinder(a,'glass',(12,1.015,10),1.18,.025,32)
        cylinder(a,'stone',(12,1.17,10),.28,.34,20)
        g.sphere(a,'glass',(12,1.4,10),.17,16,8)
        # Salvaged pilasters embedded within the wall shell, away from pictures.
        for side in (-1,1):
            for z in (-14,0,13):
                box(a,'stone',(side*(half-.11),3.5,z),(.2,6.4,.7))
                for yy in (.35,6.8):box(a,'metal',(side*(half-.18),yy,z),(.34,.3,1.0))
        # A second salvaged chandelier fills the rear salon, suspended from roof.
        cx,cz=8,-9
        rod(a,'metal',(cx,ceiling,cz),(cx,5.6,cz),.07)
        for yy,r in ((6.65,1.15),(5.8,1.85)):
            g.torus(a,'metal',(cx,yy,cz),r,.065,40,6)
            for i in range(12):
                t=math.tau*i/12;xx=cx+math.cos(t)*r;zz=cz+math.sin(t)*r
                rod(a,'metal',(cx,yy+.2,cz),(xx,yy,zz),.04)
                rod(a,'metal',(xx,yy,zz),(xx,yy+.35,zz),.024)
                cylinder(a,'lamp',(xx,yy+.40,zz),.085,.16,10)
                g.lathe(a,'glass',[(0,-.32),(.08,-.22),(.055,-.04),(0,0)],(xx,yy-.05,zz),6)
        # Deco crown fan and marble salvage outlines belong to the rear wall.
        for x in (-8,8):
            box(a,'stone',(x,4.2,-half+.05),(5,3.3,.20))
            for i in range(-3,4):
                h=1.5-abs(i)*.25
                box(a,'metal',(x+i*.45,3.4+h/2,-half+.19),(.22,h,.09))
            box(a,'carpet',(x,3.1,-half+.18),(3.8,.4,.08))
    return a

def exterior_materials(theme):
    g.FINISHES[:]=g.FINISHES[:15]
    # Remove inherited derived material nodes before creating clean finishes.
    for material in list(bpy.data.materials):bpy.data.materials.remove(material)
    palette=dict(theme['palette'])
    if theme['slug']=='woolier':palette.update(stone='a9664d')
    if theme['slug']=='fremont':palette.update(wood='b6ab9c')
    g.materials(palette,theme['code'])
    roof=g.MATS['wood'].copy();roof.name='resort_roof';g.MATS['roof']=roof;g.FINISHES.append('roof')
    if theme['slug'] in ('woolier','stockgrowers'):
        shader=roof.node_tree.nodes['Principled BSDF']
        shader.inputs['Base Color'].default_value=(.29,.32,.34,1)
        shader.inputs['Metallic'].default_value=.65;shader.inputs['Roughness'].default_value=.38
    for finish,color in [('flag_red','ce1126'),('flag_green','009b48'),('flag_white','ffffff')]:
        mat=bpy.data.materials.new(finish);mat.use_nodes=True
        rgb=[int(color[i:i+2],16)/255 for i in (0,2,4)]
        linear=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
        mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*linear,1)
        mat.diffuse_color=(*linear,1);g.MATS[finish]=mat;g.FINISHES.append(finish)
    for finish in ('lamp','screen'):g.MATS[finish].node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value=.35

def lettering(theme):
    slug=theme['slug'];name=theme['name']
    fontpath=CURSIVE if slug=='boddy' else g.FONTS/FONTS[theme['font']]
    font=bpy.data.fonts.load(str(fontpath),check_existing=True)
    curve=bpy.data.curves.new(name,'FONT');curve.body=name;curve.font=font
    curve.align_x='CENTER';curve.align_y='CENTER';curve.size=1;curve.extrude=.016;curve.resolution_u=6
    ob=bpy.data.objects.new('Original outlined name',curve);bpy.context.scene.collection.objects.link(ob)
    curve.materials.append(g.MATS['lamp'])
    y,z,width,height={'boddy':(4.7,12.38,19,1.10),'woolier':(5.75,12.93,20,.85),
                    'stockgrowers':(6.60,21.35,18,.95),'fremont':(8.65,21.68,25,1.05)}[slug]
    bpy.context.view_layer.update();scale=min(width/ob.dimensions.x,height/ob.dimensions.y)
    ob.scale=(scale,scale,scale);ob.matrix_world=g.TO_BLENDER@Matrix.Translation(Vector((0,y,z)))@Matrix.Diagonal(Vector((scale,scale,scale,1)))
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    bpy.ops.object.convert(target='MESH');ob=bpy.context.object;bpy.context.view_layer.update()
    ob.data.transform(ob.matrix_world);ob.matrix_world=Matrix.Identity(4)
    return ob,{'family':'Apple Chancery' if slug=='boddy' else theme['font'],
               'source':'locally installed system font' if slug=='boddy' else 'bundled licensed font',
               'output':'outlined static mesh; font file not embedded', 'text':name}

def export_objects(a,objects,path,master,exterior=False):
    bpy.context.preferences.filepaths.save_version=0;SOURCE.mkdir(parents=True,exist_ok=True)
    # Relative paths refer only to local retained swatches in editable masters.
    for image in bpy.data.images:
        if image.filepath and Path(bpy.path.abspath(image.filepath)).parent==e.TEXTURES:
            image.filepath='//../textures/'+Path(bpy.path.abspath(image.filepath)).name
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/master),relative_remap=True)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.select_set(True)
    args=dict(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,
              export_materials='EXPORT',export_cameras=False,export_lights=False,export_extras=False)
    if exterior:args.update(export_image_format='JPEG',export_jpeg_quality=90)
    bpy.ops.export_scene.gltf(**args)
    if exterior:e.record_shared_images(e.share_images(path))
    coords=[v for vs,_,_ in a.parts.values() for v in vs]
    low=[min(v[i] for v in coords) for i in range(3)];high=[max(v[i] for v in coords) for i in range(3)]
    triangles=e.visible_triangles(path);assert triangles<40000,(path,triangles)
    prefix='desert-dreams-3d' if exterior else 'desert-dreams-resorts'
    sidecar=path.with_suffix('.glb.import')
    if not sidecar.exists():sidecar.write_text(g.SIDECAR.replace('{path}','res://assets/'+prefix+'/'+path.name))
    return dict(triangles=triangles,parts=len(a.parts),materials=sorted('resort_'+f for f in a.parts),
                colliders=len(a.colliders),min_godot=low,max_godot=high,size_godot=[hi-lo for hi,lo in zip(high,low)],
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())

def export_exterior(theme):
    a=build_exterior(theme);g.reset();exterior_materials(theme)
    visible=g.make_objects(a);e.apply_surfaces(theme,visible);letters,font=lettering(theme)
    data=export_objects(a,visible+[letters]+g.make_colliders(a),DEST/('%d-blender.glb'%theme['code']),theme['slug']+'.blend',True)
    half=theme['footprint'][0]*8
    assert data['min_godot'][1]>=0
    assert all(abs(v[i])<=half for vs,_,_ in a.parts.values() for v in vs for i in (0,2))
    local=SOURCE/'model-manifest.json';manifest=json.loads(local.read_text()) if local.exists() else {}
    manifest[str(theme['code'])]={'lettering':font,'generator':'tools/blender_exploration/build_neighborhood_resorts.py',
                                'license':'CC-BY-NC-SA-4.0','structural_swatches':SURFACES[theme['slug']]}
    local.write_text(json.dumps(manifest,indent=2)+'\n')
    return dict(code=theme['code'],path='res://assets/desert-dreams-3d/%d-blender.glb'%theme['code'],scale=.0625,
                pivot=[0,0,0],yaw=0,height=data['max_godot'][1]/16,footprint=theme['footprint'],
                triangles=data['triangles'],source_kind='authored_blender',glb_sha256=data['sha256'],meters_per_tile=16)

def export_hall(theme):
    a=build_hall(theme);g.reset();g.FINISHES[:]=g.FINISHES[:15]
    for material in list(bpy.data.materials):bpy.data.materials.remove(material)
    g.materials(theme['palette'],theme['code'])
    return export_objects(a,g.make_objects(a)+g.make_colliders(a),HALL_DEST/(a.name+'.glb'),a.name+'.blend')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--only',nargs='*');group=parser.add_mutually_exclusive_group();group.add_argument('--halls-only',action='store_true');group.add_argument('--exteriors-only',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    if not args.halls_only:original_timber()
    for theme in THEMES:
        if args.only and theme['slug'] not in args.only:continue
        if not args.halls_only:
            entry=export_exterior(theme)
            # Reread before each update to merge current concurrent catalog work.
            cp=DEST/'catalog.json';data=json.loads(cp.read_text());rows={row['code']:row for row in data['entries']}
            rows[theme['code']]=entry;data['entries']=[rows[k] for k in sorted(rows)];cp.write_text(json.dumps(data,indent=2)+'\n')
            print('NEIGHBORHOOD_EXTERIOR',theme['code'],entry['triangles'],flush=True)
        if args.exteriors_only:continue
        model=export_hall(theme)
        cp=HALL_DEST/'catalog.json';data=json.loads(cp.read_text());name='hall_%d'%theme['code']
        data['models'][name]=model;data['halls'][str(theme['code'])]=dict(model=name,resort=theme['key'],floor=theme['floor'],
            chandelier=theme['chandelier'],signature=g.SIGNATURE_PROPS[theme['signature']])
        data['models']=dict(sorted(data['models'].items()));data['halls']=dict(sorted(data['halls'].items()))
        cp.write_text(json.dumps(data,indent=2)+'\n');print('NEIGHBORHOOD_HALL',theme['code'],model['triangles'],flush=True)

if __name__=='__main__':main()
