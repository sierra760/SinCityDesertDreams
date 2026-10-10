#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Losslessly package six original generated atlases and painting triptychs.

Transparent atlas gutters are measured rather than assuming generation obeyed
equal cells. Each complete rectangle is copied, without resampling or masking,
onto a square transparent canvas. Existing art sets are retained byte for byte.
"""
from pathlib import Path
import json
from PIL import Image
from build_casino_art import record

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/casino-art'
DEST=ROOT/'game/assets/desert-dreams-casino-art'
THEMES=json.loads((ROOT/'tools/resort_expansion.json').read_text())['resorts']
ASSETS=['symbol-s1','symbol-s2','symbol-s3','symbol-s4','symbol-s5','symbol-B',
        'payout-s1','payout-s2','payout-s3','payout-s4','payout-s5','payout-B',
        'court-jack','court-queen','court-king','card-back']

def gutters(image):
    alpha=image.getchannel('A')
    # Preserve all subject pixels; record actual whitespace seams for provenance.
    columns=[sum(v>16 for v in alpha.crop((x,0,x+1,image.height)).get_flattened_data()) for x in range(image.width)]
    rows=[sum(v>16 for v in alpha.crop((0,y,image.width,y+1)).get_flattened_data()) for y in range(image.height)]
    def seams(counts,n):
        points=[0]
        for k in (1,2,3):
            center=n*k/4
            search=range(int(center-n*.085),int(center+n*.085))
            points.append(min(search,key=lambda p:(counts[p],abs(p-center))))
        return points+[n]
    return seams(columns,image.width),seams(rows,image.height)

def square(cell):
    edge=max(256,cell.width,cell.height)+32
    out=Image.new('RGBA',(edge,edge),(0,0,0,0))
    out.paste(cell,((edge-cell.width)//2,(edge-cell.height)//2))
    return out

def build():
    path=DEST/'catalog.json';catalog=json.loads(path.read_text())
    for t in THEMES:
        source=SOURCE/t['slug'];master=source/'atlas.png'
        if not master.exists():continue
        folder=DEST/t['slug'];folder.mkdir(parents=True,exist_ok=True)
        assets={}
        with Image.open(master) as image:
            assert image.mode=='RGBA'
            xs,ys=gutters(image)
            for i,name in enumerate(ASSETS):
                col,row=i%4,i//4
                cell=square(image.crop((xs[col],ys[row],xs[col+1],ys[row+1])))
                output=folder/(name+'.png');cell.save(output,optimize=True);assets[name]=record(output,cell)
        for edit in sorted((source/'edits').glob('*.png')):
            assert edit.stem in ASSETS,edit
            with Image.open(edit) as image:
                assert image.mode=='RGBA'
                cell=square(image)
                output=folder/edit.name;cell.save(output,optimize=True);assets[edit.stem]=record(output,cell)
        painting=source/'paintings.png'
        if painting.exists():
            with Image.open(painting) as image:
                # First three cells of a square 2x2 painting study. The fourth
                # remains a source-only textile study, never an extra wall exhibit.
                w,h=image.size
                assert w==h and w%2==0,(t['slug'],image.size)
                edge=w//2
                for i,name in enumerate(['mural-history','mural-industry','mural-heritage']):
                    x,y=(i%2)*edge,(i//2)*edge
                    cell=image.crop((x,y,x+edge,y+edge))
                    output=folder/(name+'.png');cell.save(output,optimize=True);assets[name]=record(output,cell,True)
        cabinet=source/'cabinet-reels.png'
        if cabinet.exists():
            with Image.open(cabinet) as image:
                assert image.size==(480,280)
                output=folder/cabinet.name;image.save(output,optimize=True);assets['cabinet-reels']=record(output,image,True)
        catalog['sets'][t['slug']]={'assets':assets,
            'creation':'Original fictional Nevada casino illustrations',
            'generator':'tools/build_six_resort_art.py'}
        (source/'packaging.json').write_text(json.dumps({'columns':xs,'rows':ys,'assets':ASSETS},indent=2)+'\n')
        print(t['slug'],len(assets),'lossless sprites')
    path.write_text(json.dumps(catalog,indent=2)+'\n')

if __name__=='__main__':build()
