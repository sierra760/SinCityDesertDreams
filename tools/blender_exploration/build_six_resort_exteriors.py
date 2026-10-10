# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Six original Nevada-themed buildings, metres/+Y up/+Z street front.

Blender --background --python tools/blender_exploration/build_six_resort_exteriors.py
No existing building is rebuilt. Editable parts remain in the .blend masters.
"""
import sys, json, math, hashlib, struct
from pathlib import Path
import bpy
from mathutils import Matrix, Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_resort_interiors as g

ROOT = Path(__file__).resolve().parents[2]
THEMES = json.loads((ROOT/'tools/resort_expansion.json').read_text())['resorts']
SOURCE = ROOT/'assets/six-resorts/exteriors'
DEST = ROOT/'game/assets/desert-dreams-3d'

def box(a,f,p,s): g.box(a,f,p,s)
def mass(a,name,p,s,f='stone'):
    box(a,f,p,s); a.collider(name,p,s)
    if abs((p[1]-s[1]/2)-.6)<.001:
        foot=(p[0],.3,p[2]); size=(s[0],.6,s[2])
        box(a,'stone',foot,size); a.collider(name+' foundation',foot,size)
def rod(a,f,p,q,r=.12): g.rod(a,f,p,q,r,8)
def torus(a,f,p,r,t=.25,axis='z'):
    g.torus(a,f,p,r,t,48,6,axis)

def facade_polygon(a,f,points,z,depth=.6):
    n=len(points);verts=[(x,y,z+d) for d in (-depth/2,depth/2) for x,y in points]
    faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]
    faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
    a.add(f,verts,faces)

def ledge(a, x, z, w, d, y, finish='stone', thickness=.35, over=.6):
    box(a,finish,(x,y,z),(w+over*2,thickness,d+over*2))


def roof(a, x, z, w, d, y, finish='stone', parapet=.9):
    """Inset gravel-ballast membrane, coping and separate parapet faces."""
    box(a,'roof',(x,y+.06,z),(w-.4,.12,d-.4))
    for sx in (-1,1):
        box(a,finish,(x+sx*(w/2-.22),y+parapet/2,z),(.44,parapet,d))
        box(a,finish,(x,y+parapet/2,z+sx*(d/2-.22)),(w-.88,parapet,.44))
    for side in (-1,1):
        box(a,'metal',(x+side*(w/2-.22),y+parapet,z),(.6,.12,d+.16))
        box(a,'metal',(x,y+parapet,z+side*(d/2-.22)),(w+.16,.12,.6))


class ExteriorAsset(g.Asset):
    """Asset that keeps each primitive's geometry so windows can be placed last."""
    def __init__(self,name):
        super().__init__(name);self.shapes=[];self.deferred=[];self.omitted=[]
    def add(self,finish,verts,faces,smooth=False):
        super().add(finish,verts,faces,smooth)
        verts=[Vector(v) for v in verts]
        lo=Vector(tuple(min(v[i] for v in verts) for i in range(3)))
        hi=Vector(tuple(max(v[i] for v in verts) for i in range(3)))
        self.shapes.append((finish,lo,hi,verts,faces))


def window(a,x,y,z,w,h,side,finish='glass',sill='stone'):
    """Queue a window; flush_windows draws it only where nothing stands in front."""
    if getattr(a,'deferred',None) is not None:
        a.deferred.append((x,y,z,w,h,side,finish,sill));return
    draw_window(a,x,y,z,w,h,side,finish,sill)


def window_region(x,y,z,w,h,side,depth=.5):
    """Pane rectangle swept outward from the facade, slightly inset."""
    if side in ('front','back'):
        d=1 if side=='front' else -1
        return (Vector((x-w/2+.05,y-h/2+.05,min(z,z+d*depth))),Vector((x+w/2-.05,y+h/2-.05,max(z,z+d*depth))))
    d=1 if side=='right' else -1
    return (Vector((min(x,x+d*depth),y-h/2+.05,z-w/2+.05)),Vector((max(x,x+d*depth),y+h/2-.05,z+w/2-.05)))


def _blocks(shape,lo,hi):
    finish,slo,shi,verts,faces=shape
    if finish=='floor' or not all(slo[k]<hi[k] and shi[k]>lo[k] for k in range(3)):return False
    inside=lambda p:all(lo[k]<p[k]<hi[k] for k in range(3))
    if all(slo[k]>=lo[k]-1 and shi[k]<=hi[k]+1 for k in range(3)) or len(verts)==8:
        return True  # small parts and boxes: their bounds are their shape
    # Curved or slanted parts (fabric, rods, arcs): sample actual surfaces.
    for face in faces:
        for i in range(1,len(face)-1):
            p0,p1,p2=verts[face[0]],verts[face[i]],verts[face[i+1]]
            for u in range(7):
                for v in range(7-u):
                    if inside(p0+(p1-p0)*(u/6)+(p2-p0)*(v/6)):return True
    return False


def flush_windows(a):
    """Draw queued windows, omitting any whose pane another part would cross."""
    pending,a.deferred=a.deferred,None
    shapes=list(a.shapes)
    for spec in pending:
        lo,hi=window_region(*spec[:6])
        if any(_blocks(shape,lo,hi) for shape in shapes):a.omitted.append(spec)
        else:draw_window(a,*spec)


def draw_window(a,x,y,z,w,h,side,finish='glass',sill='stone'):
    """Dark reveal, glass and projecting sill, oriented on one of four elevations."""
    if side in ('front','back'):
        direction=1 if side=='front' else -1
        box(a,'sign',(x,y,z),(w+.3,h+.25,.10))
        box(a,finish,(x,y,z+direction*.065),(w,h,.04))
        box(a,sill,(x,y-h/2-.13,z+direction*.13),(w+.4,.15,.32))
    else:
        direction=1 if side=='right' else -1
        box(a,'sign',(x,y,z),(.10,h+.25,w+.3))
        box(a,finish,(x+direction*.065,y,z),(.04,h,w))
        box(a,sill,(x+direction*.13,y-h/2-.13,z),(.32,.15,w+.4))


