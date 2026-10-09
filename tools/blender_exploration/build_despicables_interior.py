# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build Despicable's 12 x 10 m half-store, half-casino hall with the resort kit.
Run Blender --background --python tools/blender_exploration/build_despicables_interior.py
The six playable machines are placed by despicables_interior_layout.gd.
"""
import sys, json, math
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_resort_interiors as kit
from build_resort_interiors import Asset,box,cylinder,lathe

FIXTURES=[('grocery aisle west',(-4.3,-.7),(.35,2.1),1.65),
          ('grocery aisle east',(-2.2,-.7),(.35,2.1),1.65),
          ('drink coolers',(-3,-4.6),(2.5,.35),2.0),
          ('checkout',(-3.4,3.4),(1.35,.6),1.05),
          ('coffee counter',(-5.55,2),(.35,.6),1.0)]

def shelves(a,x,z):
    box(a,'wood',(x,.06,z),(.7,.12,4.2))
    for side in (-1,1):
        box(a,'metal',(x, .85,z+side*2.02),(.7,1.7,.07))
    box(a,'sign',(x,.86,z),(.025,1.6,4.1))
    for row in range(4):
        y=.28+row*.38
        box(a,'stone',(x,y,z),(.7,.06,4.1))
        for side in (-1,1):
            box(a,'carpet',(x+side*.345,y+.045,z),(.035,.065,4.1))
            for i in range(14):
                zz=z-1.85+i*.28
                finish=['glass','carpet','stone','felt','wood'][i%5]
                if (i+row)%3==0:
                    cylinder(a,finish,(x+side*.19,y+.145,zz),.075,.20,8)
                    cylinder(a,'metal',(x+side*.19,y+.25,zz),.076,.012,8)
                else:
                    box(a,finish,(x+side*.19,y+.16,zz),(.20,.24,.19))
                    box(a,'stone',(x+side*.305,y+.16,zz),(.012,.075,.12))


def hall():
    a=Asset('hall_126')
    # Exactly half cream store tile, half coral casino carpet, no raised divider.
    for finish,x in [('floor',-3),('carpet',3)]:
        box(a,finish,(x,-.06,0),(6,.12,10))
        a.collider(finish+' floor',(x,-.10,0),(6,.2,10))
    box(a,'metal',(0,.002,0),(.035,.004,10))
    box(a,'ceiling',(0,3.28,0),(12.4,.16,10.4))
    a.collider('ceiling',(0,3.28,0),(12.4,.16,10.4))
    for name,center,size in [('west wall',(-6.1,1.6,0),(.2,3.2,10.4)),
                             ('east wall',(6.1,1.6,0),(.2,3.2,10.4)),
                             ('back wall',(0,1.6,-5.1),(12,3.2,.2))]:
        box(a,'wall',center,size);a.collider(name,center,size)
    for side in (-1,1):
        center=(side*3.4,1.6,5.1); size=(5.2,3.2,.2)
        box(a,'wall',center,size);a.collider('front wall',center,size)
        box(a,'metal',(side*.82,1.1,5.0),(.05,2.2,.05))
    box(a,'wall',(0,2.7,5.1),(1.6,1.0,.2));a.collider('door lintel',(0,2.7,5.1),(1.6,1.0,.2))
    # A closed physical door keeps the walker in the pocket until Interact exits.
    box(a,'glass',(0,1.1,5.02),(1.6,2.2,.06))
    a.collider('Street doors',(0,1.1,5.04),(1.6,2.2,.08))
    for x in (-.08,.08):
        box(a,'metal',(x,1.1,4.97),(.025,.32,.035))
    # Keep the interior approach and exit mat unobstructed.
    box(a,'rubber',(0,.003,4.2),(1.4,.006,1.2))
    for x in (-6.0,6.0):
        box(a,'glass',(x,.6,0),(.025,1.2,10))
        box(a,'metal',(x,1.21,0),(.03,.025,10))
    box(a,'glass',(0,.6,-4.99),(12,1.2,.025))
    for name,(x,z),(hx,hz),height in FIXTURES:
        a.collider(name,(x,height/2,z),(hx*2,height,hz*2))
        if name.startswith('grocery'):
            shelves(a,x,z)
        elif name=='drink coolers':
            box(a,'metal',(x,1,z),(5,2,.7))
            for i in range(5):
                xx=x-2+i
                box(a,'glass',(xx,1.05,z+.36),(.91,1.65,.025))
                box(a,'metal',(xx+.43,1.05,z+.395),(.035,1.73,.045))
                box(a,'metal',(xx+.32,1.05,z+.415),(.025,.45,.025))
                for row in range(3):
                    yy=.48+row*.47
                    box(a,'stone',(xx,yy,z+.38),(.83,.025,.02))
                    for k in range(4):
                        cx=xx-.30+k*.20
                        cylinder(a,'carpet' if (k+row)%2 else 'felt',(cx,yy+.14,z+.40),.065,.23,8)
                        cylinder(a,'metal',(cx,yy+.255,z+.40),.025,.035,8)
        else:
            box(a,'wood',(x,height*.48,z),(hx*2,height*.96,hz*2))
            box(a,'stone',(x,height,z),(hx*2+.03,.08,hz*2+.03))
            if name=='checkout':
                box(a,'sign',(x-.35,1.16,z),(.48,.20,.42))
                box(a,'metal',(x-.35,1.40,z-.1),(.42,.30,.12))
                box(a,'glass',(x-.35,1.42,z-.035),(.34,.17,.015))
                for i in range(4):
                    for j in range(3):box(a,'stone',(x-.49+i*.085,1.268,z+.07+j*.055),(.05,.015,.035))
                for k in range(3):
                    box(a,'wood',(x+.42+k*.23,1.23,z+.04),(.19,.34,.25))
                    box(a,'carpet',(x+.42+k*.23,1.39,z+.04),(.19,.04,.25))
            else:
                box(a,'sign',(x,1.28,z-.15),(.43,.48,.42))
                cylinder(a,'glass',(x+.04,1.2,z+.23),.12,.19,12)
                cylinder(a,'metal',(x+.04,1.31,z+.23),.14,.025,12)
                for k in range(3):cylinder(a,'stone',(x-.12,1.1+k*.06,z+.45),.065,.09,8)
    # Slim ceiling fixtures, warm store fluorescents and amber gaming lights.
    for x in (-3,3):
        for z in (-2.5,2.5):
            box(a,'metal',(x,3.12,z),(1.7,.10,.48))
            box(a,'lamp',(x,3.05,z),(1.5,.025,.34))
    # Ink panels behind runtime lettering; framed ads above walking height.
    for x,y,z,w,h in [(-3,2.8,-4.82,4.8,.5),(-3,2.25,-4.20,4,.3),
                      (3,2.8,-4.82,4.5,.42),(3,2.25,-4.82,4.5,.32)]:
        box(a,'sign',(x,y,z),(w+.10,h+.06,.03))
    for center,size,yaw in [((-3,2.08,4.82),(1.9,1.9,.06),math.pi),
                            ((-5.82,2.08,-2),(1.6,1.6,.06),math.pi/2),
                            ((2.1,2.08,4.82),(1.9,1.9,.06),math.pi)]:
        box(a,'metal',center,size,yaw)
    return a

if __name__=='__main__':
    kit.bpy.context.preferences.filepaths.save_version=0
    entry=kit.export(hall())
    path=kit.EXPORT/'catalog.json'; catalog=json.loads(path.read_text())
    catalog['models']['hall_126']=entry
    catalog.setdefault('stores',{})['126']={'model':'hall_126','venue':'com_corner_store',
        'generator':'tools/blender_exploration/build_despicables_interior.py','floor_area_m2':120,
        'retail_area_m2':60,'gaming_area_m2':60,'slots':4,'video_poker':2}
    catalog['models']=dict(sorted(catalog['models'].items()))
    path.write_text(json.dumps(catalog,indent=2)+'\n')
    print('Despicables interior:',entry['triangles'],'triangles;',entry['colliders'],'shells')
