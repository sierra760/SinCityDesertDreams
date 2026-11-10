# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""The police car replacement must remove its old solid/visible occupants only."""
import numpy as np
from tools.split_model_palms import catalog_entries, model_path, parts_of, read_glb


def _display_car(part):
    return any(np.all(part['lo'] >= [x-2.05, .21, 11.4])
               and np.all(part['hi'] <= [x+2.05, 4.1, 19.0]) for x in [-9, 10])


def test_police_lot_has_no_baked_display_cars_or_their_solid_collision():
    doc, binary = read_glb(model_path(catalog_entries()[210]).read_bytes())
    parts = parts_of(doc, binary)
    assert not [p for p in parts if _display_car(p)], 'old display cars must leave with their colliders'
    # The building body and front canopy are retained exactly.
    assert any(p['collision'] and np.allclose(p['lo'], [-14, .2, -17.5])
               and np.allclose(p['hi'], [16, 20.3, 5.5]) for p in parts)
    assert any(p['collision'] and np.allclose(p['lo'], [-2.6, 6.69, 5.35])
               and np.allclose(p['hi'], [4.6, 7.31, 8.45]) for p in parts)