def punched(a,x,z,w,d,bottom,top,step=4.2,spacing=4.5,ww=2.1,wh=2.5,finish='glass'):
    nx=max(1,int((w-2)/spacing));nz=max(1,int((d-2)/spacing))
    rows=max(1,int((top-bottom)/step))
    for iy in range(rows):
        y=bottom+iy*step
        for side,zz in [('front',z+d/2+.035),('back',z-d/2-.035)]:
            for i in range(nx):window(a,x+(i-(nx-1)/2)*spacing,y,zz,ww,wh,side,finish)
        for side,xx in [('left',x-w/2-.035),('right',x+w/2+.035)]:
            for i in range(nz):window(a,xx,y,z+(i-(nz-1)/2)*spacing,ww,wh,side,finish)


def ribbons(a,x,z,w,d,bottom,top,step=4.3,glazing=2.3,balcony=0):
    """Horizontal hotel bands, structural end piers, restrained vertical mullions."""
    for iy,y in enumerate(range(int(bottom),int(top),int(step))):
        for side in (-1,1):
            zz=z+side*(d/2+.07)
            box(a,'glass',(x,y,zz),(w-2,glazing,.12))
            for i in range(1,int(w/4)):
                box(a,'stone',(x-w/2+i*4,y,zz+side*.08),(.16,glazing+.2,.18))
            box(a,'stone',(x,y-glazing/2-.32,zz+side*balcony/2),(w+.3,.36,.35+balcony))
            if balcony:
                # Balustrade glass stands on its slab and carries the handrail.
                deck=y-glazing/2-.14;rail=deck+1.05
                box(a,'glass',(x,(deck+rail)/2,zz+side*balcony),(w-1,rail-deck,.12))
                rod(a,'metal',(x-w/2+.5,rail,zz+side*balcony),(x+w/2-.5,rail,zz+side*balcony),.045)
                for end in (-1,1):
                    rod(a,'metal',(x+end*(w/2-.5),deck,zz+side*balcony),(x+end*(w/2-.5),rail,zz+side*balcony),.045)
        for side in (-1,1):
            xx=x+side*(w/2+.07)
            box(a,'glass',(xx,y,z),(.12,glazing,d-3))
            for j in range(1,int(d/4)):
                box(a,'stone',(xx+side*.08,y,z-d/2+j*4),(.18,glazing+.2,.16))
            box(a,'stone',(xx,y-glazing/2-.32,z),(.35,.36,d+.3))


def entrance(a, style='standard'):
    # Architectural footprint and door position are an integration contract:
    # closed door at Z=28m, full outdoor capsule supported at Z=29.12m.
    mass(a,'Entrance lobby',(0,3.3,23),(15,5.4,10),'stone')
    box(a,'sign',(0,2.55,28.025),(7.2,4.5,.05))
    box(a,'glass',(0,2.45,28.06),(5.8,3.7,.12))
    for x in (-3,-1,1,3):box(a,'metal',(x,2.45,28.15),(.13,3.9,.15))
    box(a,'metal',(0,4.5,28.2),(6.3,.16,.22))
    for x in (-.6,.6):box(a,'metal',(x,2.5,28.18),(.06,.55,.12))
    # Visual stoop up to the raised door sill; collision keeps the original apron.
    # Like the plaza it has a positive underside (no grounded hillside support)
    # and stops short of the outdoor threshold capsule at Z=29.12 m.
    box(a,'floor',(0,.185,28.3),(7.6,.33,.6));box(a,'floor',(0,.48,28.15),(7.2,.26,.3))
    box(a,'metal',(0,5.8,27.8),(17,.35,4.5))
    box(a,'sign',(0,5.8,30.11),(15,1,.18))
    box(a,'metal',(0,6.32,30.12),(15.4,.09,.24))
    # Piers run from their footings up into the canopy soffit.
    for x in (-7,7):mass(a,'Canopy pier',(x,3.125,29),(.4,5.05,.4),'metal')
    for x in (-5.5,5.5):
        box(a,'metal',(x,3.1,28.03),(.32,1.05,.06))
        box(a,'lamp',(x,3.1,28.115),(.12,.85,.11))
    if style!='dust':
        for x in (-12,12):
            box(a,'stone',(x,.85,26),(4,1.1,3))
            g.palm(a,x,26,5.3,.12)


def base(a):
    # Positive underside is essential: a grounded whole-lot decorative plaza
    # would generate an impassable full-lot foundation on hillside placements.
    box(a,'floor',(0,.025,0),(62,.02,62))
    for x in range(-28,29,8):box(a,'stone',(x,.04,0),(.035,.008,62))
    for z in range(-28,29,8):box(a,'stone',(0,.041,z),(62,.008,.035))


def vault(a,p,r=6):
    # Relief layers are seated on the door face (front at z+.25), never hovering.
    g.cylinder(a,'wood',p,r,.5,48,'z')
    torus(a,'metal',(p[0],p[1],p[2]+.32),r,.28)
    torus(a,'metal',(p[0],p[1],p[2]+.3),r*.72,.11)
    for i in range(8):
        q=i*math.tau/8
        rod(a,'metal',(p[0]+math.sin(q)*r*.29,p[1]+math.cos(q)*r*.29,p[2]+.32),
            (p[0]+math.sin(q)*r*.72,p[1]+math.cos(q)*r*.72,p[2]+.32),.12)
        g.sphere(a,'metal',(p[0]+math.sin(q)*r*.87,p[1]+math.cos(q)*r*.87,p[2]+.3),.11,8,4)
    g.cylinder(a,'metal',(p[0],p[1],p[2]+.35),r*.18,.25,16,'z')


