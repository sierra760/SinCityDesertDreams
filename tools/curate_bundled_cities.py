#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
"""Curate included cities offline; never advance their simulation or read player saves.

Run after importing classic cities with build_bundled_cities.py. Themes live in
bundled_city_themes.json. The actual engine exports structural road connections;
this tool fills unnamed connections, gives streets distinct base names within
each city, and diversifies existing 4x4 resort lots.
Every candidate is loaded and its station names reconciled before publication.
"""
from __future__ import annotations

import base64
from collections import Counter, defaultdict
import copy
import hashlib
import heapq
import json
import re
import unicodedata
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import zlib

ROOT = Path(__file__).resolve().parent.parent
CITIES = ROOT / 'game/assets/cities'
THEMES = Path(__file__).with_name('bundled_city_themes.json')
# Code, key, and current overnight capacity, from Buildings / RewardParams.
RESORTS = [(251, 'arcology_comstock', 1000), (252, 'arcology_junction', 1200),
           (253, 'arcology_boulder', 1500), (254, 'arcology_orbit', 2000),
           (256, 'arcology_fix', 3200), (257, 'arcology_alibi', 1400),
           (258, 'arcology_velvet', 2200), (259, 'arcology_afterglow', 5000),
           (260, 'arcology_last', 600), (261, 'arcology_dust', 950)]
DISPLAY = dict(zip([r[0] for r in RESORTS], ['Comstock Grand', 'Silver Junction', 'Boulder Crown',
    'Desert Orbit', 'The Fix', 'Six-Week Alibi', 'Velvet Wardrobe', 'The Afterglow', 'Last Resort', 'Dust Republic']))

DISPLAY.update({262:"Boddy’s", 263:'Woolier Days', 264:'Stockgrowers', 265:'Fremont Palace'})

def endpoint(node):
    x, y, channel = node.split(',')
    return int(x), int(y), channel


def region(link, border_x):
    if border_x is None:
        return ''
    a, b = map(endpoint, link.split('>'))
    return 'sonora' if (a[0] + b[0]) / 2 < border_x else 'arizona'


def continuations(links, border_x=None):
    """Pair opposite arms at junctions; follow both arms of a degree-two bend.

    Channel-qualified endpoints keep tunnels independent of roads above them.
    At the international border only same-country links may continue a name.
    """
    nodes = defaultdict(list)
    result = {key: set() for key in sorted(links)}
    for key in result:
        a, b = key.split('>')
        nodes[a].append((key, endpoint(b)))
        nodes[b].append((key, endpoint(a)))
    for node, incident in nodes.items():
        x, y, _ = endpoint(node)
        for i, (a, p) in enumerate(incident):
            for b, q in incident[i + 1:]:
                if region(a, border_x) != region(b, border_x):
                    continue
                if len(incident) == 2 or (p[0] + q[0] == 2*x and p[1] + q[1] == 2*y):
                    result[a].add(b)
                    result[b].add(a)
    return result


def street_groups(links, border_x=None):
    adjacency = continuations(links, border_x)
    visited = set()
    groups = []
    for key in adjacency:
        if key in visited:
            continue
        pending, group = [key], []
        visited.add(key)
        while pending:
            at = pending.pop()
            group.append(at)
            for other in sorted(adjacency[at]):
                if other not in visited:
                    visited.add(other)
                    pending.append(other)
        groups.append(sorted(group))
    return groups


def name_root(name):
    """Compare the actual name across street types and English/Spanish forms."""
    folded = ''.join(char for char in unicodedata.normalize('NFKD', name.casefold())
                     if not unicodedata.combining(char))
    folded = re.sub(r'\s+(?:street|st|avenue|ave|road|rd|boulevard|blvd|drive|dr|lane|ln|court|ct|circle|cir|way|parkway|pkwy|highway|hwy|place|pl|trail|terrace|loop|bend|walk|path)\.?$', '', folded)
    folded = re.sub(r'^(?:calle|avenida|calzada|paseo|camino|boulevard)\s+(?:(?:de la|de los|de las|del|de)\s+)?', '', folded)
    return ' '.join(folded.split())


