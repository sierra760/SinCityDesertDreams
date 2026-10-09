#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Losslessly extract Despicable's inspected sprite regions without changing resort art.
Sources/prompts remain local under assets/casino-art/despicables; runtime sprites ship.
"""
from pathlib import Path
import json,hashlib
from PIL import Image
from build_casino_art import ROOT,DEST,record
SOURCE=ROOT/'assets/casino-art/despicables'
# Actual image_gen compositions have unequal row spacing. These inspected
# source rectangles preserve complete subjects and exclude neighboring artwork.
SYMBOLS=['s1','s2','s3','s4','s5','B']
CUTOUT_REGIONS=[(0,0,418,425),(418,0,836,425),(836,0,1254,425),
               (0,426,418,810),(418,426,836,810),(836,426,1254,810),
               (0,811,418,1254),(418,811,836,1254),(836,811,1254,1254)]
DECOR_REGIONS=[(0,0,627,589),(627,0,1254,589),(0,589,627,1254),(627,589,1254,1254)]

def build():
    folder=DEST/'despicables';folder.mkdir(parents=True,exist_ok=True)
    entries={}
    with Image.open(SOURCE/'cutouts.png') as sheet:
        assert sheet.mode=='RGBA' and sheet.size==(1254,1254)
        for i,name in enumerate(['symbol-'+s for s in SYMBOLS]+['court-jack','court-queen','court-king']):
            image=sheet.crop(CUTOUT_REGIONS[i]);path=folder/(name+'.png');image.save(path,optimize=True)
            entries[name]=record(path,image)
            if i<6:
                payout=folder/('payout-'+SYMBOLS[i]+'.png');image.save(payout,optimize=True)
                entries['payout-'+SYMBOLS[i]]=record(payout,image)
    with Image.open(SOURCE/'decor.png') as sheet:
        assert sheet.size==(1254,1254)
        for name,region in zip(['card-back','mural-history','mural-industry','mural-heritage'],DECOR_REGIONS):
            image=sheet.crop(region);path=folder/(name+'.png');image.save(path,optimize=True)
            entries[name]=record(path,image,True)
    cabinet=SOURCE/'cabinet-reels.png'
    if cabinet.exists():
        with Image.open(cabinet) as image:
            path=folder/'cabinet-reels.png';image.save(path,optimize=True);entries['cabinet-reels']=record(path,image,True)
    catalog=json.loads((DEST/'catalog.json').read_text())
    sources={name:{'source':(SOURCE/name).relative_to(ROOT).as_posix(),'sha256':hashlib.sha256((SOURCE/name).read_bytes()).hexdigest()}
             for name in ['cutouts.png','decor.png']}
    catalog['sets']['despicables']={'source':sources['cutouts.png']['source'],
        'source_sha256':sources['cutouts.png']['sha256'],'generator':'tools/build_despicables_art.py',
        'additional_sources':sources,'source_regions':{'cutouts':CUTOUT_REGIONS,'decor':DECOR_REGIONS},'assets':entries}
    (DEST/'catalog.json').write_text(json.dumps(catalog,indent=2)+'\n')
    print('Despicables artwork:',len(entries),'lossless sprites packaged')

if __name__=='__main__':build()