def fix(a):
    # Tall withdrawn vault slab: warm black side blades frame emerald glass.
    mass(a,'Vault hotel',(0,39.8,-7),(32,78.4,26),'wood')
    for side in (-1,1):
        zz=-7+side*13.08
        # Rear curtain wall reaches the ground-floor lobby; front rises above the club.
        glass_low=3 if side<0 else 12.5
        box(a,'glass',(0,(glass_low+75.5)/2,zz),(25,75.5-glass_low,.14))
        # Rear blades come down to grade; front blades land on the supper club.
        low=.6 if side<0 else 11
        for x in (-12,-6,0,6,12):
            box(a,'stone',(x,(low+76)/2,zz+side*.13),(.65,76-low,.55))
            box(a,'metal',(x-.23,(low+76)/2,zz+side*.44),(.09,76-low,.07))
        for y in range(15,77,4):box(a,'wood',(0,y,zz+side*.13),(25,.52,.22))
        for x in (-14.9,14.9):box(a,'metal',(x,(low+77.5)/2,-7+side*13.06),(.15,77.5-low,.12))
        for y in range(15,76,4):
            for z in (-15,-7,1):window(a,side*16.06,y,z,3.5,2.6,'right' if side>0 else 'left')
        # Lower floors beside the supper club are glazed, not blank.
        for y in (3.5,7.5,11.5):
            for z in (-15,-7):window(a,side*16.06,y,z,3.5,2.6,'right' if side>0 else 'left')
        # Supper club's exposed rear wings either side of the tower.
        for x in (-21,21):window(a,x,6.5,1.965,3.5,6.5,'back')
    # One setback penthouse and fine open crown provide a resolved silhouette.
    roof(a,0,-7,32,26,79,'stone',1.1)
    mass(a,'Penthouse',(0,81.56,-8),(24,4.88,18),'stone')
    for side in (-1,1):box(a,'glass',(0,82,-8+side*9.06),(21,2.6,.12))
    roof(a,0,-8,24,18,84,'stone',.6)
    for x in (-11,0,11):rod(a,'metal',(x,84.12,-16),(x,87,-16),.09)
    rod(a,'metal',(-11,87,-16),(11,87,-16),.11)
    # Supper club forms a proper low foreground, with dark bays and brass fins.
    mass(a,'Supper club',(0,6.8,12),(49,12.4,20),'stone')
    for x in range(-21,22,6):
        window(a,x,6.5,22.04,4.5,6.6,'front')
        box(a,'metal',(x-2.55,5.88,22.3),(.18,11.7,.65))
    for side in (-1,1):
        for z in (5,11,17):window(a,side*24.55,6.5,z,3.5,6.5,'right' if side>0 else 'left')
    roof(a,0,12,49,20,13,'stone',.85)
    ledge(a,0,12,49,20,11.8,'metal',.14,.35)
    vault(a,(0,65,6.7),5.5)
    entrance(a)
    # Vault medallion is mounted on a stone pylon standing on the lobby roof.
    box(a,'stone',(0,9.35,27.85),(6,6.7,.5))
    vault(a,(0,9.4,28.35),2.45)


def alibi(a):
    # Wings pull apart; their differing heights and staggered ends avoid a gate.
    for x,z,h in [(-18,-7,68),(18,-4,74)]:
        mass(a,'Blush hotel wing',(x,(h+.6)/2,z),(15.5,h-.6,29),'stone')
        ribbons(a,x,z,15.5,29,9,h-3,4,2.35,1.35)
        # Ground-floor rooms behind the balcony bands get their own windows.
        for side in (-1,1):
            for i in range(-1,2):window(a,x+i*4.5,4.2,z+side*14.535,2.6,2.6,'front' if side>0 else 'back')
        # Blank blush end blade anchors the balcony layers at each outer corner.
        for side in (-1,1):box(a,'stone',(x+side*7.45,h/2,z),( .65,h-1,30))
        roof(a,x,z,15.5,29,h,'ceiling',1.25)
        mass(a,'Garden penthouse',(x,h+1.66,z-4),(10.8,3.08,15),'stone')
        box(a,'glass',(x,h+2,z+3.57),(8.7,1.6,.1))
        ledge(a,x,z-4,10.8,15,h+3.35,'ceiling',.3,.7)
    # Rings are open arcs, each leaning toward its own wing with a visible split.
    for x,start in [(-4.5,.2),(4.5,math.pi+.2)]:
        g.torus(a,'metal',(x,71,-1),6.1,.49,56,6,'z',arc=math.tau-.72,start=start)
    rod(a,'metal',(-12,68,-1),(-9,68,-1),.18)
    rod(a,'metal',(-9,66.8,-1),(-9,68,-1),.16)
    rod(a,'metal',(12,74,-1),(9,74,-1),.18)
    rod(a,'metal',(9,74,-1),(9,75.2,-1),.16)
    mass(a,'Courthouse pavilion',(0,7.6,11),(16,14,16),'stone')
    box(a,'sign',(0,7.5,19.08),(13,10,.12))
    for x in (-6,-2,2,6):
        # Columns stand on plinths at the lobby roof and carry the entablature.
        g.cylinder(a,'ceiling',(x,9.4,20.1),.52,7,16)
        box(a,'ceiling',(x,6.25,20.1),(1.3,.5,1.3))
        box(a,'ceiling',(x,12.8,20.1),(1.4,.45,1.4))
    ledge(a,0,12,17,17,13.2,'ceiling',.6,.2)
    box(a,'ceiling',(0,13.3,20.3),(18.4,.9,1.4))
    facade_polygon(a,'ceiling',[(-9,13.75),(9,13.75),(0,18)],20.3,.7)
    facade_polygon(a,'stone',[(-6.3,14.25),(6.3,14.25),(0,16.85)],20.68,.12)
    roof(a,0,11,16,16,14.6,'stone',.45)
    # Forecourt pools remain flush; split into two lobes by a pale zigzag path.
    for x in (-9,9):
        g.cylinder(a,'metal',(x,.047,19),4.5,.02,32)
        g.cylinder(a,'glass',(x,.062,19),4.2,.02,32)
    entrance(a)


def arch_window(a,x,y,z,w,h):
    r=w/2;spring=y+h/2-r
    points=[(x-r,y-h/2),(x+r,y-h/2)]
    points += [(x+r*math.cos(t),spring+r*math.sin(t)) for t in [i*math.pi/12 for i in range(13)]]
    facade_polygon(a,'sign',points,z,.12)
    points2=[(x-r+.23,y-h/2+.23),(x+r-.23,y-h/2+.23)]
    points2 += [(x+(r-.23)*math.cos(t),spring+(r-.23)*math.sin(t)) for t in [i*math.pi/12 for i in range(13)]]
    facade_polygon(a,'glass',points2,z+.08,.04)
    g.torus(a,'stone',(x,spring,z+.18),r+.14,.20,24,5,'z',arc=math.pi,start=math.pi)
    for sx in (-1,1):box(a,'stone',(x+sx*(r+.14),(spring+y-h/2)/2,z+.18),(.4,spring-y+h/2,.4))
    box(a,'stone',(x,y-h/2-.12,z+.18),(w+.8,.3,.55))


