# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Original city traffic sources. Run Blender --background --python this_file.py.
All forms authored procedurally here, with no imported artwork or third-party meshes.
Source metres, +Y forward/+Z up; GLB exports -Z forward/+Y up.
Catalog applies 1/16 scale exactly once for Godot tile-space consumers.
"""
import bpy, math, json, os, sys, argparse
from pathlib import Path
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'assets/traffic-models'
EXPORT = ROOT/'game/assets/desert-dreams-traffic'
# Preview renders and manifests go to $SCDD_REVIEW_DIR (default: <repo>/tmp/review).
REVIEW = Path(os.environ.get('SCDD_REVIEW_DIR', ROOT/'tmp/review'))/'traffic-models'
KINDS = ['car','compact','sedan','taxi','pickup','van','bus','truck','police','fire_engine','ambulance','military','train','subway','ship','sailboat','helicopter','plane']
PALETTE = {
    'cream':(.85,.76,.57), 'teal':(.035,.32,.32), 'copper':(.60,.22,.085), 'gold':(.95,.56,.075),
    'red':(.65,.06,.035), 'olive':(.24,.30,.17), 'blue':(.11,.24,.38), 'glass':(.035,.11,.14),
    'rubber':(.035,.039,.037), 'metal':(.54,.57,.55), 'light':(1,.92,.68),
    'skin0':(.83,.55,.36), 'skin1':(.50,.27,.14), 'skin2':(.27,.12,.075), 'skin3':(.95,.73,.55),
    'white':(.91,.88,.78), 'purple':(.40,.20,.34),
    # Passenger cabin interior finishes; the Explore cabin shader keys on these names.
    'floor':(.14,.16,.15), 'panel':(.90,.86,.76), 'ceiling':(.93,.91,.86), 'seat':(.045,.33,.33),
    'walnut':(.31,.18,.079),
}
MATS={}; FAR=False

def reset():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for data in list(bpy.data.meshes):
        if data.users==0:bpy.data.meshes.remove(data)
    for mat in list(bpy.data.materials):
        if mat.users==0:bpy.data.materials.remove(mat)
    MATS.clear()
    for name,color in PALETTE.items():
        mat=bpy.data.materials.new('traffic_'+name);mat.diffuse_color=(*color,1);mat.use_nodes=True
        bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=.62
        if name=='metal':bs.inputs['Metallic'].default_value=.55
        MATS[name]=mat

def finish(obj,name,material):
    obj.name=name;obj.data.materials.append(MATS[material]);return obj

def box(name,loc,size,mat):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,name,mat)

def cylinder(name,loc,radius,depth,mat,axis='Z',sides=10):
    bpy.ops.mesh.primitive_cylinder_add(vertices=6 if FAR else sides,radius=radius,depth=depth,location=loc)
    o=bpy.context.object
    if axis=='X':o.rotation_euler.y=math.pi/2
    if axis=='Y':o.rotation_euler.x=math.pi/2
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    return finish(o,name,mat)

def rod(name,a,b,radius,mat):
    a,b=Vector(a),Vector(b);o=cylinder(name,(a+b)*.5,radius,(b-a).length,mat,sides=6)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o

def mesh(name,verts,faces,mat):
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
    o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);return finish(o,name,mat)

def loft(name,rings,mat):
    verts=[]
    for y,w0,w1,z0,z1 in rings:verts.extend([(-w0,y,z0),(w0,y,z0),(w1,y,z1),(-w1,y,z1)])
    faces=[(3,2,1,0)]
    for i in range(len(rings)-1):
        for j in range(4):faces.append((4*i+j,4*i+(j+1)%4,4*(i+1)+(j+1)%4,4*(i+1)+j))
    faces.append(tuple(range(len(verts)-4,len(verts))))
    return mesh(name,verts,faces,mat)

def wheels(width,length,radius=.34,count=2):
    for side in [-1,1]:
        for j in range(count):
            y=(-.32 + .64*j/max(1,count-1))*length
            cylinder('Rubber tire',(side*width*.49,y,radius),radius,.20,'rubber','X')
            if not FAR:cylinder('Hub',(side*(width*.49+.105),y,radius),radius*.48,.018,'metal','X')

def road(kind):
    # kind: (width, length, height, body color) in meters
    config={
        'car':(1.85,4.6,1.48,'copper'), 'compact':(1.64,3.2,1.48,'teal'),
        'sedan':(1.92,5.0,1.45,'blue'), 'taxi':(1.88,4.6,1.55,'gold'),
        'pickup':(2.02,5.1,1.75,'teal'), 'van':(2.05,5.5,2.35,'cream'),
        'bus':(2.5,9.0,3.0,'teal'), 'truck':(2.5,8.2,3.2,'copper'),
        'police':(1.95,4.8,1.55,'white'), 'fire_engine':(2.5,8.0,3.0,'red'),
        'ambulance':(2.35,6.0,2.8,'white'), 'military':(2.5,6.4,2.75,'olive'),
    }
    w,L,h,color=config[kind];r=.34 if h<2 else .44
    box('Lower body',(0,0,r+.22),(w,L,.48),color)
    wheels(w,L,r,3 if kind in ['truck','fire_engine','military'] else 2)
    if kind in ['car','compact','sedan','taxi','police']:
        loft('Glass cabin',[(-L*.25,w*.42,w*.31,r+.44,h-.22),(0,w*.42,w*.34,r+.44,h),(.27*L,w*.42,w*.32,r+.44,h-.38)],'glass')
        box('Solid roof',(0,-L*.03,h),(w*.69,L*.36,.09),color)
        if not FAR:
            for side in [-1,1]:box('Window pillar',(side*w*.42,-L*.04,h-.30),(.055,.085,.52),color)
    elif kind=='pickup':
        box('Cab glass',(0,L*.16,h-.42),(w*.89,L*.37,.72),'glass');box('Cab roof',(0,L*.16,h),(w*.96,L*.40,.09),color)
        box('Open bed floor',(0,-L*.28,r+.50),(w*.88,L*.36,.07),'glass')
        for side in [-1,1]:box('Bed rail',(side*w*.46,-L*.28,r+.74),(w*.08,L*.38,.43),color)
    elif kind=='bus':
        box('Passenger body',(0,0,h*.61),(w,L,h*.67),'cream')
        box('Roof',(0,0,h),(w*1.01,L*1.01,.10),color)
        box('Wrap windshield',(0,L*.504,h*.73),(w*.89,.04,h*.35),'glass')
        for side in [-1,1]:
            if FAR:box('Window stripe',(side*w*.505,0,h*.74),(.03,L*.84,h*.31),'glass')
            else:
                for j in range(7):box('Passenger window',(side*w*.505,-L*.37+j*L*.12,h*.74),(.03,L*.095,h*.31),'glass')
        if not FAR:box('Destination sign',(0,L*.51,h*.93),(w*.58,.045,.20),'gold')
    else:
        cabL=L*.29
        box('Cab',(0,L*.34,h*.49),(w,cabL,h*.66),color)
        box('Windshield',(0,L*.488,h*.68),(w*.85,.045,h*.22),'glass')
        for side in [-1,1]:box('Cab side glass',(side*w*.502,L*.34,h*.68),(.025,cabL*.72,h*.22),'glass')
        if kind=='fire_engine':
            box('Equipment body',(0,-L*.14,h*.44),(w,L*.62,h*.56),'red')
            for side in [-1,1]:
                box('Shutter panel',(side*w*.506,-L*.16,h*.45),(.025,L*.52,h*.29),'metal')
            for side in [-1,1]:box('Ladder rail',(side*.32,-L*.1,h*.91),(.065,L*.73,.08),'metal')
            if not FAR:
                for i in range(12):box('Ladder rung',(0,-L*.42+i*L*.061,h*.91),(.68,.045,.045),'metal')
        else:
            box('Cargo body',(0,-L*.16,h*.57),(w*.98,L*.66,h*.82),'olive' if kind=='military' else color)
            if kind=='military':
                for side in [-1,1]:box('Canvas edge',(side*w*.498,-L*.16,h*.70),(.03,L*.63,.10),'cream')
            if kind=='ambulance':
                for side in [-1,1]:
                    box('Medical cross vertical',(side*w*.505,-L*.15,h*.70),(.035,.18,.73),'red')
                    box('Medical cross horizontal',(side*w*.509,-L*.15,h*.70),(.035,.65,.18),'red')
    if kind=='taxi':box('Taxi roof sign',(0,0,h+.14),(.62,.27,.22),'light')
    if kind in ['police','ambulance','fire_engine']:
        for side,color2 in [(-1,'red'),(1,'blue')]:box('Emergency beacon',(side*w*.22,L*.18,h+.12),(w*.35,.20,.16),color2)
    if not FAR:
        box('Front grille',(0,L*.504,r+.22),(w*.43,.025,.18),'glass')
        for side in [-1,1]:
            box('Headlamp',(side*w*.36,L*.508,r+.31),(w*.19,.035,.16),'light')
            box('Tail lamp',(side*w*.39,-L*.508,r+.28),(w*.11,.035,.17),'red')
        box('Front bumper',(0,L*.508,r+.05),(w*.92,.12,.10),'metal')

def rail(kind):
    w,L,h=2.6,10.0,3.3
    box('Rail chassis',(0,0,.58),(w,L,.4),'metal');wheels(w*.83,L,.38,3)
    if kind=='train':
        box('Long engine hood',(0,-1.05,1.5),(w*.83,7.4,1.65),'copper')
        box('Tall cab',(0,3.05,2.03),(w,2.65,2.5),'cream')
        box('Cab windshield',(0,4.39,2.54),(w*.86,.03,.66),'glass')
        for side in [-1,1]:box('Side window',(side*w*.504,3.1,2.55),(.03,1.65,.65),'glass')
        if not FAR:
            for j in range(8):box('Cooling louvre',(0,-3.8+j*.76,2.35),(w*.75,.22,.035),'glass')
            cylinder('Diesel stack',(0,-1.3,2.6),.22,.55,'metal')
    else:
        box('Passenger carriage',(0,0,1.94),(w,L,2.52),'metal');box('Teal roof',(0,0,h),(w,L,.15),'teal')
        for side in [-1,1]:
            for j in range(3 if FAR else 8):box('Train window',(side*w*.505,-3.9+j*(3.9 if FAR else 1.11),2.25),(.03,2.6 if FAR else .85,.75),'glass')
        box('End window',(0,L*.502,2.35),(w*.75,.03,.7),'glass')
    if not FAR:
        for side in [-1,1]:box('Coupling',(0,side*(L*.5+.25),.65),(.32,.55,.22),'metal')

def boat(kind):
    if kind=='ship':
        loft('Harbor hull',[(-5,1.0,1.65,-.55,.72),(-3.8,1.4,1.7,-.65,.85),(3.5,1.25,1.6,-.60,1.0),(5.7,.03,.05,-.2,1.15)],'teal')
        box('Deckhouse',(0,-2,1.45),(2.55,3.7,1.5),'cream');box('Bridge glass',(0,-1.5,2.32),(2.30,1.8,.55),'glass');box('Bridge roof',(0,-1.5,2.65),(2.58,2.0,.10),'cream')
        cylinder('Funnel',(0,-3.2,2.4),.37,1.6,'copper')
        for y in [1.0,2.8]:box('Deck cargo',(0,y,1.1),(2.4,1.45,.65),'gold')
        if not FAR:
            for side in [-1,1]:
                rod('Guard rail',(side*1.55,-4.5,1.15),(side*1.55,3.4,1.43),.035,'metal')
                for y in [-4,-2,0,2,3]:rod('Rail post',(side*1.55,y,.83),(side*1.55,y,1.28),.026,'metal')
    else:
        loft('Sailboat hull',[(-3.0,.52,1.03,-.30,.44),(-1.5,.68,1.20,-.45,.58),(1.7,.45,.85,-.32,.6),(3.7,.02,.03,-.05,.73)],'cream')
        box('Teak deck',(0,-.65,.56),(1.6,2.8,.10),'copper');cylinder('Mast',(0,.4,3.0),.05,6,'metal',sides=8)
        mesh('Triangular mainsail',[(.05,.45,.9),(.05,.45,5.9),(.05,-2.6,1.0)],[(0,1,2),(2,1,0)],'white')
        mesh('Jib',[(0,.6,1.0),(0,.6,5.25),(0,3.25,1.0)],[(0,1,2),(2,1,0)],'gold')
        rod('Boom',(0,.4,.98),(0,-2.6,1.0),.045,'metal')

def air(kind):
    if kind=='helicopter':
        loft('Helicopter fuselage',[(-1.9,.3,.32,.75,1.48),(-1,.67,.66,.45,1.85),(.85,.70,.60,.45,1.75),(1.7,.35,.27,.76,1.27)],'teal')
        box('Cockpit glass',(0,1.03,1.3),(1.18,.95,.75),'glass')
        rod('Tail boom',(0,-1.55,1.2),(0,-4.4,1.65),.14,'teal')
        box('Tail fin',(0,-4.15,1.94),(.075,.75,1.02),'gold')
        cylinder('Rotor mast',(0,-.15,2.10),.09,.65,'metal')
        box('Main rotor',(0,-.15,2.46),(8.0,.17,.045),'rubber');box('Cross rotor',(0,-.15,2.47),(.17,8.0,.045),'rubber')
        box('Tail rotor',(.17,-4.27,1.75),(.045,1.30,.10),'rubber');box('Tail cross rotor',(.18,-4.27,1.75),(.045,.10,1.30),'rubber')
        for side in [-1,1]:
            rod('Landing skid',(side*.87,-1.5,.075),(side*.87,1.4,.075),.075,'metal')
            for y in [-.9,.9]:rod('Skid strut',(side*.87,y,.1),(side*.52,y,.67),.055,'metal')
    else:
        loft('Airliner fuselage',[(-6,.05,.05,1.1,1.3),(-4,.6,.55,.5,1.8),(3.9,.6,.55,.5,1.8),(5.9,.05,.05,1.0,1.15)],'cream')
        mesh('Swept wings',[(-.4,1.5,1.0),(-6,-1.7,.8),(-5.8,-2.7,.8),(-.4,-.4,1.0),(.4,1.5,1.0),(6,-1.7,.8),(5.8,-2.7,.8),(.4,-.4,1.0)],[(0,1,2,3),(3,2,1,0),(4,7,6,5),(5,6,7,4)],'teal')
        box('Tailplane',(0,-4.5,1.28),(4.1,1.25,.09),'teal');box('Vertical tail',(0,-4.4,2.2),(.13,1.65,1.8),'copper')
        for side in [-1,1]:cylinder('Jet engine',(side*2.5,-.8,.56),.33,1.8,'metal','Y')
        box('Flight deck glass',(0,4.3,1.49),(.82,.8,.22),'glass')
        if not FAR:
            for side in [-1,1]:
                for j in range(10):box('Cabin window',(side*.594,-3.2+j*.68,1.30),(.025,.20,.22),'glass')
        for x,y in [(-.6,-1),(.6,-1),(0,3)]:cylinder('Landing wheel',(x,y,.16),.16,.12,'rubber','X')

def pedestrian(index):
    skin='skin'+str(index%4);shirt=['teal','copper','gold','cream','blue','red','olive','purple'][index%8];trousers=['blue','cream','rubber','copper'][index//4]
    height=[1.65,1.78,1.87,1.71][index%4];wide=[.39,.48,.45,.54][index//4];leg=.46*height;torso=.28*height
    # Neutral mid-stride; catalog's shared vertex shader adds a bounded walking sway.
    for side in [-1,1]:
        box('Shoe',(side*wide*.25,.05,.065),(wide*.39,.31,.13),'rubber')
        box('Trouser leg',(side*wide*.25,0,leg*.52),(wide*.40,.22,leg-.1),trousers)
    loft('Shirt',[( -.145,wide*.5,wide*.53,leg-.03,leg+torso),(.145,wide*.5,wide*.53,leg-.03,leg+torso)],shirt)
    cylinder('Neck',(0,0,leg+torso+.04),.09,.15,skin,sides=8)
    if FAR:box('Head',(0,0,height-.16),(.29,.28,.32),skin)
    else:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8,ring_count=4,radius=1,location=(0,.015,height-.17));o=bpy.context.object;o.scale=(.155,.14,.19);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);finish(o,'Head',skin)
        box('Hair',(0,-.02,height-.025),(.28,.24,.09),'rubber' if index%3 else 'copper')
        box('Nose',(0,.157,height-.17),(.065,.065,.07),skin)
    for side in [-1,1]:
        rod('Sleeve',(side*wide*.5,0,leg+torso-.05),(side*(wide*.5+.06),0,leg+torso*.56),.092,shirt)
        rod('Forearm',(side*(wide*.5+.06),0,leg+torso*.56),(side*(wide*.5+.08),.025,leg+.04),.066,skin)
    if index%4==0:
        cylinder('Sunhat brim',(0,0,height+.02),.26,.055,'cream',sides=12);cylinder('Sunhat crown',(0,0,height+.09),.155,.13,'cream',sides=10)
    elif index%4==1:
        box('Cap',(0,0,height+.005),(.31,.29,.12),shirt);box('Cap bill',(0,.20,height-.015),(.26,.16,.035),shirt)
    elif index%4==2:
        box('Backpack',(0,-.23,leg+torso*.56),(wide*.79,.21,torso*.80),'gold' if index%3 else 'teal')
    else:
        box('Shoulder bag',(wide*.7,-.03,leg*.92),(.15,.32,.31),'copper')
    if not FAR and index>=8:
        box('Sunglasses',(0,.151,height-.12),(.30,.025,.065),'glass')

def transit(part):
    # Metres: outer 3.84 x 10; clear inside 3.40; floor top .40.
    # Both middle apertures: y in [-1.20,1.20], z in [.40,2.88].
    if part=='passenger_carriage':
        # Interior finishes are separate materials so the rider's cabin can
        # dress them procedurally: ribbed floor, ivory enamel panels, teal
        # glazed headers, woven seats, brass fittings and a lit ceiling.
        box('Low floor',(0,0,.30),(3.84,10,.20),'floor')
        for side in [-1,1]:
            for y in [-3.65,3.65]:cylinder('Rail wheel',(side*1.45,y,.12),.12,.20,'rubber','X')
            # Window apertures are genuine holes, not opaque glass panels. No
            # two boxes share a face plane, so nothing can z-fight up close.
            for y in [-3.16,3.16]:
                # Walls begin where the door jambs end, never sharing their outer face.
                box('Lower side wall',(side*1.81,y,.83),(.22,3.68,.86),'panel')
                box('Upper window header',(side*1.81,y,3.03),(.22,3.68,.62),'teal')
                for post_y in [y-1.72,y,y+1.72]:box('Window mullion',(side*1.81,post_y,1.99),(.22,.11,1.46),'panel')
                box('Brass seat frame',(side*1.40,y,.58),(.46,3.10,.05),'gold')
                for leg_y in [y-1.45,y+1.45]:box('Seat frame leg',(side*1.40,leg_y,.48),(.46,.06,.16),'gold')
                box('Bench cushion',(side*1.38,y,.69),(.56,3.20,.17),'seat')
                box('Bench back',(side*1.64,y,1.09),(.11,3.20,.62),'seat')
                box('Bench top rail',(side*1.64,y,1.42),(.13,3.24,.05),'gold')
                box('Stainless kick plate',(side*1.695,y*(3.02/3.16),.485),(.01,3.52,.15),'metal')
            box('Door lintel',(side*1.81,0,3.11),(.22,2.4,.46),'teal')
            for y in [-1.28,1.28]:box('Door jamb',(side*1.81,y,1.64),(.22,.08,2.48),'gold')
            box('Overhead stainless rail',(side*1.0,0,2.88),(.04,9.2,.04),'metal')
        for y in [-4.89,4.89]:
            box('End lower wall',(0,y,.8),(3.4,.22,.8),'panel')
            box('End header',(0,y,3.03),(3.4,.22,.62),'teal')
            for x in [-1.65,0,1.65]:box('End window mullion',(x,y,1.99),(.11,.22,1.46),'panel')
            box('End brass sill',(0,y*.9735,1.28),(3.4,.08,.04),'gold')
        box('Roof',(0,0,3.42),(3.84,10,.16),'teal')
        box('Perforated ceiling panel',(0,0,3.329),(3.38,9.76,.008),'ceiling')
        for x in [-.8,.8]:box('Cabin light strip',(x,0,3.305),(.22,8.4,.035),'light')
        for x in [-.9,.9]:rod('Grab pole',(x,1.5,.4),(x,1.5,3.3),.03,'metal')
        for x in [-.9,.9]:rod('Grab pole',(x,-1.5,.4),(x,-1.5,3.3),.03,'metal')
    elif part=='passenger_door':
        # Door origin centered horizontally; bottom just above carriage floor .40.
        box('Door lower panel',(0,0,.885),(.12,2.4,.95),'teal')
        box('Door header',(0,0,2.76),(.12,2.4,.24),'teal')
        box('Door walnut kick band',(0,0,.60),(.14,2.36,.30),'walnut')
        for y in [-1.16,0,1.16]:box('Door vertical frame',(0,y,2.0),(.12,.08,1.28),'gold')
    elif part=='platform':
        box('Platform slab',(0,0,.16),(5.0,16,.48),'cream')
        box('Tactile edge',(-2.25,0,.41),(.45,16,.025),'gold')
        for y in [-6,6]:
            rod('Sign post',(1.8,y,.4),(1.8,y,3.0),.065,'metal')
            box('Blank destination sign',(1.8,y,2.8),(.14,1.6,.6),'teal')
        for y in [-4,4]:
            box('Station bench',(.8,y,.85),(.6,2,.15),'copper')
            for dy in [-.7,.7]:box('Bench leg',(.8,y+dy,.62),(.08,.08,.44),'metal')
    elif part=='stairs':
        for i in range(16):
            top=(i+1)*.18;box('Tread %02d'%i,(0,(i+.5)*.28,top*.5),(2.0,.28,top),'cream')
            box('Tread edge',(0,i*.28+.03,top+.008),(2,.045,.018),'gold')
        for side in [-1,1]:
            rod('Handrail',(side*1.02,0,.9),(side*1.02,4.48,3.78),.04,'teal')
            for i in [0,4,8,12,15]:rod('Rail support',(side*1.02,i*.28,i*.18),(side*1.02,i*.28,i*.18+.9),.025,'metal')
    elif part=='tunnel':
        # Open-ended 16m kit, clear width 6m and 5m above rail datum.
        box('Track bed',(0,0,-.16),(6.4,16,.32),'rubber')
        for side in [-1,1]:
            box('Tunnel wall',(side*3.15,0,2.5),(.30,16,5),'cream')
            box('Rail',(side*.72,0,.05),(.08,16,.10),'metal')
            for y in [-6,-2,2,6]:box('Tunnel light',(side*2.96,y,3.7),(.04,.50,.15),'light')
        box('Tunnel ceiling',(0,0,5.15),(6.6,16,.3),'cream')
        for y in range(-7,8):box('Sleeper',(0,y,-.01),(2.3,.20,.08),'copper')

def export_model(stem,builder,far=False):
    global FAR;FAR=far;reset();builder()
    bpy.context.view_layer.update()
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
    coords=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
    minimum=[min(v[i] for v in coords) for i in range(3)];maximum=[max(v[i] for v in coords) for i in range(3)]
    triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects)
    data={
        'triangles':triangles,
        'parts':len(objects),
        'materials':sorted({m.name for o in objects for m in o.data.materials}),
        'min_godot':[minimum[0],minimum[2],-maximum[1]],
        'max_godot':[maximum[0],maximum[2],-minimum[1]],
        'size_godot':[maximum[0]-minimum[0],maximum[2]-minimum[2],maximum[1]-minimum[1]],
    }
    name=stem+('_far' if far else '')
    (SOURCE/name).parent.mkdir(parents=True,exist_ok=True);(EXPORT/name).parent.mkdir(parents=True,exist_ok=True)
    bpy.context.scene['provenance']='Original procedural geometry authored for Sin City: Desert Dreams; no external assets'
    bpy.context.scene['units']='metres, +Y forward, +Z up; Godot catalog applies /16 tile scale'
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join()
    o=bpy.context.object;o.name=name
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bpy.ops.export_scene.gltf(filepath=str(EXPORT/(name+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_cameras=False,export_lights=False)
    return data

def contact_sheet(stems, title="contact-sheet"):
    reset()
    # Each panel is normalized for readable silhouettes; sizes in catalog retain real units.
    for i,stem in enumerate(stems):
        bpy.ops.import_scene.gltf(filepath=str(EXPORT/(stem+'.glb')))
        selected=list(bpy.context.selected_objects)
        meshes=[o for o in selected if o.type=='MESH']
        coords=[o.matrix_world@Vector(v) for o in meshes for v in o.bound_box]
        low=Vector([min(v[j] for v in coords) for j in range(3)]);high=Vector([max(v[j] for v in coords) for j in range(3)])
        scale=3.7/max(high-low);center=(low+high)*.5
        x=(i%6)*5.0;y=-(i//6)*5.0
        for o in selected:
            if o.parent is None:o.location=(o.location-center)*scale+Vector((x,y,1.8));o.scale*=scale
        bpy.ops.object.text_add(location=(x-2.1,y-1.9,.05));t=bpy.context.object;t.name='Label '+stem;t.data.body=stem.replace('_',' ');t.data.size=.32;t.data.extrude=0;t.data.materials.append(MATS['rubber'])
        box('Tile',(x,y,-.1),(4.8,4.8,.12),'white')
    world=bpy.context.scene.world or bpy.data.worlds.new('Studio');bpy.context.scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.45,.47,.5,1);world.node_tree.nodes['Background'].inputs[1].default_value=.7
    bpy.ops.object.light_add(type='AREA',location=(7,-5,30));bpy.context.object.data.energy=6500;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=25
    bpy.ops.object.camera_add(location=(26,-37,47));cam=bpy.context.object;target=Vector(((min(6,len(stems))-1)*2.5,-(math.ceil(len(stems)/6)-1)*2.5,0));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=max(min(6,len(stems))*5,math.ceil(len(stems)/6)*5)*1.47;bpy.context.scene.camera=cam
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.render.resolution_x=2100;scene.render.resolution_y=2100;scene.render.resolution_percentage=100
    scene.render.filepath=str(REVIEW/(title+'.png'));scene.view_settings.view_transform='Standard';bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(title+'.blend')));bpy.ops.render.render(write_still=True)

def main():
    global REVIEW
    parser=argparse.ArgumentParser();parser.add_argument('--skip-render',action='store_true');parser.add_argument('--transit-only',action='store_true')
    parser.add_argument('--review-dir',type=Path,help='where preview renders and the geometry manifest are written')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    if args.review_dir:REVIEW=args.review_dir
    bpy.context.preferences.filepaths.save_version=0
    for p in [SOURCE,EXPORT,REVIEW]:p.mkdir(parents=True,exist_ok=True)
    catalog={'source_units':'metres','runtime_units':'tile = 16 metres','forward':'Godot -Z','provenance':'Original procedural geometry and flat colors; no external artwork or models','models':{}}
    if args.transit_only:
        catalog=json.loads((EXPORT/'catalog.json').read_text())
        for part in ['passenger_carriage','passenger_door','platform','stairs','tunnel']:
            catalog['models']['transit/'+part]=export_model('transit/'+part,lambda p=part:transit(p))
        (EXPORT/'catalog.json').write_text(json.dumps(catalog,indent=2)+'\n');(REVIEW/'geometry-manifest.json').write_text(json.dumps(catalog,indent=2)+'\n')
        if not args.skip_render:contact_sheet(['transit/'+p for p in ['passenger_carriage','passenger_door','platform','stairs','tunnel']], 'transit-kit')
        print('TRANSIT_MODELS_COMPLETE');return
    for kind in KINDS:
        fn=(lambda k=kind:road(k)) if kind in KINDS[:12] else (lambda k=kind:rail(k)) if kind in ['train','subway'] else (lambda k=kind:boat(k)) if kind in ['ship','sailboat'] else (lambda k=kind:air(k))
        for far in [False,True]:catalog['models'][kind+('_far' if far else '')]=export_model(kind,fn,far)
    for i in range(16):
        for far in [False,True]:catalog['models'][f'pedestrian_{i:02d}'+('_far' if far else '')]=export_model(f'pedestrian_{i:02d}',lambda i=i:pedestrian(i),far)
    (EXPORT/'catalog.json').write_text(json.dumps(catalog,indent=2)+'\n');(REVIEW/'geometry-manifest.json').write_text(json.dumps(catalog,indent=2)+'\n')
    if not args.skip_render:contact_sheet(KINDS+[f'pedestrian_{i:02d}' for i in range(16)])
    print('TRAFFIC_MODELS_COMPLETE',len(catalog['models']))
if __name__=='__main__':main()
