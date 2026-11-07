# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

import json

from tools import repair_models
from tools.fix_mirrored_textures import read_glb, sha
from tools.split_model_palms import catalog_entries, model_path, parts_of


def _comstock_parts():
    data = model_path(catalog_entries()[251]).read_bytes()
    doc, binary = read_glb(data)
    return data, [p for p in parts_of(doc, bytes(binary)) if not p['collision']]


def test_repaired_model_matches_its_record_and_catalog():
    data, _ = _comstock_parts()
    record = json.loads(repair_models.RECORD.read_text())['models']['251']
    assert record['state'] == 'repaired'
    assert sha(data) == record['repaired_sha256']
    assert catalog_entries()[251]['glb_sha256'] == record['repaired_sha256']
    assert catalog_entries()[251]['triangles'] == record['triangles']


def test_no_punched_window_overlaps_the_ribbon_glass():
    _, parts = _comstock_parts()
    assert not [p for p in parts if repair_models.comstock_tier_window(p)]
    ribbons = [p for p in parts if p['material'] == 'glass' and (p['hi'][1] - p['lo'][1]) > 3.9
               and 29.4 < p['lo'][1] < 47.0]
    assert len(ribbons) == 8, 'four ribbons on each of the two middle tiers'
    for part in parts:
        size = part['hi'] - part['lo']
        # Window-sized parts only: the ribbon's own crossbars span its length.
        if part['material'] not in ('glass', 'frame') or size[1] > 2.5 or max(size[0], size[2]) > 2.0:
            continue
        for ribbon in ribbons:
            overlap = (part['lo'] < ribbon['hi'] + .05) & (part['hi'] > ribbon['lo'] - .05)
            assert not overlap.all(), 'a window stands inside a ribbon of glass'


def test_canopy_lettering_stands_in_front_of_its_rim_and_slab():
    _, parts = _comstock_parts()
    slab_front = max(p['hi'][2] for p in parts if p['material'] == 'teal'
                     and 3.2 < p['lo'][1] < 3.4 and abs((p['lo'][0] + p['hi'][0]) / 2 - 4) < .1)
    rim = [p for p in parts if p['material'] == 'copper' and abs(p['lo'][1] - 3.28) < .01
           and abs(p['hi'][1] - 3.6) < .01 and p['hi'][0] - p['lo'][0] > 7]
    letters = [p for p in parts if p['material'] == 'sign_ivory' and 3.3 < p['lo'][1] < 3.6
               and 2.4 < p['lo'][0] < 5.6 and p['hi'][0] < 5.6]
    assert len(rim) == 1 and len(letters) == 12
    assert rim[0]['lo'][2] >= slab_front - 1e-3, 'the rim is not buried in the slab'
    for letter in letters:
        assert letter['lo'][2] > rim[0]['hi'][2], 'lettering sits on the rim face'
        assert rim[0]['lo'][1] <= letter['lo'][1] and letter['hi'][1] <= rim[0]['hi'][1], 'lettering fits the rim'