def ordinal(number):
    return str(number) + ('th' if 10 <= number % 100 <= 20 else {1:'st', 2:'nd', 3:'rd'}.get(number % 10, 'th'))


def candidate_names(group, bank):
    points = [endpoint(node) for link in group for node in link.split('>')]
    dx = max(p[0] for p in points) - min(p[0] for p in points)
    dy = max(p[1] for p in points) - min(p[1] for p in points)
    # Groups are processed longest first, so the major names go to major roads.
    yield from bank.get('primary', [])
    if bank.get('grid'):
        # County avenues are the diagonal/circuitous civic axes, as in the
        # L’Enfant plan. The orthogonal fabric uses letters and numbers.
        if min(dx, dy) > max(dx, dy) * .35:
            yield from (root + ' Avenue' for root in bank['roots'])
        elif dy > dx:
            yield from (ordinal(n) + ' Street' for n in range(1, 129))
        else:
            yield from (chr(n) + ' Street' for n in range(ord('A'), ord('Z') + 1))
            yield from (chr(n) * 2 + ' Street' for n in range(ord('A'), ord('Z') + 1))
    yield from bank.get('secondary', [])
    if bank.get('spanish'):
        for prefix in ['Calle ', 'Avenida ', 'Paseo de ']:
            yield from (prefix + root for root in bank['roots'])
    else:
        suffixes = ['Drive', 'Road', 'Way', 'Lane'] if min(dx, dy) > 3 else (
            ['Avenue', 'Street', 'Road', 'Lane'] if dy > dx else ['Street', 'Avenue', 'Road', 'Lane'])
        for suffix in suffixes:
            yield from (root + ' ' + suffix for root in bank['roots'])
    yield from bank.get('primary', [])


def name_streets(links, metadata, theme):
    result = copy.deepcopy(metadata)
    adjacency = continuations(links, theme.get('border_x'))
    # Preserve every authored connection/name boundary; nearest authored name
    # extends into an unnamed gap along the same continuous street.
    best, pending = {}, []
    for key, identifier in result['links'].items():
        if key in adjacency:
            heapq.heappush(pending, (0, int(identifier), key))
    while pending:
        distance, identifier, key = heapq.heappop(pending)
        if key in best:
            continue
        best[key] = (distance, identifier)
        result['links'][key] = identifier
        for other in sorted(adjacency[key]):
            if other not in best:
                heapq.heappush(pending, (distance + 1, identifier, other))
    used = {name_root(name) for name in result['streets'].values()}
    groups = street_groups(links, theme.get('border_x'))
    groups.sort(key=lambda group: (-len(group), group[0]))
    if theme.get('grid'):
        def grid_order(group):
            points = [endpoint(node) for key in group for node in key.split('>')]
            xs, ys = [p[0] for p in points], [p[1] for p in points]
            dx, dy = max(xs)-min(xs), max(ys)-min(ys)
            if min(dx,dy) > max(dx,dy)*.35:
                return 2, -len(group), group[0]
            # Numbered N/S streets run west to east; lettered E/W streets
            # run north to south, irrespective of each street's length.
            return (0, sum(xs)/len(xs), group[0]) if dy>dx else (1, sum(ys)/len(ys), group[0])
        major_count = len(theme.get('primary', []))
        groups = groups[:major_count] + sorted(groups[major_count:], key=grid_order)
    for group in groups:
        if all(key in result['links'] for key in group):
            continue
        side = region(group[0], theme.get('border_x'))
        bank = theme[side] if side else theme
        name = next((name for name in candidate_names(group, bank) if name_root(name) not in used), None)
        if name is None:
            raise ValueError('Theme name bank exhausted; add distinct base names rather than reusing a street type')
        identifier = int(result['next_street_id'])
        result['next_street_id'] = identifier + 1
        result['streets'][str(identifier)] = name
        used.add(name_root(name))
        for key in group:
            result['links'][key] = identifier
    return distinct_street_roots(result, theme)


