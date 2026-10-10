# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Six original signature tables. Export only these props, preserving the original kit.

Blender --background --factory-startup --python tools/blender_exploration/build_original_signature_props.py
All dimensions are metres; every collider stays inside the shared 3x1.6m table footprint.
"""
import sys, math, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_resort_interiors as g


def foundation(a, rounded=False):
    if rounded:
        g.cylinder(a,'wood',(0,.79,0),1,.12,32,'y',top=1)
        # An elliptic top uses an authored perimeter, avoiding a circular oversized collider.
        a.parts.pop('wood')
        pts=[(1.47*math.cos(i*math.tau/48),y,.76*math.sin(i*math.tau/48)) for y in (.74,.88) for i in range(48)]
        a.add('wood',pts,[tuple(range(47,-1,-1)),tuple(range(48,96))]+[(i,(i+1)%48,(i+1)%48+48,i+48) for i in range(48)])
    else:
        g.box(a,'wood',(0,.81,0),(2.94,.14,1.52))
        g.box(a,'metal',(0,.897,0),(2.98,.034,1.56))
    for x in (-.92,.92):
        g.box(a,'wood',(x,.37,0),(.33,.74,1.02))
        g.box(a,'metal',(x,.035,0),(.47,.07,1.15))
        g.box(a,'metal',(x,.53,.522),(.2,.08,.025))
    g.box(a,'rubber',(0,.028,0),(2.92,.052,1.46))
    a.collider('Table',(0,.45,0),(3,.9,1.6))


def dial(a, x, y, z, radius=.27, count=12):
    g.cylinder(a,'metal',(x,y,z),radius,.055,32,'z')
    g.cylinder(a,'felt',(x,y,z+.031),radius*.85,.022,32,'z')
    for i in range(count):
        t=i*math.tau/count
        g.rod(a,'lamp',(x+.73*radius*math.sin(t),y+.73*radius*math.cos(t),z+.047),
              (x+.81*radius*math.sin(t),y+.81*radius*math.cos(t),z+.047),.008,4)
    g.rod(a,'metal',(x,y,z+.058),(x+.12,y+.1,z+.058),.012,6)
    g.sphere(a,'metal',(x,y,z+.06),.035,10,6)


def vault(a):
    foundation(a)
    g.box(a,'felt',(0,.926,.14),(2.76,.025,1.12))
    g.box(a,'wood',(0,1.15,-.55),(2.82,.47,.22))
    g.box(a,'metal',(0,1.15,-.426),(2.75,.4,.022))
    for x in (-.86,0,.86):
        dial(a,x,1.16,-.397,.185)
        g.cylinder(a,'lamp',(x,.951,.26),.08,.04,16)
    for x in (-1.22,1.22):
        for y in (1.03,1.27):g.sphere(a,'metal',(x,y,-.39),.025,8,4)
    for z in (-.04,.36):g.rod(a,'metal',(-1.32,.95,z),(1.32,.95,z),.009,4)


def route(a):
    foundation(a,True)
    g.box(a,'felt',(0,.901,0),(2.3,.025,1.2))
    origin=(-1.01,.932,.47);target=(.94,.932,-.47)
    for mid,finish in [((0,.932,.47),'metal'),((-.1,.932,0),'glass'),((.26,.932,-.34),'lamp')]:
        g.rod(a,finish,origin,mid,.025,6);g.rod(a,finish,mid,target,.025,6)
        g.cylinder(a,finish,mid,.075,.022,12)
    for pos in (origin,target):g.cylinder(a,'metal',pos,.11,.035,20)
    g.box(a,'wood',(.98,1.06,-.52),(.5,.26,.24))
    g.box(a,'metal',(.98,1.199,-.52),(.46,.023,.2))
    for x in (-.52,0,.52):
        g.box(a,'metal',(x,.949,.3),(.41,.025,.28))
        g.box(a,'sign',(x,.965,.3),(.36,.01,.23))


def encore(a):
    foundation(a,True)
    g.box(a,'felt',(0,.901,.2),(2.3,.025,.84))
    g.cylinder(a,'wood',(0,.984,-.33),.48,.16,32)
    g.torus(a,'metal',(0,1.07,-.33),.47,.026,32,6)
    for x in (-1.1,1.1):
        g.cylinder(a,'metal',(x,1.21,-.56),.035,.58,12)
        g.sphere(a,'lamp',(x,1.505,-.56),.065,12,6)
    for x in [i*.095 for i in range(-10,11)]:
        g.cylinder(a,'carpet',(x,1.35,-.57),.067,.24,8)
    g.box(a,'metal',(0,1.48,-.57),(2.25,.05,.17))
    for i in range(7):
        t=(i-3)*math.pi/12
        p=(.38*math.sin(t),1.07,-.33+.38*math.cos(t))
        g.rod(a,'metal',(0,1.07,-.33),p,.012,6)
    for x in (-.65,0,.65):
        g.torus(a,'metal',(x,.94,.4),.16,.013,20,5)


def forecast(a):
    foundation(a)
    g.box(a,'felt',(0,.923,.34),(2.72,.018,.6))
    g.box(a,'wood',(0,1.09,-.27),(2.72,.35,.78),pitch=-.24)
    for x in (-.85,0,.85):
        g.box(a,'metal',(x,1.17,-.2),(.77,.025,.59),pitch=-.24)
        g.box(a,'screen',(x,1.194,-.2),(.7,.025,.52),pitch=-.24)
        for j in range(7):
            xx=x-.27+j*.085
            yy=1.25+math.sin(j*1.1)*.025
            g.rod(a,'lamp',(xx,yy,-.16),(xx+.06,yy+.012,-.16),.009,4)
        g.cylinder(a,'metal',(x,1.01,.36),.06,.06,16)
    g.rod(a,'metal',(-1.2,1.53,-.6),(1.2,1.53,-.6),.022,8)
    for x in (-1.2,1.2):g.rod(a,'metal',(x,.94,-.6),(x,1.53,-.6),.022,8)
    g.sphere(a,'lamp',(0,1.53,-.6),.09,16,8)


def contracts(a):
    foundation(a)
    g.box(a,'felt',(0,.923,0),(2.76,.022,1.28))
    for x in (-.85,0,.85):
        g.box(a,'metal',(x,.955,.12),(.59,.04,.85))
        g.box(a,'sign',(x,.981,.12),(.49,.012,.74))
        g.box(a,'glass',(x,.99,.12),(.15,.008,.2),yaw=math.pi/4)
    g.box(a,'wood',(0,1.19,-.56),(1.06,.5,.28))
    g.box(a,'metal',(0,1.19,-.404),(.99,.44,.025))
    dial(a,0,1.2,-.38,.16,8)
    for x in (-.43,.43):
        for y in (1.02,1.36):g.sphere(a,'metal',(x,y,-.378),.025,8,4)


def pot(a):
    foundation(a,True)
    g.box(a,'felt',(0,.9,0),(2.3,.023,1.22))
    g.cylinder(a,'metal',(0,.973,-.15),.31,.12,32,top=.36)
    g.cylinder(a,'wood',(0,1.046,-.15),.31,.018,32)
    g.torus(a,'metal',(0,1.06,-.15),.345,.025,32,6)
    for i,x in enumerate((-.87,0,.87)):
        g.box(a,'metal',(x,.951,.39),(.56,.044,.36))
        g.box(a,'sign',(x,.98,.39),(.49,.012,.28))
        for j in range(i+1):g.cylinder(a,'glass',(x,1.002+j*.03,.39),.085,.028,12)
    for x in (-.9,0,.9):
        g.box(a,'wood',(x,1.02,-.52),(.42,.2,.32))
        for j in range(4):g.sphere(a,'lamp',(x-.12+j*.08,1.13,-.52),.026,8,4)


def main():
    path=g.EXPORT/'catalog.json';catalog=json.loads(path.read_text())
    for name,fn in [('vault_table',vault),('route_table',route),('encore_table',encore),('forecast_console',forecast),('contract_table',contracts),('common_pot_table',pot)]:
        a=g.Asset(name);fn(a)
        assert a.triangles()<=4000,(name,a.triangles())
        catalog['models'][name]=g.export(a)
        print('ORIGINAL_SIGNATURE_PROP',name,a.triangles())
    catalog['models']=dict(sorted(catalog['models'].items()))
    path.write_text(json.dumps(catalog,indent=2)+'\n')
if __name__=='__main__':main()
