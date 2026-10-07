# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Original sculpted weather effects with editable, seamless eight-second loops.

Meshes use source metres and opaque surfaces; motion is exported, never simulated.
"""
import math
import bpy
from mathutils import Vector, noise
import disaster_art.common as c

TAU = math.tau

def _morph(obj, fn, strength=1, phase=0, cycles=1):
    """Two opposed sculpt poses continuously deform one closed mesh."""
    basis = obj.shape_key_add(name='Rest sculpt')
    for sign, label in ((1, 'Sweep A'), (-1, 'Sweep B')):
        key = obj.shape_key_add(name=label)
        for i, vert in enumerate(basis.data):
            key.data[i].co = fn(vert.co.copy(), sign)
        for frame in range(0, bpy.context.scene.frame_end + 1, 4):
            p = frame / bpy.context.scene.frame_end
            key.value = strength * max(0, sign * math.sin(TAU * (cycles*p + phase)))
            key.keyframe_insert(data_path='value', frame=frame)
    obj.data.shape_keys.animation_data.action.name = obj.name + '_sculpt_loop'
    c.linear_keys(obj.data.shape_keys.animation_data.action)
    bpy.context.scene.frame_set(0)
    return obj


def _spin(obj, turns=1, wobble=0, phase=0):
    c.animate(obj, lambda p: {'rotation_euler': (wobble*math.sin(TAU*p+phase), wobble*math.cos(TAU*p+phase), TAU*turns*p)})


def _spiral(name, r0, r1, z0, z1, start, turns, radius, material, samples=34, sides=9, vertical_scale=1):
    points=[]; radii=[]
    for i in range(samples):
        t=i/(samples-1); angle=start+turns*TAU*t
        r=r0+(r1-r0)*t
        points.append((r*math.cos(angle), r*math.sin(angle), z0+(z1-z0)*t))
        radii.append(radius * (.20+.80*math.sin(math.pi*t)**.42))
    obj=c.tube(name, points, radii, material, sides=sides, vertical_scale=vertical_scale)
    # Sculpted fine eddies break the manufactured sweep without adding objects.
    for v in obj.data.vertices:
        v.co += v.normal * (.24*noise.noise(v.co*.65))
        if material=='dust': v.co.z=max(.025,v.co.z)
    obj.data.update()
    return obj


def tornado():
    c.timeline()
    c.add_material('storm_light', (.47,.50,.50), rough=.98)
    c.add_material('storm_dark', (.22,.26,.27), rough=.98)
    main=c.group('Tornado continuous shear')
    body=c.funnel('Sculpted twisting funnel', 68, lambda t: 1.45+15.8*t**1.50,
                  'storm', rings=30, sides=40, wobble=.125)
    _morph(body, lambda v,s: Vector((v.x+s*2.4*math.sin(v.z*.083)*math.sin(math.pi*v.z/75),
                                    v.y+s*1.8*math.sin(v.z*.13+.6)*v.z/68, v.z)), phase=.15)
    _spin(main, turns=1)
    # Broad helices nest against the funnel and read as longitudinal wind shear.
    for i in range(5):
        c.GROUP=main
        pts=[]; rs=[]
        for j in range(33):
            t=j/32; z=3+61*t; a=i*TAU/5+TAU*1.25*t
            r=1.45+15.8*(z/68)**1.5
            pts.append((r*math.cos(a)+math.sin(z/68*4)*68*.045,
                        r*math.sin(a)+math.sin(z/68*5)*68*.03,z))
            rs.append((.22+1.00*t)*(.3+.7*math.sin(math.pi*t)**.4))
        ribbon=c.tube('Longitudinal shear crest %02d'%i,pts,rs,'storm_light' if i%2==0 else 'storm_dark',sides=8)
        _morph(ribbon,lambda v,s: Vector((v.x+s*2.4*math.sin(v.z*.083)*math.sin(math.pi*v.z/75),v.y+s*1.8*math.sin(v.z*.13+.6)*v.z/68,v.z)),phase=.15)
    # Fuse eddy ridges and overlapping billows into substantial turbulent masses.
    dust=c.group('Ground dust circulation')
    pieces=[]
    for i in range(3):
        pieces.append(_spiral('Grounded dust sweep %02d'%i,2.4,13.5,1.5,2.0,i*TAU/3,.88,2.9,'dust',samples=28,sides=10,vertical_scale=.7))
    for i in range(13):
        a=i*2.39996;r=7.5+4.0*math.sin(i*1.8)
        puff=c.ellipsoid('Dust turbulence %02d'%i,(r*math.cos(a),r*math.sin(a),2.0+(i%3)*.6),(5.5,4.2,3.7),'dust',uneven=.20,segments=12,rings=8)
        puff.rotation_euler.z=a+.8;pieces.append(puff)
    cloud=c.unify(pieces,'Sculpted grounded soil vortex','dust',voxel=.38,target_triangles=1750,grounded=True)
    _morph(cloud,lambda v,s:Vector((v.x+s*.35*math.sin(v.y*.6),v.y+s*.35*math.cos(v.x*.5),v.z*(1+s*.10*math.sin(v.x*.4)))),cycles=2)
    _spin(dust,2)
    cap=c.group('Storm canopy shear')
    pieces=[c.ellipsoid('Central rising thunderhead',(0,0,67.0),(34,30,8),'storm',uneven=.14,segments=20,rings=12)]
    for i in range(3):
        pieces.append(_spiral('Upper anvil fold %02d'%i,10,23,64,66,i*TAU/3,.64,4.8,'storm',samples=26,sides=10,vertical_scale=.65))
    for i in range(16):
        a=i*2.39996;r=10+11*((i*7)%16)/15
        puff=c.ellipsoid('Sheared anvil mass %02d'%i,(r*math.cos(a),r*math.sin(a),68.0+1.6*math.sin(i*2)),(13+3*math.sin(i),9,7.0+1.5*math.sin(i*2.4)),'storm',uneven=.19,segments=14,rings=8)
        puff.rotation_euler.z=a+.7;pieces.append(puff)
    canopy=c.unify(pieces,'Turbulent spreading storm anvil','storm',voxel=.52,target_triangles=2400)
    _morph(canopy,lambda v,s:Vector((v.x*(1+s*.02*math.sin(v.y*.3)),v.y*(1+s*.025*math.sin(v.x*.3)),v.z+s*.7*math.sin(v.x*.3+v.y*.2))),cycles=2)
    _spin(cap,-1,wobble=.008)
    # Each recycled debris cluster collapses at its invisible source and exit.
    for i in range(14):
        node=c.group('Orbiting debris %02d'%i)
        c.box('Tumbling masonry %02d'%i,(0,0,0),(.7+(i%3)*.35,.45+(i%2)*.3,.4),'stone' if i%3 else 'dust',bevel=.06)
        def sample(p,i=i):
            t=(p+i/14)%1; a=TAU*(3*t+i*.381); z=2+56*t
            r=3+15*t**1.45
            scale=max(.008,min(1,t*15,(1-t)*15))
            return {'location':(math.cos(a)*r,math.sin(a)*r,z),
                    'rotation_euler':(TAU*4*t,TAU*3*t,TAU*5*t),'scale':(scale,)*3}
        c.animate(node,sample,step=2)
    c.GROUP=None


def hurricane():
    c.timeline()
    c.add_material('rain',(.19,.27,.29),rough=.99)
    c.add_material('cloud_top',(.68,.71,.70),rough=.99)
    c.add_material('cloud_shadow',(.32,.39,.40),rough=.99)
    # Curved, tapered connected masses with a tall, open-walled eye.
    for i in range(4):
        band=c.group('Rolling cyclonic bank %02d'%i)
        points=[]; radii=[]
        for j in range(42):
            t=j/41; a=i*TAU/4+TAU*.94*t; r=12.2+28*t
            z=14.7-6.0*t+1.2*math.sin(t*TAU*2+i)
            points.append((r*math.cos(a),r*math.sin(a),z))
            radii.append((4.5+1.9*math.sin(math.pi*t))*(.20+.80*math.sin(math.pi*(.08+.92*t))**.4))
        material='cloud' if i%2 else 'cloud_top'
        pieces=[c.tube('Continuous cloud arm %02d'%i,points,radii,material,sides=12,vertical_scale=.73)]
        # Lopsided lofted bulges are fused into each spiral bank, never a necklace.
        for k in range(20):
            t=.045+.90*k/19;a=i*TAU/4+TAU*.94*t;r=12.2+28*t
            z=18.6-6*t+1.8*math.sin(t*TAU*2+i)
            taper=.62+.38*math.sin(math.pi*t)
            puff=c.ellipsoid('Cloud bank rolling volume %02d-%02d'%(i,k),(r*math.cos(a),r*math.sin(a),z),((12.5+2*math.sin(k*2))*taper,(8.2+1.3*math.sin(k*1.5))*taper,(8.0+1.8*math.sin(k*2.6))*taper),material,uneven=.20,segments=14,rings=8)
            puff.rotation_euler.z=a+math.pi/2;pieces.append(puff)
        cloud=c.unify(pieces,'Sculpted continuous rolling cloud arm %02d'%i,material,voxel=.48,target_triangles=2200)
        _morph(cloud,lambda v,s,i=i: Vector((v.x*(1+s*.022*math.sin(v.z*.35+i)),v.y*(1+s*.025*math.cos(v.x*.09+i)),v.z+s*.75*math.sin(v.x*.15+v.y*.12+i))),phase=i/4,cycles=2)
        _spin(band,1,wobble=.012,phase=i*1.7)
    eye=c.group('Deep eye wall')
    # Wall is annular: eye center stays genuinely open all the way down.
    verts=[]; faces=[]; sides=56
    for z,r in ((5,10),(16,11.5),(20,14.5),(20,18),(13,15),(4,13)):
        for j in range(sides):
            a=j*TAU/sides; rr=r+.6*math.sin(a*7+z*.2)
            verts.append((rr*math.cos(a),rr*math.sin(a),z+.65*math.sin(a*5)))
    for k in range(6):
        for j in range(sides):
            a=k*sides+j;b=k*sides+(j+1)%sides;d=((k+1)%6)*sides+j;e=((k+1)%6)*sides+(j+1)%sides
            faces.append((d,e,b,a))
    wall=c.mesh('Continuous hollow eye wall',verts,faces,'cloud_shadow')
    # Reversed cross-section winding keeps the annular solid outward.
    _morph(wall,lambda v,s: Vector((v.x*(1+s*.03*math.sin(v.z*.4)),v.y*(1-s*.03*math.sin(v.z*.4)),v.z+s*.65*math.sin(math.atan2(v.y,v.x)*4))),cycles=2)
    _spin(eye,1)
    # Dense tapered rain curtains reinforce the underside, with narrow streaks.
    for i in range(8):
        rain=c.group('Rain curtain %02d'%i)
        a=i*TAU/8
        pts=[]; widths=[]
        for j in range(18):
            t=j/17; theta=a+t*.55; r=20+10*t
            pts.append((r*math.cos(theta),r*math.sin(theta),7.2-1.5*t))
            widths.append(1.8*(.2+.8*math.sin(math.pi*t)**.5))
        c.tube('Swept underside rain %02d'%i,pts,widths,'rain',sides=8,vertical_scale=2.0)
        for k in range(3):
            theta=a+.08+k*.16;r=21+k*3
            x=r*math.cos(theta);y=r*math.sin(theta)
            c.tube('Rain needle %02d-%d'%(i,k),[(x,y,1.2),(x+.8,y,5),(x+1.1,y,8)], [.05,.18,.1],'rain',sides=5)
        c.animate(rain,lambda p,i=i:{'rotation_euler':(0,0,TAU*p), 'location':(0,0,.5*math.sin(TAU*(2*p+i/8)))})
    c.GROUP=None


def fire():
    c.timeline()
    c.add_material('smoke_dark',(.20,.22,.22),rough=1)
    c.add_material('smoke_light',(.37,.38,.35),rough=1)
    c.add_material('ember_red',(.58,.075,.016),rough=.8,glow=.15)
    base=c.group('Charred glowing bed')
    for i in range(5):
        a=i*TAU/5
        c.ellipsoid('Low banked coals %02d'%i,(2.2*math.cos(a),1.9*math.sin(a),.4),(3.4,2.8,.8),'ember_red',uneven=.14,segments=12,rings=6)
    # Curled asymmetrical tongues taper along their entire length, no crown mesh.
    for i in range(11):
        a=i*2.39996;r=.8+1.9*(i%3)/2;h=7+4.5*((i*7)%11)/10
        x=r*math.cos(a);y=r*math.sin(a)
        node=c.group('Independent flame tongue %02d'%i,pivot=(x,y,.25))
        pts=[];rad=[]
        for j in range(14):
            t=j/13
            bend=2.0*t*t; curl=1.3*math.sin(t*math.pi*1.55)*t
            pts.append((x+bend*math.cos(a)+curl*math.sin(a),y+bend*math.sin(a)-curl*math.cos(a),.25+h*t))
            rad.append(max(.045,(1.30 if i<6 else .87)*(1-t)**.8*(.75+.25*math.sin(t*8))))
        flame=c.tube('Curled orange tongue %02d'%i,pts,rad,'orange' if i%3==0 else 'amber',sides=10)
        # Flame object origin is world zero; pivot's keep-world parenting handles offsets.
        _morph(flame,lambda v,s,i=i,h=h: Vector((v.x+s*.7*math.sin(v.z/h*4+i)*v.z/h,v.y+s*.55*math.sin(v.z/h*5+i*.7)*v.z/h,v.z+s*.35*math.sin(v.z/h*math.pi))),phase=i/11,cycles=4+(i%3))
        c.animate(node,lambda p,i=i,x=x,y=y:{'location':(x,y,.25),'rotation_euler':(.065*math.sin(TAU*(3*p+i/11)),.1*math.sin(TAU*(4*p+i/11)),.08*math.sin(TAU*(2*p+i/11))), 'scale':(1+.08*math.sin(TAU*(5*p+i/11)),1+.06*math.cos(TAU*(4*p+i/11)),.9+.16*math.sin(TAU*(3*p+i/11)))},step=2)
        if i<5:
            inner=[(x+(v[0]-x)*.78,y+(v[1]-y)*.78,.25+(v[2]-.25)*.66) for v in pts]
            c.tube('Golden hot interior %02d'%i,inner,[v*.54 for v in rad],'core',sides=8)
    # Smoke masses each rise, swell, drift and disappear; lobes share one node.
    for i in range(8):
        node=c.group('Rising smoke curl %02d'%i)
        for k in range(3):
            a=k*TAU/3+i
            c.ellipsoid('Smoke lobe %02d-%d'%(i,k),(math.cos(a)*1.2,math.sin(a)*1.2,k*.35),(3.6,3.3,3.1),'smoke_dark' if i%2 else 'smoke_light',uneven=.17,segments=12,rings=8)
        def smoke(p,i=i):
            t=(p+i/8)%1; a=TAU*(t*.4+i*.19)
            size=max(.008,(.48+1.3*t)*min(1,t*10,(1-t)*8))
            return {'location':(1.2*math.cos(a)+3*t,1.2*math.sin(a)+t,7+18*t),'scale':(size,size,size*.86),'rotation_euler':(.2*t,.3*math.sin(a),a)}
        c.animate(node,smoke,step=2)
    for i in range(10):
        node=c.group('Rising ember %02d'%i)
        c.ellipsoid('Hot ember fleck %02d'%i,(0,0,0),(.12,.12,.44),'core',segments=6,rings=4)
        def ember(p,i=i):
            t=(2*p+i/10)%1;a=i*2.4+t*2
            size=max(.008,min(1,t*15,(1-t)*10))
            return {'location':((1+3*t)*math.cos(a)+2*t,(1+3*t)*math.sin(a),2+17*t),'scale':(size,)*3,'rotation_euler':(t*2,t*4,0)}
        c.animate(node,ember,step=2)
    c.GROUP=None


def beam():
    c.timeline()
    c.add_material('beam_gold',(1,.65,.14),rough=.42,glow=.7)
    c.add_material('beam_pale',(1,.86,.43),rough=.4,glow=.9)
    core=c.group('Living beam core')
    pts=[(.24*math.sin(i*.55),.24*math.cos(i*.7),i*75/30) for i in range(31)]
    rad=[1.05+.65*(1-i/30)+.12*math.sin(i*1.3) for i in range(31)]
    shaft=c.tube('Tapered brilliant shaft',pts,rad,'beam_pale',sides=12)
    _morph(shaft,lambda v,s: Vector((v.x+s*.22*math.sin(v.z*.33),v.y+s*.22*math.cos(v.z*.29),v.z)),cycles=4)
    # Three true braided strands change radius along their path.
    for i in range(3):
        node=c.group('Braided filament %02d'%i)
        points=[];radii=[]
        for j in range(83):
            t=j/82;a=i*TAU/3+t*TAU*4;r=1.9+1.1*math.sin(math.pi*t)
            points.append((r*math.cos(a),r*math.sin(a),t*75))
            radii.append(.26+.14*math.sin(math.pi*t))
        obj=c.tube('Golden helix %02d'%i,points,radii,'beam_gold' if i%2 else 'amber',sides=7)
        _morph(obj,lambda v,s:Vector((v.x*(1+s*.13*math.sin(v.z*.13)),v.y*(1+s*.13*math.sin(v.z*.13)),v.z)),phase=i/3,cycles=3)
        _spin(node,2)
    for i in range(4):
        arc=c.group('Forking energy discharge %02d'%i)
        for k in range(3):
            a=i*TAU/4+k*.45;z=9+k*20+i*3
            profile=[(1.2,0),(4.0,3),(2.9,4.0),(6.0,7.2),(3.5,8.2),(1.2,12)]
            pts=[(r*math.cos(a+.05*j),r*math.sin(a+.05*j),z+zz) for j,(r,zz) in enumerate(profile)]
            bolt=c.tube('Angular plasma fork %02d-%d'%(i,k),pts,[.14,.22,.16,.20,.13,.07],'beam_gold' if k%2 else 'orange',sides=6)
            _morph(bolt,lambda v,s,i=i:Vector((v.x+s*.35*math.sin(v.z*.8+i),v.y+s*.35*math.cos(v.z*.7+i),v.z)),phase=i/4,cycles=6)
        c.animate(arc,lambda p,i=i:{'rotation_euler':(0,0,.20*math.sin(TAU*(3*p+i/4))),'scale':(1+.22*math.sin(TAU*(4*p+i/4)),1+.22*math.sin(TAU*(4*p+i/4)),1)})
    for i in range(7):
        node=c.group('Descending energy packet %02d'%i)
        c.ellipsoid('Stretched plasma packet %02d'%i,(0,0,0),(3.1,3.1,5.0),'core',segments=12,rings=8)
        def packet(p,i=i):
            t=(2*p+i/7)%1;size=max(.008,min(1,t*14,(1-t)*14))
            return {'location':(0,0,74*(1-t)),'scale':(size,size,size*(.75+.35*math.sin(TAU*t)))}
        c.animate(node,packet,step=2)
    flare=c.group('Rotating impact blossom')
    c.ellipsoid('Molten impact heart',(0,0,.6),(6.5,6.5,1.6),'core',uneven=.1,segments=18,rings=8)
    for i in range(8):
        a=i*TAU/8
        points=[(math.cos(a+t*.45)*(1+9*t),math.sin(a+t*.45)*(1+9*t),.45+4.2*math.sin(math.pi*t)) for t in [j/12 for j in range(13)]]
        c.tube('Impact petal %02d'%i,points,[.15+.62*math.sin(math.pi*j/12) for j in range(13)],'orange' if i%2 else 'beam_gold',sides=8)
    c.animate(flare,lambda p:{'rotation_euler':(0,0,TAU*p),'scale':(1+.14*math.sin(TAU*4*p),1+.14*math.sin(TAU*4*p),1+.24*math.sin(TAU*3*p))})
    for i in range(3):
        node=c.group('Expanding ground shock %02d'%i)
        points=[(3*math.cos(TAU*j/36),3*math.sin(TAU*j/36),.35) for j in range(37)]
        ring=c.tube('Ground energy arc %02d'%i,points,[.16]*37,'amber',sides=6)
        basis=ring.shape_key_add(name='Full energy arc')
        thin=ring.shape_key_add(name='Dissipated arc')
        for j,v in enumerate(basis.data):
            at=v.co.copy();r=math.hypot(at.x,at.y);ratio=(3+(r-3)*.004)/r
            thin.data[j].co=(at.x*ratio,at.y*ratio,.35+(at.z-.35)*.004)
        for frame in range(0,bpy.context.scene.frame_end+1,2):
            t=(2*frame/bpy.context.scene.frame_end+i/3)%1
            thin.value=1-min(1,t*12,(1-t)*12)
            thin.keyframe_insert(data_path='value',frame=frame)
        c.linear_keys(ring.data.shape_keys.animation_data.action)
        def shock(p,i=i):
            t=(2*p+i/3)%1;fade=min(1,t*12,(1-t)*12)
            return {'scale':(.6+2.8*t,.6+2.8*t,1),'location':(0,0,-.34*(1-fade))}
        c.animate(node,shock,step=2)
    for i in range(10):
        node=c.group('Impact spark %02d'%i)
        c.ellipsoid('Elongated hot spark %02d'%i,(0,0,0),(.16,.16,.7),'beam_pale',segments=6,rings=4)
        def spark(p,i=i):
            t=(2*p+i/10)%1;a=i*2.39996;size=max(.008,min(1,t*20,(1-t)*10))
            return {'location':((.6+9*t)*math.cos(a),(.6+9*t)*math.sin(a),.5+11*t*(1-t)), 'rotation_euler':(math.sin(a)*t*2,math.cos(a)*t*2,a),'scale':(size,)*3}
        c.animate(node,spark,step=2)
    c.GROUP=None