def distinct_street_roots(metadata, theme):
    """Repair existing suffix-only repeats without changing IDs or geometry.

    Reserve every root already in use before renaming: a replacement must never
    take the root of another existing street, even one visited later. Keep a
    primary road's name first, otherwise the longest named identity keeps it.
    """
    roots, links = defaultdict(list), defaultdict(list)
    for identifier, name in metadata['streets'].items():
        roots[name_root(name)].append(str(identifier))
    for key, identifier in metadata['links'].items():
        links[str(identifier)].append(key)
    banks = [theme['sonora'], theme['arizona']] if theme.get('border_x') is not None else [theme]
    primary = {name.casefold() for bank in banks for name in bank.get('primary', [])}
    def priority(identifier):
        return metadata['streets'][identifier].casefold() not in primary, -len(links[identifier]), int(identifier)
    used = set(roots)
    for root in sorted(roots):
        identifiers = sorted(roots[root], key=priority)
        for identifier in identifiers[1:]:
            group = sorted(links[identifier])
            if not group:
                raise ValueError('A street identity has no connections: ' + identifier)
            side = region(group[0], theme.get('border_x'))
            bank = theme[side] if side else theme
            name = next((name for name in candidate_names(group, bank) if name_root(name) not in used), None)
            if name is None:
                raise ValueError('Theme needs additional distinct base names for an existing street')
            metadata['streets'][identifier] = name
            used.add(name_root(name))
    return metadata


def diversify_resorts(doc, lots):
    """Use unused 4x4 designs first, keeping exact lot corners and other layers.

    Current active-tourism saves already contain every design if they repeat;
    refuse to silently rewrite occupied tourism records if future inputs differ.
    """
    city = doc['city']
    lots = sorted((lot for lot in lots if lot['size'] == [4, 4]), key=lambda lot: (lot['anchor'][1], lot['anchor'][0]))
    counts = Counter(lot['code'] for lot in lots)
    present = set(counts)
    available = [r for r in RESORTS if r[0] not in present]
    seen, changes = set(), []
    building = zlib.decompress(base64.b64decode(city['layers']['building']))
    width = 1 if len(building) == 128*128 else 2
    codes = list(building) if width == 1 else list(struct.unpack('<16384H', building))
    for lot in lots:
        old = lot['code']
        replacement = None
        if old in seen and available:
            replacement = available.pop(0)
        elif old in seen and counts and counts[old] > min(counts.values()) + 1:
            replacement = min((r for r in RESORTS if r[0] in counts), key=lambda r: (counts[r[0]], r[0]))
        if replacement is not None:
            code, key, capacity = replacement
            anchor = lot['anchor']
            x, y = anchor
            anchor_key = f'{x},{y}'
            record = city['facilities'][anchor_key]
            if doc['snapshot'].get('systems', {}).get('tourism', {}).get('state', {}).get('records'):
                raise ValueError('A resort replacement would invalidate live tourism occupancy; curate that source explicitly')
            if int(record.get('residents', 0)) > 0:
                raise ValueError('An occupied legacy arcology requires explicit migration before replacement')
            for dy in range(4):
                for dx in range(4):
                    index = (y+dy)*128+x+dx
                    if codes[index] != old:
                        raise ValueError(f'Incomplete 4x4 resort footprint at {anchor}')
                    codes[index] = code
            record['key'], record['capacity'] = key, capacity
            reward = doc['snapshot'].get('systems', {}).get('rewards', {}).get('arcologies', {}).get(anchor_key)
            if reward is not None:
                reward['capacity'] = capacity
            changes.append({'anchor': anchor, 'from': DISPLAY[old], 'to': DISPLAY[code]})
            lot['code'], lot['key'] = code, key
            counts[old] -= 1
            counts[code] += 1
        seen.add(old)
    if changes:
        # Promote legacy one-byte layers when a new resort code exceeds 255.
        packed = struct.pack('<16384H', *codes)
        city['layers']['building'] = base64.b64encode(zlib.compress(packed)).decode()
        doc['version'] = 2
    return changes, lots


