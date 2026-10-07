# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Original distressed airliner and authored flight/effect animation."""
import math
import bpy
from disaster_art import common as c

def plane():
    c.timeline(8)
    z=34.5
    airframe=c.group("Airframe", pivot=(0,0,z))
    c.tube("Streamlined fuselage",[(0,-16,z),(0,-13,z),(0,-7,z),(0,7,z),(0,13,z),(0,16,z)],[.07,1.6,2,2,1.3,.05],"white",24)
    for side in [-1,1]:
        # Closed swept wings with a bevelled leading edge.
        x=side
        verts=[(x*1,4,z),(x*15,-5,z-.7),(x*14.4,-7.8,z-.7),(x*1,-2.8,z),
               (x*1,4,z-.35),(x*15,-5,z-1.05),(x*14.4,-7.8,z-1.05),(x*1,-2.8,z-.35)]
        faces=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
        if side>0: faces=[tuple(reversed(f)) for f in faces]
        c.mesh("Swept wing",verts,faces,"teal",False)
        c.tube("Turbofan nacelle",[(side*5,-2,z-1.3),(side*5,1.5,z-1.3)],[.85,.77],"metal",16)
        c.ellipsoid("Dark engine intake",(side*5,1.53,z-1.3),(1.35,.06,1.35),"dark",0,16,8)
        c.box("Winglet",(side*14.6,-6.2,z+.3),(.23,2.2,2.0),"copper",.08)
        for i in range(13):
            c.ellipsoid("Cabin window",(side*1.94,-9+i*1.35,z+.5),(.10,.47,.50),"dark",0,8,6)
        fin=c.box("Horizontal stabilizer",(side*3.2,-12.3,z+.35),(7,2,.25),"teal",.08)
        fin.rotation_euler.z=side*-.15
    c.tube("Flight deck glass",[(-.82,12,z+.9),(0,13,z+1),(.82,12,z+.9)],[.40,.42,.40],"dark",10)
    c.mesh("Swept vertical fin",[(-.15,-14,z),(.15,-14,z),(-.15,-15,z+6),(.15,-15,z+6),(-.15,-10,z+6),(.15,-10,z+6),(-.15,-9,z),(.15,-9,z)],[(0,2,4,6),(7,5,3,1),(0,1,3,2),(2,3,5,4),(4,5,7,6),(6,7,1,0)],"copper",False)
    # Contrasting seam and original tail chevron remain legible at city scale.
    for side in [-1,1]:
        c.GROUP=airframe
        c.tube("Cabin belt",[(side*1.95,-10,z-.15),(side*2.01,7,z-.15)],[.09,.09],"copper",6)
        c.tube("Tail chevron",[(side*.18,-13.8,z+4.6),(side*.18,-11.5,z+3.7),(side*.18,-13,z+2.8)],[.18,.18,.18],"white",6)
        fan=c.group("Turbine_L" if side<0 else "Turbine_R",pivot=(side*5,1.57,z-1.3),parent=airframe)
        for blade in range(7):
            angle=blade*math.tau/7
            part=c.box("Turbine blade",(side*5+.38*math.cos(angle),1.59,z-1.3+.38*math.sin(angle)),(.54,.08,.15),"metal",.025)
            part.rotation_euler.y=-angle
        c.animate(fan,lambda p:{"rotation_euler":(0,p*math.tau*12,0)},step=2)
        flap=c.group("Aileron_L" if side<0 else "Aileron_R",pivot=(side*10,-5.6,z-.7),parent=airframe)
        part=c.box("Hinged aileron",(side*10,-6.3,z-.74),(6,1.35,.20),"copper",.07)
        c.animate(flap,lambda p,s=side:{"rotation_euler":(.13*s*math.sin(p*math.tau*2),0,0)})
    c.animate(airframe,lambda p:{"rotation_euler":(-.035+.025*math.sin(p*math.tau*2),.11*math.sin(p*math.tau),.025*math.sin(p*math.tau*2)),"location":(0,0,z+.6*math.sin(p*math.tau*2))})

    c.group("Engine_flame_anchor",pivot=(-5,-3,z-1.3),parent=airframe)
    for i in range(5):
        part=c.tube("Engine fire tongue",[(-5+(i-2)*.18,-3,z-1.3),(-5+(i-2)*.3,-5,z-1.2+math.sin(i)*.3),(-5+math.sin(i)*.5,-8-i*.3,z-1.1)],[.38,.45,.035],"orange" if i%2 else "amber",8)
        # Individual tongues articulate around the engine, not the map origin.
        pivot=c.group("Engine_flame_%02d"%i,pivot=(-5,-3,z-1.3),parent=airframe)
        c.attach(part,pivot)
        c.animate(pivot,lambda p,i=i:{"scale":(1,1+.2*math.sin(p*math.tau*7+i),1+.16*math.cos(p*math.tau*5+i)),"rotation_euler":(.08*math.sin(p*math.tau*5+i),0,.055*math.cos(p*math.tau*7+i))},step=2)

    # Small overlapping billows move downwind, expand and disappear at the tail.
    # Offsets keep the plume continually supplied while the airplane banks.
    for i in range(14):
        c.GROUP=None
        puff=c.ellipsoid("Advecting_engine_smoke_%02d"%i,(0,0,0),(2.6,3.5,2.7),"storm",.27,12,8)
        def smoke(p,i=i):
            age=(p*2+i/14)%1
            fade=min(1,age*12)*min(1,(1-age)*9)
            size=max(.008,fade*(.55+age*2.5))
            return {"location":(-5+math.sin(age*5+i*.8)*age*.9,-3-age*35,z-1.3+age*8),"scale":(size,size,size*.85),"rotation_euler":(age*.9,age*.5,i*.7+age)}
        c.animate(puff,smoke,step=2)
    bpy.context.scene.frame_set(0)
