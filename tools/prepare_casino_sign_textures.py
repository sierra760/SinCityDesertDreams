# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare authored color art, matching light maps and cabinet contours.

Original generated illustration files remain untouched. This is technical
texture-channel and mesh preparation: no replacement lettering is drawn.
"""
from pathlib import Path
import json
import math

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'assets/casino-signs'


def simplify(points, tolerance):
    if len(points) <= 2:
        return points
    a,b=np.asarray(points[0],float),np.asarray(points[-1],float)
    delta=b-a
    mid=np.asarray(points[1:-1],float)
    length=np.linalg.norm(delta)
    distance=np.abs(delta[0]*(mid[:,1]-a[1])-delta[1]*(mid[:,0]-a[0]))/length if length else np.linalg.norm(mid-a,axis=1)
    at=int(np.argmax(distance))+1
    if distance[at-1] <= tolerance:
        return [points[0],points[-1]]
    return simplify(points[:at+1],tolerance)[:-1]+simplify(points[at:],tolerance)


def contour(image):
    alpha=np.array(image.getchannel('A').resize((256,128),Image.Resampling.BILINEAR))>160
    edges={}
    h,w=alpha.shape
    def edge(a,b):edges.setdefault(a,[]).append(b)
    for y in range(h):
        for x in range(w):
            if not alpha[y,x]:continue
            if y==0 or not alpha[y-1,x]:edge((x,y),(x+1,y))
            if x==w-1 or not alpha[y,x+1]:edge((x+1,y),(x+1,y+1))
            if y==h-1 or not alpha[y+1,x]:edge((x+1,y+1),(x,y+1))
            if x==0 or not alpha[y,x-1]:edge((x,y+1),(x,y))
    loops=[]
    while edges:
        start=next(iter(edges));p=start;loop=[]
        while p in edges:
            loop.append(p);q=edges[p].pop()
            if not edges[p]:del edges[p]
            p=q
            if p==start:break
        if len(loop)>8:loops.append(loop)
    def area(loop):return abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(loop,loop[1:]+loop[:1])))
    loop=max(loops,key=area)
    # Split a closed contour at opposite points before simplifying it.
    middle=len(loop)//2
    poly=simplify(loop[:middle+1],.65)[:-1]+simplify(loop[middle:]+loop[:1],.65)[:-1]
    # Round pixel-grid stairs into a manufactured metal rim. Simplify again
    # after corner cutting so the neon does not reveal a jagged pixel trace.
    rounded=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        rounded.extend([(a[0]*.75+b[0]*.25,a[1]*.75+b[1]*.25),
                        (a[0]*.25+b[0]*.75,a[1]*.25+b[1]*.75)])
    middle=len(rounded)//2
    tolerance=.7
    while True:
        poly=simplify(rounded[:middle+1],tolerance)[:-1]+simplify(rounded[middle:]+rounded[:1],tolerance)[:-1]
        if len(poly)<=128:break
        tolerance+=.15
    return [[round(x/w*2-1,6),round(1-y/h*2,6)] for x,y in poly]


def artwork_mask(size, polygon):
    """Regions in the approved 1024 x 512 art, scaled with the input texture."""
    mask=Image.new('L',size)
    ImageDraw.Draw(mask).polygon([(x*size[0]/1024,y*size[1]/512) for x,y in polygon],fill=255)
    return np.asarray(mask)/255


def sheep_neon(size):
    """Trace the existing mascot's silhouette and expression, not the enamel."""
    paths=[
        # Seated wool body, ears and head crest.
        [(344,191),(338,176),(341,151),(350,123),(369,102),(405,82),
         (443,73),(479,75),(507,70),(510,52),(524,39),(540,30),(555,28),
         (581,30),(600,39),(611,52),(610,61),(621,59),(637,65),
         (650,73),(640,82),(625,87),(615,84),(624,108),(638,135),(648,163),(650,185),
         (640,198),(616,199),(595,194),(572,198),(547,194),(522,198),
         (497,194),(477,199),(452,194),(429,198),(405,193),(379,198),
         (360,193),(344,191)],
        # Left ear and both cheeks meeting the chin.
        [(526,65),(508,72),(489,84),(477,91),(488,98),(507,101),(527,93)],
        [(535,68),(529,89),(537,112),(552,126),(572,133),(591,127),(605,109),(606,88),(600,64)],
        [(611,69),(623,67),(638,74)],
        # Eyes, nose and the broad, upturned smile.
        [(540,78),(544,76),(548,80),(548,86),(543,88),(540,84),(540,78)],
        [(590,73),(594,70),(598,73),(598,79),(594,82),(590,78),(590,73)],
        [(568,101),(573,106),(580,109),(586,104),(589,98)],
        [(580,109),(580,116)],
        [(561,114),(569,120),(581,122),(593,118),(601,110)],
    ]
    # Smooth tubes follow the painted contour; supersampling preserves fine
    # facial details through mipmaps without turning the sheep into a floodlight.
    scale=3
    mask=Image.new('L',(1024*scale,512*scale));draw=ImageDraw.Draw(mask)
    for path in paths:
        p=np.asarray(path,float)
        padded=np.vstack([p[0],p,p[-1]])
        smooth=[]
        for i in range(1,len(padded)-2):
            a,b,c,d=padded[i-1:i+3]
            for t in np.linspace(0,1,10,endpoint=False):
                q=.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
                smooth.append(tuple(q*scale))
        smooth.append(tuple(p[-1]*scale))
        draw.line(smooth,fill=255,width=3*scale,joint='curve')
    return np.asarray(mask.resize(size,Image.Resampling.LANCZOS))/255


