#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Losslessly package four original atlases and twelve wall paintings.

Individual card edits take priority over shared atlas cells to avoid neighboring
subjects leaking into their visible bounds. Cabinet faces use the actual native
SlotCabinetDisplay in an isolated project, then this packager is run again.
Source images/prompts stay in the locally excluded assets/casino-art folder.
"""
import argparse, json, shutil
from pathlib import Path
from PIL import Image
from build_casino_art import record, apply_reviewed_art
from build_six_resort_art import gutters, square, ASSETS
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/casino-art'
DEST=ROOT/'game/assets/desert-dreams-casino-art'
THEMES=json.loads((ROOT/'tools/neighborhood_resorts.json').read_text())['resorts']

def build(only=None):
    path=DEST/'catalog.json';catalog=json.loads(path.read_text())
    with Image.open(SOURCE/'neighborhood/paintings.png') as paintings:
        assert paintings.width*4==paintings.height*3
        for row,t in enumerate(THEMES):
            if only and t['slug'] not in only:continue
            folder=DEST/t['slug'];folder.mkdir(parents=True,exist_ok=True);assets={}
            with Image.open(SOURCE/t['slug']/'atlas.png') as atlas:
                assert atlas.mode=='RGBA'
                xs,ys=gutters(atlas)
                for i,name in enumerate(ASSETS):
                    c,r=i%4,i//4
                    cell=square(atlas.crop((xs[c],ys[r],xs[c+1],ys[r+1])))
                    output=folder/(name+'.png');cell.save(output,optimize=True);assets[name]=record(output,cell)
            for edit in sorted((SOURCE/t['slug']/'edits').glob('*.png')):
                assert edit.stem in ('court-jack','court-queen','court-king','card-back'),edit
                with Image.open(edit) as cell:
                    assert cell.mode=='RGBA' and cell.width==cell.height,edit
                    output=folder/edit.name;shutil.copyfile(edit,output)
                    assets[edit.stem]=record(output,cell)
            edge=paintings.width//3
            for col,name in enumerate(['mural-history','mural-industry','mural-heritage']):
                cell=paintings.crop((col*edge,row*edge,(col+1)*edge,(row+1)*edge))
                output=folder/(name+'.png');cell.save(output,optimize=True);assets[name]=record(output,cell,True)
            cabinet=SOURCE/t['slug']/'cabinet-reels.png'
            if cabinet.exists():
                with Image.open(cabinet) as cell:
                    assert cell.size==(480,280)
                    output=folder/cabinet.name;cell.save(output,optimize=True);assets['cabinet-reels']=record(output,cell,True)
            catalog['sets'][t['slug']]={'assets':assets,'creation':'Original fictional Nevada casino illustrations','generator':'tools/build_neighborhood_resort_art.py'}
            apply_reviewed_art(catalog['sets'][t['slug']], SOURCE/t['slug'], folder)
            (SOURCE/t['slug']/'packaging.json').write_text(json.dumps({'columns':xs,'rows':ys,'assets':ASSETS},indent=2)+'\n')
            print(t['slug'],len(assets),'lossless runtime illustrations')
    path.write_text(json.dumps(catalog,indent=2)+'\n')
if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--only',nargs='+',choices=[t['slug'] for t in THEMES])
    build(parser.parse_args().only)
