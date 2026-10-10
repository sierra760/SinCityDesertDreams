# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Original six casino halls, sharing the validated walkable floor program.

Blender --background --factory-startup --python tools/blender_exploration/build_six_resort_halls.py
Only new halls are exported; original halls and prop kit are never rebuilt.
"""
import sys, math, json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_resort_interiors as g
ROOT=Path(__file__).resolve().parents[2]
g.SIGNATURE_PROPS.update({'vault_circuit': 'vault_table', 'alibi_route': 'route_table', 'velvet_encore': 'encore_table', 'afterglow_forecast': 'forecast_console', 'last_bank': 'contract_table', 'dust_pool': 'common_pot_table'})
THEMES=json.loads((ROOT/'tools/resort_expansion.json').read_text())['resorts']

def ring(a,c,r,t=.15,f='metal',axis='y'):
    g.torus(a,f,c,r,t,40,6,axis)
def rod(a,p,q,f='metal',r=.055):g.rod(a,f,p,q,r,8)

def columns(a,slug):
    for x,z in g.COLUMNS:
        g.column_square(a,x,z,'wood' if slug in ('fix','velvet') else 'stone')
        # All four supports keep the exact shared 1.2m collision footprint.
        a.collider('Column',(x,g.CEILING/2,z),(1.2,g.CEILING,1.2))

def decoration(a,slug):
    g.flat_ceiling(a);g.cornice(a,((10.6,.3,.4),(10.2,.35,.35)))
    g.wall_bands(a,'wood',.6,1.2,.06,True)
    g.wall_bands(a,'metal',1.23,.07,.08,True)
    g.wall_bands(a,'metal',9.4,.12,.06)
    columns(a,slug)
    if slug=='fix':
        g.coffers(a,4,.24,.3)
        # Vault-like suspended canopy over the pit: concentric rings and brass bolts.
        for r in (3,4.5,6):ring(a,(0,8.2,2),r,.18)
        for i in range(16):
            t=i*math.tau/16
            rod(a,(3*math.cos(t),8.2,2+3*math.sin(t)),(6*math.cos(t),8.2,2+6*math.sin(t)),r=.085)
            g.sphere(a,'lamp',(5.5*math.cos(t),8.2,2+5.5*math.sin(t)),.13,8,4)
        for z in range(-18,19,4):
            g.box(a,'metal',(21.7,5.2,z),(.14,6,.12))
            g.box(a,'glass',(21.76,7,z),(.08,2.6,2.8))
    elif slug=='alibi':
        g.coffers(a,5,.18,.2)
        # Two intertwined wedding rings, floating above the gaming pit.
        for x in (-2.1,2.1):ring(a,(x,8.8,2),3.8,.25)
        for z in (-17,-9,-1,7,15):
            for side in (-1,1):
                ring(a,(side*21.8,7.7,z),1.15,.1,axis='x')
                g.box(a,'glass',(side*21.84,6.7,z),(.04,3,2.5))
        g.wall_bands(a,'glass',8.8,.35,.04)
    elif slug=='velvet':
        # Scalloped theatrical valances remain well above walking and paintings.
        for side in (-1,1):
            for z in range(-18,19,3):
                if side==-1 and abs(z+12)<4:continue  # Full framed painting and lamp clearance.
                g.box(a,'carpet',(side*21.7,9.4,z),(.35,2.1,2.85))
                g.sphere(a,'carpet',(side*21.6,8.5,z),.68,12,6)
                g.sphere(a,'lamp',(side*21.3,8.4,z),.09,8,4)
        ring(a,(0,8.8,2),4.3,.25)
        # Keyhole outline, flat on the ceiling and readable on approach.
        ring(a,(0,10.35,-9),2,.18)
        for x in (-.65,.65):rod(a,(x,10.35,-8),(x,10.35,-4),r=.16)
        rod(a,(-.65,10.35,-4),(.65,10.35,-4),r=.16)
        for x in range(-18,19,6):g.box(a,'metal',(x,10.6,0),(.12,.15,40))
    elif slug=='afterglow':
        # Broad radial canopy, cocktail bubbles, optimistic atomic-age geometry.
        for i in range(24):
            t=i*math.tau/24
            rod(a,(1.8*math.cos(t),9.2,2+1.8*math.sin(t)),(7.8*math.cos(t),9.2,2+7.8*math.sin(t)),r=.09)
            g.sphere(a,'lamp',(7.8*math.cos(t),9.2,2+7.8*math.sin(t)),.2,10,5)
        for x in (-2,0,2):ring(a,(x,9.5,-12),2.2,.08,f='glass',axis='z')
        for z in range(-18,19,6):
            g.box(a,'glass',(21.7,6.5,z),(.05,4.3,4.8))
            ring(a,(21.62,6.5,z),1.5,.08,axis='x')
    elif slug=='last':
        g.coffers(a,4,.26,.35)
        # Restored bank ceiling with glass bottle rosettes and diamond medallion.
        for x in (-16,-8,0,8,16):
            for z in (-16,-8,0,8,16):
                ring(a,(x,10.5,z),.6,.09,f='glass')
        corners=[(-4,8.6,2),(0,8.6,-4),(4,8.6,2),(0,8.6,8)]
        for p,q in zip(corners,corners[1:]+corners[:1]):rod(a,p,q,r=.18)
        for z in (-17,-9,-1,7,15):
            g.box(a,'stone',(21.76,6.3,z),(.14,5.8,2.8))
            for y in (4.5,6,7.5):
                for zz in (-.75,0,.75):g.cylinder(a,'glass',(21.6,y,z+zz),.25,.12,12,'x')
    else:
        # Original suspended shade sails and a prismatic light canopy, no copied event art.
        for x in (-10,0,10):
            pts=[(x-4,10.6,-14),(x+4,10.6,-14),(x+4,10.6,14),(x-4,10.6,14),(x,9.2,0)]
            a.add('ceiling',pts,[(i,(i+1)%4,4) for i in range(4)]+[(4,(i+1)%4,i) for i in range(4)])
            for p in pts[:4]:rod(a,p,pts[4],r=.06)
        for y,r in ((7.6,3),(9.4,5)):
            pts=[(r*math.cos(i*math.pi/3),y,2+r*math.sin(i*math.pi/3)) for i in range(6)]
            for p,q in zip(pts,pts[1:]+pts[:1]):rod(a,p,q,'glass',.14)
        for z in range(-18,19,5):g.box(a,'metal',(21.75,6.5,z),(.15,5.5,.12))

def main():
    path=g.EXPORT/'catalog.json';catalog=json.loads(path.read_text())
    for theme in THEMES:
        code=theme['code'];g.RESORTS[code]=theme
        a=g.Asset('hall_%d'%code)
        g.hall_shell(a,code);decoration(a,theme['slug']);g.floor_features(a,code);g.heritage_gallery(a,code)
        assert a.triangles()<=40000,(code,a.triangles())
        catalog['models'][a.name]=g.export(a)
        catalog['halls'][str(code)]={'model':a.name,'resort':theme['key'],'floor':theme['floor'],
            'chandelier':theme['chandelier'],'signature':g.SIGNATURE_PROPS[theme['signature']]}
        print('SIX_RESORT_HALL',code,a.triangles())
    catalog['models']=dict(sorted(catalog['models'].items()));catalog['halls']=dict(sorted(catalog['halls'].items()))
    path.write_text(json.dumps(catalog,indent=2)+'\n')
if __name__=='__main__':main()