def light_map(image,code):
    rgba=np.asarray(image,float)/255
    r,g,b=rgba[:,:,:3].transpose(2,0,1)
    h,w=r.shape
    yy,xx=np.mgrid[:h,:w];y=yy/h;x=xx/w
    high=np.maximum.reduce([r,g,b]);low=np.minimum.reduce([r,g,b])
    pale=np.clip((low-.52)/.30,0,1)*np.clip((high-.65)/.25,0,1)
    pink=np.clip((r-g-.18)*4,0,1)*np.clip((b-.28)*3,0,1)
    cyan=np.clip((np.minimum(g,b)-r-.12)*5,0,1)*np.clip((g-.4)*3,0,1)
    strength=pale
    tint=np.stack([np.ones_like(r),np.full_like(r,.72),np.full_like(r,.35)],axis=2)
    if code==252:
        # The silver enamel has shaded midtones below the generic pale cutoff.
        strength=np.clip((low-.26)/.18,0,1)*.72*(y>.38)*(y<.59)*(x>.22)*(x<.78)
        green=(g>r*1.35)&(g>b*1.05)&(y>.60)&(y<.85)&(x>.14)&(x<.86)
        strength=np.maximum(strength,green*.60)
    elif code==263:
        green=(g>r*1.35)&(g>b*1.1)&(y>.40)&(y<.84)&(x>.08)&(x<.94)
        strength=green.astype(float)*.60
        # The pale enamel itself remains dark: only its green name is lit.
    elif code==257:
        strength=pale*(y>.36)
        ribbon=artwork_mask(image.size,[(304,149),(390,131),(497,114),(590,110),
            (783,118),(788,194),(640,190),(500,200),(400,212),(309,230)])
        red=(r>g*1.5)&(g<.28)
        strength=np.maximum(strength,red*ribbon*.70)
    elif code in (251,264):
        strength=pale*np.where(y>.35,1,.15)
    glow=tint*strength[:,:,None]
    glow=np.maximum(glow,np.stack([pink,pink*.08,pink*.55],axis=2)*.8)
    glow=np.maximum(glow,np.stack([cyan*.1,cyan,cyan],axis=2)*.8)
    if code==263:
        glow=np.maximum(glow,tint*sheep_neon(image.size)[:,:,None]*.70)
    glow*=rgba[:,:,3:4]
    return Image.fromarray(np.uint8(np.clip(glow,0,1)*255),'RGB')


def main():
    dest=SOURCE/'textures';dest.mkdir(parents=True,exist_ok=True)
    for row in json.loads((ROOT/'tools/casino_signs.json').read_text())['signs']:
        code=row['code']
        art=Image.open(SOURCE/'illustrations'/f'{code}.png').convert('RGBA')
        if art.getextrema()[3][0]==255:raise ValueError(f'{code}: sign art has no transparent background')
        # All approved faces were authored in the same 2:1 canvas; keep that
        # ratio rather than stretching type to arbitrary facade bands.
        art=art.resize((1024,512),Image.Resampling.LANCZOS)
        art.save(dest/f'{code}-color.png')
        light_map(art,code).save(dest/f'{code}-light.png')
        (dest/f'{code}-contour.json').write_text(json.dumps(contour(art),indent=2)+'\n')
        print(code,'prepared color/light/contour')


if __name__=='__main__':main()
