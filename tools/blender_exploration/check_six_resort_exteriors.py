# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check the six added resort exteriors for floating parts and crossed windows.

Blender --background --python tools/blender_exploration/check_six_resort_exteriors.py [-- slug ...]

Rebuilds each exterior's primitives in memory (nothing is written) and reports:
- parts not connected to the ground through touching geometry;
- slender vertical members (columns, piers, posts, fins) whose bottom or top end
  touches nothing, except the listed intentional free ends;
- any part other than a window's own reveal, glass and sill standing in front of
  a window pane.
Exits non-zero when anything is reported.
"""
import sys, json, math, traceback
from pathlib import Path
import bpy  # noqa: F401  (generator imports require Blender)
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_six_resort_exteriors as s

TOL = .06
# Free tips by design: sunburst ray tip, prism mast finial.
FREE_ENDS = {('afterglow', 'top', (0.0, 56.5, -7.5)), ('dust', 'top', (0.0, 24.0, 27.0))}
# Windows the generator omits because massing stands in front of them (behind
# lobbies, wings, parapets or sails). A change means rows appeared or vanished.
EXPECTED_OMITTED = {'fix': 6, 'alibi': 0, 'velvet': 40, 'afterglow': 4, 'last': 3, 'dust': 4}
WRAPPERS = {'box', 'rod', 'torus', 'facade_polygon', 'mass', 'window', 'draw_window', 'ledge', 'roof',
            'punched', 'ribbons', 'arch_window', 'vault', 'sail', 'dust_stack'}


class Recorder(s.ExteriorAsset):
    def __init__(self, name):
        super().__init__(name); self.prims = []
    def add(self, finish, verts, faces, smooth=False):
        super().add(finish, verts, faces, smooth)
        stack = [f for f in traceback.extract_stack()[:-1] if f.filename.endswith('build_six_resort_exteriors.py')]
        inner = [f for f in stack if f.name not in WRAPPERS]
        where = '%s:%d' % (inner[-1].name, inner[-1].lineno) if inner else '?'
        self.prims.append((finish, [Vector(v) for v in verts], [tuple(f) for f in faces], where))


def triangles(faces):
    return [(f[0], f[i], f[i+1]) for f in faces for i in range(1, len(f)-1)]


def check(slug):
    windows = []
    draw = s.draw_window
    def recording(asset, x, y, z, w, h, side, finish='glass', sill='stone'):
        start = len(asset.prims); draw(asset, x, y, z, w, h, side, finish, sill)
        windows.append((start, len(asset.prims), (x, y, z, w, h, side)))
    s.draw_window = recording
    try:
        a = s.build(slug, Recorder(slug))
    finally:
        s.draw_window = draw
    P = a.prims; n = len(P)
    lo = [Vector(tuple(min(v[i] for v in p[1]) for i in range(3))) for p in P]
    hi = [Vector(tuple(max(v[i] for v in p[1]) for i in range(3))) for p in P]
    bvh = [BVHTree.FromPolygons(p[1], triangles(p[2]), epsilon=0.0) for p in P]
    near_cache = {}
    def near(i):
        if i not in near_cache:
            near_cache[i] = [j for j in range(n) if j != i and
                             all(lo[i][k]-TOL <= hi[j][k] and lo[j][k]-TOL <= hi[i][k] for k in range(3))]
        return near_cache[i]
    def distance(points, j):
        best = 1e9
        for p in points:
            hit = bvh[j].find_nearest(p)
            if hit[0] is not None: best = min(best, hit[3])
            if best < TOL: break
        return best
    def centres(i):
        return [sum((P[i][1][k] for k in f), Vector())/len(f) for f in P[i][2]]
    def touching(i, j):
        return (bool(bvh[i].overlap(bvh[j])) or distance(P[i][1], j) < TOL or distance(P[j][1], i) < TOL
                or distance(centres(i), j) < TOL or distance(centres(j), i) < TOL
                or all(lo[j][k]-TOL <= lo[i][k] and hi[i][k] <= hi[j][k]+TOL for k in range(3)))
    adjacent = {i: set() for i in range(n)}
    for i in range(n):
        for j in near(i):
            if j > i and touching(i, j): adjacent[i].add(j); adjacent[j].add(i)
    grounded = {i for i in range(n) if lo[i].y <= .06}; stack = list(grounded)
    while stack:
        for j in adjacent[stack.pop()]:
            if j not in grounded: grounded.add(j); stack.append(j)
    problems = []
    for i in range(n):
        if i not in grounded:
            problems.append('floating %s from %s at %s' % (P[i][0], P[i][3], tuple(round(c, 2) for c in lo[i])))
    for i in range(n):
        size = hi[i]-lo[i]
        if size.y < 1 or size.y < 3*max(size.x, size.z): continue
        for end, y in (('bottom', lo[i].y), ('top', hi[i].y)):
            if end == 'bottom' and y <= .06: continue
            ring = [v for v in P[i][1] if abs(v.y-y) < .02]
            c = sum(ring, Vector())/len(ring)
            key = (slug, end, (round(c.x, 1), round(y, 1), round(c.z, 1)))
            if key in FREE_ENDS: continue
            reach = max(TOL, max(size.x, size.z)*.6)
            if not any((bvh[j].find_nearest(Vector((c.x, y, c.z)))[3] or 1e9) < reach or
                       (lo[j].x-TOL <= c.x <= hi[j].x+TOL and lo[j].z-TOL <= c.z <= hi[j].z+TOL and lo[j].y-TOL <= y <= hi[j].y+TOL)
                       for j in near(i)):
                problems.append('loose %s end of %s from %s at %s' % (end, P[i][0], P[i][3], key[2]))
    own = set()
    for start, stop, _ in windows: own.update(range(start, stop))
    for start, stop, spec in windows:
        region = s.window_region(*spec)
        for j in range(n):
            if j in own: continue
            if s._blocks((P[j][0], lo[j], hi[j], P[j][1], P[j][2]), *region):
                problems.append('%s from %s crosses window at %s' % (P[j][0], P[j][3], spec[:3]))
    expected = EXPECTED_OMITTED.get(slug)
    if expected is not None and len(a.omitted) != expected:
        problems.append('%d windows omitted behind massing, expected %d' % (len(a.omitted), expected))
    print('SIX_RESORT_OMITTED %s %d' % (slug, len(a.omitted)))
    return problems


def main():
    slugs = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(s.BUILDERS)
    report = {slug: check(slug) for slug in slugs}
    for slug, problems in report.items():
        print('SIX_RESORT_GEOMETRY %s %s' % (slug, 'clean' if not problems else '%d problems' % len(problems)))
        for line in problems[:40]: print('  ' + line)
    if any(report.values()): sys.exit(1)


if __name__ == '__main__':
    main()
