# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Serializable farm art contract, in Godot metres (+Y up, +Z front).

Only this module defines stock fences and obstacles. Blender and the livestock
manifest writer both consume it. Pen bounds are fence centre lines; navigation
must inset by the animal's clearance radius. Stock-pen surface is at y=.14 metres (the support slab ends at .12).
"""
from pathlib import Path
import re

FENCE_THICKNESS = .16
TURN_MARGIN = .2

ROOT = Path(__file__).resolve().parents[2]
# side, jobs, water/tile, power/tile, livestock/lot, species, pollution
ROSTER = {
    'vegetables': (1,4,3,0,0,'',1), 'alfalfa': (2,6,3,0,0,'',1),
    'grain': (2,4,1,0,0,'',1), 'cattle_range': (3,6,1,0,8,'beef_cattle',0),
    'sheep_pasture': (3,5,1,0,10,'sheep',0), 'greenhouse': (1,10,2,2,0,'',0),
    'nursery': (2,24,2,1,0,'',0), 'dairy': (3,40,3,1,8,'dairy_cattle',4),
    'feedlot': (3,32,2,1,12,'beef_cattle',6), 'market_garden': (2,24,3,1,0,'',1),
}


def building_roster(root=ROOT):
    source = (root/'game/scripts/core/buildings.gd').read_text()
    block = source.split('const _ROSTER := [',1)[1].split('\n]',1)[0]
    rows = re.findall(r'\[&"([^"\n]+)",\s*"([^"\n]+)",\s*(\d+),\s*(\d+),\s*Category\.(\w+),', block)
    assert len(rows) == int(re.search(r'const COUNT := (\d+)',source)[1]), 'building roster parse coverage'
    assert len({r[0] for r in rows}) == len(rows), 'duplicate building key'
    return [dict(code=i,key=r[0],name=r[1],footprint=[int(r[2]),int(r[3])],category=r[4]) for i,r in enumerate(rows)]


def runtime_values(root=ROOT):
    source = (root/'game/scripts/sim/data/agriculture_params.gd').read_text()
    return {m[0]:(int(m[1]),int(m[2]),int(m[3]),int(m[4]),int(m[5]),m[6],int(m[7]))
            for m in re.findall(r'&"(\w+)":\s*\[(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*&"(\w*)",\s*(\d+)\]',source)}


def obstacle(kind, x, z, width, depth, height):
    return dict(kind=kind, center=[x,.12+height/2,z], size=[width,height,depth],
                bounds=[x-width/2,z-depth/2,x+width/2,z+depth/2])


def pen(name, bounds, count, obstacles):
    x0,z0,x1,z1=bounds
    gate_x=(x0+x1)/2
    segments=[([x0,z0],[x1,z0],False),([x1,z0],[x1,z1],False),
              ([x1,z1],[gate_x+1.5,z1],False),([gate_x+1.5,z1],[gate_x-1.5,z1],True),
              ([gate_x-1.5,z1],[x0,z1],False),([x0,z1],[x0,z0],False)]
    return dict(name=name,bounds=bounds,count=count,ground_y=.14,
                fences=[dict(a=a,b=b,gate=gate,height=1.65,thickness=FENCE_THICKNESS) for a,b,gate in segments],
                obstacles=obstacles)


def enclosure(key):
    if key == 'cattle_range':
        pens=[pen('range',[-21,-20,21,20],8,[obstacle('shelter',-12,-15,12,7,3.6),obstacle('trough',14,-14,5,1.6,.8)])]
    elif key == 'sheep_pasture':
        pens=[pen('pasture',[-21,-20,21,20],10,[obstacle('shelter',12,-15,12,7,3.2),obstacle('trough',-14,-13,4,1.4,.65)])]
    elif key == 'dairy':
        pens=[pen('dairy_yard',[-21,-1,21,20],8,[obstacle('shelter',-13,4,12,7,3.6),obstacle('trough',14,4,5,1.6,.8),obstacle('feed_bunk',8,17,16,1.5,.8)])]
    elif key == 'feedlot':
        pens=[pen('west',[-21,-20,-2,20],6,[obstacle('shelter',-11.5,-14,13,7,3.6),obstacle('trough',-6,8,4,1.6,.8),obstacle('feed_bunk',-17,15,5,1.5,.8)]),
              pen('east',[2,-20,21,20],6,[obstacle('shelter',11.5,-14,13,7,3.6),obstacle('trough',6,8,4,1.6,.8),obstacle('feed_bunk',17,15,5,1.5,.8)])]
    else:
        return None
    for item in pens:
        for fence in item['fences']:
            fence['style'] = 'woven_wire' if key == 'sheep_pasture' else 'pipe_rail'
    return dict(units='metres',ground_y=.14,species=ROSTER[key][5],count=ROSTER[key][4],pens=pens)


def lot_definitions(root=ROOT):
    rows = [r for r in building_roster(root) if r['category']=='AGRICULTURAL']
    expected={'ag_'+k for k in ROSTER}|{f'ag_{state}_{n}x{n}' for state in ('prepared','dormant') for n in (1,2,3)}
    assert {r['key'] for r in rows} == expected, 'agricultural roster identity coverage'
    assert runtime_values(root) == ROSTER, 'runtime/authoring roster mismatch'
    result=[]
    for row in rows:
        key=row['key'][3:]
        row=dict(row)
        if key in ROSTER:
            side,jobs,water,power,count,species,pollution=ROSTER[key]
            assert row['footprint']==[side,side], 'authoring footprint/roster mismatch'
            row.update(state='active',jobs=jobs,water=water,power=power,livestock=count,species=species,pollution=pollution,enclosure=enclosure(key))
        else:
            row.update(state=key.split('_')[0],jobs=0,water=0,power=0,livestock=0,species='',pollution=0,enclosure=None)
        result.append(row)
    return result