def repeat_inventory(doc, lots):
    counts = Counter(lot['code'] for lot in lots)
    metadata = doc['city']['street_naming']
    result = []
    for code in sorted(counts):
        if counts[code] <= 1:
            continue
        entries = []
        for lot in sorted(lots, key=lambda row: (row['anchor'][1], row['anchor'][0])):
            if lot['code'] != code:
                continue
            x,y = lot['anchor']; width,height = lot['size']
            def distance(item):
                key, identifier = item
                points = [endpoint(node) for node in key.split('>')]
                distance = min(max(x-px,0,px-(x+width-1)) + max(y-py,0,py-(y+height-1)) for px,py,_ in points)
                return distance, metadata['streets'][str(identifier)], key
            nearest = min(metadata['links'].items(), key=distance) if metadata['links'] else None
            entries.append({'anchor':lot['anchor'], 'nearby_street':metadata['streets'][str(nearest[1])] if nearest else ''})
        result.append({'casino':DISPLAY[code], 'footprint':next(lot['size'] for lot in lots if lot['code']==code), 'lots':entries})
    return result


def write_inventory(reports, path):
    lines = ['# Repeated bundled-city casinos', '',
        'Inventory after the November 8, 2026 city refresh. Coordinates are zero-based city tiles; each coordinate is the top-left lot anchor. Nearby streets are location aids, not entrance guarantees.', '',
        'All ten 4×4 designs are used before a repeat is retained. Bonanza Gap has eleven 4×4 lots and Valle del Mar has thirteen. Smaller resorts already repeated in the native cities are included below too.', '',
        '| City | Casino | Footprint | Lot anchors and nearby streets |',
        '| --- | --- | --- | --- |']
    for report in sorted(reports, key=lambda row: row['name']):
        for record in report['repeated_resorts']:
            locations = '; '.join('(%d, %d) — %s' % (*lot['anchor'], lot['nearby_street']) for lot in record['lots'])
            lines.append('| %s | %s | %d×%d | %s |' % (report['name'], record['casino'], *record['footprint'], locations))
    lines += ['', 'Cities absent from this table have no repeated gaming-resort design. Original classic source files and personal saves were not edited.', '']
    path.write_text('\n'.join(lines))


def curate(doc, topology, theme):
    result = copy.deepcopy(doc)
    city = result['city']
    links = [key for segment in topology['segments'] for key in segment['links']]
    metadata = city.get('street_naming', {'schema':1, 'next_street_id':1, 'streets':{}, 'links':{}, 'station_auto':{}})
    city['street_naming'] = name_streets(links, metadata, theme)
    # Native wire format stores IDs as decimal strings, including old IDs.
    city['street_naming']['next_street_id'] = str(city['street_naming']['next_street_id'])
    city['street_naming']['links'] = {key:str(identifier) for key,identifier in city['street_naming']['links'].items()}
    renamed = [{'street_id':str(identifier), 'from':old, 'to':city['street_naming']['streets'][str(identifier)]}
               for identifier,old in metadata['streets'].items()
               if city['street_naming']['streets'][str(identifier)] != old]
    removed = len(city.get('signs', {}))
    city['signs'] = {}
    old_name = city['name']
    city['name'] = theme.get('name', old_name)
    result['header']['name'] = city['name']
    all_lots = copy.deepcopy(topology['lots'])
    changes, lots = diversify_resorts(result, all_lots)
    repeats = []
    counts = Counter(lot['code'] for lot in lots)
    for code in sorted(counts):
        if counts[code] > 1:
            repeats.append({'casino':DISPLAY[code], 'lots':[lot['anchor'] for lot in lots if lot['code'] == code]})
    return result, {'name':city['name'], 'previous_name':old_name, 'theme':theme['theme'],
        'street_renames':renamed, 'streets':len(city['street_naming']['streets']), 'connections':len(links), 'removed_signs':removed,
        'resort_replacements':changes, 'repeated_4x4_resorts':repeats, 'repeated_resorts':repeat_inventory(result, all_lots)}


