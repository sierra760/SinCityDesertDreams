# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Original vehicle detail authoring and conservative batch derivations.

The historic traffic silhouettes supply the category dimensions. Near geometry
adds modeled construction, rounded sections and separate moving parts. Static
middle/far keep their inexpensive topology; they are grounded and fitted to the
immutable original catalog size. Nothing here authors physics.
"""
import importlib.util
import math
from pathlib import Path
import bpy
from mathutils import Vector
from . import common
from .contracts import validate_model

_spec=importlib.util.spec_from_file_location('_traffic_source',Path(__file__).resolve().parents[1]/'build_traffic_models.py')
legacy=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(legacy)
KINDS=legacy.KINDS
ROOT=None


def _material(obj): return obj.data.materials[0].name.removeprefix('traffic_').split('.')[0]


def _batch_palette(kind):
    """Keep service-vehicle paint identities through the inexpensive tiers."""
    if kind not in ('police', 'helicopter'):
        return
    cream=legacy.MATS['cream']
    cream.diffuse_color=(.88,.79,.59,1)
    cream.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.88,.79,.59,1)
    if kind=='helicopter':
        bpy.data.objects['Helicopter fuselage'].data.materials[0]=cream
        return
    paint=legacy.MATS['white']
    paint.name='traffic_patrol_paint'
    paint.diffuse_color=(.085,.11,.12,1)
    paint.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.085,.11,.12,1)
    bpy.data.objects['Solid roof'].data.materials[0]=cream
    # Cream hardware shares the roof paint so the middle tier stays at six
    # materials while retaining separate glazing, tires and both beacon colors.
    for obj in bpy.context.scene.objects:
        if obj.type=='MESH':
            for slot in obj.material_slots:
                if slot.material in (legacy.MATS['metal'], legacy.MATS['light']):
                    slot.material=cream


def _replace_lofts(kind):
    for obj in list(bpy.context.scene.objects):
        if obj.type!='MESH': continue
        if obj.name not in ['Glass cabin','Harbor hull','Sailboat hull','Helicopter fuselage','Airliner fuselage']: continue
        coordinates=[obj.matrix_world@v.co for v in obj.data.vertices]
        rings=[]
        for i in range(0,len(coordinates),4):
            a,b,c,d=coordinates[i:i+4];rings.append((a.y,abs(a.x),abs(c.x),a.z,c.z))
        mat=_material(obj);name=obj.name
        bpy.data.objects.remove(obj,do_unlink=True)
        # Intermediate longitudinal sections soften transition shoulders without
        # changing category landmarks (deck, nose, cabin and tail stations).
        expanded=[]
        for i,ring in enumerate(rings[:-1]):
            expanded.append(ring)
            following=rings[i+1]
            expanded.append(tuple((a+b)*.5 for a,b in zip(ring,following)))
        expanded.append(rings[-1])
        common.rounded_loft(legacy,name,expanded,mat,16,kind in ['helicopter','plane'])


def _road_body(kind):
    body=bpy.data.objects.get('Lower body')
    if body is None: return
    w,L,_=body.dimensions
    bottom=body.location.z-.24;top=body.location.z+.24
    color=_material(body)
    bpy.data.objects.remove(body,do_unlink=True)
    # Four distinct passenger-car proportions, broad utility shoulders and a
    # tapered nose/boot. The silhouette is visible above the wheel openings.
    nose=.80 if kind=='compact' else .89
    rings=[(-L*.5,w*.41,w*.43,bottom+.08,top-.08),(-L*.40,w*.50,w*.49,bottom,top),
           (L*.31,w*.50,w*.48,bottom,top),(L*.47,w*.47,w*.46,bottom+.035,top-.035),
           (L*.5,w*.40,w*.43,bottom+.08,top-.075)]
    body=common.rounded_loft(legacy,'Pressed fenders and sills',rings,color)
    return body


def _utility_cab(kind):
    if kind not in ['van','truck','fire_engine','ambulance','military']:return
    cab=bpy.data.objects.get('Cab');w,_,height=cab.dimensions
    h=height/.66;L=cab.location.y/.34;color=_material(cab)
    for obj in list(bpy.context.scene.objects):
        if obj.name.startswith(('Cab side glass','Windshield')) or obj==cab:bpy.data.objects.remove(obj,do_unlink=True)
    top=.92*h if kind=='van' else .82*h
    nose=.63*h if kind=='van' else .51*h
    common.rounded_loft(legacy,'Sloped utility cab',[(L*.195,w*.50,w*.445,h*.16,top),
        (L*.365,w*.50,w*.445,h*.16,top),(L*.487,w*.465,w*.43,h*.16,nose)],color)
    # The windscreen follows the sloped cowl, with an opaque surrounding frame.
    for side in [-1,1]:
        x=side
        legacy.mesh('Framed cab side window',[(x*w*.447,L*.225,top-.10),(x*w*.447,L*.35,top-.10),
            (x*w*.479,L*.425,h*.54),(x*w*.490,L*.225,h*.54)],[(0,1,2,3),(3,2,1,0)],'glass')
    ya=L*.383;yb=L*.458
    za=top+(nose-top)*(.383-.365)/(.487-.365)+.018
    zb=top+(nose-top)*(.458-.365)/(.487-.365)+.018
    legacy.mesh('Split utility windscreen',[(-w*.38,ya,za),(w*.38,ya,za),(w*.38,yb,zb),(-w*.38,yb,zb)],[(0,1,2,3),(3,2,1,0)],'glass')
    legacy.rod('Windscreen center frame',(0,ya,za+.01),(0,yb,zb+.01),.018,color)
    for side in [-1,1]:
        legacy.box('Cab entry step',(side*w*.48,L*.265,h*.20),(.20,L*.18,.065),'metal')
        legacy.rod('Cab grab handle',(side*w*.47,L*.21,h*.39),(side*w*.47,L*.21,h*.57),.015,'metal')
    if kind=='truck':
        for side in [-1,1]:
            for j in range(10):legacy.box('Freight box corrugation',(side*w*.491,-L*.44+j*L*.059,h*.57),(.025,.033,h*.70),'metal')
    if kind=='van':
        for side in [-1,1]:
            legacy.box('Van sliding panel seam',(side*w*.492,-L*.13,h*.57),(.02,.022,h*.65),'glass')
            legacy.box('Van sliding pull',(side*w*.502,-L*.17,h*.59),(.022,.24,.055),'metal')
    if kind=='ambulance':
        for side in [-1,1]:
            legacy.box('Ambulance module stripe',(side*w*.494,-L*.16,h*.40),(.026,L*.63,.075),'red')
            legacy.box('Module roof beacon',(side*w*.32,-L*.06,h*.98+.045),(.27,.22,.08),'red')
    if kind in ['ambulance','fire_engine']:
        for obj in bpy.context.scene.objects:
            if obj.name.startswith('Emergency beacon'):
                obj.location.y=L*.28;obj.location.z=top+.08
        legacy.box('Beacon mounting plate',(0,L*.28,top+.012),(w*.82,.23,.024),'metal')
    if kind=='fire_engine':
        for y in [-L*.33,L*.15]:
            for side in [-1,1]:legacy.rod('Ladder rack',(side*.32,y,h*.72),(side*.32,y,h*.91),.035,'metal')
    if kind=='military':
        cargo=bpy.data.objects.get('Cargo body');bpy.data.objects.remove(cargo,do_unlink=True)
        for obj in list(bpy.context.scene.objects):
            if obj.name.startswith('Canvas edge'):bpy.data.objects.remove(obj,do_unlink=True)
        legacy.box('Troop deck',(0,-L*.16,h*.34),(w*.94,L*.66,.15),'olive')
        section=[(-w*.46,h*.44),(-w*.46,h*.74),(-w*.36,h*.90),(0,h*.95),(w*.36,h*.90),(w*.46,h*.74),(w*.46,h*.44)]
        verts=[(x,y,z) for y in [-L*.48,L*.17] for x,z in section]
        canopy=legacy.mesh('Open backed utility canvas',verts,[(i,i+1,i+8,i+7) for i in range(6)],'olive')
        mod=canopy.modifiers.new('Canvas edge thickness','SOLIDIFY');mod.thickness=.018
        bpy.context.view_layer.objects.active=canopy;bpy.ops.object.modifier_apply(modifier=mod.name)
        for y in [-L*.475,-L*.26,-L*.04,L*.165]:
            for a,b in zip(section[:-1],section[1:]):legacy.rod('Canvas supported bow',(a[0],y,a[1]),(b[0],y,b[1]),.025,'cream')
            for side in [-1,1]:legacy.rod('Canvas deck mounting',(side*w*.46,y,h*.36),(side*w*.46,y,h*.46),.025,'metal')
        for side in [-1,1]:
            legacy.box('Troop bench',(side*w*.30,-L*.15,h*.47),(w*.20,L*.51,.08),'cream')
            for y in [-L*.35,L*.05]:legacy.rod('Troop bench leg',(side*w*.30,y,h*.35),(side*w*.30,y,h*.47),.035,'metal')
        legacy.cylinder('Rear mounted spare',(0,-L*.496,h*.58),.31,.17,'rubber','Y',24)
        legacy.cylinder('Spare wheel hub',(0,-L*.496-.09,h*.58),.14,.025,'metal','Y',16)


def _transit_marks(kind):
    if kind not in ['train','subway','bus']:return
    x,y,z=(1.095,-1.8,1.62) if kind=='train' else (1.334,0,1.32) if kind=='subway' else (1.266,0,1.20)
    for side in [-1,1]:
        bpy.ops.object.text_add(location=(side*x,y,z))
        obj=bpy.context.object;obj.name='Desert Transit DT monogram';obj.data.body='DT';obj.data.align_x='CENTER';obj.data.size=.38;obj.data.extrude=.0015
        obj.rotation_euler=(math.pi/2,0,side*math.pi/2)
        obj.data.materials.append(legacy.MATS['cream' if kind=='train' else 'teal'])
        bpy.ops.object.convert(target='MESH')


def _details(kind):
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
    low,high=common.bounds(objects)
    w,L,h=high[0]-low[0],high[1]-low[1],high[2]
    if kind=='pickup':
        cab=bpy.data.objects.get('Cab glass')
        color='teal';w=2.02;L=5.1;h=1.75
        bpy.data.objects.remove(cab,do_unlink=True)
        shell=legacy.box('Pressed pickup cabin',(0,L*.16,1.25),(w*.89,L*.37,1.02),color)
        common.bevel(shell,.075,3)
        legacy.box('Pickup windscreen',(0,L*.347,1.38),(w*.77,.022,.49),'glass')
        legacy.box('Pickup rear glass',(0,-L*.027,1.39),(w*.65,.022,.42),'glass')
        for side in [-1,1]:legacy.box('Pickup side glass',(side*w*.447,L*.16,1.38),(.025,L*.28,.48),'glass')
        legacy.box('Pickup tailgate',(0,-L*.473,1.08),(w*.91,.09,.43),color)
        legacy.box('Tailgate pull',(0,-L*.484,1.16),(.28,.018,.05),'metal')
        objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
        low,high=common.bounds(objects);w,L,h=high[0]-low[0],high[1]-low[1],high[2]
    if kind in KINDS[:12]:
        color=next((_material(o) for o in objects if 'fenders' in o.name),'cream')
        cabin_y=.16*L if kind=='pickup' else .10*L if kind in ['car','compact','sedan','taxi','police'] else .21*L
        for side in [-1,1]:
            # Door gaps and handles belong below the glass belt.
            y=cabin_y-.13*L if kind=='pickup' else cabin_y+.06*L
            legacy.box('Door handle',(side*w*.469,y,h*.48),(.035,.19,.038),'metal')
            legacy.box('Door rear shut line',(side*w*.455,y-.13,h*.45),(.016,.017,h*.22),'glass')
            mirror=legacy.box('Wing mirror',(side*w*.455,cabin_y+.15*L,h*.70),(.10,.19,.12),color)
            common.bevel(mirror,.027)
            legacy.rod('Mirror arm',(side*w*.465,cabin_y+.15*L,h*.62),(side*w*.455,cabin_y+.15*L,h*.70),.014,'metal')
        grille=bpy.data.objects.get('Front grille')
        if grille:
            for i in range(7):
                legacy.box('Grille vertical',(grille.location.x+(i-3)*grille.dimensions.x/8,grille.location.y+.019,grille.location.z),(.021,.018,grille.dimensions.z*.78),'metal')
        if kind in ['truck','van','ambulance']:
            for side in [-1,1]:
                legacy.box('Cargo rear door',(side*w*.23,-L*.478,h*.51),(w*.43,.025,h*.57),'cream' if kind=='ambulance' else 'metal')
                legacy.rod('Rear locking bar',(side*w*.12,-L*.485,h*.27),(side*w*.12,-L*.485,h*.74),.016,'metal')
        if kind=='fire_engine':
            for side in [-1,1]:
                for y in [-2,-1,0,1]:
                    legacy.box('Equipment locker pull',(side*w*.477,y,h*.46),(.025,.26,.045),'glass')
                legacy.cylinder('Hose reel',(side*w*.47,-2.6,h*.48),.24,.12,'rubber','X',20)
        if kind=='bus':
            for z in [h*.27,h*.31,h*.35]: legacy.box('Rear engine cooling grille',(0,-L*.48,z),(w*.68,.035,.045),'glass')
            legacy.box('Passenger entrance',(w*.468,L*.435,h*.48),(.03,L*.07,h*.68),'glass')
            legacy.box('Entry door divider',(w*.487,L*.435,h*.48),(.025,.038,h*.68),'metal')
    elif kind in ['train','subway']:
        if kind=='subway':
            # Door openings replace passenger panes; never layer door glass over
            # the original evenly spaced windows on either side of the carriage.
            for pane in list(bpy.context.scene.objects):
                if pane.name.startswith('Train window') and any(abs(pane.location.y-y)<pane.dimensions.y*.5+.44 for y in [-2.6,2.6]):
                    bpy.data.objects.remove(pane,do_unlink=True)
        for side in [-1,1]:
            for y in [-3.2,3.2]:
                legacy.box('Bogie axle housing',(side*.91,y,.40),(.18,1.65,.22),'rubber')
            if kind=='train':
                legacy.rod('Long walkway handrail',(side*1.13,-4.35,1.42),(side*1.13,1.55,1.42),.022,'metal')
                for y in [-4,-2,0,1.5]:legacy.rod('Walkway upright',(side*1.13,y,.72),(side*1.13,y,1.42),.018,'metal')
            else:
                for y in [-2.6,2.6]:
                    legacy.box('Sliding double door',(side*1.308,y,1.56),(.035,.88,1.62),'teal')
                    legacy.box('Door glass',(side*1.331,y,2.00),(.021,.66,.57),'glass')
                    legacy.box('Door split',(side*1.346,y,1.56),(.01,.022,1.6),'metal')
        if kind=='train':
            for side in [-1,1]:legacy.cylinder('Cab headlight',(side*.66,4.425,2.10),.115,.065,'light','Y',16)
    elif kind=='ship':
        for side in [-1,1]:
            for y in [-3.0,-2.3,-1.6,-.9]:legacy.cylinder('Deckhouse portlight',(side*1.285,y,1.62),.17,.035,'glass','X',16)
            for y in [-3.5,0,2.5]:legacy.cylinder('Mooring bollard',(side*1.22,y,.99),.075,.28,'metal',sides=12)
        legacy.rod('Bridge aerial',(0,-2.2,2.7),(0,-2.2,3.17),.026,'metal')
    elif kind=='sailboat':
        for y in [-2.7,3.2]:legacy.rod('Standing rigging',(0,.4,5.82),(0,y,.69),.012,'metal')
        for side in [-1,1]:legacy.rod('Shroud',(0,.4,5.65),(side*.92,.0,.62),.012,'metal')
        legacy.box('Cockpit well',(0,-1.35,.64),(.76,1.13,.045),'glass')
    elif kind=='helicopter':
        for side in [-1,1]:
            legacy.rod('Cabin glazing frame',(side*.625,.55,.85),(side*.595,.55,1.78),.023,'metal')
            legacy.box('Cabin door handle',(side*.686,-.30,.89),(.035,.21,.04),'metal')
            for y in [-.6,-.4,-.2]:legacy.box('Engine cooling slot',(side*.49,y,1.77),(.03,.10,.08),'glass')
    elif kind=='plane':
        for old_name in ['Vertical tail','Flight deck glass']:
            obj=bpy.data.objects.get(old_name)
            if obj:bpy.data.objects.remove(obj,do_unlink=True)
        verts=[(x,y,z) for x in [-.065,.065] for y,z in [(-5.2,1.25),(-4.95,3.08),(-4.30,3.08),(-3.58,1.25)]]
        legacy.mesh('Swept vertical stabilizer',verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'copper')
        for side in [-1,1]:
            legacy.mesh('Framed flight deck pane',[(0,4.10,1.755),(side*.34,4.10,1.635),(side*.21,4.85,1.425),(0,4.85,1.51)],[(0,1,2,3),(3,2,1,0)],'glass')
            legacy.box('Engine wing pylon',(side*2.5,-.65,.98),(.12,.67,.30),'metal')
        for x,y in [(-.6,-1),(.6,-1),(0,3)]:
            legacy.rod('Landing gear oleo',(x,y,.16),(x,y,.65),.035,'metal')
        for side in [-1,1]:
            legacy.cylinder('Engine intake',(side*2.5,.112,.56),.273,.025,'glass','Y',24)
            legacy.cylinder('Engine spinner',(side*2.5,.135,.56),.077,.09,'metal','Y',16)
            legacy.box('Wing navigation light',(side*5.87,-2.05,.825),(.10,.12,.055),'red' if side<0 else 'light')


def _moving_parts(kind):
    motion={'wheels':[],'rotors':[]}
    # Source cylinders identify their axles exactly before replacing polygon tires.
    tires=[o for o in bpy.context.scene.objects if o.type=='MESH' and (o.name.startswith('Rubber tire') or o.name.startswith('Landing wheel'))]
    for obj in list(bpy.context.scene.objects):
        if obj.name.startswith('Hub') and obj.type=='MESH':bpy.data.objects.remove(obj,do_unlink=True)
    for index,obj in enumerate(tires):
        pos=obj.location.copy();radius=max(v.co.y for v in obj.data.vertices)
        # Primitive cylinder rotation is applied in the legacy builder. Its Z
        # extent gives exact tire radius even for a polygon with no Y extreme.
        radius=max(abs(v.co.z) for v in obj.data.vertices)
        width=max(v.co.x for v in obj.data.vertices)-min(v.co.x for v in obj.data.vertices)
        name='Axle%02d%s'%(index//2,'Left' if pos.x<0 else 'Right')
        name='Wheel%02d'%index
        pos.z=radius
        bpy.data.objects.remove(obj,do_unlink=True)
        wheel=common.pivot(name,pos);spin=common.pivot('Spin',(0,0,0),wheel)
        bpy.ops.mesh.primitive_torus_add(major_radius=radius*.78,minor_radius=radius*.22,
            major_segments=24,minor_segments=8,location=(0,0,0),rotation=(0,math.pi/2,0))
        tire=bpy.context.object;legacy.finish(tire,'Rounded road tire','rubber')
        bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
        # Round tire gives true contact in every spin phase.
        tire.parent=spin
        for side in [-1,1]:
            hub=legacy.cylinder('Recessed alloy rim',(side*radius*.225,0,0),radius*.63,.018,'metal','X',24);hub.parent=spin
            inset=legacy.cylinder('Painted wheel center',(side*radius*.26,0,0),radius*.34,.025,'glass','X',16);inset.parent=spin
            for j in range(6):
                a=j*math.tau/6
                spoke=legacy.rod('Radial wheel spoke',(side*radius*.28,math.sin(a)*radius*.2,math.cos(a)*radius*.2),(side*radius*.28,math.sin(a)*radius*.53,math.cos(a)*radius*.53),radius*.035,'metal');spoke.parent=spin
        steer=kind in KINDS[:12] and pos.y>0 or kind=='plane' and pos.y>0
        motion['wheels'].append(dict(node=name,radius_m=radius,axis='X',steer=steer,steering_axis='Y',axle_source_m=list(pos)))
        bodies=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name in ['Pressed fenders and sills','Cargo body','Cab','Equipment body','Passenger body','Pressed pickup cabin','Sloped utility cab']]
        for body in bodies:
            cutter=legacy.cylinder('Wheel well tool',pos,radius*1.09,.65,'rubber','X',32)
            bpy.context.view_layer.objects.active=body
            mod=body.modifiers.new('Open tire arch','BOOLEAN');mod.operation='DIFFERENCE';mod.object=cutter;mod.solver='EXACT'
            bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)
    if motion['wheels']:motion['wheel_radius_m']=motion['wheels'][0]['radius_m']
    if kind=='helicopter':
        for name,prefixes,center,axis,rate in [('MainRotor',['Main rotor','Cross rotor'],(0,-.15,2.465),'Y',24),('TailRotor',['Tail rotor','Tail cross rotor'],(.175,-4.27,1.75),'X',31)]:
            joint=common.pivot(name,center)
            for obj in list(bpy.context.scene.objects):
                if obj.type=='MESH' and any(obj.name.startswith(p) for p in prefixes):
                    obj.parent=joint;obj.location-=Vector(center)
            motion['rotors'].append(dict(node=name,axis=axis,radians_per_second=rate))
    return motion


def _passenger_detail(kind):
    spec=importlib.util.spec_from_file_location('_explore_vehicle_source',Path(__file__).resolve().parents[1]/'blender_exploration/build_vehicles.py')
    authored=importlib.util.module_from_spec(spec);spec.loader.exec_module(authored)
    authored.reset();root=authored.car()
    stretch={'car':1.0,'compact':.76,'sedan':1.17,'taxi':1.02,'police':1.08}[kind]
    # Short hatch, long sedan and service cruiser retain circular wheels: body
    # panels stretch longitudinally while whole axle pivots move with the cabin.
    for obj in list(root.children_recursive):
        if obj.parent==root: obj.location.y*=stretch
        if obj.type=='MESH' and obj.parent==root:
            bpy.context.view_layer.objects.active=obj
            bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
            bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
            for v in obj.data.vertices:v.co.y*=stretch
    colors={'car':(.58,.225,.095),'compact':(.045,.36,.34),'sedan':(.07,.15,.25),
            'taxi':(.86,.49,.045),'police':(.085,.11,.12)}
    paint=authored.MAT['Copper enamel'];paint.diffuse_color=(*colors[kind],1)
    paint.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*colors[kind],1)
    if kind=='compact':
        roof=authored.MAT['Warm cream'];roof.diffuse_color=(.77,.82,.66,1)
        roof.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.77,.82,.66,1)
    if kind=='taxi':
        authored.box('Taxi illuminated roof sign',(0,0,1.30),(.57,.22,.14),'Ivory lamp',root,.025)
        for side in [-1,1]:
            for j in range(6):authored.box('Cab checker',(side*.889,-.30+j*.095,.59),(.018,.055,.06),'Dark grille',root)
    if kind=='police':
        authored.box('Lightbar mounting rail',(0,0,1.27),(.94,.19,.045),'Warm alloy',root,.01)
        for side in [-1,1]:authored.box('Patrol beacon',(side*.28,0,1.335),(.38,.17,.11),'Red lamp' if side<0 else 'Teal canopy',root,.032)
        for side in [-1,1]:authored.box('Ivory patrol door',(side*.884,-.08,.52),(.018,1.05,.20),'Warm cream',root,.015)
    motion={'wheel_radius_m':.24,'wheels':[],'rotors':[]}
    for name in ['WheelFrontLeft','WheelFrontRight','WheelRearLeft','WheelRearRight']:
        node=next(o for o in root.children if o.name==name)
        motion['wheels'].append(dict(node=name,radius_m=.24,axis='X',steer='Front' in name,steering_axis='Y',axle_source_m=list(node.location)))
    # Flatten top-level parent only so the common root/fitting logic is shared.
    for obj in list(root.children):obj.parent=None
    bpy.data.objects.remove(root,do_unlink=True)
    return motion


def _helicopter_detail():
    spec=importlib.util.spec_from_file_location('_scout_source',Path(__file__).resolve().parents[1]/'blender_exploration/build_vehicles.py')
    authored=importlib.util.module_from_spec(spec);spec.loader.exec_module(authored)
    authored.reset();root=authored.helicopter()
    for obj in root.children_recursive:
        if obj.type=='MESH':
            bpy.context.view_layer.objects.active=obj
            bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
            bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
        if obj.parent==root:
            if obj.type=='MESH':
                # Stretch only the aft structural section, preserving framed cabin.
                for v in obj.data.vertices:
                    y=v.co.y+obj.location.y
                    if y<-.75:v.co.y=-.75+(y+.75)*2.4-obj.location.y
            elif obj.name=='TailRotor':obj.location.y=-.75+(obj.location.y+.75)*2.4
        if obj.parent and obj.parent.name=='MainRotor':
            obj.location.x*=1.6;obj.location.y*=1.6
            if obj.type=='MESH':
                for v in obj.data.vertices:v.co.x*=1.6;v.co.y*=1.6
    for obj in list(root.children):obj.parent=None
    bpy.data.objects.remove(root,do_unlink=True)
    return {'wheels':[],'rotors':[{'node':'MainRotor','axis':'Y','radians_per_second':24},{'node':'TailRotor','axis':'X','radians_per_second':31}]}


def _batch_structure(kind):
    if kind=='subway' and legacy.FAR:
        # Broad distant panes retain a solid end frame rather than projecting
        # unsupported glass past the carriage nose and tail.
        carriage=bpy.data.objects.get('Passenger carriage')
        end=carriage.dimensions.y*.5-.15
        for pane in bpy.context.scene.objects:
            if not pane.name.startswith('Train window'):continue
            low=max(-end,pane.location.y-pane.dimensions.y*.5)
            high=min(end,pane.location.y+pane.dimensions.y*.5)
            pane.location.y=(low+high)*.5
            factor=(high-low)/pane.dimensions.y
            for vertex in pane.data.vertices:vertex.co.y*=factor
    # Keep visible hub faces; hidden axial side/back faces buy useful silhouette
    # and support geometry without increasing the established middle cost.
    for obj in list(bpy.context.scene.objects):
        if obj.type!='MESH' or not obj.name.startswith('Hub'):continue
        points=[obj.matrix_world@v.co for v in obj.data.vertices]
        positive=obj.location.x>0
        edge=max(p.x for p in points) if positive else min(p.x for p in points)
        ring=[p for p in points if abs(p.x-edge)<1e-5]
        center=sum(ring,Vector())/len(ring)
        ring.sort(key=lambda p:math.atan2(p.z-center.z,p.y-center.y),reverse=not positive)
        bpy.data.objects.remove(obj,do_unlink=True)
        legacy.mesh('Outward axle hub',ring,[tuple(range(len(ring)))],'metal')
    if kind in ['car','compact','sedan','taxi','police']:
        body=bpy.data.objects.get('Lower body');w,L,_=body.dimensions
        roof=bpy.data.objects.get('Solid roof');h=roof.location.z;r=.34
        obj=bpy.data.objects.get('Glass cabin');bpy.data.objects.remove(obj,do_unlink=True)
        legacy.loft('Supported cabin glazing',[(-L*.25,w*.42,w*.31,r+.44,h-.22),(-L*.21,w*.42,w*.34,r+.44,h),
            (L*.15,w*.42,w*.34,r+.44,h),(.27*L,w*.42,w*.32,r+.44,h-.38)],'glass')
    if kind=='pickup':
        w,L,h=2.02,5.1,1.75
        obj=bpy.data.objects.get('Cab glass');bpy.data.objects.remove(obj,do_unlink=True)
        legacy.box('Supported pickup cabin',(0,L*.16,1.25),(w*.89,L*.37,1.02),'teal')
        for side in [-1,1]:
            x=side*w*.447
            legacy.mesh('Pickup side pane',[(x,L*.02,1.12),(x,L*.30,1.12),(x,L*.30,1.62),(x,L*.02,1.62)],[(0,1,2,3),(3,2,1,0)],'glass')
        for y in [L*.347,-L*.027]:legacy.mesh('Pickup end pane',[(-w*.38,y,1.12),(w*.38,y,1.12),(w*.38,y,1.62),(-w*.38,y,1.62)],[(0,1,2,3),(3,2,1,0)],'glass')
        # Closing the back uses a single supported panel at distant scale.
        legacy.mesh('Pickup tailgate',[(-w*.46,-L*.473,.87),(w*.46,-L*.473,.87),(w*.46,-L*.473,1.29),(-w*.46,-L*.473,1.29)],[(0,1,2,3),(3,2,1,0)],'teal')
    if kind in ['van','truck','fire_engine','ambulance','military']:
        cab=bpy.data.objects.get('Cab');w,_,height=cab.dimensions;h=height/.66;L=cab.location.y/.34;paint=_material(cab)
        for obj in list(bpy.context.scene.objects):
            if obj==cab or obj.name.startswith(('Windshield','Cab side glass')):bpy.data.objects.remove(obj,do_unlink=True)
        top=h*(.92 if kind=='van' else .82);nose=h*(.63 if kind=='van' else .51)
        legacy.loft('Batch sloped cab',[(L*.195,w*.5,w*.445,h*.16,top),(L*.365,w*.5,w*.445,h*.16,top),(L*.487,w*.465,w*.43,h*.16,nose)],paint)
        for side in [-1,1]:
            legacy.mesh('Batch side glass',[(side*w*.447,L*.225,top-.10),(side*w*.447,L*.35,top-.10),(side*w*.479,L*.425,h*.54),(side*w*.49,L*.225,h*.54)],[(0,1,2,3),(3,2,1,0)],'glass')
        ya=L*.383;yb=L*.458;za=top+(nose-top)*(.383-.365)/(.487-.365)+.018;zb=top+(nose-top)*(.458-.365)/(.487-.365)+.018
        legacy.mesh('Batch windscreen',[(-w*.38,ya,za),(w*.38,ya,za),(w*.38,yb,zb),(-w*.38,yb,zb)],[(0,1,2,3),(3,2,1,0)],'glass')
        if kind in ['ambulance','fire_engine']:
            for obj in bpy.context.scene.objects:
                if obj.name.startswith('Emergency beacon'):obj.location.y=L*.28;obj.location.z=top+.08
        if kind=='fire_engine':
            for y in [-L*.33,L*.15]:
                legacy.box('Ladder rack',(0,y,h*.815),(.70,.06,h*.19),'metal')
        if kind=='military':
            cargo=bpy.data.objects.get('Cargo body');bpy.data.objects.remove(cargo,do_unlink=True)
            for obj in list(bpy.context.scene.objects):
                if obj.name.startswith('Canvas edge'):bpy.data.objects.remove(obj,do_unlink=True)
            section=[(-w*.46,h*.32),(-w*.46,h*.74),(-w*.36,h*.90),(w*.36,h*.90),(w*.46,h*.74),(w*.46,h*.32)]
            verts=[(x,y,z) for y in [-L*.48,L*.17] for x,z in section]
            legacy.mesh('Faceted utility canvas',verts,[(i,(i+1)%6,(i+1)%6+6,i+6) for i in range(6)]+[(5,4,3,2,1,0),(6,7,8,9,10,11)],'olive')
    if kind=='plane':
        for obj in list(bpy.context.scene.objects):
            if not obj.name.startswith('Cabin window'):continue
            side=1 if obj.location.x>0 else -1
            x=obj.location.x+side*obj.dimensions.x*.5;y=obj.location.y;z=obj.location.z;dy=obj.dimensions.y*.5;dz=obj.dimensions.z*.5
            bpy.data.objects.remove(obj,do_unlink=True)
            legacy.mesh('Batch cabin pane',[(x,y-dy,z-dz),(x,y+dy,z-dz),(x,y+dy,z+dz),(x,y-dy,z+dz)],[(0,1,2,3),(3,2,1,0)],'glass')
        for x,y in [(-.6,-1),(.6,-1),(0,3)]:legacy.box('Landing gear strut',(x,y,.39),(.06,.06,.47),'metal')
        for side in [-1,1]:legacy.box('Engine wing pylon',(side*2.5,-.65,.98),(.12,.67,.30),'metal')
        fin=bpy.data.objects.get('Vertical tail')
        for v in fin.data.vertices:
            if v.co.z>0:v.co.y=v.co.y*.42-.25


def _swept_samples(root,motion):
    samples=[]
    nodes={o.name:o for o in root.children_recursive}
    for index in range(16):
        phase=index*math.tau/16
        for entry in motion.get('wheels',[]):
            node=nodes[entry['node']]
            if entry['steer']:node.rotation_euler.z=[-.45,0,.45][index%3]
            spin=next(child for child in node.children if child.name.startswith('Spin'))
            spin.rotation_euler.x=phase
        for entry in motion.get('rotors',[]):
            node=nodes[entry['node']]
            node.rotation_euler[2 if entry['axis']=='Y' else 0]=phase
        samples.append(common.bounds(root.children_recursive))
    for entry in motion.get('wheels',[]):
        node=nodes[entry['node']];node.rotation_euler.z=0
        next(child for child in node.children if child.name.startswith('Spin')).rotation_euler.x=0
    for entry in motion.get('rotors',[]):nodes[entry['node']].rotation_euler=(0,0,0)
    return samples


def build_vehicle(kind: str, detail: str, envelope: dict) -> dict:
    """Build selected kind in the current Blender scene; return validated metadata."""
    global ROOT
    if kind not in KINDS or detail not in ['detailed','middle','far']: raise ValueError('unknown vehicle or tier')
    legacy.FAR=detail=='far';legacy.reset()
    builder=legacy.road if kind in KINDS[:12] else legacy.rail if kind in ['train','subway'] else legacy.boat if kind in ['ship','sailboat'] else legacy.air
    passenger=detail=='detailed' and kind in ['car','compact','sedan','taxi','police']
    if passenger: motion=_passenger_detail(kind)
    elif detail=='detailed' and kind=='helicopter':motion=_helicopter_detail()
    else:
        builder(kind)
        if kind=='bus':
            # Continuous raised roof band connects the former detached roof lip.
            legacy.box('Supported bus roof band',(0,0,2.8925),(2.48,8.95,.125),'cream')
        motion={}
    if detail=='detailed' and not passenger and kind!='helicopter':
        _replace_lofts(kind)
        if kind in KINDS[:12]:_road_body(kind)
        # Round broad roofs, cargo bodies and equipment; never round glazing
        # into a translucent lump or decimate wheels/rotor contact geometry.
        for obj in list(bpy.context.scene.objects):
            if obj.type=='MESH' and len(obj.data.vertices)==8 and not obj.name.startswith(('Main rotor','Cross rotor','Tail rotor','Tail cross')):
                common.bevel(obj,min(obj.dimensions)*.14,2)
        _utility_cab(kind)
        _details(kind)
        _transit_marks(kind)
        motion=_moving_parts(kind)
    elif detail!='detailed':
        _batch_structure(kind)
        _batch_palette(kind)
        # Keep the established batch complexity. Six shared paints maximum.
        for old,new in [('light','cream'),('white','cream'),('gold','cream')]:
            used={m for o in bpy.context.scene.objects if o.type=='MESH' for m in o.data.materials}
            if len(used)<=6:break
            for obj in bpy.context.scene.objects:
                if obj.type=='MESH':
                    for slot in obj.material_slots:
                        if slot.material==legacy.MATS[old]:slot.material=legacy.MATS[new]
    ROOT=common.pivot(kind.title().replace('_','')+'Model')
    for obj in list(bpy.context.scene.objects):
        if obj==ROOT or obj.parent is not None:continue
        if obj.type=='MESH':
            bpy.context.view_layer.objects.active=obj
            bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
            bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
        obj.parent=ROOT
    samples=_swept_samples(ROOT,motion) if detail=='detailed' else []
    swept=[[min(b[0][i] for b in samples) for i in range(3)],[max(b[1][i] for b in samples) for i in range(3)]] if samples else None
    if swept: swept[0][2]=common.bounds(ROOT.children_recursive)[0][2]
    factors,offset=common.normalize(ROOT,envelope['size_godot'],kind in ['ship','sailboat'],detail!='detailed',swept)
    for wheel in motion.get('wheels',[]):
        wheel['radius_m']*=factors[2]
        wheel['axle_source_m']=[(value+offset[i])*factors[i] for i,value in enumerate(wheel['axle_source_m'])]
    if 'wheel_radius_m' in motion:motion['wheel_radius_m']*=factors[2]
    contacts=[]
    for obj in ROOT.children_recursive:
        if obj.type=='MESH' and obj.name.startswith(('Rubber tire','Landing wheel','Rounded road tire','Rounded tyre','Landing skid')):
            contacts.append({'node':obj.name,'bounds_source_m':common.bounds([obj])})
    motion_bounds=_swept_samples(ROOT,motion) if detail=='detailed' else []
    common.merge_static(ROOT)
    result=common.measurements(ROOT)
    result['contact_parts']=contacts
    result['motion_bounds_source_m']=motion_bounds
    low,high=result['bounds_source_m']
    result.update(kind=kind,tier='near' if detail=='detailed' else detail,
        units='meters',meters_per_tile=16,source_forward='+Y',source_up='+Z',godot_forward='-Z',godot_up='+Y',
        origin='waterline' if kind in ['ship','sailboat'] else 'contact',
        envelope_m=envelope['size_godot'],motion=motion,
        contact_error_m=0 if kind in ['ship','sailboat'] and low[2]<0<high[2] else abs(low[2]))
    # Floating point fits need a tight tolerance only in recorded measurements.
    result['size_m']=[min(a,b) if a-b<1e-5 else a for a,b in zip(result['size_m'],result['envelope_m'])]
    errors=validate_model(result)
    if errors:raise ValueError((kind,detail,errors,result))
    return result
