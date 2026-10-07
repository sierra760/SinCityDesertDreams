# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

import importlib.util
import hashlib
import os
import re
import tempfile
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("runner", Path(__file__).parents[1] / "run_tests.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class ClassificationTests(unittest.TestCase):
    def test_clean_terminal_summary(self):
        self.assertTrue(runner.classify_output(0, "Godot\nResults: 12 passed, 0 failed\n")[0])

    def test_failed_and_missing_summary(self):
        for output in ("Results: 2 passed, 1 failed\n", "Godot\n", "Results: 0 passed, 0 failed\n"):
            with self.subTest(output=output):
                self.assertFalse(runner.classify_output(0, output)[0])

    def test_nonzero_exit_rejects_green_text(self):
        self.assertFalse(runner.classify_output(1, "Results: 1 passed, 0 failed\n")[0])

    def test_engine_and_resource_diagnostics_reject_green(self):
        for diagnostic in ("SCRIPT ERROR: bad", "ERROR: resource missing", "WARNING: ObjectDB instances leaked at exit", "26 resources still in use at exit", "Parse Error: bad", "Compile Error: bad"):
            with self.subTest(diagnostic=diagnostic):
                self.assertFalse(runner.classify_output(0, "Results: 1 passed, 0 failed\n" + diagnostic)[0])

    def test_failed_import_raises(self):
        completed = subprocess.CompletedProcess([], 1, stdout="", stderr="import failed")
        with patch.object(runner.subprocess, "run", return_value=completed):
            with self.assertRaises(RuntimeError):
                runner.refresh_class_cache("godot")

    def test_diagnostic_import_raises_despite_zero_exit(self):
        completed = subprocess.CompletedProcess([], 0, stdout="", stderr="ERROR: Cannot load texture")
        with patch.object(runner.subprocess, "run", return_value=completed):
            with self.assertRaises(RuntimeError):
                runner.refresh_class_cache("godot")

    def test_timeout_keeps_both_test_streams(self):
        timeout = subprocess.TimeoutExpired([], 1, output=b"partial stdout", stderr=b"script diagnostic")
        with patch.object(runner.subprocess, "run", side_effect=timeout):
            ok, output = runner.run_one("godot", Path("test_fixture.gd"), 1)
        self.assertFalse(ok)
        self.assertIn("partial stdout", output)
        self.assertIn("script diagnostic", output)

    def test_import_timeout_retains_both_streams(self):
        timeout = subprocess.TimeoutExpired([], 1, output=b"import stdout", stderr=b"import stderr")
        with patch.object(runner.subprocess, "run", side_effect=timeout), patch.object(runner, "retain_output") as retained:
            with self.assertRaises(RuntimeError):
                runner.refresh_class_cache("godot")
        self.assertIn("import stdout", retained.call_args.args[1])
        self.assertIn("import stderr", retained.call_args.args[1])


class IsolatedProjectTests(unittest.TestCase):
    def fixture(self, parent):
        source = Path(parent) / "source-game"
        source.mkdir()
        (source / "project.godot").write_text('[application]\nconfig/name="Game"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="SinCityDesertDreams"\n\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        (source / "tests").mkdir()
        (source / "tests" / "test_fixture.gd").write_text('extends SceneTree\n')
        for relative in [".godot/cache", "export/game.zip", "assets/export/authored.txt"]:
            path = source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(relative)
        return source

    def hashes(self, source):
        return {str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in source.rglob("*") if path.is_file()}

    def test_copy_changes_only_custom_userdata_and_keeps_source_hashes(self):
        with tempfile.TemporaryDirectory() as fixture_dir:
            source = self.fixture(fixture_dir)
            before = self.hashes(source)
            names = []
            for attempt in range(2):
                with runner.isolated_test_project(source) as copied:
                    self.assertNotEqual(copied, source)
                    settings = (copied / "project.godot").read_text()
                    name = re.search(r'config/custom_user_dir_name="([^\"]+)"', settings).group(1)
                    self.assertTrue(name.startswith("SinCityDesertDreamsTests-"))
                    names.append(name)
                    original = (source / "project.godot").read_text()
                    self.assertEqual(settings.replace(name, "SinCityDesertDreams"), original)
                    self.assertFalse((copied / ".godot").exists())
                    self.assertFalse((copied / "export").exists())
                    for relative in ["tests/test_fixture.gd", "assets/export/authored.txt"]:
                        self.assertEqual((copied / relative).read_bytes(), (source / relative).read_bytes())
                self.assertFalse(copied.exists(), "temporary project must be cleaned after context exit")
            self.assertNotEqual(names[0], names[1])
            self.assertEqual(self.hashes(source), before)

    def test_default_main_imports_private_copy_and_cleans_on_every_exit(self):
        with tempfile.TemporaryDirectory() as fixture_dir:
            source = self.fixture(fixture_dir)
            before = self.hashes(source)
            for outcome in ["success", "failed-test", "failed-import"]:
                seen = []
                def importing(_godot):
                    seen.append(runner.GAME)
                    self.assertTrue((runner.GAME / "project.godot").is_file())
                    self.assertNotEqual(runner.GAME, source)
                    if outcome == "failed-import":
                        raise RuntimeError("declared import failure")
                with patch.dict(os.environ, {}, clear=True), patch.object(runner, "GAME", source), \
                     patch.object(runner, "find_godot", return_value="godot"), \
                     patch.object(runner, "refresh_class_cache", side_effect=importing), \
                     patch.object(runner, "run_one", return_value=(outcome == "success", "Results: 1 passed, 0 failed\n")):
                    result = runner.main(["--no-import", "test_fixture.gd"])
                    self.assertEqual(result, 0 if outcome == "success" else 1)
                    self.assertEqual(runner.GAME, source)
                self.assertEqual(len(seen), 1, "fresh default copy imports even with --no-import")
                self.assertFalse(seen[0].exists())
            self.assertEqual(self.hashes(source), before)

    def test_explicit_override_remains_caller_owned_and_supports_no_import(self):
        with tempfile.TemporaryDirectory() as fixture_dir:
            source = self.fixture(fixture_dir)
            before = self.hashes(source)
            with patch.dict(os.environ, {"TEST_GAME_PATH": str(source)}, clear=True), \
                 patch.object(runner, "find_godot", return_value="godot"), \
                 patch.object(runner, "isolated_test_project") as isolated, \
                 patch.object(runner, "refresh_class_cache") as importing, \
                 patch.object(runner, "run_one", return_value=(True, "Results: 1 passed, 0 failed\n")) as run:
                self.assertEqual(runner.main(["--no-import", "test_fixture.gd"]), 0)
                isolated.assert_not_called()
                importing.assert_not_called()
                self.assertEqual(run.call_args.args[1].parent.parent, source.resolve())
            self.assertTrue(source.exists())
            self.assertEqual(self.hashes(source), before)


if __name__ == "__main__":
    unittest.main()