def velvet(a):
    # Deep wine-colored theater, rising in setbacks to a rolled fan crown.
    mass(a,'Cabaret center',(2,31.3,-7),(20,61.4,25),'carpet')
    for x,z,w,d,h in [(-16,2,14,24,34),(18,4,13,24,27)]:
        mass(a,'Salon wing',(x,(h+.6)/2,z),(w,h-.6,d),'stone')
        punched(a,x,z,w,d,6,h-2,4.5,4.5,1.8,2.6)
        roof(a,x,z,w,d,h,'carpet',1.1)
        # Belt courses and balconies fall midway between window rows (6 m + 4.5 m steps);
        # railings stay below the sill of the window above.
        for k in range(int((h-8.25)/9)+1):
            y=8.25+9*k
            ledge(a,x,z,w,d,y,'wood',.45,.6)
            box(a,'wood',(x,y,z+d/2+.6),(w-1,.25,1.6))
            rod(a,'metal',(x-w/2+.6,y+.9,z+d/2+1.3),(x+w/2-.6,y+.9,z+d/2+1.3),.055)
            for dx in range(-int(w/2)+1,int(w/2),2):rod(a,'wood',(x+dx,y,z+d/2+1.3),(x+dx,y+.9,z+d/2+1.3),.055)
    for side in (-1,1):
        zz=-7+side*12.55
        for x in (-6.0,10.0):
            box(a,'stone',(x,33,zz),(.9,58,.45))
            box(a,'metal',(x,33,zz+side*.3),(.16,58,.12))
        for y in range(10,59,4):
            for x in (-3.5,7.5):window(a,x,y,zz-side*.02,1.55,2.55,'front' if side>0 else 'back')
        # Central satin-red panel intentionally has no generic hotel grid.
        box(a,'stone',(2,33,zz+side*.18),(5.6,57,.3))
        for x in (.1,3.9):box(a,'metal',(x,33,zz+side*.38),(.13,57,.12))
        for y in range(8,59,4):
            for z in (-15,-7,1):window(a,2+side*10.06,y,z,2,2.55,'right' if side>0 else 'left')
    # Barrel crown carries the fan profile through the full depth of the tower.
    # Its curved roof resolves the two elevations as architecture, not signboards.
    profile=[(-8,60),(12,60)]+[(2+10*math.cos(t),60+10*math.sin(t)) for t in [i*math.pi/32 for i in range(33)]]
    facade_polygon(a,'carpet',profile,-7,25.5)
    for side in (-1,1):
        zz=-7+side*12.8
        for r in (9.2,7.8,6.4):g.torus(a,'metal',(2,60,zz),r,.13,40,6,'z',arc=math.pi,start=math.pi)
    # Keyhole is a single warm silhouette integrated with the crown's fan ribs.
    keyhole=[(-.5,56.5),(4.5,56.5)]
    keyhole += [(2+2.55*math.cos(t),64.5+2.55*math.sin(t)) for t in [-.9+i*(math.pi+1.8)/40 for i in range(41)]]
    facade_polygon(a,'lamp',keyhole,5.96,.16)
    for x in (.6,3.4):box(a,'metal',(x,35,5.95),(.12,41,.15))
    # Black iron balcony rails and tall arched salon openings dress the foreground.
    mass(a,'Cabaret foyer',(0,6.8,15),(40,12.4,13),'carpet')
    for x in (-15,-9,9,15):
        arch_window(a,x,6.7,21.58,3.8,8.2)
        box(a,'wood',(x,3.8,22.2),(4.6,.35,1.8))
        for dx in (-1.8,-.9,0,.9,1.8):rod(a,'wood',(x+dx,4,23),(x+dx,5.2,23),.05)
        rod(a,'metal',(x-2,5.2,23),(x+2,5.2,23),.06)
    ledge(a,0,15,40,13,13.1,'metal',.23,.7)
    entrance(a)
    facade_polygon(a,'carpet',[(-8,5.97),(8,5.97),(8,8.4),(6.3,9.2),(-6.3,9.2),(-8,8.4)],28.4,.8)
    for x in range(-7,8,2):
        g.cylinder(a,'carpet',(x,6.42,30.03),.7,.25,12,'z')
        g.sphere(a,'lamp',(x,6.18,30.23),.09,8,4)


def afterglow(a):
    # Continuous long slab and stepped terraces: emphatically horizontal.
    mass(a,'Observation hotel',(0,19.3,-7),(51,37.4,29),'stone')
    ribbons(a,0,-7,51,29,13,35,4,2.25)
    # Lower guest floors: rear band and the side bays behind the podium.
    for y in (4.6,8.6):
        box(a,'glass',(0,y,-21.57),(49,2.25,.12))
        for i in range(1,12):box(a,'stone',(-25.5+i*4,y,-21.65),(.16,2.45,.18))
        box(a,'stone',(0,y-1.445,-21.6),(51.3,.36,.35))
        for side in (-1,1):
            box(a,'glass',(side*25.57,y,-10),(.12,2.25,21))
            box(a,'stone',(side*25.6,y-1.445,-10),(.35,.36,21.3))
    # Broad blank end piers and emphatic brow give bunker-era concrete weight.
    for side in (-1,1):
        for z in (-19.5,5.5):box(a,'ceiling',(side*25.2,18.77,z),(1.7,37.47,1.7))
    roof(a,0,-7,51,29,38,'stone',1)
    mass(a,'Observation lounge',(0,40.235,-9),(32,4.23,16),'stone')
    for side in (-1,1):
        box(a,'glass',(0,40.8,-9+side*8.07),(29.5,2.4,.14))
        box(a,'glass',(side*16.07,40.8,-9),(.14,2.4,13.5))
    ledge(a,0,-9,32,16,42.5,'ceiling',.45,2)
    # Open rail terrace wraps lounge on all sides, on an actual accessible-scale deck.
    for z in (-20.5,6.5):
        rod(a,'metal',(-24,39.3,z),(24,39.3,z),.065)
        for x in range(-24,25,3):rod(a,'metal',(x,38.12,z),(x,39.3,z),.045)
    for x in (-24,24):
        rod(a,'metal',(x,39.3,-20.5),(x,39.3,6.5),.065)
        for z in range(-17,6,3):rod(a,'metal',(x,38.12,z),(x,39.3,z),.045)
    # Open sunburst with an orange half-disc; edge-on fins remain visible obliquely.
    points=[(-8.5,43.5),(8.5,43.5)]+[(8.5*math.cos(t),43.5+8.5*math.sin(t)) for t in [i*math.pi/32 for i in range(33)]]
    facade_polygon(a,'metal',points,-8,.65)
    g.torus(a,'ceiling',(0,43.5,-7.57),8.6,.16,48,6,'z',arc=math.pi,start=math.pi)
    for i in range(11):
        q=(i+.5)*math.pi/11
        p=(math.cos(q)*8.6,43.5+math.sin(q)*8.6,-7.5)
        tip=(math.cos(q)*(13 if i%2 else 15),43.5+math.sin(q)*(13 if i%2 else 15),-7.5)
        rod(a,'metal',p,tip,.17)
    for x in (-5,5):rod(a,'metal',(x,42.7,-8),(x,44,-8),.16)
    mass(a,'Low casino podium',(0,5.4,12),(53,9.6,20),'stone')
    for x in range(-23,24,4):
        window(a,x,5.1,22.04,2.8,5.9,'front')
        box(a,'ceiling',(x-1.7,5.4,22.45),(.35,8.4,1))
    for side in (-1,1):
        for z in (5,11,17):window(a,side*26.55,5.1,z,3.2,5.9,'right' if side>0 else 'left')
    roof(a,0,12,53,20,10.3,'stone',.65)
    ledge(a,0,12,53,20,9.4,'glass',.18,.9)
    for x in (-18,18):
        box(a,'ceiling',(x,11.9,14),(10,.28,7))
        for dx in (-4,4):rod(a,'metal',(x+dx,10.42,14),(x+dx,11.8,14),.08)
    entrance(a)


