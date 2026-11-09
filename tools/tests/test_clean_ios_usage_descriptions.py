# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""The iOS Info.plist check and cleanup."""
from __future__ import annotations
import plistlib
import sys
import zipfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import clean_ios_usage_descriptions as tool  # noqa: E402

EXPORTED = {
    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "ITSAppUsesNonExemptEncryption": False,
    "NSCameraUsageDescription": "",
    "NSMicrophoneUsageDescription": "",
    "NSPhotoLibraryUsageDescription": "",
}
BUILT = {
    "CFBundleIdentifier": "com.example.game",
    "CFBundleShortVersionString": "0.7",
    "CFBundleVersion": "0.7",
}
PBXPROJ = """
    buildSettings = {
        MARKETING_VERSION = 0.7;
        CURRENT_PROJECT_VERSION = 12;
    };
    buildSettings = {
        MARKETING_VERSION = 0.7;
        CURRENT_PROJECT_VERSION = 12;
    };
"""


def export_dir(root: Path, values: dict) -> Path:
    (root / "SC2D").mkdir(parents=True)
    (root / "SC2D.xcodeproj").mkdir()
    (root / "SC2D.xcodeproj" / "project.pbxproj").write_text(PBXPROJ, encoding="utf-8")
    plist = root / "SC2D" / "SC2D-Info.plist"
    plist.write_bytes(plistlib.dumps(values, sort_keys=False))
    return plist


def test_check_names_each_empty_key_and_changes_nothing(tmp_path, capsys):
    plist = export_dir(tmp_path, EXPORTED)
    before = plist.read_bytes()
    assert tool.main([str(tmp_path), "--check"]) == 1
    out = capsys.readouterr().out
    for key in tool.EMPTY_UNUSED_KEYS:
        assert f"FAIL: {key} is empty" in out
    assert plist.read_bytes() == before


def test_check_resolves_versions_from_the_xcode_project(tmp_path, capsys):
    export_dir(tmp_path, EXPORTED)
    tool.main([str(tmp_path / "SC2D.xcodeproj")])
    out = capsys.readouterr().out
    assert "CFBundleShortVersionString: 0.7 (from MARKETING_VERSION)" in out
    assert "CFBundleVersion: 12 (from CURRENT_PROJECT_VERSION)" in out
    assert "Raise it before every upload" in out


def test_apply_removes_only_the_empty_keys_then_check_passes(tmp_path, capsys):
    values = dict(EXPORTED, NSCameraUsageDescription="Scan a code.")
    plist = export_dir(tmp_path, values)
    assert tool.main([str(plist), "--apply"]) == 0
    cleaned = plistlib.loads(plist.read_bytes())
    assert cleaned["NSCameraUsageDescription"] == "Scan a code."
    assert "NSMicrophoneUsageDescription" not in cleaned
    assert "NSPhotoLibraryUsageDescription" not in cleaned
    assert cleaned["ITSAppUsesNonExemptEncryption"] is False
    assert tool.main([str(tmp_path)]) == 0
    assert "OK:" in capsys.readouterr().out


def test_check_reports_other_empty_purpose_strings_and_missing_keys(tmp_path, capsys):
    plist = tmp_path / "Info.plist"
    plist.write_bytes(plistlib.dumps({"CFBundleIdentifier": "a.b", "CFBundleVersion": " ",
                                      "NSLocationWhenInUseUsageDescription": ""}))
    assert tool.main([str(plist), "--check"]) == 1
    out = capsys.readouterr().out
    assert "FAIL: NSLocationWhenInUseUsageDescription is empty" in out
    assert "FAIL: CFBundleShortVersionString is missing" in out
    assert "FAIL: CFBundleVersion is empty" in out


def test_check_reads_a_binary_plist_inside_an_ipa(tmp_path, capsys):
    ipa = tmp_path / "game.ipa"
    with zipfile.ZipFile(ipa, "w") as archive:
        archive.writestr("Payload/SC2D.app/Info.plist",
                         plistlib.dumps(dict(BUILT, NSMicrophoneUsageDescription=""), fmt=plistlib.FMT_BINARY))
        archive.writestr("Payload/SC2D.app/Frameworks/A.framework/Info.plist", plistlib.dumps({}))
    before = ipa.read_bytes()
    assert tool.main([str(ipa), "--check"]) == 1
    out = capsys.readouterr().out
    assert "FAIL: NSMicrophoneUsageDescription is empty" in out
    assert "CFBundleVersion: 0.7" in out
    assert ipa.read_bytes() == before


def test_check_reads_an_app_and_an_xcarchive(tmp_path):
    app = tmp_path / "A.xcarchive" / "Products" / "Applications" / "SC2D.app"
    app.mkdir(parents=True)
    (app / "Info.plist").write_bytes(plistlib.dumps(BUILT))
    assert tool.main([str(app)]) == 0
    assert tool.main([str(tmp_path / "A.xcarchive"), "--check"]) == 0


def test_apply_refuses_built_products(tmp_path):
    app = tmp_path / "SC2D.app"
    app.mkdir()
    (app / "Info.plist").write_bytes(plistlib.dumps(dict(BUILT, NSCameraUsageDescription="")))
    before = (app / "Info.plist").read_bytes()
    with pytest.raises(SystemExit):
        tool.main([str(app), "--apply"])
    assert (app / "Info.plist").read_bytes() == before


def test_check_and_apply_cannot_be_combined(tmp_path):
    plist = export_dir(tmp_path, EXPORTED)
    with pytest.raises(SystemExit):
        tool.main([str(plist), "--check", "--apply"])
