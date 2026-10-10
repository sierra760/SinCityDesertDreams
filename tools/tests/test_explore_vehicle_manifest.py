# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Vehicle metadata invariants, including untrusted malformed values."""
import json
from pathlib import Path
from tools.model_art.contracts import validate_model

ROOT = Path(__file__).resolve().parents[2]
KINDS = 'car compact sedan taxi pickup van bus truck police fire_engine ambulance military train subway ship sailboat helicopter plane'.split()

def test_malformed_kind_and_unbounded_integer_are_errors():
    for entry in [{'kind': []}, {'kind':'car', 'tier':'near', 'triangles':10**10000}, {'kind':'car','motion':{'wheel_radius_m':10**10000}}, {'kind':'car','motion':{12:'X'}}]:
        assert validate_model(entry)

def test_all_vehicle_manifests():
    models=json.loads((ROOT/'game/assets/desert-dreams-traffic/catalog.json').read_text())['models']
    for kind in KINDS:
        entry=models[kind]
        assert entry['detail_path'].endswith(kind+'_detail.glb')
        for tier in ['detailed','middle','far']:
            contract=entry['tiers'][tier]
            assert validate_model(contract)==[], (kind,tier,validate_model(contract))
            assert contract['contact_error_m'] < .00001
        assert entry['tiers']['far']['triangles'] < entry['tiers']['middle']['triangles']
        assert entry['tiers']['middle']['triangles'] <= entry['original_middle_triangles']
        assert entry['size_godot']==entry['original_envelope']['size_godot']
        for key in ['min_godot','max_godot']:
            assert entry[key]==entry['original_envelope'][key]
        if kind not in ['ship','sailboat','helicopter']:
            assert len(entry['animation']['wheels'])>=3
        if kind=='helicopter': assert len(entry['animation']['rotors'])==2
