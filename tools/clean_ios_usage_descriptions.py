#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check or clean the Info.plist of an iOS export.

Godot writes empty camera, microphone and photo-library purpose strings into
the exported Info.plist. The game uses none of those, and App Store Connect
rejects an upload that carries an empty purpose string.

PATH may be:
  an Info.plist file;
  a Godot iOS export directory or its .xcodeproj;
  a built .app, an .xcarchive or an .ipa.

--check (the default) changes nothing. It exits 1 and names each purpose
string that is empty and each required key that is missing or empty. It also
prints the version and build number as a reminder: every upload to App Store
Connect needs a build number that has not been used before.

--apply removes the three empty, unused purpose strings from an exported
project's plist. Populated descriptions are kept. Run it after every Godot iOS
export and before archiving. It refuses built products (.app, .xcarchive,
.ipa); export again and clean the project instead.
"""
from __future__ import annotations
import argparse
import plistlib
import re
import zipfile
from pathlib import Path

EMPTY_UNUSED_KEYS = (
    "NSCameraUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSPhotoLibraryUsageDescription",
)
REQUIRED_KEYS = (
    "CFBundleIdentifier",
    "CFBundleShortVersionString",
    "CFBundleVersion",
)
BUILD_SETTINGS = {
    "$(MARKETING_VERSION)": "MARKETING_VERSION",
    "$(CURRENT_PROJECT_VERSION)": "CURRENT_PROJECT_VERSION",
}
IPA_PLIST = re.compile(r"^Payload/[^/]+\.app/Info\.plist$")


class Target:
    """A located Info.plist: its bytes, where it is and whether it may be edited."""

    def __init__(self, label: str, data: bytes, file: Path | None, project: Path | None):
        self.label = label
        self.data = data
        self.file = file  # Set only for a plist that --apply may rewrite.
        self.project = project  # project.pbxproj that supplies build settings.


def _single(matches: list[Path], what: str, where: Path) -> Path:
    if not matches:
        raise SystemExit(f"error: no {what} in {where}")
    if len(matches) > 1:
        names = ", ".join(str(match) for match in matches)
        raise SystemExit(f"error: more than one {what} in {where}: {names}")
    return matches[0]


def _project_file(directory: Path) -> Path | None:
    found = sorted(directory.glob("*.xcodeproj/project.pbxproj"))
    return found[0] if len(found) == 1 else None


def locate(path: Path) -> Target:
    if not path.exists():
        raise SystemExit(f"error: {path} does not exist")
    if path.is_file() and path.suffix == ".ipa":
        with zipfile.ZipFile(path) as archive:
            names = [name for name in archive.namelist() if IPA_PLIST.match(name)]
            if len(names) != 1:
                raise SystemExit(f"error: expected one Payload/*.app/Info.plist in {path}, found {len(names)}")
            return Target(f"{path}!{names[0]}", archive.read(names[0]), None, None)
    if path.is_file():
        return Target(str(path), path.read_bytes(), path, _project_file(path.parent.parent))
    if path.suffix == ".app":
        plist = path / "Info.plist"
        if not plist.is_file():
            raise SystemExit(f"error: no Info.plist in {path}")
        return Target(str(plist), plist.read_bytes(), None, None)
    if path.suffix == ".xcarchive":
        plist = _single(sorted(path.glob("Products/Applications/*.app/Info.plist")), "app Info.plist", path)
        return Target(str(plist), plist.read_bytes(), None, None)
    directory = path.parent if path.suffix == ".xcodeproj" else path
    plist = _single(sorted(directory.glob("*/*-Info.plist")), "exported *-Info.plist", directory)
    return Target(str(plist), plist.read_bytes(), plist, _project_file(directory))


def build_settings(project: Path | None) -> dict[str, list[str]]:
    """Distinct values of the version build settings in an Xcode project."""
    settings: dict[str, list[str]] = {}
    if project is None or not project.is_file():
        return settings
    text = project.read_text(encoding="utf-8", errors="replace")
    for name in BUILD_SETTINGS.values():
        values = re.findall(rf"\b{name}\s*=\s*\"?([^\";]*)\"?;", text)
        settings[name] = sorted(set(value.strip() for value in values))
    return settings


def resolve(value: object, settings: dict[str, list[str]]) -> str:
    text = "" if value is None else str(value)
    name = BUILD_SETTINGS.get(text)
    if name is None:
        return text
    values = settings.get(name, [])
    if not values:
        return f"{text} (not resolved)"
    return " / ".join(values) + f" (from {name})"


def empty_purpose_strings(data: dict) -> list[str]:
    return [key for key, value in data.items()
            if key.endswith("UsageDescription") and isinstance(value, str) and not value.strip()]


def check(target: Target) -> int:
    data = plistlib.loads(target.data)
    settings = build_settings(target.project)
    problems = [f"{key} is empty" for key in empty_purpose_strings(data)]
    for key in REQUIRED_KEYS:
        if key not in data:
            problems.append(f"{key} is missing")
        elif not str(data[key]).strip():
            problems.append(f"{key} is empty")
    print(f"Checked {target.label}")
    version = resolve(data.get("CFBundleShortVersionString"), settings)
    build = resolve(data.get("CFBundleVersion"), settings)
    print(f"CFBundleShortVersionString: {version or '(none)'}")
    print(f"CFBundleVersion: {build or '(none)'}")
    print("Reminder: App Store Connect accepts each CFBundleVersion once per version. "
          "Raise it before every upload.")
    if not problems:
        print("OK: no empty purpose strings and no missing required keys.")
        return 0
    for problem in problems:
        print(f"FAIL: {problem}")
    return 1


def apply(target: Target) -> int:
    if target.file is None:
        raise SystemExit("error: --apply edits an exported project's plist only. "
                         "A built .app, .xcarchive or .ipa must be exported and built again.")
    data = plistlib.loads(target.data)
    empty = [key for key in EMPTY_UNUSED_KEYS if key in data and data[key] == ""]
    if not empty:
        print("No empty unused iOS purpose strings.")
        return 0
    expected = dict(data)
    for key in empty:
        del expected[key]
    updated = plistlib.dumps(expected, fmt=plistlib.FMT_XML, sort_keys=False)
    if plistlib.loads(updated) != expected:
        raise ValueError("Plist round-trip changed unrelated values")
    target.file.write_bytes(updated)
    print("Removed only empty values: " + ", ".join(empty))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path", type=Path, help="Info.plist, export directory, .xcodeproj, .app, .xcarchive or .ipa")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="report problems and change nothing (default)")
    mode.add_argument("--apply", action="store_true", help="remove the empty unused purpose strings")
    args = parser.parse_args(argv)
    target = locate(args.path)
    return apply(target) if args.apply else check(target)


if __name__ == "__main__":
    raise SystemExit(main())
