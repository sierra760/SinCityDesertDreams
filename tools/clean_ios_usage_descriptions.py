#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Remove Godot's empty, unused iOS purpose strings from an exported plist.

The current app does not use camera, microphone or photo-library access.
Populated descriptions are preserved. Run after every Godot iOS export and
before archiving. --apply changes only the given plist; without it, check only.
"""
from __future__ import annotations
import argparse
import plistlib
from pathlib import Path

EMPTY_UNUSED_KEYS = (
    "NSCameraUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSPhotoLibraryUsageDescription",
)

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plist", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    original = args.plist.read_bytes()
    data = plistlib.loads(original)
    empty = [key for key in EMPTY_UNUSED_KEYS if key in data and data[key] == ""]
    if not empty:
        print("No empty unused iOS purpose strings.")
        return 0
    if not args.apply:
        print("Remove empty unused keys before archive: " + ", ".join(empty))
        return 1
    expected = dict(data)
    for key in empty:
        del expected[key]
    updated = plistlib.dumps(expected, fmt=plistlib.FMT_XML, sort_keys=False)
    if plistlib.loads(updated) != expected:
        raise ValueError("Plist round-trip changed unrelated values")
    args.plist.write_bytes(updated)
    print("Removed only empty values: " + ", ".join(empty))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