def last(a):
    # Chamfered glass tower, with bronze mullions and an independent solid core.
    poly=[(-9,-21),(12,-21),(17,-16),(17,4),(12,9),(-9,9),(-14,4),(-14,-16)]
    g.prism(a,'glass',poly,.6,69)
    a.collider('Glass hotel core',(1.5,34.8,-6),(31,68.4,30))
    box(a,'stone',(1.5,.3,-6),(31,.6,30));a.collider('Hotel foundation',(1.5,.3,-6),(31,.6,30))
    for p,q in zip(poly,poly[1:]+poly[:1]):
        for y in range(7,69,4):rod(a,'metal',(p[0],y,p[1]),(q[0],y,q[1]),.09)
        length=math.hypot(q[0]-p[0],q[1]-p[1]);count=max(1,int(length/4))
        for i in range(count+1):
            t=i/count;x=p[0]+(q[0]-p[0])*t;z=p[1]+(q[1]-p[1])*t
            rod(a,'stone',(x,1,z),(x,69,z),.15)
    g.prism(a,'stone',poly,69,70)
    g.prism(a,'roof',[(x*.9+.15,z*.9-.6) for x,z in poly],70,70.12)
    # Bank reads as heavy historic masonry, with paired piers and deep arcades.
    mass(a,'Historic bank',(-4,12.3,12),(43,23.4,20),'stone')
    for y in (1.3,3.0,13.4,22.6,24.1):ledge(a,-4,12,43,20,y,'stone',.55,.65)
    for x in (-22,-16,-10,-4,2,8,14):
        arch_window(a,x,7.8,22.13,3.5,8.6)
        window(a,x,18.2,22.09,2.8,5,'front')
        for dx in (-2.1,2.1):box(a,'ceiling',(x+dx,11.95,22.25),(.48,20.75,.55))
    for side,xx in [('left',-25.55),('right',17.55)]:
        for z in (5,11,17):
            window(a,xx,7.7,z,3.2,7,side)
            window(a,xx,18.2,z,2.8,5,side)
    for x in (-21,-14,-7,0,7,14):window(a,x,17.8,1.94,2.8,5,'back')
    roof(a,-4,12,43,20,24.2,'stone',1.2)
    for x in range(-24,18,2):box(a,'stone',(x,24.1,22.8),(.62,.8,.65))
    # Local stone scars are sparse and deterministic, not an all-over stripe texture.
    for x,y,w in [(-25,20,.65),(-19,11,.9),(-13,21,.75),(-7,16,.8),(-1,11,.7),(5,21,.9),(17,16,.55)]:
        facade_polygon(a,'wall',[(x-w/2,y-.3),(x+w/2,y-.22),(x+w*.4,y+.1),(x,y+.24),(x-w*.4,y+.06)],22.025,.04)
    # Bottle-glass side annex has green bottle ends in masonry mortar.
    mass(a,'Bottle glass annex',(-27,5.3,7),(5,9.4,20),'stone')
    for y in range(2,10,2):
        for z in range(-1,17,2):g.cylinder(a,'glass',(-29.56,y,z),.45,.18,10,'x')
    ledge(a,-27,7,5,20,10.2,'metal',.2,.35)
    # Diamond has an open brass perimeter, rather than a coin pasted to the roof.
    center=(1.5,76,-6)
    points=[(1.5,82,-6),(6,76,-6),(1.5,70,-6),(-3,76,-6)]
    for p,q in zip(points,points[1:]+points[:1]):rod(a,'metal',p,q,.35)
    facade_polygon(a,'glass',[(1.5,81.6),(5.6,76),(1.5,70.4),(-2.6,76)],-6,.3)
    rod(a,'metal',(1.5,76,-5.8),(1.5,80,-5.8),.09)
    entrance(a)
    ledge(a,0,23,15,10,6.6,'stone',.35,.35)


def sail(a,corners,sag=3):
    """Tensioned fabric with a curved perimeter and sewn panel seams."""
    n=12
    def point(u,v):
        p=Vector(corners[0])*(1-u)*(1-v)+Vector(corners[1])*u*(1-v)+Vector(corners[2])*u*v+Vector(corners[3])*(1-u)*v
        # Edge midpoint retreats into fabric; corners remain anchored exactly.
        center=sum((Vector(c) for c in corners),Vector())/4
        retreat=.08*(math.sin(math.pi*u)+math.sin(math.pi*v))
        p.x+=(center.x-p.x)*retreat;p.z+=(center.z-p.z)*retreat
        p.y-=sag*math.sin(math.pi*u)*math.sin(math.pi*v)
        return tuple(p)
    verts=[point(i/n,j/n) for j in range(n+1) for i in range(n+1)]
    faces=[]
    for j in range(n):
        for i in range(n):
            k=j*(n+1)+i
            faces.extend([(k,k+1,k+n+2),(k,k+n+2,k+n+1)])
    # Real fabric thickness avoids coincident opposite faces: recalculated
    # normals and both native renderers require distinct upper/lower vertices.
    count=len(verts)
    fabric=verts+[(x,y-.045,z) for x,y,z in verts]
    shell=faces+[(c+count,b+count,aa+count) for aa,b,c in faces]
    boundary=list(range(n+1))+[j*(n+1)+n for j in range(1,n+1)]+[n*(n+1)+i for i in range(n-1,-1,-1)]+[j*(n+1) for j in range(n-1,0,-1)]
    for p,q in zip(boundary,boundary[1:]+boundary[:1]):shell.append((p,p+count,q+count,q))
    a.add('ceiling',fabric,shell,True)
    for edge in range(4):
        pts=[point(i/n,0) if edge==0 else point(1,i/n) if edge==1 else point(1-i/n,1) if edge==2 else point(0,1-i/n) for i in range(n+1)]
        for p,q in zip(pts,pts[1:]):rod(a,'metal',p,q,.07)
    for u in (.25,.5,.75):
        pts=[point(u,j/n) for j in range(n+1)]
        for p,q in zip(pts,pts[1:]):rod(a,'stone',p,q,.025)


