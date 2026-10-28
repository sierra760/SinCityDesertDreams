#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Make game/export_presets.cfg export unsigned builds on CI runners.

Usage: python3 tools/ci/prepare_export_presets.py [path/to/export_presets.cfg]

CI has no signing identities, so the macOS preset is switched to the built-in
ad-hoc signer with notarization off. The Windows preset must already be
unsigned and the iOS preset must export only the Xcode project; xcodebuild then
builds it with signing disabled. Every other setting is left as committed.
Run it only on a disposable checkout: the file is rewritten in place.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT = ROOT / "game" / "export_presets.cfg"

# Options written for CI, by preset name.
SET: dict[str, dict[str, str]] = {
    "macOS": {
        "export/distribution_type": "0",  # Testing
        "codesign/codesign": "1",  # Built-in ad-hoc
        "notarization/notarization": "0",
    },
}
# Options CI relies on that must already be committed this way.
REQUIRE: dict[str, dict[str, str]] = {
    "Windows x64": {"codesign/enable": "false"},
    "iOS": {"application/export_project_only": "true"},
}


def options_section(text: str, preset: str) -> tuple[int, int]:
    """Return the start and end offsets of a preset's [preset.N.options] body."""
    for header in re.finditer(r"(?m)^\[preset\.(\d+)\]\s*$", text):
        body_end = text.find("\n[", header.end())
        body = text[header.end():body_end if body_end >= 0 else len(text)]
        if re.search(r'(?m)^name="' + re.escape(preset) + r'"\s*$', body):
            options = re.search(r"(?m)^\[preset\." + header.group(1) + r"\.options\]\s*$", text)
            if not options:
                raise ValueError(f"preset {preset!r} has no options section")
            end = text.find("\n[", options.end())
            return options.end(), end if end >= 0 else len(text)
    raise ValueError(f"no export preset named {preset!r}")


def option(text: str, preset: str, key: str) -> re.Match[str]:
    start, end = options_section(text, preset)
    found = list(re.compile(r"(?m)^" + re.escape(key) + r"=(.*)$").finditer(text, start, end))
    if len(found) != 1:
        raise ValueError(f"{preset}: expected one {key} option, found {len(found)}")
    return found[0]


def prepare(text: str) -> str:
    for preset, options in REQUIRE.items():
        for key, value in options.items():
            current = option(text, preset, key).group(1).strip()
            if current != value:
                raise ValueError(f"{preset}: {key} must be {value} for CI, not {current}")
    for preset, options in SET.items():
        for key, value in options.items():
            match = option(text, preset, key)
            text = text[:match.start(1)] + value + text[match.end(1):]
    return text


def main(argv: list[str]) -> int:
    path = Path(argv[0]) if argv else DEFAULT
    try:
        updated = prepare(path.read_text(encoding="utf-8"))
    except ValueError as exc:
        print(f"{path}: {exc}", file=sys.stderr)
        return 1
    path.write_text(updated, encoding="utf-8", newline="")
    print(f"{path}: macOS uses ad-hoc signing without notarization; Windows and iOS are unsigned")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
