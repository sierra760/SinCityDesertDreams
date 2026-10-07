# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Editable original disaster art. Run Blender --background --python this_file.py.

Source metres, +Y forward/+Z up; exported Godot scenes use -Z forward/+Y up.
Runtime applies /16 once. No imported meshes, textures or fonts.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector, noise

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/disaster-models"
RUNTIME = ROOT / "game/assets/desert-dreams-disasters"
KINDS = ["tornado", "hurricane", "monster", "beam", "riot", "plane", "fire"]
MATS = {}
GROUP = None
PALETTE = {
    "storm": ((.34,.37,.40), .96, 0, 0),
    "cloud": ((.60,.64,.67), .98, 0, 0),
    "dust": ((.53,.41,.29), .97, 0, 0),
    "stone": ((.51,.42,.27), .91, 0, 0),
    "armor": ((.12,.30,.29), .77, .15, 0),
    "ivory": ((.88,.76,.48), .68, 0, 0),
    "dark": ((.035,.045,.046), .64, 0, 0),
    "amber": ((1,.53,.08), .48, 0, .6),
    "core": ((1,.90,.51), .42, 0, 1.2),
    "orange": ((.98,.23,.035), .58, 0, .3),
    "white": ((.84,.83,.72), .50, .12, 0),
    "teal": ((.045,.31,.34), .55, .12, 0),
    "copper": ((.63,.22,.08), .56, .18, 0),
    "metal": ((.42,.47,.49), .43, .6, 0),
    "skin": ((.66,.42,.25), .90, 0, 0),
    "blue": ((.10,.19,.28), .86, 0, 0),
}


def reset():
    global GROUP
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        if block.users == 0: bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        if block.users == 0: bpy.data.materials.remove(block)
    MATS.clear()
    GROUP = None
    for name, (color, rough, metal, glow) in PALETTE.items():
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*color, 1)
        mat.use_nodes = True
        bs = mat.node_tree.nodes.get("Principled BSDF")
        bs.inputs["Roughness"].default_value = rough
        bs.inputs["Metallic"].default_value = metal
        col = mat.node_tree.nodes.new("ShaderNodeVertexColor")
        col.layer_name = "Mottle"
        mat.node_tree.links.new(col.outputs["Color"], bs.inputs["Base Color"])
        if glow:
            # glTF vertex colors modulate albedo, not emission. A constant
            # palette color exports the same warm glow to both engine backends.
            bs.inputs["Emission Color"].default_value = (*color, 1)
            bs.inputs["Emission Strength"].default_value = glow
        MATS[name] = mat


def group(name, pivot=(0, 0, 0), parent=None):
    global GROUP
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = pivot
    bpy.context.view_layer.update()
    if parent is not None: attach(obj, parent)
    GROUP = obj
    return obj


def finish(obj, name, material, smooth=True, grain=.12):
    obj.name = name
    if GROUP is not None: attach(obj, GROUP)
    obj.data.materials.append(MATS[material])
    color = PALETTE[material][0]
    colors = obj.data.color_attributes.new(name="Mottle", type="FLOAT_COLOR", domain="POINT")
    for v, entry in zip(obj.data.vertices, colors.data):
        at = obj.matrix_world @ v.co
        variation = 1 + grain * noise.noise(at * .27) + grain * .35 * noise.noise(at * 1.13)
        entry.color = (*[min(1, max(0, x*variation)) for x in color], 1)
    uv = obj.data.uv_layers.new(name="UVMap") if not obj.data.uv_layers else obj.data.uv_layers.active
    # Cubic UV projection remains editable, including custom loft and ribbon faces.
    for poly in obj.data.polygons:
        axis = max(range(3), key=lambda i: abs(poly.normal[i]))
        axes = [i for i in range(3) if i != axis]
        for index in poly.loop_indices:
            at = obj.data.vertices[obj.data.loops[index].vertex_index].co
            uv.data[index].uv = (at[axes[0]] / 16, at[axes[1]] / 16)
        poly.use_smooth = smooth
    return obj


def mesh(name, verts, faces, material, smooth=True):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return finish(obj, name, material, smooth)


def box(name, loc, size, material, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Soft manufactured edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, name, material, False)


def ellipsoid(name, loc, size, material, uneven=0, segments=16, rings=10):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=.5, location=loc)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if uneven:
        for v in obj.data.vertices:
            v.co *= 1 + uneven * noise.noise(v.co * .33 + Vector((3,7,11)))
    return finish(obj, name, material)


def tube(name, points, radii, material, sides=12, vertical_scale=1):
    verts = []
    for i, (point, radius) in enumerate(zip(points, radii)):
        point = Vector(point)
        tangent = Vector(points[min(i+1,len(points)-1)]) - Vector(points[max(0,i-1)])
        tangent.normalize()
        ref = Vector((0,0,1)) if abs(tangent.z) < .85 else Vector((0,1,0))
        u = tangent.cross(ref).normalized()
        v = tangent.cross(u).normalized()
        for j in range(sides):
            angle = j * math.tau / sides
            offset = (u*math.cos(angle) + v*math.sin(angle)) * radius
            offset.z *= vertical_scale
            verts.append(point + offset)
    faces = [tuple(reversed(range(sides)))]
    for i in range(len(points)-1):
        for j in range(sides):
            a = i*sides+j; b = i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.append(tuple(range(len(verts)-sides,len(verts))))
    return mesh(name, verts, faces, material)


