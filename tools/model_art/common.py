# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Blender source helpers. World-meter geometry, explicit pivot hierarchy."""
import math
import bpy
from mathutils import Vector


def pivot(name, location=(0,0,0), parent=None):
    node=bpy.data.objects.new(name,None)
    bpy.context.collection.objects.link(node)
    node.parent=parent
    node.location=location
    return node


def bounds(objects):
    bpy.context.view_layer.update()
    points=[o.matrix_world@v.co for o in objects if o.type=='MESH' for v in o.data.vertices]
    return [[min(p[i] for p in points) for i in range(3)],
            [max(p[i] for p in points) for i in range(3)]]


def measurements(root):
    objects=list(root.children_recursive)
    low,high=bounds(objects)
    return dict(triangles=sum(len(p.vertices)-2 for o in objects if o.type=='MESH' for p in o.data.polygons),
                materials=len({m for o in objects if o.type=='MESH' for m in o.data.materials}),
                bounds_source_m=[low,high],size_m=[high[0]-low[0],high[2]-low[2],high[1]-low[1]],
                nodes=[o.name for o in objects],
                material_names=sorted({m.name for o in objects if o.type=='MESH' for m in o.data.materials}),
                mesh_parts=sum(o.type=='MESH' for o in objects))


def bevel(obj, width, segments=2):
    if width<=0: return
    bpy.context.view_layer.objects.active=obj
    mod=obj.modifiers.new('Manufactured rolled edge','BEVEL')
    mod.width=width;mod.segments=segments
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # Weighted corner normals keep broad sheet metal planar.
    mod=obj.modifiers.new('Panel corner normals','WEIGHTED_NORMAL')
    bpy.ops.object.modifier_apply(modifier=mod.name)


def rounded_loft(builder, name, rings, material, segments=16, ellipse=False):
    """Rounded trapezoidal sections; longitudinal stations are authored, not a box bevel."""
    vertices=[]
    for y,wb,wt,zb,zt in rings:
        for i in range(segments):
            angle=math.tau*i/segments
            s,c=math.sin(angle),math.cos(angle)
            zunit=math.copysign(abs(s)**(.9 if ellipse else .35),s)
            width=wb+(wt-wb)*(zunit+1)*.5
            x=width*math.copysign(abs(c)**(.9 if ellipse else .35),c)
            vertices.append((x,y,(zb+zt)*.5+zunit*(zt-zb)*.5))
    faces=[tuple(range(segments-1,-1,-1))]
    for ring in range(len(rings)-1):
        for j in range(segments): faces.append((ring*segments+j,(ring+1)*segments+j,(ring+1)*segments+(j+1)%segments,ring*segments+(j+1)%segments))
    faces.append(tuple(range((len(rings)-1)*segments,len(rings)*segments)))
    obj=builder.mesh(name,vertices,faces,material)
    for poly in obj.data.polygons: poly.use_smooth=len(poly.vertices)==4
    return obj


def normalize(root, target_size, waterline=False, exact=False, swept_bounds=None):
    """Fit visual only. Physical envelope values are never inferred from changed art."""
    low,high=swept_bounds if swept_bounds is not None else bounds(root.children_recursive)
    source_size=[high[i]-low[i] for i in range(3)]
    desired=[target_size[0],target_size[2],target_size[1]]
    factors=[desired[i]/source_size[i] for i in range(3)]
    if not exact: factors=[min(factors)*.999999]*3
    offset=[-(high[0]+low[0])*.5,-(high[1]+low[1])*.5,0 if waterline else -low[2]]
    # Bake into local meshes and empty translations, retaining identity scale pivots.
    for obj in [root]+list(root.children_recursive):
        if obj==root: continue
        if obj.parent==root: obj.location=Vector([(obj.location[i]+offset[i])*factors[i] for i in range(3)])
        else: obj.location=Vector([obj.location[i]*factors[i] for i in range(3)])
        if obj.type=='MESH':
            # Builders apply rotations before parenting; local coordinates have source axes.
            for v in obj.data.vertices: v.co=Vector([v.co[i]*factors[i] for i in range(3)])
    return factors,offset


def merge_static(root):
    groups={}
    for obj in list(root.children_recursive):
        if obj.type=='MESH': groups.setdefault((obj.parent,obj.data.materials[0]),[]).append(obj)
    for (parent,material),parts in groups.items():
        if len(parts)<2: continue
        bpy.ops.object.select_all(action='DESELECT')
        for obj in parts: obj.select_set(True)
        bpy.context.view_layer.objects.active=parts[0]
        bpy.ops.object.join();parts[0].name=parent.name+' '+material.name


def export(root,path):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [root]+list(root.children_recursive): obj.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
        export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
    # Blender globally uniquifies empty names. Child Spin is a local path contract.
    import json,struct
    data=path.read_bytes();at=12;chunks=[]
    while at<len(data):
        size,kind=struct.unpack_from('<II',data,at);at+=8;payload=data[at:at+size];at+=size
        if kind==0x4e4f534a:
            doc=json.loads(payload)
            for node in doc.get('nodes',[]):
                if 'mesh' not in node and node.get('name','').startswith('Spin.'): node['name']='Spin'
            payload=json.dumps(doc,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4)
        chunks.append(struct.pack('<II',len(payload),kind)+payload)
    body=b''.join(chunks);path.write_bytes(struct.pack('<III',0x46546c67,2,12+len(body))+body)
    # glTF discards redundant double-sided faces; budgets and manifest counts
    # describe the actual exported indexed triangles, with source count retained.
    return sum(doc['accessors'][primitive['indices']]['count']//3
               for mesh in doc.get('meshes',[]) for primitive in mesh.get('primitives',[]))