def dust_stack(a,x,z,w,d,bottom,top,offset=0):
    mass(a,'Rust hotel stack',(x,(bottom+top)/2,z),(w,top-bottom,d),'stone')
    for side in (-1,1):
        # The top row keeps its frame clear of the roof parapet.
        for iy,y in enumerate(range(int(bottom+3),int(top-1.6),4)):
            # Clustered windows and solid rust panels vary by floor without noise.
            for i in range(int((w-2)/3)):
                xx=x-w/2+2.3+i*3
                if (i+iy+offset)%5==0:continue
                window(a,xx,y,z+side*(d/2+.06),1.65,2.5,'front' if side>0 else 'back','glass','wood')
            for i in range(int((d-2)/4)):
                zz=z-d/2+2.6+i*4
                window(a,x+side*(w/2+.06),y,zz,2,2.5,'right' if side>0 else 'left','glass','wood')
        low=.035 if bottom<=.6 else bottom
        for xx in (-w/2+.4,w/2-.4):box(a,'metal',(x+xx,(top+low)/2,z+side*(d/2+.12)),(.3,top-low,.25))
    roof(a,x,z,w,d,top,'metal',.6)
    # Belt courses sit midway between window rows (rows start at int(bottom+3), 4 m apart).
    for y in range(int(bottom+3)+6,int(top)-1,12):ledge(a,x,z,w,d,y,'wood',.2,.2)


def dust(a):
    # Offset modular stacks with genuine setbacks, asymmetry and visible roof decks.
    dust_stack(a,-20,-12,16,19,.6,48,0)
    dust_stack(a,-18,-13,13,16,48,62,1)
    dust_stack(a,20,-10,16,22,.6,57,2)
    dust_stack(a,21,-12,12,17,57,68,0)
    dust_stack(a,-20,13,15,18,.6,32,3)
    dust_stack(a,21,14,14,17,.6,38,1)
    for x,z,h,top in [(-12.2,-14,62,66),(15.2,-14,68,72),(-13,14,32,38),(14.5,14,38,44)]:
        rod(a,'metal',(x,h,z),(x,top,z),.15)
    # Two overlapping sails articulate the courtyard instead of one white plane.
    sail(a,[(-11.2,64,-14),(11.4,70,-14),(11.7,43,14),(-11.7,37,14)],4.5)
    sail(a,[(-11.7,35,13),(11.7,41,13),(12,15,23.5),(-12,19,23.5)],2.5)
    for p,q in [((-12.2,66,-14),(-11.2,64,-14)),((15.2,72,-14),(11.4,70,-14)),((-13,38,14),(-11.7,37,14)),((14.5,44,14),(11.7,43,14)),((-13,36,14),(-11.7,35,13)),((14.5,42,14),(11.7,41,13)),((-13,19,21.5),(-12,19,23.5)),((14.5,15,21.5),(12,15,23.5))]:
        rod(a,'metal',p,q,.075)
    # Freestanding original open prism: emphatic violet body with contrasting rods.
    ring=[]
    for y,r,phase in [(9,3,0),(16,4,math.pi/4),(23,2,0)]:
        pts=[(r*math.cos(phase+i*math.pi/2),y,27+r*math.sin(phase+i*math.pi/2)) for i in range(4)]
        for p,q in zip(pts,pts[1:]+pts[:1]):rod(a,'metal',p,q,.18)
        ring.append(pts)
    for lower,upper in zip(ring,ring[1:]):
        for p,q in zip(lower,upper):rod(a,'glass',p,q,.36)
    # Mast stands on the canopy; every ring is braced back to it by spokes.
    rod(a,'metal',(0,5.97,27),(0,24,27),.16)
    for pts in ring:
        for p in pts:rod(a,'metal',(0,p[1],27),p,.08)
    mass(a,'Courtyard salon',(0,4.3,16),(23,7.4,11),'wood')
    for x in (-8,-4,4,8):window(a,x,4.2,21.57,2.7,4.4,'front','glass','metal')
    roof(a,0,16,23,11,8,'metal',.55)
    entrance(a,'dust')
    # Art car is an inhabited-looking whimsical chassis with a sculptural canopy.
    # Wheels rest on the plaza; the chassis rides on them.
    mass(a,'Art car plinth',(-18,1.55,26),(8,1.1,4),'wood')
    for x in (-20.5,-15.5):
        for z in (24.1,27.9):
            g.cylinder(a,'rubber',(x,.86,z),.82,.36,16,'z')
            g.cylinder(a,'metal',(x,.86,z+(.2 if z>26 else -.2)),.38,.05,12,'z')
    for x in (-21,-15):rod(a,'metal',(x,2.1,26),(x,5.15,26),.1)
    sail(a,[(-22,5.5,24),(-14,4.5,24),(-14,5.5,28),(-22,4.5,28)],.2)
    g.sphere(a,'glass',(-18,5,26),.7,12,6)

def validate_sail_clearance(asset):
    """Catch fabric passing through its opaque hotel volumes before packaging."""
    verts,faces,_=asset.parts.get('ceiling',([],[],[]))
    samples=list(verts)
    samples.extend(sum((verts[i] for i in face),Vector())/len(face) for face in faces)
    for name,volume,_ in asset.colliders:
        if not name.startswith('Rust hotel stack'):continue
        lo=Vector(tuple(min(v[i] for v in volume) for i in range(3)))
        hi=Vector(tuple(max(v[i] for v in volume) for i in range(3)))
        for p in samples:
            assert not all(lo[i]+.02<p[i]<hi[i]-.02 for i in range(3)), ('Sail intersects hotel',name,tuple(p))


