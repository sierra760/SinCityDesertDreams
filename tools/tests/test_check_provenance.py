# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("checker", Path(__file__).parents[1] / "check_provenance.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class PublicEnumTests(unittest.TestCase):
    def scan(self, text):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "fixture.gd"
            path.write_text(text)
            with patch.object(checker, "ROOT", root):
                return checker.scan_file(path, set())

    def test_qualified_hash_algorithm_is_allowed(self):
        enum = "HASH_SHA256"
        self.assertEqual(self.scan("hash.start(HashingContext." + enum + ")"), [])

    def test_other_matches_on_same_line_are_still_rejected(self):
        enum = "HASH_SHA256"
        address = "count_4CB6"
        findings = self.scan("HashingContext." + enum + "; " + address + " = 1")
        self.assertEqual(len(findings), 1)
        self.assertIn(address, findings[0])

    def test_unqualified_or_extended_token_is_not_exempt(self):
        enum = "HASH_SHA256"
        self.assertEqual(len(self.scan(enum + " = 1")), 1)
        self.assertEqual(len(self.scan("HashingContext." + enum + "A = 1")), 1)


class SkippedOutputTests(unittest.TestCase):
    def test_gitignored_export_copies_are_skipped(self):
        token = "SC" + "2K"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in ("game/export/copy/fixture.gd", "game/scripts/fixture.gd"):
                path = root / relative
                path.parent.mkdir(parents=True)
                path.write_text(token + "\n")
            with patch.object(checker, "ROOT", root), \
                    patch.object(checker, "ALLOW_FILE", root / "missing.txt"), \
                    patch("builtins.print") as printed:
                self.assertEqual(checker.main(["game"]), 1)
            output = " ".join(str(call.args[0]) for call in printed.call_args_list)
            self.assertIn("game/scripts/fixture.gd", output)
            self.assertNotIn("game/export/", output)


if __name__ == "__main__":
    unittest.main()
