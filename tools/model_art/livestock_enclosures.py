# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Write navigation profiles from the exact static farm enclosure definitions."""
import copy
import hashlib
import math


def clear(point,pen,radius):
    x,z=point;x0,z0,x1,z1=pen['bounds']
    fence=max(f['thickness'] for f in pen['fences'])/2
    if not (x0+radius+fence<=x<=x1-radius-fence and z0+radius+fence<=z<=z1-radius-fence):return False
    for o in pen['obstacles']:
        a,b,c,d=o['bounds']
        dx=max(a-x,0,x-c);dz=max(b-z,0,z-d)
        if dx<=radius and dz<=radius:return False
    return True


def make_profiles(root,rows,species):
    result={}
    for row in rows:
        if not row['enclosure']:continue
        key=row['key'][3:];profile=copy.deepcopy(row['enclosure']);s=species[profile['species']]
        radius=s['body_radius']+s['turn_margin']
        profile.update(animal_count=profile.pop('count'),model=f"res://assets/desert-dreams-3d/{row['code']}-blender.glb",body_radius=s['body_radius'],turn_margin=s['turn_margin'],scale=s['scale'])
        profile['model_sha256']=hashlib.sha256((root/'game'/profile['model'][6:]).read_bytes()).hexdigest()
        for pen in profile['pens']:
            x0,z0,x1,z1=pen['bounds'];f=max(f['thickness'] for f in pen['fences'])/2
            pen['navigation_bounds']=[x0+radius+f,z0+radius+f,x1-radius-f,z1-radius-f]
            pen['spawns']=[]
            # Front-to-back sparse rows; retain a full body gap at rest.
            for z in range(math.floor(z1-radius-f),math.ceil(z0+radius+f)-1,-1):
                for x in range(math.ceil(x0+radius+f),math.floor(x1-radius-f)+1):
                    point=[x,z]
                    if clear(point,pen,radius+.05) and all(math.dist(point,p)>2*radius+.25 for p in pen['spawns']):pen['spawns'].append(point)
                    if len(pen['spawns'])==pen['count']:break
                if len(pen['spawns'])==pen['count']:break
            assert len(pen['spawns'])==pen['count'],(key,pen['name'],'spawn packing',radius)
            def approach(kind):
                o=next((o for o in pen['obstacles'] if o['kind']==kind),None)
                if not o:return [pen['spawns'][len(pen['spawns'])//2]]
                a,b,c,d=o['bounds'];points=[[(a+c)/2,d+radius+.15],[(a+c)/2,b-radius-.15],[a-radius-.15,(b+d)/2],[c+radius+.15,(b+d)/2]]
                valid=[p for p in points if clear(p,pen,radius)]
                assert valid,(key,pen['name'],kind,'no accessible approach')
                return [valid[0]]
            pen['drink_targets']=approach('trough');pen['feed_targets']=approach('feed_bunk')
        result[key]=profile
    return result
