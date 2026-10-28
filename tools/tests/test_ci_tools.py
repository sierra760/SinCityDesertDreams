# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / "ci" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


presets = load("prepare_export_presets")
smoke = load("smoke_export")


class ExportPresetTests(unittest.TestCase):
    def committed(self):
        return (TOOLS.parent / "game" / "export_presets.cfg").read_text(encoding="utf-8")

    def section(self, text, name):
        start, end = presets.options_section(text, name)
        return text[start:end]

    def test_committed_presets_become_unsigned(self):
        original = self.committed()
        prepared = presets.prepare(original)
        mac = self.section(prepared, "macOS")
        self.assertIn("\ncodesign/codesign=1\n", mac)
        self.assertIn("\nnotarization/notarization=0\n", mac)
        self.assertIn("\nexport/distribution_type=0\n", mac)
        # Other presets, including the App Store one that shares option names, keep their values.
        for name in ("macOS App Store", "Windows x64", "iOS", "Linux"):
            self.assertEqual(self.section(prepared, name), self.section(original, name))
        self.assertEqual(len(prepared.splitlines()), len(original.splitlines()))

    def test_signed_windows_preset_is_refused(self):
        text = self.committed()
        start, end = presets.options_section(text, "Windows x64")
        signed = text[:start] + text[start:end].replace("codesign/enable=false", "codesign/enable=true") + text[end:]
        with self.assertRaisesRegex(ValueError, "codesign/enable must be false"):
            presets.prepare(signed)

    def test_missing_preset_is_refused(self):
        with self.assertRaisesRegex(ValueError, "no export preset named"):
            presets.prepare('[preset.0]\n\nname="Linux"\n\n[preset.0.options]\n\nx=1\n')


class SmokeExportTests(unittest.TestCase):
    def fake_game(self, directory, output, code=0):
        game = Path(directory) / "game"
        game.write_text(f"#!/bin/sh\nprintf '%s\\n' '{output}'\nexit {code}\n")
        game.chmod(0o755)
        return game

    def test_app_bundle_resolves_its_executable(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Game.app"
            (app / "Contents" / "MacOS").mkdir(parents=True)
            with open(app / "Contents" / "Info.plist", "wb") as handle:
                plistlib.dump({"CFBundleExecutable": "Sin City"}, handle)
            self.assertEqual(smoke.executable(app), app / "Contents" / "MacOS" / "Sin City")

    def test_clean_run_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            game = self.fake_game(directory, "Godot Engine v4.7.2.stable")
            self.assertEqual(smoke.main([str(game), "--log", str(Path(directory) / "smoke.log")]), 0)

    def test_diagnostics_and_failed_exit_fail(self):
        for output, code in (("SCRIPT ERROR: bad", 0), ("ERROR: missing resource", 0), ("fine", 3)):
            with self.subTest(output=output, code=code), tempfile.TemporaryDirectory() as directory:
                game = self.fake_game(directory, output, code)
                self.assertEqual(smoke.main([str(game), "--log", str(Path(directory) / "smoke.log")]), 1)


if __name__ == "__main__":
    unittest.main()
