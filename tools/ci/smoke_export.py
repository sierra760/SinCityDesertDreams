#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Launch an exported game headless for a few hundred frames and check its log.

Usage: python3 tools/ci/smoke_export.py EXECUTABLE_OR_APP [--frames N] [--log PATH]

Accepts a Windows .exe, a macOS .app bundle or any exported executable. The run
fails when the game exits non-zero, times out, or prints the same engine,
script or resource diagnostics that fail tools/run_tests.py. The exported game
uses its own user-data directory, so run it only on a disposable CI machine.
"""

from __future__ import annotations

import argparse
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_tests import ENGINE_ERROR  # noqa: E402


def executable(target: Path) -> Path:
    if target.suffix == ".app":
        with open(target / "Contents" / "Info.plist", "rb") as handle:
            return target / "Contents" / "MacOS" / plistlib.load(handle)["CFBundleExecutable"]
    return target


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("target", type=Path)
    parser.add_argument("--frames", type=int, default=300)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args(argv)
    binary = executable(args.target.resolve())
    log = (args.log or Path(tempfile.mkdtemp(prefix="sincity-smoke-")) / "smoke.log").resolve()
    log.parent.mkdir(parents=True, exist_ok=True)
    cmd = [str(binary), "--headless", "--audio-driver", "Dummy", "--quit-after", str(args.frames), "--log-file", str(log)]
    print(" ".join(cmd), flush=True)
    try:
        proc = subprocess.run(cmd, capture_output=True, encoding="utf-8", errors="replace", timeout=args.timeout)
        status = f"exit {proc.returncode}" if proc.returncode else ""
        output = (proc.stdout or "") + (proc.stderr or "")
    except subprocess.TimeoutExpired:
        status, output = f"no exit within {args.timeout} s", ""
    # A Windows GUI build has no console, so its messages reach only the log.
    if log.exists():
        output += log.read_text(encoding="utf-8", errors="replace")
    print(output.strip()[-8000:])
    diagnostic = ENGINE_ERROR.search(output)
    if status or diagnostic:
        print(f"\nsmoke run failed: {status or 'diagnostic ' + repr(diagnostic.group(0).strip())}", file=sys.stderr)
        return 1
    print(f"\nsmoke run clean: {args.frames} frames")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
