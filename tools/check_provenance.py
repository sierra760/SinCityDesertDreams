#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Refuse content that should not be in a published repository.

Scans game/ and docs/ for tokens that point at a commercial game's binary or
resources, for suspiciously large numeric tables, and for file names we never
want to see again. Exit status is non-zero when anything is found.

Usage: python3 tools/check_provenance.py [paths...]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PATHS = ["game", "docs", "tools", "README.md", "CONTRIBUTING.md"]
ALLOW_FILE = ROOT / "tools" / "provenance_allow.txt"
# Local, gitignored build output: export staging copies, archives and caches.
# It is never published, so copies of allowlisted files there are not findings.
SKIP_PREFIXES = ("game/export/", "game/.godot/")

TEXT_SUFFIXES = {".gd", ".md", ".py", ".json", ".txt", ".cfg", ".tscn", ".tres",
                 ".gdshader", ".gdshaderinc", ".godot", ".yml", ".yaml", ".toml"}

# Words that only show up when someone is describing another program's insides.
BANNED_WORDS = [
    r"\bdisassembl\w*",
    r"\bdecompil\w*",
    r"\bMacintosh\b",
    r"\bMac ?1\.2\b",
    r"\bPowerPC\b",
    r"\bPPC\b",
    r"\b68k\b",
    r"\bPEF\b",
    r"\bTOC\s*0x",
    r"\bDATA\s*0x",
    r"\bCODE\s*0x",
    r"\bresource fork\b",
    r"\bSPRT\b",
    r"\bTSET\b",
    r"\bPICT\b",
    r"\bSCURK\b",
    r"\bMaxis\b",
    r"\bElectronic Arts\b",
    r"\bSimCity\b",
    r"\bSC2K\b",
    r"\bextract-[a-z-]+\.py",
    r"\bppc_oracle\b",
    r"\bpef_analyzer\b",
    r"\boriginal (memory|worker|binary|executable|game|source)\b",
    r"\bXBLD\b|\bXZON\b|\bXBIT\b|\bXTER\b|\bXUND\b|\bXMIC\b|\bXTRF\b|\bXPLT\b|\bXVAL\b|\bXCRM\b|\bXPLC\b|\bXFIR\b|\bXPOP\b|\bXROG\b|\bALTM\b|\bMISC\b",
]

# Hex offsets used as identifiers: 0x2D604, DATA9ED8, count_4CB6, 41490.
# Short masks such as 0xFF or 0x1F are ordinary code and are not flagged.
HEX_ID = re.compile(r"(?<![A-Za-z0-9_])(?:0x[0-9A-F]{5,6}|[0-9][0-9A-F]{3,5})(?![A-Za-z0-9_])")
HEX_ID_WORDY = re.compile(r"\b[A-Za-z_]+(?=[0-9A-F]{4,6}\b)[0-9A-F]*[0-9][0-9A-F]*\b")
# Godot's qualified public hashing enum is an algorithm, not an address.
PUBLIC_ENUMS = {"HashingContext.HASH_SHA256"}
# Long runs of integers on one line are almost always a dumped table.
NUMBER_RUN = re.compile(r"(?:-?\d+\s*,\s*){24,}")

BANNED_FILENAMES = re.compile(
    r"^(newspaper_text_data|original_.*|.*_reference|reference_.*|sc2k_.*)\.gd$"
)

banned_re = [re.compile(p, re.IGNORECASE) for p in BANNED_WORDS]


def load_allow() -> set[str]:
    if not ALLOW_FILE.exists():
        return set()
    lines = []
    for raw in ALLOW_FILE.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            lines.append(line)
    return set(lines)


def is_hex_identifier(token: str, line: str) -> bool:
    """A four-to-six digit hex-looking token that is not an ordinary number."""
    if token.lower().startswith("0x"):
        return True
    # Plain decimal numbers are fine; only flag when letters A-F are present.
    return any(c in "ABCDEF" for c in token)


def scan_file(path: Path, allow: set[str]) -> list[str]:
    findings: list[str] = []
    rel = path.relative_to(ROOT).as_posix()
    if rel in allow:
        return findings
    if BANNED_FILENAMES.match(path.name) and rel not in allow:
        findings.append(f"{rel}: file name is on the banned list")
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return findings
    for number, line in enumerate(text.splitlines(), 1):
        key = f"{rel}:{number}"
        if key in allow:
            continue
        for pattern in banned_re:
            m = pattern.search(line)
            if m:
                findings.append(f"{key}: banned token '{m.group(0)}'")
                break
        else:
            for m in HEX_ID.finditer(line):
                if is_hex_identifier(m.group(0), line):
                    findings.append(f"{key}: hex identifier '{m.group(0)}'")
                    break
            else:
                m = next((candidate for candidate in HEX_ID_WORDY.finditer(line)
                          if not any(line[:candidate.end()].endswith(enum)
                                     for enum in PUBLIC_ENUMS)), None)
                if m and not path.suffix == ".json":
                    findings.append(f"{key}: address-style identifier '{m.group(0)}'")
                elif NUMBER_RUN.search(line) and path.suffix != ".json":
                    findings.append(f"{key}: long numeric run (dumped table?)")
    return findings


def main(argv: list[str]) -> int:
    allow = load_allow()
    targets = [ROOT / p for p in (argv or DEFAULT_PATHS)]
    findings: list[str] = []
    for target in targets:
        if target.is_file():
            files = [target]
        elif target.is_dir():
            files = [p for p in target.rglob("*") if p.is_file()]
        else:
            continue
        for path in files:
            if path.suffix.lower() not in TEXT_SUFFIXES:
                continue
            if path.relative_to(ROOT).as_posix().startswith(SKIP_PREFIXES):
                continue
            if "/assets/" in path.as_posix() and path.suffix == ".json":
                continue  # asset manifests and provenance records carry hashes, not identifiers
            findings.extend(scan_file(path, allow))
    for line in findings:
        print(line)
    if findings:
        print(f"\n{len(findings)} finding(s).", file=sys.stderr)
        return 1
    print("provenance check clean")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