BUILDERS = dict(fix=fix,alibi=alibi,velvet=velvet,afterglow=afterglow,last=last,dust=dust)

def visible_triangles(path):
    data=path.read_bytes()
    length,kind=struct.unpack_from('<II',data,12)
    assert kind==0x4e4f534a
    doc=json.loads(data[20:20+length])
    def count(index):
        node=doc['nodes'][index]
        if node.get('name','').endswith('-colonly'):return 0
        total=0
        if 'mesh' in node:
            for primitive in doc['meshes'][node['mesh']]['primitives']:
                assert primitive.get('mode',4)==4
                accessor=primitive.get('indices',primitive['attributes']['POSITION'])
                total+=doc['accessors'][accessor]['count']//3
        return total+sum(count(child) for child in node.get('children',[]))
    return sum(count(index) for index in doc['scenes'][doc.get('scene',0)]['nodes'])

TEXTURES = ROOT/'assets/six-resorts/textures'
TEXTURE_META = {}
GRAVEL, TERRAZZO = ('gravel-roof', 4.0), ('terrazzo-paving', 8.0)
# Each resort's own facade swatch, scaled in metres per repeat. Glass, metal,
# lamps, signs and fabric keep plain authored finishes.
SURFACES = {
    'fix': dict(wood=('granite', 6.0), stone=('granite', 4.0), floor=TERRAZZO, roof=GRAVEL),
    'alibi': dict(stone=('scored-stucco', 4.0), ceiling=('granite', 3.0), floor=TERRAZZO, roof=GRAVEL),
    'velvet': dict(stone=('brick', 2.4), carpet=('brick', 2.4), floor=TERRAZZO, roof=GRAVEL),
    'afterglow': dict(stone=('board-formed-concrete', 4.0), ceiling=('board-formed-concrete', 4.0),
                      floor=TERRAZZO, roof=GRAVEL),
    'last': dict(stone=('rusticated-sandstone', 3.0), ceiling=('granite', 3.0), floor=TERRAZZO, roof=GRAVEL),
    'dust': dict(stone=('corrugated-steel', 3.0), wood=('corrugated-steel', 3.0), floor=TERRAZZO, roof=GRAVEL),
}
JPEG_SIDECAR = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def surface_material(finish, name, period):
    """Texture x authored palette (linear), the shared building-material contract."""
    original = g.MATS[finish]
    mat = original.copy(); mat.name = '%s • %s' % (finish, name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes['Principled BSDF']
    base = tuple(shader.inputs['Base Color'].default_value)
    mean = TEXTURE_META[name+'.png']['mean_linear']
    factor = tuple(min(1.0, base[i]/mean[i]) for i in range(3)) + (1.0,)
    image = bpy.data.images.load(str(TEXTURES/(name+'.png')), check_existing=True)
    tex = nodes.new('ShaderNodeTexImage'); tex.image = image
    # Masters already hold a mirrored 2 x 2 tile; plain repeat imports as
    # texture_repeat in Godot (mirrored wrap would be clamped).
    tex.extension = 'REPEAT'; tex.interpolation = 'Linear'
    mix = nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'
    mix.inputs[0].default_value = 1.0; mix.inputs[7].default_value = factor
    links.new(tex.outputs['Color'], mix.inputs[6]); links.new(mix.outputs[2], shader.inputs['Base Color'])
    mat['surface_texture'] = name; mat['meters_per_repeat'] = period
    return mat


def apply_surfaces(theme, objects):
    """Assign each mapped finish its swatch with world-metre box-projected UVs."""
    if not TEXTURE_META:
        TEXTURE_META.update({r['file']: r for r in json.loads((TEXTURES/'manifest.json').read_text())['textures']})
    mapping = SURFACES[theme['slug']]
    for obj in objects:
        finish = obj.name.removeprefix(theme['slug']+' ')
        if obj.type != 'MESH' or finish not in mapping: continue
        name, period = mapping[finish]
        obj.data.materials[0] = surface_material(finish, name, period)
        uv = obj.data.uv_layers.new(name='SurfaceUV')
        for poly in obj.data.polygons:
            axis = max(range(3), key=lambda k: abs(poly.normal[k]))
            for index in poly.loop_indices:
                v = obj.data.vertices[obj.data.loops[index].vertex_index].co
                # Blender Z is up: vertical faces keep courses horizontal.
                a_, b_ = (v.y, v.z) if axis == 0 else (v.x, v.z) if axis == 1 else (v.x, v.y)
                tile = period*TEXTURE_META[name+'.png'].get('periods', 1)
                uv.data[index].uv = (a_/tile, b_/tile)


def share_images(path):
    """Move the GLB's embedded swatches to content-addressed surfaces/ images."""
    raw = path.read_bytes()
    n = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20+n]); binary = raw[28+n:]
    records = []
    for image in doc.get('images', []):
        view = doc['bufferViews'][image.pop('bufferView')]
        data = binary[view.get('byteOffset', 0):view.get('byteOffset', 0)+view['byteLength']]
        assert image['mimeType'] == 'image/jpeg'
        digest = hashlib.sha256(data).hexdigest()
        image['uri'] = 'surfaces/%s.jpg' % digest
        target = DEST/image['uri']; target.parent.mkdir(exist_ok=True)
        if not target.exists(): target.write_bytes(data)
        assert target.read_bytes() == data
        sidecar = target.with_suffix('.jpg.import')
        if not sidecar.exists(): sidecar.write_text(JPEG_SIDECAR)
        records.append({'path': image['uri'], 'sha256': digest, 'bytes': len(data), 'source_name': image.get('name', '')})
    used = set()
    def collect(value):
        if isinstance(value, dict):
            for k, v in value.items():
                if k == 'bufferView': used.add(v)
                else: collect(v)
        elif isinstance(value, list):
            for v in value: collect(v)
    collect({k: v for k, v in doc.items() if k not in ('bufferViews', 'buffers')})
    packed = bytearray(); views = []; remap = {}
    for old in sorted(used):
        view = dict(doc['bufferViews'][old]); offset = view.get('byteOffset', 0)
        while len(packed) % 4: packed.append(0)
        view['byteOffset'] = len(packed); packed.extend(binary[offset:offset+view['byteLength']])
        remap[old] = len(views); views.append(view)
    def renumber(value):
        if isinstance(value, dict):
            for k, v in value.items():
                if k == 'bufferView': value[k] = remap[v]
                else: renumber(v)
        elif isinstance(value, list):
            for v in value: renumber(v)
    for k in list(doc):
        if k not in ('bufferViews', 'buffers'): renumber(doc[k])
    doc['bufferViews'] = views
    while len(packed) % 4: packed.append(0)
    doc['buffers'] = [{'byteLength': len(packed)}]
    encoded = json.dumps(doc, separators=(',', ':'), ensure_ascii=False).encode()
    encoded += b' '*((-len(encoded)) % 4)
    size = 12+8+len(encoded)+8+len(packed)
    path.write_bytes(struct.pack('<III', 0x46546c67, 2, size)+struct.pack('<II', len(encoded), 0x4e4f534a)
                     + encoded+struct.pack('<II', len(packed), 0x004e4942)+bytes(packed))
    return records


