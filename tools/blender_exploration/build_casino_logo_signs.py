# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Physical logo cabinets with original illustrated enamel and light maps.

Run prepare_casino_sign_textures.py, then this script in Blender, then
casino_sign_models.py. Editable masters and full-resolution illustrations
stay under assets/casino-signs, outside the runtime package.
"""
import argparse
import json
import math
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/casino-signs'


def rgb(value):
    a=[int(value[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in a)


def material(name,color,metal=0,emission=None):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    node=mat.node_tree.nodes['Principled BSDF']
    node.inputs['Base Color'].default_value=(*rgb(color),1)
    node.inputs['Metallic'].default_value=metal
    node.inputs['Roughness'].default_value=.52
    if emission:
        node.inputs['Emission Color'].default_value=(*rgb(emission),1)
        node.inputs['Emission Strength'].default_value=.035
    return mat


class Cabinet:
    def __init__(self,row):
        self.row=row;self.w=row['width'];self.h=row['height']
        self.c=Vector(row['center']);self.objects=[]
        self.case=material('sign_logo_case','343632',.6)
        self.metal=material('sign_logo_metal',row['metal'],.55)
        self.neon=material('sign_logo_neon_a',row['a'],.05,row['a'])
        self.face=material('sign_logo_letters','ffffff')
        shader=self.face.node_tree.nodes['Principled BSDF']
        for suffix,target in [('color','Base Color'),('light','Emission Color')]:
            tex=self.face.node_tree.nodes.new('ShaderNodeTexImage')
            tex.image=bpy.data.images.load(str(SOURCE/'textures'/f'{row["code"]}-{suffix}.png'),check_existing=True)
            self.face.node_tree.links.new(tex.outputs['Color'],shader.inputs[target])
        shader.inputs['Emission Strength'].default_value=.035
        shader.inputs['Metallic'].default_value=0
        shader.inputs['Roughness'].default_value=.68

    def point(self,x,y,z):return (self.c.x+x*self.w/2,-(self.c.z+z),self.c.y+y*self.h/2)

    def mesh(self,name,vertices,faces,mat):
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
        bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
        ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);mesh.materials.append(mat)
        self.objects.append(ob)
        return ob

    def plate(self,points,depth,thickness,mat):
        count=len(points);contour=[Vector((x,y,0)) for x,y in points]
        lookup={tuple(v):i for i,v in enumerate(contour)}
        tris=[list(t) if isinstance(t[0],int) else [lookup[tuple(v)] for v in t] for t in tessellate_polygon([contour])]
        vertices=[self.point(x,y,z) for z in (depth-thickness,depth) for x,y in points]
        faces=[tuple(t) for t in tris]+[tuple(i+count for i in t) for t in tris]
        faces += [(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
        return self.mesh('Shaped metal cabinet',vertices,faces,mat)

    def front(self,points):
        contour=[Vector((x,y,0)) for x,y in points];lookup={tuple(v):i for i,v in enumerate(contour)}
        tris=[list(t) if isinstance(t[0],int) else [lookup[tuple(v)] for v in t] for t in tessellate_polygon([contour])]
        ob=self.mesh('Illustrated enamel and channel letters',[self.point(x,y,.045) for x,y in points],tris,self.face)
        uv=ob.data.uv_layers.new(name='SignFaceUV')
        for loop in ob.data.loops:
            x,y=points[loop.vertex_index]
            uv.data[loop.index].uv=((x+1)/2,(y+1)/2)

    def border(self,points):
        curve=bpy.data.curves.new('Continuous glass rim','CURVE');curve.dimensions='3D'
        curve.bevel_depth=max(.018,self.w*.0016);curve.bevel_resolution=0;curve.use_fill_caps=True
        spline=curve.splines.new('POLY');spline.points.add(len(points)-1);spline.use_cyclic_u=True
        for p,(x,y) in zip(spline.points,points):p.co=(*self.point(x*.994,y*.994,.07),1)
        ob=bpy.data.objects.new('Physical neon rim',curve);bpy.context.collection.objects.link(ob)
        curve.materials.append(self.neon);self.objects.append(ob)

    def box(self,x,y,width,height,front,back,mat):
        self.plate([(x-width/2,y-height/2),(x+width/2,y-height/2),(x+width/2,y+height/2),(x-width/2,y+height/2)],front,front-back,mat)

    def supports(self,points):
        # Four discrete stand-offs or two posts. Everything is above the
        # doorway head, or beside the entrance in the resort's own frontage.
        if self.row.get('mount')=='posts':
            base=self.row['base']
            for x in (-.50,.50):
                crossings=[]
                for a,b in zip(points,points[1:]+points[:1]):
                    if abs(b[0]-a[0])<1e-8:
                        if abs(x-a[0])<1e-6:crossings.extend([a[1],b[1]])
                    elif min(a[0],b[0])<=x<=max(a[0],b[0]):
                        crossings.append(a[1]+(b[1]-a[1])*(x-a[0])/(b[0]-a[0]))
                if not crossings:raise ValueError(f'{self.row["code"]}: no cabinet over support {x}')
                # Each post follows the lower silhouette at its own x and
                # extends 12 cm into the physical metal backing, not a shared
                # guessed bottom edge. This also handles sloped rocket signs.
                top=self.c.y+min(crossings)*self.h/2+.12
                if top<=base:raise ValueError('support base is above its cabinet')
                mid=(base+top)/2
                self.box(x,(mid-self.c.y)*2/self.h,.035,(top-base)*2/self.h,-.13,-.34,self.case)
                self.box(x,(base-self.c.y)*2/self.h,.10,.025,.09,-.56,self.metal)
        else:
            for x in (-.55,.55):
                for y in (-.35,.35):self.box(x,y,.07,.05,-.10,-.50,self.case)

    def export(self):
        points=json.loads((SOURCE/'textures'/f'{self.row["code"]}-contour.json').read_text())
        self.plate(points,-.005,.22,self.metal)
        self.front(points);self.border(points);self.supports(points)
        bpy.ops.object.select_all(action='DESELECT')
        for ob in self.objects:ob.select_set(True)
        bpy.context.view_layer.objects.active=self.objects[0]
        bpy.ops.object.convert(target='MESH');bpy.ops.object.join()
        ob=bpy.context.object;ob.name='CasinoLogo%d'%self.row['code']
        ob['casino_logo_name']=self.row['name'];ob['casino_logo_shape']=self.row['shape']
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        modifier=ob.modifiers.new('Export triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=modifier.name)
        dest=SOURCE/'models';dest.mkdir(parents=True,exist_ok=True)
        path=dest/f'{self.row["code"]}-logo'
        bpy.context.preferences.filepaths.save_version=0
        for image in bpy.data.images:
            if image.source=='FILE' and image.filepath:
                image.filepath=bpy.path.relpath(image.filepath,start=str(dest))
        bpy.ops.wm.save_as_mainfile(filepath=str(path.with_suffix('.blend')))
        bpy.ops.export_scene.gltf(filepath=str(path.with_suffix('.glb')),export_format='GLB',use_selection=True,
                                  export_yup=True,export_extras=True,export_animations=False,
                                  export_cameras=False,export_lights=False,export_materials='EXPORT',export_apply=True)
        print('ILLUSTRATED_CASINO_LOGO',self.row['code'],len(ob.data.polygons),'triangles',flush=True)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--only',nargs='*',type=int)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    for row in json.loads((ROOT/'tools/casino_signs.json').read_text())['signs']:
        if args.only and row['code'] not in args.only:continue
        bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
        for mat in list(bpy.data.materials):bpy.data.materials.remove(mat)
        Cabinet(row).export()


if __name__=='__main__':main()