def engine_step(godot, project, args):
    import run_tests
    command = [godot, '--headless', '--audio-driver', 'Dummy', '--path', str(project),
               '-s', 'res://tools/bundled_city_topology.gd', '--'] + [str(arg) for arg in args]
    process = subprocess.run(command, capture_output=True, text=True, timeout=1800)
    output = process.stdout + process.stderr
    ok, reason = run_tests.classify_output(process.returncode, output)
    if not ok:
        raise RuntimeError(f'City curation engine check failed ({reason}):\n{output}')


def main():
    import run_tests
    themes = json.loads(THEMES.read_text())['cities']
    godot = run_tests.find_godot()
    reports = []
    with run_tests.isolated_test_project(ROOT / 'game') as project, tempfile.TemporaryDirectory(prefix='scdd-curated-') as temporary:
        output = Path(temporary)
        scan = subprocess.run([godot, '--headless', '--audio-driver', 'Dummy', '--path', str(project), '--import'],
                              capture_output=True, text=True, timeout=900)
        if scan.returncode or run_tests.ENGINE_ERROR.search(scan.stdout + scan.stderr):
            raise RuntimeError('Isolated import failed:\n' + scan.stdout + scan.stderr)
        # Prefer an explicitly regenerated original over its previous curated alias.
        sources = []
        for original, theme in themes.items():
            alias = theme.get('name', original)
            path = project / 'assets/cities' / (original + '.sc2d')
            if not path.exists():
                path = project / 'assets/cities' / (alias + '.sc2d')
            if not path.exists():
                raise ValueError(f'Missing included city: {original}')
            sources.append((original, path))
        topology_path = output / 'topology.json'
        engine_step(godot, project, ['inspect', topology_path] + [path for _, path in sources])
        topologies = json.loads(topology_path.read_text())
        candidates = []
        for original, path in sources:
            doc, report = curate(json.loads(path.read_text()), topologies[str(path)], themes[original])
            target = output / (report['name'] + '.sc2d')
            target.write_text(json.dumps(doc, ensure_ascii=False, separators=(',', ':')) + '\n')
            candidates.append(target)
            reports.append(report)
        engine_step(godot, project, ['stations', output] + candidates)
        for target in candidates:
            document = json.loads(target.read_text())
            document['city']['street_naming'] = json.loads(Path(str(target) + '.naming.json').read_text())
            target.write_text(json.dumps(document, ensure_ascii=False, separators=(',', ':')) + '\n')
        engine_step(godot, project, ['validate', output] + candidates)
        provenance = json.loads((CITIES / 'provenance.json').read_text())
        old_entries = {entry['name']:entry for entry in provenance['cities']}
        entries = []
        for original, theme in themes.items():
            name = theme.get('name', original)
            record = copy.deepcopy(old_entries.get(original, old_entries.get(name, {})))
            target = output / (name + '.sc2d')
            record.update(name=name, file=target.name, bytes=target.stat().st_size,
                          sha256=hashlib.sha256(target.read_bytes()).hexdigest())
            record['curation'] = {'date':'2026-11-08', 'original_name':original,
                'theme':theme['theme'], 'tool':'tools/curate_bundled_cities.py',
                'street_naming_policy':'Distinct base names within each city, across street types and languages',
                'changes':'Themed continuous street names, classic signs removed, 4x4 resort variety; original terrain and simulation history retained.'}
            entries.append(record)
        # All twelve candidates passed the actual loader before any publication.
        for target in candidates:
            shutil.copyfile(target, CITIES / target.name)
        for original, theme in themes.items():
            if theme.get('name', original) != original:
                old = CITIES / (original + '.sc2d')
                if old.exists():
                    old.unlink()
        provenance['cities'] = sorted(entries, key=lambda row: row['name'].casefold())
        (CITIES / 'provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
    (ROOT / 'docs/art/bundled-city-curation.json').write_text(json.dumps({'date':'2026-11-08','cities':reports},ensure_ascii=False,indent=2)+'\n')
    write_inventory(reports, ROOT / 'docs/art/bundled-city-casino-repeats.md')
    print(f'Curated {len(reports)} included cities')


if __name__ == '__main__':
    main()
