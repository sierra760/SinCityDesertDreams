# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Reviewed illustrations must survive every supported packaging entry point."""
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_casino_art import apply_reviewed_art

class ReviewedCasinoArtTests(unittest.TestCase):
    def test_repair_replaces_atlas_fragment_and_records_exact_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'assets/casino-art/dust'
            folder = root / 'game/assets/desert-dreams-casino-art/dust'
            (source / 'reviewed').mkdir(parents=True)
            folder.mkdir(parents=True)
            original = folder / 'symbol-s2.png'
            Image.new('RGBA', (256,256), 'red').save(original)
            repair = source / 'reviewed/symbol-s2.png'
            image = Image.new('RGBA', (256,256))
            image.paste('blue', (48,48,208,208))
            image.save(repair)
            untouched = folder / 'card-back.png'
            Image.new('RGBA', (256,256), 'green').save(untouched)
            before = untouched.read_bytes()
            entry = {'assets': {'symbol-s2': {}, 'card-back': {'untouched': True}}}
            apply_reviewed_art(entry, source, folder, root)
            self.assertEqual(original.read_bytes(), repair.read_bytes())
            self.assertEqual(entry['assets']['symbol-s2']['content_region'], [46,46,164,164])
            provenance = entry['reviewed_overrides']['symbol-s2']
            self.assertEqual(provenance['source'], 'assets/casino-art/dust/reviewed/symbol-s2.png')
            self.assertEqual(provenance['sha256'], hashlib.sha256(repair.read_bytes()).hexdigest())
            self.assertEqual(untouched.read_bytes(), before)
            self.assertEqual(entry['assets']['card-back'], {'untouched': True})
            first = original.read_bytes()
            apply_reviewed_art(entry, source, folder, root)
            self.assertEqual(original.read_bytes(), first)

    def test_unframed_reel_icons_have_complete_isolated_silhouettes(self):
        art = Path(__file__).resolve().parents[2] / 'game/assets/desert-dreams-casino-art'
        for theme in ['comstock', 'junction', 'boulder', 'orbit']:
            for symbol in ['s1', 's2', 's3', 's4', 's5', 'B']:
                with self.subTest(theme=theme, symbol=symbol):
                    with Image.open(art/theme/('symbol-'+symbol+'.png')) as image:
                        self.assertEqual(image.mode, 'RGBA')
                        bounds = image.getchannel('A').point(lambda a: 255 if a > 16 else 0).getbbox()
                        self.assertIsNotNone(bounds)
                        self.assertGreater(min(bounds[0], bounds[1], image.width-bounds[2], image.height-bounds[3]), 0,
                                           'subject or adjacent atlas fragment reaches image edge')

    def test_catalog_keeps_every_shipped_venue_after_rebuilding(self):
        import json
        art = Path(__file__).resolve().parents[2] / 'game/assets/desert-dreams-casino-art'
        catalog = json.loads((art/'catalog.json').read_text())
        themes = {path.name for path in art.iterdir() if path.is_dir() and (path/'card-back.png').exists()}
        self.assertEqual(set(catalog['sets']), themes)

    def test_absent_repairs_leave_existing_package_unchanged(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            entry = {'assets': {'card-back': {'unchanged': True}}}
            apply_reviewed_art(entry, root/'source', root/'dest', root)
            self.assertEqual(entry, {'assets': {'card-back': {'unchanged': True}}})

    def test_unknown_asset_cannot_silently_expand_runtime_catalog(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'source/reviewed').mkdir(parents=True)
            Image.new('RGBA', (256,256)).save(root/'source/reviewed/typo.png')
            with self.assertRaises(ValueError):
                apply_reviewed_art({'assets': {}}, root/'source', root/'dest', root)

if __name__ == '__main__': unittest.main()
