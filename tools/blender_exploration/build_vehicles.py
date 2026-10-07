# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Owned low-poly exploration vehicles. Blender 5.2+: --background --python this.py.
Meters, Blender +Y forward/+Z up; GLB converts to Godot -Z forward/+Y up.
Only model mesh objects and named pivot empties are exported; studio is preview-only.
"""
import bpy, math, json, argparse, sys, struct
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/blender-exploration'
EXPORT=ROOT/'game/assets/desert-dreams-exploration'
PREVIEW=SOURCE/'previews'
MAT={}

def material(name,color,metal=0.0,rough=.48):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
    MAT[name]=m;return m

def reset():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for m in list(bpy.data.materials):bpy.data.materials.remove(m)
    MAT.clear()
    for name,c,metal,rough in [
        ('Copper enamel',(.58,.225,.095),.38,.32),('Warm cream',(.88,.79,.59),.12,.42),
        ('Deep teal enamel',(.035,.245,.255),.32,.34),('Teal canopy',(.055,.18,.205),.52,.22),
        ('Rubber charcoal',(.025,.032,.035),.0,.8),('Warm alloy',(.58,.58,.49),.72,.28),
        ('Dark grille',(.055,.07,.065),.35,.54),('Ivory lamp',(.98,.89,.59),.18,.22),
        ('Amber lamp',(.96,.40,.065),.12,.25),('Red lamp',(.58,.045,.022),.1,.24),
        ('Blade graphite',(.065,.09,.095),.35,.48),('Seat leather',(.25,.115,.055),0,.75)]:material(name,c,metal,rough)

def pivot(name,loc=(0,0,0),parent=None):
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=loc;o.parent=parent;return o

def finish(o,name,mat,parent,bevel=0):
    o.name=name;o.data.materials.append(MAT[mat]);o.parent=parent
    if bevel:
        mod=o.modifiers.new('Small manufactured edge','BEVEL');mod.width=bevel;mod.segments=1
        bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
    return o

def box(name,loc,size,mat,parent,bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,name,mat,parent,bevel)

def cylinder(name,loc,radius,depth,mat,parent,axis='Z',vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=loc)
    o=bpy.context.object
    if axis=='X':o.rotation_euler.y=math.pi/2
    elif axis=='Y':o.rotation_euler.x=math.pi/2
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    return finish(o,name,mat,parent)

def rod(name,a,b,radius,mat,parent,vertices=8):
    a,b=Vector(a),Vector(b);o=cylinder(name,(a+b)*.5,radius,(b-a).length,mat,parent,vertices=vertices)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o

def mesh(name,vertices,faces,mat,parent):
    m=bpy.data.meshes.new(name);m.from_pydata(vertices,[],faces);m.update();o=bpy.data.objects.new(name,m);bpy.context.collection.objects.link(o);return finish(o,name,mat,parent)

def panel(name,pts,mat,parent):return mesh(name,pts,[tuple(range(len(pts)))],mat,parent)

def loft(name,rings,mat,parent):
    # Rings: y, bottom half-width, top half-width, bottom z, top z.
    verts=[]
    for y,wb,wt,zb,zt in rings:verts += [(-wb,y,zb),(wb,y,zb),(wt,y,zt),(-wt,y,zt)]
    faces=[(3,2,1,0)]
    for i in range(len(rings)-1):
        for j in range(4):faces.append((i*4+j,i*4+(j+1)%4,(i+1)*4+(j+1)%4,(i+1)*4+j))
    faces.append(tuple(range((len(rings)-1)*4,len(rings)*4)))
    return mesh(name,verts,faces,mat,parent)

def torus(name,loc,major,minor,mat,parent,axis='X',major_segments=16,minor_segments=6):
    bpy.ops.mesh.primitive_torus_add(major_radius=major,minor_radius=minor,major_segments=major_segments,minor_segments=minor_segments,location=loc)
    o=bpy.context.object
    if axis=='X':o.rotation_euler.y=math.pi/2
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    return finish(o,name,mat,parent)

def car():
    root=pivot('CarModel')
    body=loft('Sculpted cruiser body',[(-2.02,.67,.70,.32,.55),(-1.82,.85,.88,.31,.65),(-.95,.86,.88,.29,.70),(.85,.86,.88,.29,.70),(1.74,.84,.87,.32,.63),(2.03,.72,.77,.34,.55)],'Copper enamel',root)
    # Real wheel-well cutouts keep tyre and fender silhouettes distinct.
    for side in [-1,1]:
        for y in [-1.35,1.34]:
            cutter=cylinder('Temporary wheel arch cutter',(side*.83,y,.24),.282,.36,'Dark grille',root,'X',20)
            mod=body.modifiers.new('Wheel arch','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
            bpy.context.view_layer.objects.active=body;bpy.ops.object.modifier_apply(modifier=mod.name)
            bpy.data.objects.remove(cutter,do_unlink=True)
    loft('Cream hardtop cabin',[(-.92,.69,.57,.68,.80),(-.57,.69,.59,.69,1.19),(.52,.69,.59,.69,1.19),(1.0,.69,.58,.69,.86)],'Warm cream',root)
    box('Floating cream roof',(-0.,-.03,1.205),(1.26,1.15,.045),'Warm cream',root,.02)
    # Dark glass panes sit just proud of the trapezoidal cabin faces.
    panel('Wide front windscreen',[(-.584,.536,1.185),(.584,.536,1.185),(.568,.945,.908),(-.568,.945,.908)],'Teal canopy',root)
    # Rear loft rises from .85014m at y=-.875 to 1.15657m at y=-.60.
    # The full-height rear windshield sits 15-19mm above it, inside side frames.
    panel('Rear wraparound glass',[(-.575,-.60,1.172),(-.559,-.875,.869),(.559,-.875,.869),(.575,-.60,1.172)],'Teal canopy',root)
    for side in [-1,1]:
        x=lambda value:side*value
        # Mirroring X requires reversing the right pane's face winding.
        panel('Side front glass'+str(side),[(x(.604),.48,1.16),(x(.686),.875,.84),(x(.693),-.035,.735),(x(.608),-.035,1.16)][::(-1 if side>0 else 1)],'Teal canopy',root)
        panel('Side rear quarter glass'+str(side),[(x(.608),-.085,1.16),(x(.693),-.085,.735),(x(.69),-.84,.735),(x(.60),-.55,1.16)][::(-1 if side>0 else 1)],'Teal canopy',root)
        rod('Slim B pillar'+str(side),(x(.692),-.06,.74),(x(.604),-.06,1.17),.018,'Warm cream',root)
        rod('Side belt chrome'+str(side),(x(.884),-1.73,.60),(x(.884),1.67,.60),.012,'Warm alloy',root)
        rod('Door lower seam'+str(side),(x(.885),-.78,.35),(x(.885),.72,.35),.005,'Dark grille',root,6)
        rod('Door trailing seam'+str(side),(x(.886),-.79,.36),(x(.886),-.79,.66),.005,'Dark grille',root,6)
        box('Chrome door handle'+str(side),(x(.898),-.49,.665),(.023,.17,.025),'Warm alloy',root,.006)
        rod('Mirror stalk'+str(side),(x(.68),.70,.79),(x(.91),.71,.84),.012,'Warm alloy',root)
        box('Mirror shell'+str(side),(x(.91),.72,.855),(.07,.13,.075),'Copper enamel',root,.015)
        box('Mirror reflective face'+str(side),(x(.911),.647,.855),(.05,.008,.052),'Warm alloy',root)
        # Raised sculptural fender shoulders, separate from rolling wheels.
        for y in [-1.35,1.35]:
            box('Fender crown '+str((side,y)),(x(.80),y,.605),(.17,.72,.16),'Copper enamel',root,.06)
        box('Rear amber fin jewel'+str(side),(x(.735),-1.94,.598),(.10,.055,.075),'Red lamp',root,.008)
        cylinder('Round headlamp'+str(side),(x(.56),2.038,.52),.105,.035,'Warm alloy',root,'Y',16)
        cylinder('Headlamp lens'+str(side),(x(.56),2.060,.52),.081,.019,'Ivory lamp',root,'Y',16)
        box('Front amber indicator'+str(side),(x(.76),2.02,.405),(.105,.025,.04),'Amber lamp',root,.008)
        box('Tail light'+str(side),(x(.59),-2.037,.48),(.21,.025,.095),'Red lamp',root,.014)
    # Hood ridge, restrained grille and polished bumpers; no logo/badge.
    rod('Hood centre pressed ridge',(0,.99,.712),(0,1.93,.587),.014,'Warm cream',root)
    box('Inset grille',(0,2.036,.435),(.77,.027,.16),'Dark grille',root,.015)
    for x in [-.33,-.22,-.11,0,.11,.22,.33]:box('Grille upright',(x,2.054,.435),(.017,.018,.125),'Warm alloy',root)
    for y in [-2.105,2.115]:box('Rounded bumper',(0,y,.335),(1.66,.08,.075),'Warm alloy',root,.025)
    box('Blank rear plate recess',(0,-2.058,.48),(.29,.018,.095),'Dark grille',root,.01)
    for side in [-1,1]:
        for front in [True,False]:
            y=1.34 if front else -1.35
            wheel=pivot(('WheelFront' if front else 'WheelRear')+('Left' if side<0 else 'Right'),(side*.74,y,.24),root)
            spin=pivot('Spin',(0,0,0),wheel)
            # Rounded tyre radius=.24, width=.15, wheel center leaves steering clearance.
            torus('Rounded tyre',(0,0,0),.183,.057,'Rubber charcoal',spin)
            cylinder('Tyre core',(0,0,0),.197,.14,'Rubber charcoal',spin,'X',16)
            for outside in [-1,1]:
                cylinder('Recessed rim',(outside*.076,0,0),.147,.014,'Warm alloy',spin,'X',12)
                cylinder('Dark wheel inset',(outside*.085,0,0),.112,.006,'Dark grille',spin,'X',12)
                cylinder('Copper hubcap',(outside*.09,0,0),.073,.019,'Copper enamel',spin,'X',12)
                for ang in range(0,360,60):
                    a=math.radians(ang)
                    rod('Radial alloy spoke',(outside*.091,math.sin(a)*.065,math.cos(a)*.065),(outside*.091,math.sin(a)*.132,math.cos(a)*.132),.012,'Warm alloy',spin,6)
            for i in range(16):
                a=i*math.tau/16; tread=box('Raised tyre tread',(0,math.sin(a)*.232,math.cos(a)*.232),(.10,.042,.014),'Rubber charcoal',spin)
                tread.rotation_euler.x=-a
    return root

def helicopter():
    root=pivot('HelicopterModel')
    loft('Cream scout fuselage',[(-1.03,.26,.31,.60,1.27),(-.62,.49,.46,.48,1.59),(.44,.51,.44,.49,1.67),(1.15,.40,.35,.58,1.36),(1.47,.22,.20,.70,1.02)],'Warm cream',root)
    loft('Teal belly',[(-.86,.23,.39,.53,.78),(.48,.32,.49,.43,.73),(1.37,.18,.32,.61,.83)],'Deep teal enamel',root)
    # Broad canopy separated into individually framed panes.
    panel('Front canopy left',[(-.025,1.48,1.025),(-.205,1.468,1.025),(-.351,1.157,1.366),(-.025,1.155,1.385)],'Teal canopy',root)
    panel('Front canopy right',[(.025,1.48,1.025),(.025,1.155,1.385),(.351,1.157,1.366),(.205,1.468,1.025)],'Teal canopy',root)
    for side in [-1,1]:
        x=lambda value:side*value
        panel('Pilot side glazing'+str(side),[(x(.452),.43,1.64),(x(.363),1.14,1.35),(x(.404),1.13,.91),(x(.505),.43,.85)],'Teal canopy',root)
        panel('Cabin side glazing'+str(side),[(x(.459),.36,1.62),(x(.474),-.54,1.55),(x(.501),-.57,.88),(x(.515),.36,.85)],'Teal canopy',root)
        rod('Canopy frame A'+str(side),(x(.45),.43,1.65),(x(.51),.43,.83),.025,'Warm cream',root)
        rod('Canopy lower frame'+str(side),(x(.51),-.56,.84),(x(.405),1.14,.88),.02,'Warm cream',root)
        rod('Door seam'+str(side),(x(.508),-.64,.72),(x(.482),-.64,1.47),.009,'Deep teal enamel',root)
        box('Cabin handle'+str(side),(x(.52),-.38,.81),(.02,.15,.035),'Warm alloy',root,.008)
        # Low skids make the airframe visibly grounded at rest.
        rod('Landing skid'+str(side),(x(.67),-1.04,.055),(x(.67),1.14,.055),.055,'Dark grille',root,10)
        rod('Skid raised nose'+str(side),(x(.67),1.14,.055),(x(.67),1.36,.19),.055,'Dark grille',root,10)
        for y in [-.57,.65]:rod('Skid strut'+str((side,y)),(x(.41),y,.64),(x(.67),y,.11),.036,'Warm alloy',root)
        box('Amber body stripe'+str(side),(x(.506),-.10,.755),(.015,1.25,.045),'Amber lamp',root)
        cylinder('Navigation lamp'+str(side),(x(.512),-.43,1.45),.039,.032,'Red lamp' if side<0 else 'Amber lamp',root,'X',8)
    rod('Canopy center mullion',(0,1.49,1.01),(0,1.155,1.40),.021,'Warm cream',root)
    cylinder('Nose landing lamp',(0,1.47,.805),.075,.04,'Ivory lamp',root,'Y',12)
    loft('Tapered tail boom',[(-2.03,.055,.07,1.08,1.29),(-1.45,.105,.12,.97,1.25),(-.77,.25,.25,.76,1.24)],'Deep teal enamel',root)
    # Side fin is vertically shaped and below the main-rotor height.
    mesh('Tail stabilizer fin',[(-.035,-2.01,1.11),(.035,-2.01,1.11),(-.035,-1.82,1.88),(.035,-1.82,1.88),(-.035,-1.61,1.16),(.035,-1.61,1.16)],[(0,2,4),(1,5,3),(0,1,3,2),(2,3,5,4),(4,5,1,0)],'Warm cream',root)
    box('Tail horizontal stabilizer',(0,-1.57,1.17),(.79,.24,.045),'Warm cream',root,.015)
    loft('Engine cowling',[(-.72,.27,.21,1.45,1.80),(-.12,.31,.25,1.56,1.86),(.19,.20,.16,1.59,1.79)],'Deep teal enamel',root)
    for side in [-1,1]:
        for i in range(5):box('Engine vent louvre',(side*.291,-.45+i*.07,1.685),(.027,.035,.11),'Dark grille',root,.005)
        cylinder('Engine exhaust',(side*.225,-.72,1.655),.055,.17,'Warm alloy',root,'Y',10)
        cylinder('Exhaust opening',(side*.225,-.812,1.655),.04,.012,'Dark grille',root,'Y',10)
    cylinder('Rotor transmission',(0,0,1.87),.15,.18,'Warm alloy',root,vertices=12)
    cylinder('Rotor mast',(0,0,2.015),.045,.20,'Dark grille',root,vertices=10)
    rotor=pivot('MainRotor',(0,0,2.115),root)
    cylinder('Main rotor hub',(0,0,0),.14,.07,'Warm alloy',rotor,vertices=12)
    for i in range(3):
        a=i*math.tau/3
        coords=[(.11,-.065,0),(1.72,-.075,0),(2.07,-.015,0),(2.03,.09,0),(.27,.115,0)]
        verts=[]
        for z in [-.012,.012]:
            verts.extend([(x*math.cos(a)-y*math.sin(a),x*math.sin(a)+y*math.cos(a),z) for x,y,_ in coords])
        faces=[tuple(range(4,-1,-1)),tuple(range(5,10))]+[(j,(j+1)%5,(j+1)%5+5,j+5) for j in range(5)]
        mesh('Main rotor blade'+str(i),verts,faces,'Blade graphite',rotor)
        # Painted high-visibility outer strip, no translucent rotor-disk substitute.
        tip=box('Amber rotor tip'+str(i),(1.96*math.cos(a),1.96*math.sin(a),.014),(.13,.10,.007),'Amber lamp',rotor);tip.rotation_euler.z=a
    tail=pivot('TailRotor',(.115,-1.87,1.39),root)
    cylinder('Tail rotor hub',(0,0,0),.072,.12,'Warm alloy',tail,'X',10)
    for i in range(2):
        a=i*math.pi
        blade=box('Tail rotor blade'+str(i),(.07,math.sin(a)*.17,math.cos(a)*.17),(.025,.064,.31),'Blade graphite',tail,.008)
        blade.rotation_euler.x=-a
        tip=box('Tail amber tip'+str(i),(.087,math.sin(a)*.3,math.cos(a)*.3),(.009,.06,.045),'Amber lamp',tail);tip.rotation_euler.x=-a
    return root

def objects_under(root):return [root]+list(root.children_recursive)
def bounds(root):
    bpy.context.view_layer.update();points=[o.matrix_world@v.co for o in objects_under(root) if o.type=='MESH' for v in o.data.vertices]
    return [[min(v[i] for v in points) for i in range(3)],[max(v[i] for v in points) for i in range(3)]]
def look_at(obj,target):obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
def preview(root,name):
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
    scene.render.resolution_x=1024;scene.render.resolution_y=1024;scene.render.resolution_percentage=100
    scene.world.color=(.22,.22,.22);scene.view_settings.view_transform='AgX'
    # Studio elements never appear in the selected GLB export.
    ground=box('Preview ground',(0,0,-.055),(200,200,.10),'Warm cream',None)
    ground.data.materials.clear();ground.data.materials.append(material('Preview sand',(.19,.155,.12),0,.8))
    for name_l,loc,power,size in [('Key',(4,2,7),1100,5),('Fill',(-4,0,4),750,4),('Rim',(1,-5,5),1000,3)]:
        data=bpy.data.lights.new(name_l,'AREA');data.energy=power;data.shape='DISK';data.size=size;o=bpy.data.objects.new(name_l,data);bpy.context.collection.objects.link(o);o.location=loc;look_at(o,(0,0,.8))
    data=bpy.data.cameras.new('Preview camera');cam=bpy.data.objects.new('Preview camera',data);bpy.context.collection.objects.link(cam);scene.camera=cam;data.type='ORTHO';data.ortho_scale=6.2;data.clip_end=1000
    views=[('three-quarter',(5.8,7.8,5.0)),('front',(0,9,2.8))]
    if name=='car':views.append(('rear-three-quarter',(5.8,-7.8,4.2)))
    for suffix,loc in views:
        data.ortho_scale=(3.7 if name=='car' else 5.2) if suffix=='front' else 6.2
        cam.location=loc;look_at(cam,(0,0,.8));scene.render.filepath=str(PREVIEW/(name+'-'+suffix+'.png'));bpy.ops.render.render(write_still=True)
    # Keep studio editable but hidden from render only through its collection convention.

def merge_by_pivot_material(root):
    groups={}
    for o in objects_under(root):
        if o.type=='MESH':groups.setdefault((o.parent,o.data.materials[0].name),[]).append(o)
    for (parent,mat),parts in groups.items():
        if len(parts)<2:continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in parts:o.select_set(True)
        bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join()
        parts[0].name=parent.name+' '+mat

def normalize_glb_pivots(path):
    data=path.read_bytes();magic,version,length=struct.unpack_from('<III',data);at=12;chunks=[]
    while at<len(data):
        size,kind=struct.unpack_from('<II',data,at);at+=8;payload=data[at:at+size];at+=size
        if kind==0x4e4f534a:
            doc=json.loads(payload)
            for node in doc['nodes']:
                if 'mesh' not in node and node.get('name','').startswith('Spin.') and node['name'][5:].isdigit():node['name']='Spin'
            payload=json.dumps(doc,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4)
        chunks.append(struct.pack('<II',len(payload),kind)+payload)
    body=b''.join(chunks);path.write_bytes(struct.pack('<III',magic,version,12+len(body))+body)

def build(name):
    reset();bpy.context.preferences.filepaths.save_version=0;root=car() if name=='car' else helicopter();bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1.0
    bpy.context.view_layer.update();rest=bounds(root)
    merge_by_pivot_material(root)
    triangles=sum(len(poly.vertices)-2 for o in objects_under(root) if o.type=='MESH' for poly in o.data.polygons)
    if name=='car':
        wheel_nodes=[o for o in objects_under(root) if o.name.startswith('WheelFront')]
        measured=[]
        for angle in [-35,-20,0,20,35]:
            for o in wheel_nodes:o.rotation_euler.z=math.radians(angle)
            measured.append({'steering_degrees':angle,'bounds_blender':bounds(root)})
        for o in wheel_nodes:o.rotation_euler.z=0
        assert triangles<=6500,triangles
        assert all(b['bounds_blender'][0][0]>=-.96 and b['bounds_blender'][1][0]<=.96 and b['bounds_blender'][0][1]>=-2.24 and b['bounds_blender'][1][1]<=2.24 and b['bounds_blender'][0][2]>=-.001 and b['bounds_blender'][1][2]<=1.28 for b in measured),measured
    else:
        measured=[];main=next(o for o in objects_under(root) if o.name=='MainRotor');tail=next(o for o in objects_under(root) if o.name=='TailRotor')
        for i in range(72):
            main.rotation_euler.z=i*math.tau/72;tail.rotation_euler.x=i*math.tau/72
            measured.append({'phase_degrees':i*5,'bounds_blender':bounds(root)})
        main.rotation_euler.z=0;tail.rotation_euler.x=0
        assert all(b['bounds_blender'][0][0]>=-4 and b['bounds_blender'][1][0]<=4 and b['bounds_blender'][0][1]>=-2.24 and b['bounds_blender'][1][1]<=2.24 and b['bounds_blender'][0][2]>=-.001 and b['bounds_blender'][1][2]<=2.24 for b in measured),measured
    bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT')
    for o in objects_under(root):o.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(EXPORT/(name+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_apply=True)
    normalize_glb_pivots(EXPORT/(name+'.glb'))
    hierarchy=[{'name':o.name,'parent':o.parent.name if o.parent else None,'type':o.type} for o in objects_under(root)]
    if name=='car':
        motion_contract='Front wheel parent yaw +/-35 degrees; child Spin rolls local X'
    else:
        motion_contract='MainRotor turns GodotY; TailRotor turns GodotX; physical box unchanged'
    info={
        'name':name,
        'units':'meters',
        'blender_forward':'+Y',
        'godot_forward':'-Z',
        'runtime_scale':.0625,
        'triangles':triangles,
        'rest_bounds_blender':rest,
        'motion_bounds_samples':measured,
        'hierarchy':hierarchy,
        'materials':[{'name':m.name,'rgba':list(m.diffuse_color)} for m in MAT.values()],
        'owned_geometry':True,
        'external_textures':False,
        'motion_contract':motion_contract,
    }
    (PREVIEW/(name+'.json')).write_text(json.dumps(info,indent=2)+'\n')
    preview(root,name)
    # Save full editable model + preview studio. Root selects precisely exportable model.
    bpy.ops.object.select_all(action='DESELECT');root.select_set(True);bpy.context.view_layer.objects.active=root
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
    print('VEHICLE_COMPLETE',name,'triangles',triangles,'bounds',rest)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--only',choices=['car','helicopter']);argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [];args=parser.parse_args(argv)
    for p in [SOURCE,EXPORT,PREVIEW]:p.mkdir(parents=True,exist_ok=True)
    for name in ([args.only] if args.only else ['car','helicopter']):build(name)
