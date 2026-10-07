#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Check the owned Blender runtime assets and their shared surface textures."""

from __future__ import annotations

import hashlib
import json
import math
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "game/assets/desert-dreams-3d"
FIELDS = {"code", "path", "scale", "pivot", "yaw", "height", "footprint",
          "triangles", "source_kind", "glb_sha256", "meters_per_tile"}


def check() -> tuple[int, int]:
    catalog = json.loads((ASSETS / "catalog.json").read_text())
    assert set(catalog) == {"version", "status", "entries"}, "unexpected catalog metadata"
    entries = catalog["entries"]
    material_manifest = ROOT / 'docs/art/building-materials.json'
    shared_images = {}
    if material_manifest.exists():
        material_data = json.loads(material_manifest.read_text())
        assert sorted(row['code'] for row in material_data['models']) == list(range(112,256)), 'material provenance coverage'
        for row in material_data['textures']:
            name = row['path']
            assert re.fullmatch(r'surfaces/[a-f0-9]{64}\.(jpg|png)', name), 'shared texture path'
            path = ASSETS / name
            assert hashlib.sha256(path.read_bytes()).hexdigest() == row['sha256'], f'{name}: shared texture hash'
            assert 'mipmaps/generate=true' in path.with_suffix(path.suffix+'.import').read_text(), f'{name}: mipmaps'
            shared_images[name] = row
    assert sorted(e["code"] for e in entries) == list(range(112, 256)), "coverage or duplicate code"
    total_bytes = 0
    for entry in entries:
        code = entry["code"]
        assert set(entry) == FIELDS, f"{code}: unexpected runtime metadata"
        name = f"{code}-blender.glb"
        assert entry["path"] == f"res://assets/desert-dreams-3d/{name}", f"{code}: asset path"
        assert entry["scale"] == 1 / 16 and entry["meters_per_tile"] == 16, f"{code}: scale"
        assert entry["pivot"] == [0, 0, 0] and entry["yaw"] == 0, f"{code}: transform"
        assert math.isfinite(entry["height"]) and entry["height"] > 0, f"{code}: height"
        assert entry["source_kind"] == "authored_blender", f"{code}: asset origin"
        assert len(entry["footprint"]) == 2 and all(v in (1, 2, 3, 4) for v in entry["footprint"]), f"{code}: footprint"
        data = (ASSETS / name).read_bytes()
        assert hashlib.sha256(data).hexdigest() == entry["glb_sha256"], f"{code}: content hash"
        magic, version, size = struct.unpack_from("<III", data)
        assert (magic, version, size) == (0x46546C67, 2, len(data)), f"{code}: GLB header"
        length, kind = struct.unpack_from("<II", data, 12)
        assert kind == 0x4E4F534A, f"{code}: JSON chunk"
        gltf = json.loads(data[20:20 + length])
        assert all('uri' not in v for v in gltf.get('buffers',[])), f'{code}: external geometry'
        for image in gltf.get('images',[]):
            assert 'uri' not in image or image['uri'] in shared_images, f'{code}: unapproved external texture'
        if shared_images:
            source = next(row for row in material_data['models'] if row['code'] == code)
            assert source['runtime_glb_sha256'] == entry['glb_sha256'], f'{code}: material provenance hash'
        assert any(n.get("name", "").endswith("-colonly") for n in gltf["nodes"]), f"{code}: physical shell"
        sidecar = (ASSETS / (name + ".import")).read_text()
        for required in (f'source_file="{entry["path"]}"', 'meshes/generate_lods=true',
                         'nodes/use_name_suffixes=true', 'gltf/naming_version=2',
                         'gltf/embedded_image_handling=1'):
            assert required in sidecar, f"{code}: missing import setting {required}"
        if code == 203:
            tail = sidecar.split("_subresources=", 1)[1]
            settings, _ = json.JSONDecoder().raw_decode(tail)
            shell = settings["meshes"]["203-blender_Hollow faceted cooling tower shell"]
            assert shell["lods/normal_merge_angle"] == 0.0, "203: faceted shell import policy"
        if code in (222, 230):
            assert entry["triangles"] <= {222: 128, 230: 288}[code], f"{code}: minimal paving budget"
        total_bytes += len(data)
    plantings = json.loads((ASSETS / "landscaping.json").read_text())
    seen = set()
    for profile in plantings["entries"]:
        code = profile["code"]
        assert code not in seen, f"{code}: duplicate planting profile"
        seen.add(code)
        model = next(e for e in entries if e["code"] == code)
        assert profile["glb_sha256"] == model["glb_sha256"], f"{code}: stale planting clearance"
        for x, y, z, height, radius in profile["palms"]:
            assert all(math.isfinite(v) for v in (x, y, z, height, radius)), f"{code}: planting values"
            assert y >= 0 and 0 < radius < height, f"{code}: planting dimensions"
            assert abs(x) + radius <= model["footprint"][0] / 2, f"{code}: palm outside lot width"
            assert abs(z) + radius <= model["footprint"][1] / 2, f"{code}: palm outside lot depth"
    presets = (ROOT / "game/export_presets.cfg").read_text()
    filters = [line for line in presets.splitlines() if line.startswith("include_filter=")]
    assert filters and all("assets/desert-dreams-3d/catalog.json" in line for line in filters), "export catalog inclusion"
    assert all("assets/desert-dreams-3d/landscaping.json" in line for line in filters), "export landscaping inclusion"
    textures = json.loads((ROOT / "docs/art/ground-textures.json").read_text())["textures"]
    assert sorted(row["file"] for row in textures) == ["desert-rock.png", "desert-sand.png", "road-grain.png"], "ground material coverage"
    for row in textures:
        path = ASSETS / "textures" / row["file"]
        data = path.read_bytes()
        assert hashlib.sha256(data).hexdigest() == row["sha256"], f"{path.name}: texture hash"
        assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path.name}: PNG signature"
        assert list(struct.unpack_from(">II", data, 16)) == row["dimensions"], f"{path.name}: texture dimensions"
        assert "mipmaps/generate=true" in path.with_suffix(".png.import").read_text(), f"{path.name}: mipmaps required"
    return len(entries), total_bytes


if __name__ == "__main__":
    count, size = check()
    print(f"3D package clean: {count} models, {size:,} GLB bytes; hashes, import settings and export filters verified")
