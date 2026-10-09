#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Check the gaming resort hall and prop package in game/assets/desert-dreams-resorts."""

from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "game/assets/desert-dreams-resorts"
HALLS = ["hall_126", "hall_251", "hall_252", "hall_253", "hall_254"]
PROPS = ["slot_cabinet", "slot_stool", "blackjack_table", "roulette_table", "money_wheel",
         "video_poker_terminal", "faro_table", "chuck_a_luck_cage", "baccarat_table", "trajectory_console",
         "chandelier_gaslamp", "chandelier_lantern", "chandelier_turbine", "chandelier_starburst",
         "banquette", "bar_stool", "standard_sign"]
OPEN = {"slot_stool", "bar_stool", "standard_sign", "chandelier_gaslamp", "chandelier_lantern",
        "chandelier_turbine", "chandelier_starburst"}
FINISHES = {"resort_" + f for f in ("floor", "carpet", "wall", "ceiling", "stone", "wood", "metal", "cove", "foliage",
            "glass", "felt", "lamp", "sign", "screen", "rubber")}
FIELDS = {"triangles", "parts", "materials", "colliders", "min_godot", "max_godot", "size_godot", "sha256"}


def gltf(data: bytes) -> dict:
    magic, version, size = struct.unpack_from("<III", data)
    assert (magic, version, size) == (0x46546C67, 2, len(data)), "GLB header"
    length, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A, "JSON chunk"
    return json.loads(data[20:20 + length])


def check() -> tuple[int, int]:
    catalog = json.loads((ASSETS / "catalog.json").read_text())
    for key in ("source_units", "runtime_units", "forward", "provenance", "generator", "models", "halls"):
        assert key in catalog, f"catalog {key}"
    models = catalog["models"]
    assert sorted(models) == sorted(HALLS + PROPS), "model coverage"
    assert sorted(catalog["halls"]) == ["251", "252", "253", "254"], "hall coverage"
    stores = catalog.get("stores", {})
    assert set(stores) == {"126"}, "store coverage"
    store = stores["126"]
    assert store["model"] == "hall_126" and store["slots"] == 4 and store["video_poker"] == 2, "store machines"
    assert store["retail_area_m2"] == store["gaming_area_m2"] == 60, "half store, half casino"
    assert (ROOT / store["generator"]).exists(), "store generator present"
    total = 0
    for name, entry in models.items():
        assert set(entry) == FIELDS, f"{name}: catalog fields"
        path = ASSETS / f"{name}.glb"
        data = path.read_bytes()
        assert hashlib.sha256(data).hexdigest() == entry["sha256"], f"{name}: content hash"
        document = gltf(data)
        assert all("uri" not in b for b in document.get("buffers", [])), f"{name}: external geometry"
        assert not document.get("images"), f"{name}: no bitmap textures"
        materials = {m.get("name") for m in document.get("materials", [])}
        assert materials and materials <= FINISHES, f"{name}: finish material names {materials - FINISHES}"
        assert sorted(materials) == entry["materials"], f"{name}: catalog materials"
        shells = [n for n in document["nodes"] if n.get("name", "").endswith("-colonly")]
        assert len(shells) == entry["colliders"], f"{name}: collision shell count"
        if name not in OPEN:
            assert shells, f"{name}: collision shells"
        budget = 40000 if name.startswith("hall_") else 1500 if name == "slot_cabinet" else 4000
        assert 0 < entry["triangles"] <= budget, f"{name}: triangle budget {entry['triangles']} > {budget}"
        sidecar = (ASSETS / f"{name}.glb.import").read_text()
        for required in (f'source_file="res://assets/desert-dreams-resorts/{name}.glb"', "meshes/generate_lods=true",
                         "nodes/use_name_suffixes=true", "gltf/naming_version=2", "gltf/embedded_image_handling=1", 'uid="uid://'):
            assert required in sidecar, f"{name}: import setting {required}"
        total += len(data)
    for code, hall in catalog["halls"].items():
        assert hall["model"] == f"hall_{code}", f"hall {code}: model"
        assert hall["chandelier"] in models and hall["signature"] in models, f"hall {code}: kit"
    provenance = json.loads((ASSETS / "provenance.json").read_text())
    assert provenance["generator"] == catalog["generator"], "provenance generator"
    assert (ROOT / provenance["generator"]).exists(), "generator present"
    assert (ASSETS / "README.md").exists(), "package README"
    presets = (ROOT / "game/export_presets.cfg").read_text()
    filters = [line for line in presets.splitlines() if line.startswith("include_filter=")]
    assert filters and all("assets/desert-dreams-resorts/catalog.json" in line for line in filters), "export catalog inclusion"
    return len(models), total


if __name__ == "__main__":
    count, size = check()
    print(f"Resort package clean: {count} models, {size:,} GLB bytes; hashes, budgets, shells, materials, import settings and export filters verified")