def record_shared_images(records):
    manifest = ROOT/'docs/art/building-materials.json'
    data = json.loads(manifest.read_text())
    known = {row['path'] for row in data['textures']}
    data['textures'].extend(r for r in records if r['path'] not in known)
    manifest.write_text(json.dumps(data, indent=2)+'\n')


def exterior_materials(theme):
    palette=dict(theme['palette'])
    overrides={
        'fix':dict(stone='303c35',wood='403a33',glass='27684f',ink='111c18'),
        'alibi':dict(stone='dcb3a7',glass='699e88',wood='76594d'),
        'velvet':dict(stone='752a36',carpet='481d2d',glass='ac8053ff',wood='211c25',lamp='eab879'),
        'afterglow':dict(stone='ddd0ac',glass='79aa91',wood='60594a',metal='cb8144ff'),
        'last':dict(stone='b99b73',glass='368f91',wood='514335'),
        'dust':dict(stone='a76143ff',metal='76442f',glass='74608c',wood='4b3830'),
    }
    palette.update(overrides[theme['slug']])
    if 'roof' in g.FINISHES: g.FINISHES.remove('roof')
    # Previous resorts' derived materials would otherwise force .001 name suffixes.
    for mat in list(bpy.data.materials):
        if not mat.name.startswith('resort_') or mat.name == 'resort_roof': bpy.data.materials.remove(mat)
    g.materials(palette)
    # Gravel-ballast roof membrane is its own finish, tinted with the palette's dark trim.
    roof = g.MATS['wood'].copy(); roof.name = 'resort_roof'; g.MATS['roof'] = roof
    g.FINISHES.append('roof')
    # Sunlit glass should retain its color; signs remain warm without bleaching.
    for finish in ('lamp','screen'):
        g.MATS[finish].node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value=.35
    if theme['slug']=='last':
        g.MATS['wall'].diffuse_color=(.26,.19,.11,1)
        g.MATS['wall'].node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.26,.19,.11,1)
    if theme['slug']=='velvet':
        g.MATS['floor'].diffuse_color=(.11,.075,.065,1)
        g.MATS['floor'].node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.11,.075,.065,1)


def build(slug,asset=None):
    a=asset or ExteriorAsset(slug);base(a);BUILDERS[slug](a);flush_windows(a)
    if slug=='dust':validate_sail_clearance(a)
    return a


def export(theme):
    a=build(theme['slug'])
    g.reset(); exterior_materials(theme);visible=g.make_objects(a);apply_surfaces(theme,visible)
    objects=visible+g.make_colliders(a)
    # Readable original signage is geometry, attached to a front fascia.
    text=bpy.data.curves.new(theme['name'],'FONT');text.body=theme['name'].upper()
    text.align_x='CENTER';text.size=.55;text.extrude=.01
    o=bpy.data.objects.new('Original resort lettering',text);bpy.context.scene.collection.objects.link(o)
    o.location=g.TO_BLENDER@Vector((0,5.52,30.23));o.rotation_euler=(math.pi/2,0,0)
    text.materials.append(g.MATS['lamp']);bpy.context.view_layer.update()
    if o.dimensions.x>13:o.scale*=13/o.dimensions.x
    bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH')
    # Bake the placement into the vertices: like every other visible part it then
    # exports with an identity node, so the runtime compiler merges it into the
    # building's surfaces and opaque shadow proxy instead of a separate caster.
    letters=bpy.context.object;bpy.context.view_layer.update()
    letters.data.transform(letters.matrix_world);letters.matrix_world=Matrix.Identity(4)
    objects.append(letters)
    SOURCE.mkdir(parents=True,exist_ok=True);DEST.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    # Masters reference the swatches relative to assets/six-resorts/exteriors/.
    for image in bpy.data.images:
        if image.filepath and Path(bpy.path.abspath(image.filepath)).parent == TEXTURES:
            image.filepath = '//../textures/' + Path(bpy.path.abspath(image.filepath)).name
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(theme['slug']+'.blend')),relative_remap=True)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.select_set(True)
    path=DEST/('%d-blender.glb'%theme['code'])
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,
        export_materials='EXPORT',export_cameras=False,export_lights=False,export_extras=False,
        export_image_format='JPEG',export_jpeg_quality=90)
    record_shared_images(share_images(path))
    coords=[v for vs,_,_ in a.parts.values() for v in vs]
    high=max(v.y for v in coords)
    assert min(v.y for v in coords)>=0 and all(abs(v.x)<=32 and abs(v.z)<=32 for v in coords)
    triangles=visible_triangles(path)
    assert triangles<40000
    sidecar=DEST/(path.name+'.import')
    if not sidecar.exists():sidecar.write_text(g.SIDECAR.replace('{path}','res://assets/desert-dreams-3d/'+path.name))
    return {'code':theme['code'],'path':'res://assets/desert-dreams-3d/'+path.name,'scale':.0625,'pivot':[0,0,0],
        'yaw':0,'height':high/16,'footprint':[4,4],'triangles':triangles,'source_kind':'authored_blender',
        'glb_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'meters_per_tile':16}

def main():
    catalog_path=DEST/'catalog.json';catalog=json.loads(catalog_path.read_text())
    entries={e['code']:e for e in catalog['entries']}
    for theme in THEMES:
        entries[theme['code']]=export(theme);print('SIX_RESORT_EXTERIOR',theme['code'],entries[theme['code']]['triangles'])
    catalog['entries']=[entries[c] for c in sorted(entries)]
    catalog_path.write_text(json.dumps(catalog,indent=2)+'\n')
if __name__=='__main__':main()
