#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Package image_gen masters into lossless, individually addressable game sprites.

Generated content is preserved: regular atlas cells are extracted losslessly,
and visible subject bounds are recorded for centered presentation. Original
masters, transparent cutouts, paintings, reel bakes and prompts remain in
assets/casino-art/.
"""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/casino-art'
DEST = ROOT / 'game/assets/desert-dreams-casino-art'
ASSETS = ['symbol-s1', 'symbol-s2', 'symbol-s3', 'symbol-s4', 'symbol-s5', 'symbol-B',
          'court-jack', 'court-queen', 'court-king', 'card-back', 'mural-history', 'mural-industry']
SETS = ['comstock', 'junction', 'boulder', 'orbit']
# image_gen placed these subjects in a different order on three cutout sheets.
# Bind their visually inspected positions to the unchanged payout symbol IDs.
PAYOUT_CELLS = {'comstock': [0,1,2,5,3,4], 'junction': [0,1,2,3,4,5],
                'boulder': [0,1,2,5,3,4], 'orbit': [0,1,2,5,3,4]}

def content_region(image, full_bleed=False):
    if full_bleed:
        return [0,0,image.width,image.height]
    if image.mode == 'RGBA':
        mask=image.getchannel('A').point(lambda a: 255 if a > 16 else 0)
    else:
        rgb=image.convert('RGB')
        corners=[rgb.getpixel(p) for p in [(0,0),(rgb.width-1,0),(0,rgb.height-1),(rgb.width-1,rgb.height-1)]]
        background=tuple(sorted(c[cidx] for c in corners)[1] for cidx in range(3))
        channels=ImageChops.difference(rgb,Image.new('RGB',rgb.size,background)).split()
        mask=ImageChops.lighter(ImageChops.lighter(channels[0],channels[1]),channels[2]).point(lambda d:255 if d>45 else 0)
    box=mask.getbbox() or (0,0,image.width,image.height)
    # Keep anti-aliased edges around the measured subject.
    x0,y0,x1,y1=max(0,box[0]-2),max(0,box[1]-2),min(image.width,box[2]+2),min(image.height,box[3]+2)
    return [x0,y0,x1-x0,y1-y0]

def record(path, image, full_bleed=False):
    return {'size':list(image.size),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'content_region':content_region(image,full_bleed)}

def build():
    catalog = {'license': 'CC BY-NC-SA 4.0', 'generator': 'tools/build_casino_art.py',
               'creation': 'Built-in image_gen; original fictional illustrations inspired by Nevada history',
               'prompts': 'assets/casino-art/prompts.json', 'grid': [4, 3], 'sets': {}}
    catalog['refinement_prompts'] = 'assets/casino-art/refinement-prompts.json'
    catalog['cabinet_creation'] = 'Actual SlotStage renderer; tools/qa/bake_slot_cabinets.gd'
    catalog['shared_suits'] = {path.stem: {'path':path.relative_to(DEST).as_posix(),
                              'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                              'creation':'Original continuous SVG silhouette'}
                              for path in sorted((DEST/'suits').glob('*.svg'))}
    for name in SETS:
        sources = SOURCE / name
        master = sources / 'sheet.png'
        with Image.open(master) as sheet:
            width, height = sheet.size
            assert width * 3 == height * 4, (name, sheet.size)
            assert width % 4 == 0 and height % 3 == 0, (name, sheet.size)
            edge = width // 4
            folder = DEST / name
            folder.mkdir(parents=True, exist_ok=True)
            entries = {}
            for index, asset in enumerate(ASSETS):
                x, y = (index % 4) * edge, (index // 4) * edge
                path = folder / (asset + '.png')
                sheet.crop((x, y, x + edge, y + edge)).save(path, optimize=True)
                with Image.open(path) as cell:
                    entries[asset] = record(path,cell)
            for rank in ['jack','queen','king']:
                override=sources/'portraits'/('court-'+rank+'.png')
                if override.exists():
                    with Image.open(override) as image:
                        assert image.mode=='RGBA', 'Court portrait must retain generated alpha'
                        path=folder/('court-'+rank+'.png');image.save(path,optimize=True)
                        entries['court-'+rank]=record(path,image)
            payouts=sources/'payouts.png'
            if payouts.exists():
                with Image.open(payouts) as icons:
                    assert icons.mode=='RGBA', 'Payout master must retain generated alpha'
                    assert icons.width*2==icons.height*3
                    size=icons.width//3
                    for symbol,index in zip(['s1','s2','s3','s4','s5','B'],PAYOUT_CELLS[name]):
                        x,y=(index%3)*size,(index//3)*size
                        cell=icons.crop((x,y,x+size,y+size))
                        path=folder/('payout-'+symbol+'.png');cell.save(path,optimize=True)
                        entries['payout-'+symbol]=record(path,cell)

            # Individually generated replacements avoid adjacent-sheet artwork
            # leaking across a cell boundary. Preserve each generated PNG's alpha.
            for symbol in ['s1','s2','s3','s4','s5','B']:
                override=sources/'payouts'/(symbol+'.png')
                if override.exists():
                    with Image.open(override) as image:
                        assert image.mode=='RGBA', 'Payout replacement must retain generated alpha'
                        path=folder/('payout-'+symbol+'.png');image.save(path,optimize=True)
                        entries['payout-'+symbol]=record(path,image)
            heritage=sources/'heritage.png'
            if heritage.exists():
                with Image.open(heritage) as image:
                    path=folder/'mural-heritage.png';image.save(path,optimize=True)
                    entries['mural-heritage']=record(path,image,True)
            cabinet=sources/'cabinet-reels.png'
            if cabinet.exists():
                with Image.open(cabinet) as image:
                    path=folder/'cabinet-reels.png';image.save(path,optimize=True)
                    entries['cabinet-reels']=record(path,image,True)
            catalog['sets'][name] = {'source': master.relative_to(ROOT).as_posix(),
                                     'source_sha256': hashlib.sha256(master.read_bytes()).hexdigest(),
                                     'assets': entries}
            for symbol in ['s1','s2','s3','s4','s5','B']:
                override=sources/'payouts'/(symbol+'.png')
                if override.exists():
                    catalog['sets'][name].setdefault('payout_overrides',{})[symbol]={
                        'source':override.relative_to(ROOT).as_posix(),
                        'sha256':hashlib.sha256(override.read_bytes()).hexdigest()}
            for rank in ['jack','queen','king']:
                override=sources/'portraits'/('court-'+rank+'.png')
                if override.exists():
                    catalog['sets'][name].setdefault('portrait_overrides',{})[rank]={
                        'source':override.relative_to(ROOT).as_posix(),
                        'sha256':hashlib.sha256(override.read_bytes()).hexdigest()}
            for suffix in ['payouts','heritage','cabinet-reels']:
                extra=sources/(suffix+'.png')
                if extra.exists():
                    catalog['sets'][name].setdefault('additional_sources',{})[suffix]={
                        'source':extra.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(extra.read_bytes()).hexdigest()}
    (DEST / 'catalog.json').write_text(json.dumps(catalog, indent=2) + '\n')
    if (SOURCE/'despicables'/'cutouts.png').exists():
        from build_despicables_art import build as build_store
        build_store()
    if any((SOURCE/name/'atlas.png').exists() for name in ['fix','alibi','velvet','afterglow','last','dust']):
        from build_six_resort_art import build as build_six
        build_six()
    print('Casino artwork:',sum(len(s['assets']) for s in catalog['sets'].values()),'lossless sprites packaged')

if __name__ == '__main__':
    build()