def funnel(name, height, radius_fn, material, rings=28, sides=48, wobble=.10):
    verts = []
    for i in range(rings+1):
        t = i/rings
        radius = radius_fn(t)
        for j in range(sides):
            a = j*math.tau/sides
            r = radius*(1+wobble*math.sin(a*5-t*15)+wobble*.4*math.sin(a*9+t*17))
            verts.append((r*math.cos(a)+math.sin(t*4)*height*.045,
                          r*math.sin(a)+math.sin(t*5)*height*.03, t*height))
    faces = [tuple(reversed(range(sides)))]
    for i in range(rings):
        for j in range(sides):
            a=i*sides+j; b=i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.append(tuple(range(len(verts)-sides,len(verts))))
    return mesh(name,verts,faces,material)


def unify(parts, name, material, voxel, target_triangles, grounded=False):
    """Fuse intersecting sculpt masses, retaining an editable manifold surface."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts: obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join(); obj=bpy.context.object
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    mod=obj.modifiers.new("Joined organic mass","REMESH")
    mod.mode="VOXEL";mod.voxel_size=voxel;mod.use_smooth_shade=True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=obj.modifiers.new("Soft sculpt transitions","SMOOTH")
    mod.factor=.45;mod.iterations=3
    bpy.ops.object.modifier_apply(modifier=mod.name)
    triangles=sum(len(p.vertices)-2 for p in obj.data.polygons)
    if triangles>target_triangles:
        mod=obj.modifiers.new("Bounded sculpt detail","DECIMATE")
        mod.ratio=target_triangles/triangles
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if grounded:
        bottom=min(v.co.z for v in obj.data.vertices)
        for v in obj.data.vertices: v.co.z-=bottom
    obj.data.materials.clear()
    for color in list(obj.data.color_attributes): obj.data.color_attributes.remove(color)
    return finish(obj,name,material)


def attach(obj, parent):
    """Reparent without moving source geometry; pivots remain explicit."""
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world
    bpy.context.view_layer.update()


def add_material(name, color, rough=.85, metal=0.0, glow=0.0):
    PALETTE[name] = (tuple(color), rough, metal, glow)
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bs = mat.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Metallic"].default_value = metal
    node = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    node.layer_name = "Mottle"
    mat.node_tree.links.new(node.outputs["Color"], bs.inputs["Base Color"])
    if glow:
        bs.inputs["Emission Color"].default_value = (*color, 1)
        bs.inputs["Emission Strength"].default_value = glow
    MATS[name] = mat
    return mat


def timeline(seconds=8.0, fps=30):
    scene = bpy.context.scene
    scene.render.fps = fps
    scene.frame_start = 0
    scene.frame_end = round(seconds * fps)
    scene.frame_set(0)


def animate(obj, sampler, step=4):
    """Key editable transforms from sampler(normalized_phase)->property dict.

    Values are absolute local transforms. Frame 0 and the last frame must have
    equivalent poses. Use integer turns for rotations, and small scale at wrap
    for recycled particles. All active actions export together as Incident_loop.
    """
    scene = bpy.context.scene
    end = scene.frame_end
    for frame in sorted(set(range(0, end + 1, step)) | {end}):
        values = sampler(frame / end)
        for prop, value in values.items():
            setattr(obj, prop, value)
            obj.keyframe_insert(data_path=prop, frame=frame)
    if obj.animation_data and obj.animation_data.action:
        obj.animation_data.action.name = obj.name + "_loop"
        linear_keys(obj.animation_data.action)
    scene.frame_set(0)


def rigid_skin(obj, rig, bone):
    """Attach a closed accessory to one deform bone without changing rest pose."""
    attach(obj, rig)
    vg = obj.vertex_groups.new(name=bone)
    vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    mod = obj.modifiers.new("Authored skeleton", "ARMATURE")
    mod.object = rig


def make_rig(name, bones):
    """bones: iterable of (name, head_xyz, tail_xyz, parent_name_or_None)."""
    bpy.ops.object.select_all(action="DESELECT")
    data = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in bones:
        bone = data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        if parent: bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.show_in_front = True
    for bone in rig.pose.bones: bone.rotation_mode = "XYZ"
    return rig


def skin_weights(obj, rig, sampler):
    """sampler(world_vertex)->{bone_name:weight}; weights normalized per vertex."""
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    attach(obj, rig)
    groups = {}
    for vertex in obj.data.vertices:
        weights = sampler(world @ vertex.co)
        total = sum(weights.values())
        assert total > 0
        for name, weight in weights.items():
            if weight <= 0: continue
            if name not in groups: groups[name] = obj.vertex_groups.new(name=name)
            groups[name].add([vertex.index], weight / total, "REPLACE")
    mod = obj.modifiers.new("Authored skeleton", "ARMATURE")
    mod.object = rig


def animate_rig(rig, sampler, step=4):
    """sampler(phase)->{bone_name:{rotation_euler/location/scale:value}}."""
    scene = bpy.context.scene
    end = scene.frame_end
    for frame in sorted(set(range(0, end + 1, step)) | {end}):
        for name, values in sampler(frame / end).items():
            bone = rig.pose.bones[name]
            for prop, value in values.items():
                setattr(bone, prop, value)
                bone.keyframe_insert(data_path=prop, frame=frame)
    if rig.animation_data and rig.animation_data.action:
        rig.animation_data.action.name = rig.name + "_loop"
        linear_keys(rig.animation_data.action)
    scene.frame_set(0)


def linear_keys(action):
    # Blender 5 uses slotted actions. Sampling smooth authored curves before
    # linear interpolation prevents overshoot at recycled particle boundaries.
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points: key.interpolation = "LINEAR"
