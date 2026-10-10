#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Prepare the six added resorts' facade, paving and roof surface textures.

Reads the locally kept 1024px source swatches in assets/six-resorts/texture-sources/
and writes neutral grayscale albedo masters to assets/six-resorts/textures/ with
a manifest. Each master is flattened (broad lighting drift removed) and given a
common light mean so the exterior generator's multiplicative palette factor
reproduces each resort's authored color. Meter scale and finish assignment
live in tools/blender_exploration/build_six_resort_exteriors.py.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/six-resorts/texture-sources'
OUT = ROOT / 'assets/six-resorts/textures'
NAMES = ('granite', 'scored-stucco', 'brick', 'board-formed-concrete',
         'rusticated-sandstone', 'corrugated-steel', 'terrazzo-paving', 'gravel-roof')
TARGET_MEAN = 0.86  # sRGB, matching the earlier shared building swatches
# Swatches tinted to darker palettes keep more relief with a lower mean.
TARGETS = {'gravel-roof': .70, 'corrugated-steel': .80, 'brick': .80, 'granite': .80}
# Minimum relief (standard deviation) so swatches still read on dark palettes.
MIN_STD = {'granite': .10}
DEFAULT_MIN_STD = .06
SIZE = 1024


def linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= .04045, c / 12.92, ((c + .055) / 1.055) ** 2.4)


def prepare(name: str) -> dict:
    image = Image.open(SOURCE / f'{name}.png').convert('L').resize((SIZE, SIZE), Image.LANCZOS)
    gray = np.asarray(image, dtype=np.float64) / 255
    # Divide out only very broad shading so courses, planks and joints remain.
    drift = np.asarray(image.filter(ImageFilter.GaussianBlur(SIZE / 6)), dtype=np.float64) / 255
    flat = gray / np.maximum(drift, .05) * drift.mean()
    # Affine remap about the mean: keep relief contrast, never blow highlights.
    target = TARGETS.get(name, TARGET_MEAN)
    mean, high = flat.mean(), np.percentile(flat, 99.5)
    gain = min(target / mean, (.97 - target) / max(high - mean, 1e-6))
    flat = target + (flat - mean) * gain
    floor = MIN_STD.get(name, DEFAULT_MIN_STD)
    if flat.std() < floor:
        flat = target + (flat - target) * (floor / flat.std())
    if name == 'granite':
        # Crisp pale joints on the 3 x 4 panel grid already faint in the swatch,
        # so dark cladding still reads as jointed panels (mirror tiling keeps edges).
        for k in range(4):
            x = round(k * SIZE / 3); flat[:, max(0, x-2):x+2] = .97
        for k in range(5):
            y = round(k * SIZE / 4); flat[max(0, y-2):y+2, :] = .97
    flat = np.clip(flat, 0, 1)
    data = (flat * 255 + .5).astype(np.uint8)
    # Godot's standard material cannot mirror-wrap, so bake the mirror: a 2 x 2
    # reflected tile repeats seamlessly with ordinary repeat wrapping.
    data = np.block([[data, data[:, ::-1]], [data[::-1, :], data[::-1, ::-1]]])
    path = OUT / f'{name}.png'
    Image.fromarray(data, 'L').convert('RGB').save(path, optimize=True)
    lin = float(linear(data / 255).mean())
    return {'file': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'dimensions': [SIZE * 2, SIZE * 2], 'periods': 2, 'mean_rgb': [float(data.mean())] * 3, 'mean_linear': [lin] * 3}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rows = [prepare(name) for name in NAMES]
    manifest = {'title': 'Six added resort surface textures',
                'provenance': 'Texture swatches made for this project from written material descriptions; '
                              'no photographs, scans, third-party textures or game screenshots were used.',
                'processing': 'tools/build_resort_surface_textures.py: grayscale, broad shading flattened, '
                              f'mean normalised to {TARGET_MEAN} sRGB ({TARGETS} for darker finishes), {SIZE}px swatch '
                              'mirrored into a seamless 2 x 2 repeat tile.',
                'textures': rows}
    (OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Wrote {len(rows)} resort surface textures to {OUT}')


if __name__ == '__main__':
    main()
