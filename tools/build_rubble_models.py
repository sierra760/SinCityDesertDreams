# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Build the original editable rubble and contamination kit.

blender --factory-startup --background --python-exit-code 1 --python tools/build_rubble_models.py [-- --render]

One 16 m tile is centred on the origin, Blender +Z up, +Y north. The exported
glTF is +Y up / -Z north; the runtime applies /16 once.

Each variant is an empty named Rubble1..Rubble4 or Contamination. Its children:
  "Drape ..."  low heightfield meshes (dust heap, stains). The runtime lays every
               vertex on the terrain and keeps its authored height above ground.
  "Solid ..."  rigid pieces that also receive a walk-blocking box.
  other        rigid loose debris, rested on the ground under its footprint.
Rigid pieces have their pivot on the ground and their lowest faces slightly
below it. Identical prototypes share one mesh across placements and variants.
No imported meshes, textures, fonts or reference art.
"""
import argparse
import hashlib
import json
import math
import random
import struct
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/rubble-models'
RUNTIME = ROOT / 'game/assets/desert-dreams-rubble'
VARIANTS = ['Rubble1', 'Rubble2', 'Rubble3', 'Rubble4', 'Contamination']
TRIANGLE_BUDGET = 4000          # exported triangles per variant
CONTENT_EXTENT = 7.0            # metres from the tile centre; tiles are 16 m
DRAPE_EXTENT = 7.9              # ground skirts may nearly reach the tile edge


def linear(hex_color):
    def channel(c):
        c /= 255
        return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4
    value = hex_color.lstrip('#')
    return tuple(channel(int(value[i:i + 2], 16)) for i in (0, 2, 4))


# name: (sRGB, finish). Colours live in the Mottle corner colours; the four
# finishes are the only materials, so batching sees few surfaces.
COLORS = {
    'stucco': ('#d8c09c', 'matte'), 'stucco_dark': ('#c4a984', 'matte'),
    'plaster': ('#b8a487', 'matte'), 'teal': ('#3f8c89', 'paint'),
    'coral': ('#d47a62', 'paint'), 'cream': ('#efe2c2', 'paint'),
    'terracotta': ('#b0603f', 'matte'), 'concrete': ('#a29d93', 'matte'),
    'concrete_dark': ('#7c776f', 'matte'), 'block': ('#b3ada2', 'matte'),
    'timber': ('#8a6744', 'matte'), 'timber_grey': ('#8c7d6a', 'matte'),
    'rust': ('#7c4a2d', 'metal'), 'steel': ('#8d9290', 'metal'),
    'dust': ('#8d7c63', 'matte'), 'dust_dark': ('#76664f', 'matte'),
    'hazard': ('#dfb22b', 'paint'), 'black': ('#2b2926', 'paint'),
    'puddle': ('#5d7424', 'gloss'), 'stain': ('#6f6a44', 'matte'),
    'stain_dark': ('#4f4c35', 'matte'), 'brush': ('#6e5c48', 'matte'),
    'sign': ('#e9e3d2', 'paint'),
}
FINISHES = {'matte': (.93, 0.0), 'paint': (.78, 0.0), 'metal': (.62, .35), 'gloss': (.42, 0.0)}
COLOR_INDEX = {name: i for i, name in enumerate(COLORS)}
MATS = {}
PROTOTYPES = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    PROTOTYPES.clear()
    for finish, (rough, metal) in FINISHES.items():
        mat = bpy.data.materials.new('Rubble ' + finish)
        if mat.node_tree is None:
            mat.use_nodes = True
        shader = mat.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Roughness'].default_value = rough
        shader.inputs['Metallic'].default_value = metal
        node = mat.node_tree.nodes.new('ShaderNodeVertexColor')
        node.layer_name = 'Mottle'
        mat.node_tree.links.new(node.outputs['Color'], shader.inputs['Base Color'])
        MATS[finish] = mat


# ---------------------------------------------------------------- geometry

class Shape:
    """bmesh with a per-face colour tag (material_index = COLOR_INDEX)."""

    def __init__(self):
        self.bm = bmesh.new()

    def face(self, points, color):
        verts = [self.bm.verts.new(p) for p in points]
        f = self.bm.faces.new(verts)
        f.material_index = COLOR_INDEX[color]
        return f

    def prism(self, outline, z0, z1, top, side, bottom=None, matrix=None):
        """Closed extrusion of a CCW outline; `matrix` maps (u,v,w) to source."""
        m = matrix or Matrix.Identity(4)
        low = [self.bm.verts.new(m @ Vector((x, y, z0))) for x, y in outline]
        high = [self.bm.verts.new(m @ Vector((x, y, z1))) for x, y in outline]
        faces = [self.bm.faces.new(list(reversed(low))), self.bm.faces.new(high)]
        faces[0].material_index = COLOR_INDEX[bottom or side]
        faces[1].material_index = COLOR_INDEX[top]
        n = len(outline)
        for i in range(n):
            j = (i + 1) % n
            f = self.bm.faces.new((low[i], low[j], high[j], high[i]))
            f.material_index = COLOR_INDEX[side]
            faces.append(f)
        return faces

    def box(self, center, size, color, rotation=0.0, tilt=(0.0, 0.0), top=None):
        sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
        m = (Matrix.Translation(center) @ Matrix.Rotation(rotation, 4, 'Z')
             @ Matrix.Rotation(tilt[0], 4, 'X') @ Matrix.Rotation(tilt[1], 4, 'Y'))
        self.prism([(-sx, -sy), (sx, -sy), (sx, sy), (-sx, sy)], -sz, sz, top or color, color, matrix=m)

    def rod(self, points, radius, color, sides=4):
        """Thin prism along a polyline (rebar, sticks, wire)."""
        rings = []
        for k, p in enumerate(points):
            p = Vector(p)
            a = Vector(points[min(k + 1, len(points) - 1)]) - Vector(points[max(k - 1, 0)])
            a.normalize()
            side = a.cross(Vector((0, 0, 1)))
            if side.length < 1e-4:
                side = a.cross(Vector((1, 0, 0)))
            side.normalize()
            up = side.cross(a)
            rings.append([self.bm.verts.new(p + radius * (math.cos(t) * side + math.sin(t) * up))
                          for t in (math.tau * i / sides for i in range(sides))])
        for r0, r1 in zip(rings, rings[1:]):
            for i in range(sides):
                j = (i + 1) % sides
                self.bm.faces.new((r0[i], r0[j], r1[j], r1[i])).material_index = COLOR_INDEX[color]
        self.bm.faces.new(list(reversed(rings[0]))).material_index = COLOR_INDEX[color]
        self.bm.faces.new(rings[-1]).material_index = COLOR_INDEX[color]

    def lump(self, center, size, color, rng, jitter=.2, flatten=.35, rotation=0.0):
        """Faceted rock/concrete chunk; its underside is flattened and sunk."""
        start = len(self.bm.verts)
        bmesh.ops.create_icosphere(self.bm, subdivisions=1, radius=.5)
        self.bm.verts.ensure_lookup_table()
        made = [self.bm.verts[i] for i in range(start, len(self.bm.verts))]
        rot = Matrix.Rotation(rotation, 3, 'Z')
        for v in made:
            p = v.co.copy()
            p *= 1 + rng.uniform(-jitter, jitter)
            if p.z < 0:
                p.z *= flatten
            p = Vector((p.x * size[0], p.y * size[1], (p.z + .5 * flatten) * size[2]))
            v.co = rot @ p + Vector(center) - Vector((0, 0, .06 * size[2]))
        for f in {f for v in made for f in v.link_faces}:
            f.material_index = COLOR_INDEX[color]

    def mesh(self, name, grain=.10, seed=0, closed=True, smooth=False, recolor=None):
        bm = self.bm
        if closed:
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        data = bpy.data.meshes.new(name)
        bm.to_mesh(data)
        bm.free()
        rng = random.Random(seed)
        names = list(COLORS)
        chosen = []
        for poly in data.polygons:
            color_name = names[poly.material_index]
            if recolor is not None:
                color_name = recolor(poly, color_name, rng)
            chosen.append(color_name)
        used = []
        for color_name in chosen:
            if COLORS[color_name][1] not in used:
                used.append(COLORS[color_name][1])
        for finish in used:
            data.materials.append(MATS[finish])
        colors = data.color_attributes.new(name='Mottle', type='FLOAT_COLOR', domain='CORNER')
        uv = data.uv_layers.new(name='UVMap')
        offset = Vector((seed * 1.7, seed * .9, seed * 2.3))
        for poly, color_name in zip(data.polygons, chosen):
            base = linear(COLORS[color_name][0])
            face = 1 + rng.uniform(-.045, .045)
            poly.material_index = used.index(COLORS[color_name][1])
            axis = max(range(3), key=lambda i: abs(poly.normal[i]))
            axes = [i for i in range(3) if i != axis]
            for index in poly.loop_indices:
                co = data.vertices[data.loops[index].vertex_index].co
                shade = face * (1 + grain * noise.noise(co * .9 + offset) + grain * .4 * noise.noise(co * 3.1 + offset))
                colors.data[index].color = (*[min(1, max(0, c * shade)) for c in base], 1)
                uv.data[index].uv = (co[axes[0]] / 4, co[axes[1]] / 4)
            poly.use_smooth = smooth
        data.update()
        return data


def proto(name, build):
    if name not in PROTOTYPES:
        PROTOTYPES[name] = build()
    return PROTOTYPES[name]


def jagged(rng, start, end, steps, low, high):
    """Broken top profile between two (x, height) points."""
    points = []
    for i in range(1, steps):
        t = i / steps
        x = start[0] + (end[0] - start[0]) * t
        h = start[1] + (end[1] - start[1]) * t + rng.uniform(low, high)
        points.append((x, max(.18, h)))
    return points


# ---------------------------------------------------------------- prototypes

def wall_fragment(name, length, high, low, thickness, seed, outer='stucco', band='teal'):
    def build():
        rng = random.Random(seed)
        top = [(length, low)] + list(reversed(jagged(rng, (0, high), (length, low), 7, -.32, .22))) + [(0, high)]
        outline = [(0, -.12), (length, -.12)] + top
        s = Shape()
        # (u, v, w) -> (u, w - t/2, v): a vertical wall along +X, faces +-Y.
        m = Matrix(((1, 0, 0, -length / 2), (0, 0, 1, -thickness / 2), (0, 1, 0, 0), (0, 0, 0, 1)))
        s.prism(outline, 0, thickness, 'plaster', 'plaster', matrix=m)
        bmesh.ops.bisect_plane(s.bm, geom=s.bm.verts[:] + s.bm.edges[:] + s.bm.faces[:],
                               plane_co=(0, 0, .85), plane_no=(0, 0, 1))
        for f in s.bm.faces:
            f.normal_update()
        bmesh.ops.recalc_face_normals(s.bm, faces=s.bm.faces[:])
        for f in s.bm.faces:
            c = f.calc_center_median()
            if abs(f.normal.y) > .9:
                outside = f.normal.y < 0
                f.material_index = COLOR_INDEX[(band if c.z < .85 else outer) if outside else 'plaster']
        return s.mesh(name, seed=seed)
    return proto(name, build)


def slab(name, width, depth, thickness, seed, face='concrete', core='concrete_dark', pivot_edge=False):
    def build():
        rng = random.Random(seed)
        broken = [(width / 2 - (width * i / 6), depth / 2 + rng.uniform(-.35, .15)) for i in range(7)]
        outline = [(-width / 2, -depth / 2), (width / 2 + rng.uniform(-.2, .1), -depth / 2)] + broken
        if pivot_edge:
            outline = [(x, y + depth / 2) for x, y in outline]
        s = Shape()
        s.prism(outline, -thickness * .5, thickness * .5, face, core)
        return s.mesh(name, seed=seed)
    return proto(name, build)


def lumps(name, count, spread, sizes, colors, seed):
    def build():
        rng = random.Random(seed)
        s = Shape()
        for i in range(count):
            r = spread * math.sqrt(rng.random())
            a = rng.uniform(0, math.tau)
            size = rng.uniform(*sizes)
            s.lump((r * math.cos(a), r * math.sin(a), 0),
                   (size * rng.uniform(.8, 1.3), size * rng.uniform(.7, 1.1), size * rng.uniform(.45, .8)),
                   rng.choice(colors), rng, rotation=rng.uniform(0, math.tau))
        return s.mesh(name, seed=seed)
    return proto(name, build)


def ibeam(name, length, depth, bend, seed, color='rust'):
    def build():
        w, t = depth * .55, depth * .09
        profile = [(-w / 2, 0), (w / 2, 0), (w / 2, t), (t / 2, t), (t / 2, depth - t), (w / 2, depth - t),
                   (w / 2, depth), (-w / 2, depth), (-w / 2, depth - t), (-t / 2, depth - t), (-t / 2, t), (-w / 2, t)]
        s = Shape()
        stations = 5
        rings = []
        for k in range(stations):
            u = k / (stations - 1)
            x = (u - .5) * length
            angle = bend * max(0, u - .45) * 2
            twist = bend * .6 * max(0, u - .45)
            m = Matrix.Translation((x, 0, 0)) @ Matrix.Rotation(angle, 4, 'Z') @ Matrix.Rotation(twist, 4, 'X')
            rings.append([s.bm.verts.new(m @ Vector((0, py, pz - .05))) for py, pz in profile])
        for r0, r1 in zip(rings, rings[1:]):
            n = len(profile)
            for i in range(n):
                j = (i + 1) % n
                s.bm.faces.new((r0[i], r0[j], r1[j], r1[i])).material_index = COLOR_INDEX[color]
        s.bm.faces.new(list(reversed(rings[0]))).material_index = COLOR_INDEX[color]
        s.bm.faces.new(rings[-1]).material_index = COLOR_INDEX[color]
        return s.mesh(name, seed=seed, grain=.16)
    return proto(name, build)


def column_stub(name, height, seed):
    def build():
        rng = random.Random(seed)
        s = Shape()
        half = .28
        outline = [(-half, -half), (half, -half), (half, half), (-half, half)]
        faces = s.prism(outline, -.1, height, 'concrete', 'concrete')
        for v in faces[1].verts:
            v.co.z += rng.uniform(-.35, .1)
        for i in range(5):
            x, y = rng.uniform(-.18, .18), rng.uniform(-.18, .18)
            top = height + rng.uniform(.25, .7)
            lean = Vector((rng.uniform(-.35, .35), rng.uniform(-.35, .35), 0))
            s.rod([(x, y, height - .3), (x, y, height + .05), Vector((x, y, top)) + lean * .4,
                   Vector((x, y, top + .1)) + lean], .018, 'rust')
        return s.mesh(name, seed=seed)
    return proto(name, build)


def planks(name, count, seed, color='timber'):
    def build():
        rng = random.Random(seed)
        s = Shape()
        z = 0.0
        for i in range(count):
            length = rng.uniform(2.6, 4.2)
            s.box((rng.uniform(-.4, .4), rng.uniform(-.5, .5), z + .05), (length, .24, .07),
                  rng.choice([color, 'timber_grey']), rotation=rng.uniform(-.7, .7),
                  tilt=(rng.uniform(-.06, .06), rng.uniform(-.08, .08)))
            z += .06
        return s.mesh(name, seed=seed)
    return proto(name, build)


def roof_tiles(name, count, spread, seed):
    def build():
        rng = random.Random(seed)
        s = Shape()
        for i in range(count):
            a, r = rng.uniform(0, math.tau), spread * math.sqrt(rng.random())
            arc = [(.13 * math.cos(t), .13 * math.sin(t)) for t in (0, math.pi / 3, 2 * math.pi / 3, math.pi)]
            inner = [(x * .78, y * .78) for x, y in reversed(arc)]
            m = (Matrix.Translation((r * math.cos(a), r * math.sin(a), .02)) @ Matrix.Rotation(rng.uniform(0, math.tau), 4, 'Z')
                 @ Matrix.Rotation(rng.uniform(-.25, .25), 4, 'Y') @ Matrix.Rotation(-math.pi / 2, 4, 'X'))
            s.prism(arc + inner, -.2, .2, 'terracotta', 'terracotta', matrix=m)
        return s.mesh(name, seed=seed, grain=.14)
    return proto(name, build)


def cinder_blocks(name, seed):
    def build():
        rng = random.Random(seed)
        s = Shape()
        for layer, n in enumerate((4, 3, 1)):
            for i in range(n):
                if rng.random() < .18:
                    continue
                s.box(((i - n / 2 + .5) * .42 + rng.uniform(-.04, .04), rng.uniform(-.04, .04), .1 + layer * .2),
                      (.4, .2, .2), 'block', rotation=rng.uniform(-.08, .08))
        for i in range(3):
            s.box((rng.uniform(-1.1, 1.1), rng.uniform(.4, 1.0), .08), (.4, .2, .2), 'block',
                  rotation=rng.uniform(0, math.tau), tilt=(rng.uniform(-.4, .4), 0))
        return s.mesh(name, seed=seed)
    return proto(name, build)


def corrugated(name, width, length, sag, seed, color='rust'):
    def build():
        waves, rows = 7, 4
        s = Shape()
        grid = []
        for j in range(rows + 1):
            v = (j / rows - .5) * length
            row = []
            for i in range(waves * 2 + 1):
                u = (i / (waves * 2) - .5) * width
                z = (.035 if i % 2 else -.035) + sag * (1 - (2 * j / rows - 1) ** 2) + .06
                row.append((u, v, z))
            grid.append(row)
        top = [[s.bm.verts.new(p) for p in row] for row in grid]
        under = [[s.bm.verts.new((p[0], p[1], p[2] - .02)) for p in row] for row in grid]
        for j in range(rows):
            for i in range(waves * 2):
                s.bm.faces.new((top[j][i], top[j][i + 1], top[j + 1][i + 1], top[j + 1][i])).material_index = COLOR_INDEX[color]
                s.bm.faces.new((under[j + 1][i], under[j + 1][i + 1], under[j][i + 1], under[j][i])).material_index = COLOR_INDEX[color]
        for j in range(rows):
            for a, b in ((0, 0), (waves * 2, waves * 2)):
                s.bm.faces.new((top[j][a], top[j + 1][a], under[j + 1][a], under[j][a])).material_index = COLOR_INDEX[color]
        for row in (0, rows):
            for i in range(waves * 2):
                s.bm.faces.new((top[row][i], under[row][i], under[row][i + 1], top[row][i + 1])).material_index = COLOR_INDEX[color]
        return s.mesh(name, seed=seed, grain=.2)
    return proto(name, build)


def drum(name, seed, body='hazard', band='black', tipped=False):
    def build():
        rng = random.Random(seed)
        s = Shape()
        sides, r, h = 12, .29, .88
        outline = [(r * math.cos(math.tau * i / sides), r * math.sin(math.tau * i / sides)) for i in range(sides)]
        s.prism(outline, 0, h, body, body)
        for z0 in (.3, .58):
            ring = [(x * 1.04, y * 1.04) for x, y in outline]
            s.prism(ring, z0, z0 + .03, band, band)
        s.prism([(x * .2 + .12, y * .2 + .1) for x, y in outline[::2]], h, h + .02, 'steel', 'steel')
        for v in s.bm.verts:
            v.co.x += .012 * noise.noise(v.co * 6 + Vector((seed, 0, 0)))
        if tipped:
            bmesh.ops.rotate(s.bm, verts=s.bm.verts[:], matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'), cent=(0, 0, 0))
            bmesh.ops.translate(s.bm, verts=s.bm.verts[:], vec=(-h / 2, 0, r - .04))
        else:
            bmesh.ops.translate(s.bm, verts=s.bm.verts[:], vec=(0, 0, -.03))
        recolor = (lambda p, c, g: 'rust' if c == body and g.random() < .16 else c)
        return s.mesh(name, seed=seed, grain=.12, recolor=recolor)
    return proto(name, build)


def warning_sign(name, seed):
    def build():
        s = Shape()
        s.box((0, 0, .95), (.08, .08, 2.0), 'timber_grey')
        plate = Matrix.Translation((0, -.06, 1.55)) @ Matrix.Rotation(math.pi / 2, 4, 'X')
        s.prism([(-.48, -.36), (.48, -.36), (.48, .36), (-.48, .36)], 0, .03, 'hazard', 'black', bottom='sign', matrix=plate)
        # Plain three-blade warning symbol, a little proud of the plate face.
        symbol = Matrix.Translation((0, -.09, 1.55)) @ Matrix.Rotation(math.pi / 2, 4, 'X')
        s.prism([(.055 * math.cos(math.tau * i / 10), .055 * math.sin(math.tau * i / 10)) for i in range(10)],
                0, .012, 'black', 'black', matrix=symbol)
        for blade in range(3):
            centre = math.pi / 2 + blade * math.tau / 3
            arc = [centre - .52 + 1.04 * i / 5 for i in range(6)]
            outline = [(.09 * math.cos(t), .09 * math.sin(t)) for t in arc] + \
                      [(.27 * math.cos(t), .27 * math.sin(t)) for t in reversed(arc)]
            s.prism(outline, 0, .012, 'black', 'black', matrix=symbol)
        return s.mesh(name, seed=seed, grain=.05)
    return proto(name, build)


def stake_line(name, points, seed):
    def build():
        rng = random.Random(seed)
        s = Shape()
        for p in points:
            s.box((p[0], p[1], .45), (.06, .06, 1.0), 'timber_grey', tilt=(rng.uniform(-.08, .08), rng.uniform(-.08, .08)))
        for a, b in zip(points, points[1:]):
            n = 8
            for k in range(n):
                t0, t1 = k / n, (k + 1) / n
                p0 = Vector((a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0, .82 - .22 * math.sin(math.pi * t0)))
                p1 = Vector((a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1, .82 - .22 * math.sin(math.pi * t1)))
                d = (p1 - p0)
                side = d.cross(Vector((0, 0, 1))).normalized() * .004
                color = 'hazard' if k % 2 == 0 else 'black'
                s.face([p0 - side, p1 - side, p1 - side + Vector((0, 0, .07)), p0 - side + Vector((0, 0, .07))], color)
                s.face([p0 + side + Vector((0, 0, .07)), p1 + side + Vector((0, 0, .07)), p1 + side, p0 + side], color)
        return s.mesh(name, seed=seed, grain=.05, closed=False)
    return proto(name, build)


def dead_brush(name, seed):
    def build():
        rng = random.Random(seed)
        s = Shape()

        def branch(base, direction, length, radius, depth):
            end = base + direction * length
            s.rod([base, (base + end) / 2 + Vector((rng.uniform(-.05, .05), rng.uniform(-.05, .05), 0)), end], radius, 'brush', sides=3)
            if depth == 0:
                return
            for _ in range(2):
                d = (direction + Vector((rng.uniform(-.9, .9), rng.uniform(-.9, .9), rng.uniform(-.1, .4)))).normalized()
                branch(end, d, length * .62, radius * .65, depth - 1)
        for _ in range(4):
            d = Vector((rng.uniform(-.6, .6), rng.uniform(-.6, .6), 1)).normalized()
            branch(Vector((0, 0, -.05)), d, rng.uniform(.35, .55), .025, 2)
        return s.mesh(name, seed=seed, grain=.1)
    return proto(name, build)


def puddle(name, radius, seed):
    def build():
        rng = random.Random(seed)
        s = Shape()
        n = 18
        s.face([(radius * (1 + rng.uniform(-.28, .18)) * math.cos(math.tau * i / n) * 1.25,
                 radius * (1 + rng.uniform(-.28, .18)) * math.sin(math.tau * i / n), .07) for i in range(n)], 'puddle')
        return s.mesh(name, seed=seed, grain=.06, closed=False)
    return proto(name, build)


def fallen_sign(name, seed):
    """Toppled roadside arrow sign: coral face, cream rim, bulb studs."""
    def build():
        rng = random.Random(seed)
        s = Shape()
        arrow = [(-2.1, -.45), (1.0, -.45), (1.0, -.85), (2.2, 0), (1.0, .85), (1.0, .45), (-2.1, .45)]
        lie = Matrix.Translation((0, 0, .04)) @ Matrix.Rotation(.16, 4, 'X')
        s.prism(arrow, 0, .22, 'coral', 'cream', matrix=lie)
        for i in range(14):
            t = i / 13
            x = -1.95 + 3.0 * t
            for y in (-.33, .33):
                s.box(lie @ Vector((x, y, .25)), (.07, .07, .06), 'cream')
        s.rod([lie @ Vector((-2.0, 0, .1)), Vector((-2.9, .2, .05)), Vector((-3.6, .5, .05))], .07, 'steel', sides=6)
        return s.mesh(name, seed=seed, grain=.08)
    return proto(name, build)


def drape(name, radius, height, seed, base='dust', specks=(), speck_share=.0, rings=5, segments=16,
          stretch=(1.0, 1.0), lumpiness=.25, lift=.0, square=0.0):
    """Low heightfield heap or stain; z is height above the local ground.
    `square` blends the outline toward the tile square so neighbouring rubble
    skirts meet; vertices never pass DRAPE_EXTENT."""
    def build():
        rng = random.Random(seed)
        s = Shape()
        wobble = [1 + rng.uniform(-lumpiness, lumpiness * .6) for _ in range(segments)]
        centre = s.bm.verts.new((0, 0, heap_profile(height, 0, 0, seed) + lift))
        verts = [[centre]]
        for r in range(1, rings + 1):
            t = r / rings
            ring = []
            for k in range(segments):
                # Staggered, jittered spokes keep the facets from reading as wedges.
                # The outline ring keeps exact spokes: with 16 segments the tile
                # diagonals are spokes, so a centred one-ring fan never crosses a facet crease.
                a = math.tau * (k + (.5 * (r % 2) + rng.uniform(-.3, .3)) * (r < rings)) / segments
                w = (wobble[k] + wobble[(k + 1) % segments]) * .5 if r == rings else wobble[k]
                rr = radius * t * w * (1 + .06 * noise.noise(Vector((a * 2, t * 3, seed))))
                h = heap_profile(height, t, a, seed) if r < rings else 0.0
                rr /= max(abs(math.cos(a)), abs(math.sin(a))) ** square
                x = max(-DRAPE_EXTENT, min(DRAPE_EXTENT, rr * math.cos(a) * stretch[0]))
                y = max(-DRAPE_EXTENT, min(DRAPE_EXTENT, rr * math.sin(a) * stretch[1]))
                ring.append(s.bm.verts.new((x, y, h + lift)))
            verts.append(ring)
        tags = []
        for k in range(segments):
            j = (k + 1) % segments
            tags.append(s.bm.faces.new((centre, verts[1][k], verts[1][j])))
        for r in range(1, rings):
            for k in range(segments):
                j = (k + 1) % segments
                for tri in ((verts[r][k], verts[r + 1][k], verts[r + 1][j]), (verts[r][k], verts[r + 1][j], verts[r][j])):
                    f = s.bm.faces.new(tri)
                    f.material_index = COLOR_INDEX[specks[0]] if specks and 1 < r < rings - 1 and rng.random() < speck_share else COLOR_INDEX[base]
                    if f.material_index != COLOR_INDEX[base]:
                        f.material_index = COLOR_INDEX[rng.choice(specks)]
        for f in tags:
            f.material_index = COLOR_INDEX[base]
        return s.mesh(name, seed=seed, grain=.22, closed=False)
    return proto(name, build)


def heap_profile(height, t, angle, seed):
    if height <= 0:
        return 0.0
    shape = (1 - t * t) ** 1.15
    bumps = 1 + .45 * noise.noise(Vector((math.cos(angle) * t * 2.2, math.sin(angle) * t * 2.2, seed))) \
        + .2 * noise.noise(Vector((math.cos(angle) * t * 6, math.sin(angle) * t * 6, seed + 9)))
    return max(0.0, height * shape * bumps)


def gravel(name, count, spread, colors, seed, size=(.12, .3)):
    """Cheap jittered-box gravel: twelve triangles a stone."""
    def build():
        rng = random.Random(seed)
        s = Shape()
        for _ in range(count):
            r, a = spread * math.sqrt(rng.random()), rng.uniform(0, math.tau)
            d = rng.uniform(*size)
            start = len(s.bm.verts)
            s.box((r * math.cos(a), r * math.sin(a), d * .2), (d, d * rng.uniform(.6, 1.0), d * rng.uniform(.4, .7)),
                  rng.choice(colors), rotation=rng.uniform(0, math.tau), tilt=(rng.uniform(-.3, .3), rng.uniform(-.3, .3)))
            s.bm.verts.ensure_lookup_table()
            for i in range(start, len(s.bm.verts)):
                s.bm.verts[i].co += Vector([rng.uniform(-.025, .025) for _ in range(3)])
        return s.mesh(name, seed=seed, grain=.12)
    return proto(name, build)


def on_heap(cx, cy, radius, height, x, y, lift=.05):
    t = math.hypot(x - cx, y - cy) / radius
    return lift + (heap_profile(height, t, math.atan2(y - cy, x - cx), 0) * .55 if t < 1 else 0.0)


# ---------------------------------------------------------------- layouts

def place(parent, name, data, x, y, z=0.0, yaw=0.0, tilt=(0.0, 0.0), scale=1.0):
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = (x, y, z)
    obj.rotation_euler = (tilt[0], tilt[1], yaw)
    obj.scale = (scale, scale, scale)
    return obj


def scatter(rng, count, inner, outer, taken, gap):
    found = []
    tries = 0
    while len(found) < count and tries < 4000:
        tries += 1
        r = math.sqrt(rng.uniform(inner * inner, outer * outer))
        a = rng.uniform(0, math.tau)
        p = (r * math.cos(a), r * math.sin(a))
        if max(abs(p[0]), abs(p[1])) > CONTENT_EXTENT - .6:
            continue
        if all(math.dist(p, q) >= gap for q in taken + found):
            found.append(p)
    return found


def variant(name):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    return root


def rubble1():
    """Collapsed stucco house: wall corner, painted slabs, roof tile and timber."""
    root, rng = variant('Rubble1'), random.Random(11)
    place(root, 'Drape heap', drape('heap stucco', 5.6, .85, 11, specks=('stucco', 'terracotta', 'plaster', 'timber'), speck_share=.12, lift=.05), .4, -.3)
    place(root, 'Drape skirt', drape('skirt dust', 8.2, .0, 12, base='dust_dark', rings=1, lumpiness=.04, square=1.0), 0, 0, 0)
    place(root, 'Solid wall west', wall_fragment('wall stucco long', 4.4, 2.3, .55, .24, 1), -3.0, 2.9, 0, yaw=0)
    place(root, 'Solid wall north', wall_fragment('wall stucco short', 3.0, 1.9, .4, .24, 2, band='coral'), -5.08, 1.4, 0, yaw=math.pi / 2)
    place(root, 'Slab painted A', slab('slab stucco wide', 3.2, 2.2, .2, 3, face='stucco', core='plaster', pivot_edge=True), 1.6, 2.5, .05, yaw=.3, tilt=(.42, 0))
    place(root, 'Slab painted B', slab('slab teal', 2.4, 1.6, .2, 4, face='teal', core='plaster'), -1.2, -1.8, .32, yaw=1.1, tilt=(.12, -.08))
    place(root, 'Slab painted C', slab('slab stucco small', 1.8, 1.3, .18, 5, face='stucco_dark', core='plaster'), 3.4, -2.6, .12, yaw=2.4, tilt=(-.1, .05))
    place(root, 'Roof tiles A', roof_tiles('tiles wide', 22, 1.5, 6), .6, .5, .42)
    place(root, 'Roof tiles B', roof_tiles('tiles narrow', 12, 1.0, 7), -2.6, -3.6, .02)
    place(root, 'Planks A', planks('planks four', 4, 8), 2.3, .2, .3, yaw=.6)
    place(root, 'Planks B', planks('planks two', 2, 9, color='timber_grey'), -4.3, -1.6, .0, yaw=2.0)
    taken = [(-3.0, 2.9), (-5.08, 1.4), (1.6, 2.5), (-1.2, -1.8), (3.4, -2.6)]
    for i, (x, y) in enumerate(scatter(rng, 9, 1.0, 6.2, taken, 1.4)):
        data = lumps('chunks stucco', 6, .7, (.25, .55), ('stucco', 'plaster', 'stucco_dark', 'teal'), 21)
        h = max(0.0, .5 * (1 - (math.hypot(x - .4, y + .3) / 5.6) ** 2))
        place(root, f'Chunks {i}', data, x, y, h * .7, yaw=rng.uniform(0, math.tau), scale=rng.uniform(.8, 1.15))
    for i, (x, y) in enumerate([(.9, -.8), (-1.6, .9), (2.2, -3.4)]):
        place(root, f'Gravel {i}', gravel('gravel stucco', 20, 1.6, ('stucco', 'plaster', 'terracotta', 'stucco_dark', 'teal'), 81),
              x, y, on_heap(.4, -.3, 5.6, .85, x, y), yaw=i * 2.1)
    return root


def rubble2():
    """Concrete commercial block: column stubs, broken floor plates, blocks."""
    root, rng = variant('Rubble2'), random.Random(22)
    place(root, 'Drape heap', drape('heap concrete', 6.0, .75, 21, base='dust', specks=('concrete', 'concrete_dark', 'block', 'coral'), speck_share=.12, lift=.05), -.2, .3)
    place(root, 'Drape skirt', drape('skirt grey', 8.2, .0, 22, base='dust_dark', rings=1, lumpiness=.04, square=1.0), 0, 0)
    place(root, 'Solid column A', column_stub('column tall', 1.9, 1), -3.2, -2.9)
    place(root, 'Solid column B', column_stub('column short', 1.1, 2), 3.1, 3.0, yaw=.2)
    place(root, 'Solid slab leaning', slab('plate leaning', 3.6, 2.6, .26, 3, pivot_edge=True), -.6, 2.6, .05, yaw=-.25, tilt=(.5, 0))
    place(root, 'Slab floor A', slab('plate floor', 3.0, 2.4, .26, 4), 1.5, -1.4, .38, yaw=.7, tilt=(.08, -.12))
    place(root, 'Slab floor B', slab('plate small', 2.0, 1.5, .22, 5, face='concrete_dark', core='concrete'), -2.9, .6, .2, yaw=2.2, tilt=(-.15, .1))
    place(root, 'Blocks', cinder_blocks('blocks stack', 6), 3.6, -3.6, yaw=.4)
    place(root, 'Sheet steel', corrugated('sheet galvanized', 1.6, 2.8, .12, 7, color='steel'), 4.2, .6, .1, yaw=1.4, tilt=(.05, .14))
    taken = [(-3.2, -2.9), (3.1, 3.0), (-.6, 2.6), (1.5, -1.4), (-2.9, .6), (3.6, -3.6), (4.2, .6)]
    for i, (x, y) in enumerate(scatter(rng, 11, .8, 6.3, taken, 1.25)):
        data = lumps('chunks concrete', 6, .75, (.25, .6), ('concrete', 'concrete_dark', 'block'), 23)
        h = max(0.0, .45 * (1 - (math.hypot(x + .2, y - .3) / 6.0) ** 2))
        place(root, f'Chunks {i}', data, x, y, h * .7, yaw=rng.uniform(0, math.tau), scale=rng.uniform(.8, 1.2))
    for i, (x, y) in enumerate([(-.4, -.2), (1.8, 1.6), (-2.2, -1.2)]):
        place(root, f'Gravel {i}', gravel('gravel concrete', 20, 1.6, ('concrete', 'concrete_dark', 'block', 'coral'), 82),
              x, y, on_heap(-.2, .3, 6.0, .75, x, y), yaw=i * 2.1)
    return root


def rubble3():
    """Light industrial: twisted beams, rusted sheeting, a drum and timber."""
    root, rng = variant('Rubble3'), random.Random(33)
    place(root, 'Drape heap', drape('heap industrial', 4.8, .6, 31, base='dust_dark', specks=('rust', 'concrete', 'timber'), speck_share=.12, lift=.05), .8, .4)
    place(root, 'Drape skirt', drape('skirt industrial', 8.2, .0, 32, base='dust', rings=1, lumpiness=.04, square=1.0), 0, 0)
    place(root, 'Beam A', ibeam('beam bent', 5.4, .42, .5, 1), .3, 1.6, .1, yaw=.25)
    place(root, 'Beam B', ibeam('beam twisted', 4.6, .36, -.7, 2), -1.6, -1.2, .15, yaw=2.1, tilt=(0, .06))
    place(root, 'Beam C', ibeam('beam short', 3.0, .3, .2, 3, color='steel'), 3.4, -2.2, .05, yaw=1.0)
    place(root, 'Sheet A', corrugated('sheet rust wide', 2.2, 3.4, .25, 4), -3.6, 2.3, .05, yaw=.5, tilt=(.1, -.05))
    place(root, 'Sheet B', corrugated('sheet rust bent', 1.8, 2.6, -.18, 5), 2.2, 3.8, .2, yaw=2.6, tilt=(.22, .1))
    place(root, 'Sheet C', corrugated('sheet steel', 1.6, 2.2, .1, 6, color='steel'), -3.9, -3.4, .05, yaw=1.7)
    place(root, 'Solid drum', drum('drum rust', 7, body='rust', band='steel'), 4.4, .9, yaw=.3)
    place(root, 'Drum tipped', drum('drum steel tipped', 8, body='steel', band='rust', tipped=True), -.4, -4.0, yaw=2.9)
    place(root, 'Solid column', column_stub('column industrial', 1.4, 9), -4.6, .2)
    place(root, 'Pallet', planks('pallet', 3, 10), 1.6, -3.6, yaw=.9)
    taken = [(.3, 1.6), (-1.6, -1.2), (3.4, -2.2), (-3.6, 2.3), (2.2, 3.8), (-3.9, -3.4), (4.4, .9), (-.4, -4.0), (-4.6, .2), (1.6, -3.6)]
    for i, (x, y) in enumerate(scatter(rng, 7, .6, 6.3, taken, 1.2)):
        data = lumps('chunks industrial', 5, .7, (.22, .5), ('concrete', 'concrete_dark', 'rust'), 34)
        place(root, f'Chunks {i}', data, x, y, 0, yaw=rng.uniform(0, math.tau), scale=rng.uniform(.8, 1.15))
    for i, (x, y) in enumerate([(1.4, -.4), (-1.0, 2.2)]):
        place(root, f'Gravel {i}', gravel('gravel industrial', 24, 1.5, ('concrete', 'concrete_dark', 'rust', 'timber'), 83),
              x, y, on_heap(.8, .4, 4.8, .6, x, y), yaw=i * 2.1)
    return root


def rubble4():
    """Scattered roadside lot: toppled arrow sign, small heaps, mixed debris."""
    root, rng = variant('Rubble4'), random.Random(44)
    place(root, 'Drape heap west', drape('heap small west', 3.2, .5, 41, specks=('coral', 'cream', 'stucco', 'terracotta'), speck_share=.12, lift=.05), -2.8, -1.4)
    place(root, 'Drape heap east', drape('heap small east', 2.7, .42, 42, specks=('stucco', 'block', 'teal'), speck_share=.12, lift=.05), 3.0, 2.2)
    place(root, 'Drape skirt', drape('skirt mixed', 8.2, .0, 43, base='dust_dark', rings=1, lumpiness=.04, square=1.0), 0, 0)
    place(root, 'Fallen sign', fallen_sign('sign arrow', 1), .6, -.4, .0, yaw=-.35)
    place(root, 'Solid wall stub', wall_fragment('wall teal stub', 2.4, 1.5, .45, .24, 2, outer='teal', band='stucco_dark'), -3.6, 3.3, yaw=.15)
    place(root, 'Blocks', cinder_blocks('blocks loose', 3), 3.8, -2.6, yaw=1.2)
    place(root, 'Roof tiles', roof_tiles('tiles scatter', 14, 1.3, 4), -2.4, -1.2, .3)
    place(root, 'Planks', planks('planks three', 3, 5), 2.4, 2.0, .28, yaw=2.3)
    place(root, 'Slab coral', slab('slab coral', 2.0, 1.4, .18, 6, face='coral', core='plaster'), -.6, 3.4, .06, yaw=.8, tilt=(.06, .1))
    taken = [(-2.8, -1.4), (3.0, 2.2), (.6, -.4), (-3.6, 3.3), (3.8, -2.6), (-.6, 3.4)]
    for i, (x, y) in enumerate(scatter(rng, 10, .5, 6.3, taken, 1.3)):
        data = lumps('chunks mixed', 5, .6, (.22, .5), ('stucco', 'concrete', 'coral', 'block'), 45)
        place(root, f'Chunks {i}', data, x, y, 0, yaw=rng.uniform(0, math.tau), scale=rng.uniform(.8, 1.2))
    for i, (x, y, cx, cy, r, h) in enumerate([(-2.8, -1.4, -2.8, -1.4, 3.2, .5), (3.0, 2.2, 3.0, 2.2, 2.7, .42)]):
        place(root, f'Gravel {i}', gravel('gravel mixed', 22, 1.3, ('stucco', 'concrete', 'coral', 'cream', 'block'), 84),
              x, y, on_heap(cx, cy, r, h, x, y), yaw=i * 2.1)
    return root


def contamination():
    """Fenced toxic spill: stained ground, leaking drums, warning sign, dead brush."""
    root, rng = variant('Contamination'), random.Random(55)
    place(root, 'Drape stain', drape('stain wide', 7.4, .0, 51, base='stain', specks=('stain_dark', 'dust_dark'), speck_share=.4, rings=3, lumpiness=.2, square=.6), .2, -.2)
    place(root, 'Drape stain dark', drape('stain core', 3.0, .02, 52, base='stain_dark', specks=('stain',), speck_share=.25, rings=2, segments=12, lumpiness=.35, lift=.03), 1.2, .6)
    place(root, 'Puddle A', puddle('puddle large', 1.3, 53), 1.4, .8)
    place(root, 'Puddle B', puddle('puddle small', .7, 54), -1.9, -2.2)
    place(root, 'Solid drum A', drum('drum hazard', 1), 2.6, 2.0)
    place(root, 'Solid drum B', drum('drum hazard', 1), 3.25, 1.6, yaw=1.2)
    place(root, 'Solid drum C', drum('drum hazard rust', 2, body='rust', band='hazard'), 2.9, 2.75, yaw=2.5)
    place(root, 'Drum tipped A', drum('drum hazard tipped', 3, tipped=True), .3, 1.6, yaw=-.4)
    place(root, 'Drum tipped B', drum('drum steel tipped toxic', 4, body='steel', band='hazard', tipped=True), -2.8, -1.4, yaw=2.2)
    place(root, 'Warning sign', warning_sign('sign warning', 1), -3.8, 3.6, yaw=.35)
    place(root, 'Stakes', stake_line('stakes front', [(-5.6, -5.4), (-2.0, -5.7), (1.7, -5.4), (5.4, -5.6), (5.7, -2.2)], 6), 0, 0)
    for i, (x, y) in enumerate([(-4.6, .4), (4.6, -3.6), (-.8, 4.6), (-5.0, -3.0)]):
        place(root, f'Brush {i}', dead_brush(f'brush {i % 2}', 60 + i % 2), x, y, yaw=rng.uniform(0, math.tau), scale=rng.uniform(.85, 1.15))
    for i, (x, y) in enumerate([(4.8, 4.6), (-.6, -3.6), (5.4, 1.2)]):
        place(root, f'Rocks {i}', lumps('rocks dark', 3, .5, (.25, .45), ('stain_dark', 'dust_dark', 'concrete_dark'), 70), x, y, yaw=rng.uniform(0, math.tau))
    return root


def group_loose(root):
    """Join loose debris into four quadrant groups so each tile adds few nodes.

    Solid pieces and drapes stay separate. Each group's pivot is its footprint
    centre on the ground, so the runtime rests it on the slope under it.
    """
    bpy.context.view_layer.update()
    loose = [o for o in root.children if o.type == 'MESH' and not o.name.startswith(('Solid', 'Drape'))]
    quadrants = {}
    for obj in loose:
        x, y = obj.location.x, obj.location.y
        quadrants.setdefault(('N' if y >= 0 else 'S') + ('E' if x >= 0 else 'W'), []).append(obj)
    for label, parts in sorted(quadrants.items()):
        bpy.ops.object.select_all(action='DESELECT')
        target = parts[0]
        target.data = target.data.copy()
        for obj in parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = target
        if len(parts) > 1:
            bpy.ops.object.join()
        target.parent = None
        bpy.ops.object.select_all(action='DESELECT')
        target.select_set(True)
        bpy.context.view_layer.objects.active = target
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        points = [v.co for v in target.data.vertices]
        cx = (min(p.x for p in points) + max(p.x for p in points)) / 2
        cy = (min(p.y for p in points) + max(p.y for p in points)) / 2
        for v in target.data.vertices:
            v.co.x -= cx
            v.co.y -= cy
        target.location = (cx, cy, 0)
        target.parent = root
        target.name = f'Debris {root.name} {label}'
        target.data.name = target.name


# ---------------------------------------------------------------- checks/export

def mesh_objects(root):
    return [o for o in root.children_recursive if o.type == 'MESH']


def check_variant(root):
    bpy.context.view_layer.update()
    tris = 0
    for obj in mesh_objects(root):
        tris += sum(len(p.vertices) - 2 for p in obj.data.polygons)
        world = [obj.matrix_world @ v.co for v in obj.data.vertices]
        assert all(math.isfinite(c) for p in world for c in p), obj.name
        extent = max(max(abs(p.x), abs(p.y)) for p in world)
        assert extent <= (DRAPE_EXTENT + 1e-4 if obj.name.startswith('Drape') else CONTENT_EXTENT + .35), (obj.name, 'outside tile margin', extent)
        if obj.name.startswith('Drape'):
            assert all(p.z >= -1e-6 for p in [obj.matrix_local @ v.co for v in obj.data.vertices]), (obj.name, 'below ground')
            assert all(v.co.z >= -1e-6 for v in obj.data.vertices) and obj.rotation_euler.z == 0
        else:
            low = min(p.z for p in world)
            # Grouped debris may lie wholly on a heap; heaps are under 1 m.
            allowance = 1.0 if obj.name.startswith('Debris') else .08
            assert low < obj.location.z + allowance, (obj.name, 'floating pivot', low)
        assert obj.data.color_attributes.get('Mottle') and obj.data.uv_layers, obj.name
        if obj.name.startswith('Solid'):
            assert not obj.name.startswith('Drape')
    assert tris <= TRIANGLE_BUDGET, (root.name, tris)
    return tris


def glb_metrics(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack('<III', data[:12])
    assert magic == 0x46546c67 and version == 2 and length == len(data)
    size, kind = struct.unpack('<II', data[12:20])
    assert kind == 0x4e4f534a
    doc = json.loads(data[20:20 + size])
    tris = 0
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            assert {'POSITION', 'NORMAL', 'COLOR_0'} <= set(primitive['attributes']), mesh['name']
            tris += doc['accessors'][primitive['indices']]['count'] // 3
    names = [n['name'] for n in doc['nodes']]
    for name in VARIANTS:
        assert name in names, name
    assert not any(n.endswith(('-col', '-colonly', '-convcolonly', '-noimp', '-rigid')) for n in names)
    return {'runtime_triangles': tris, 'runtime_meshes': len(doc['meshes']),
            'runtime_materials': len(doc.get('materials', [])), 'nodes': len(names)}


def render_review(roots, directory):
    directory.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = scene.render.resolution_y = 900
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new('Review') if scene.world is None else scene.world
    scene.world = world
    try:
        world.use_nodes = True
    except AttributeError:
        pass
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (.62, .70, .78, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = .9
    ground = bpy.data.meshes.new('Review ground')
    ground.from_pydata([(-8, -8, 0), (8, -8, 0), (8, 8, 0), (-8, 8, 0)], [], [(0, 1, 2, 3)])
    sand = bpy.data.materials.new('Review sand')
    try:
        sand.use_nodes = True
    except AttributeError:
        pass
    sand.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*linear('#bfa27d'), 1)
    sand.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = .95
    ground.materials.append(sand)
    plane = bpy.data.objects.new('Review ground', ground)
    scene.collection.objects.link(plane)
    sun = bpy.data.objects.new('Review sun', bpy.data.lights.new('Review sun', 'SUN'))
    sun.data.energy = 3.2
    sun.rotation_euler = (math.radians(48), math.radians(12), math.radians(35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new('Review camera', bpy.data.cameras.new('Review camera'))
    scene.collection.objects.link(cam)
    scene.camera = cam
    outputs = []
    for view, (location, ortho) in {'iso': ((19, -19, 17), 17.5), 'street': ((7.5, -11.5, 2.6), None)}.items():
        cam.location = location
        target = Vector((0, 0, .4 if ortho is None else 0))
        cam.rotation_euler = (target - Vector(location)).to_track_quat('-Z', 'Y').to_euler()
        cam.data.type = 'ORTHO' if ortho else 'PERSP'
        if ortho:
            cam.data.ortho_scale = ortho
        else:
            cam.data.lens = 24
        for root in roots:
            for other in roots:
                hide = other is not root
                for obj in [other] + list(other.children_recursive):
                    obj.hide_render = hide
            scene.render.filepath = str(directory / f'{root.name}-{view}.png')
            bpy.ops.render.render(write_still=True)
            outputs.append(scene.render.filepath)
    for obj in (plane, sun, cam):
        bpy.data.objects.remove(obj)
    return outputs


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument('--render', type=Path, default=None, help='write review renders to this folder')
    args = parser.parse_args(argv)
    reset()
    kit = bpy.data.objects.new('RubbleKit', None)
    bpy.context.collection.objects.link(kit)
    roots = [rubble1(), rubble2(), rubble3(), rubble4(), contamination()]
    for root in roots:
        group_loose(root)
        root.parent = kit
    report = {'units': 'metres', 'meters_per_tile': 16, 'content_extent_metres': CONTENT_EXTENT,
              'variants': {}, 'shared_prototypes': len(PROTOTYPES)}
    for root in roots:
        objs = mesh_objects(root)
        report['variants'][root.name] = {
            'source_triangles': check_variant(root),
            'pieces': len(objs),
            'drapes': sum(o.name.startswith('Drape') for o in objs),
            'solids': sum(o.name.startswith('Solid') for o in objs),
        }
    SOURCE.mkdir(parents=True, exist_ok=True)
    RUNTIME.mkdir(parents=True, exist_ok=True)
    blend = SOURCE / 'rubble-kit.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
    glb = RUNTIME / 'rubble-kit.glb'
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [kit] + list(kit.children_recursive):
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB', use_selection=True, export_yup=True,
                              export_materials='EXPORT', export_animations=False, export_cameras=False,
                              export_lights=False, export_apply=False)
    report.update(glb_metrics(glb))
    report['glb_sha256'] = hashlib.sha256(glb.read_bytes()).hexdigest()
    (SOURCE / 'rubble-kit-metrics.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    provenance = {
        'authoring_tool': bpy.app.version_string and f'Blender {bpy.app.version_string}',
        'generator': 'tools/build_rubble_models.py', 'source': 'assets/rubble-models/rubble-kit.blend',
        'source_units': 'metres', 'runtime_scale': 0.0625, 'north': 'Godot -Z',
        'provenance': 'Original procedural geometry and vertex-colour materials; no external meshes, textures, fonts or artwork',
        'variants': report['variants'], 'glb_sha256': report['glb_sha256'],
    }
    (RUNTIME / 'provenance.json').write_text(json.dumps(provenance, indent=2, sort_keys=True) + '\n')
    if args.render:
        render_review(roots, args.render)
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
