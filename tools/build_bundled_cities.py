#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
"""Build the included cities as native `.sc2d` saves.

Classic `.sc2` sources in game/assets/cities are imported by the game host
inside an isolated project copy (with its own user data) and saved exactly as a
player's Import Classic City → Save would write them. Already-native saves are
copied byte-for-byte. Only the `.sc2d` files and provenance.json are exported;
the classic sources stay in the repository as conversion inputs and fixtures.

    python3 tools/build_bundled_cities.py --native "Adaven=/path/to/Adaven.sc2d"
    python3 tools/build_bundled_cities.py --city "Oro Canyon"

Classic cities are saved under their catalog name. Without --city every classic
city is rebuilt; existing provenance entries for cities not rebuilt are kept.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_tests  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CITIES = ROOT / "game" / "assets" / "cities"
CLASSIC = ["Aliso Niguel", "Foothills Ranch", "Grant Pass - Soledad", "La Presa",
           "Lawndale", "Oro Canyon", "Salton Shores", "Valle del Mar"]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def engine_version(godot: str) -> str:
    return subprocess.run([godot, "--version"], capture_output=True, text=True).stdout.strip()


def convert(godot: str, names: list[str], output: Path) -> None:
    with run_tests.isolated_test_project(ROOT / "game") as project:
        subprocess.run([godot, "--headless", "--audio-driver", "Dummy", "--path", str(project), "--import"],
                       check=False, capture_output=True)
        proc = subprocess.run([godot, "--headless", "--audio-driver", "Dummy", "--path", str(project),
                               "-s", "res://tools/build_bundled_cities.gd", "--", str(output)] + names,
                              capture_output=True, text=True, timeout=1800)
        print(proc.stdout + proc.stderr)
        ok, reason = run_tests.classify_output(proc.returncode, proc.stdout + proc.stderr)
        if not ok:
            sys.exit(f"conversion failed: {reason}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--native", action="append", default=[], metavar="NAME=PATH",
                        help="include an existing native save, copied byte-for-byte")
    parser.add_argument("--city", action="append", default=[], metavar="NAME",
                        help="rebuild only this classic city (repeatable)")
    args = parser.parse_args(argv)
    classic = args.city or CLASSIC
    unknown = [name for name in classic if name not in CLASSIC]
    if unknown:
        sys.exit(f"not a classic included city: {', '.join(unknown)}")
    native = {}
    for item in args.native:
        name, _, path = item.partition("=")
        source = Path(path).expanduser()
        if not name or not source.is_file() or source.suffix != ".sc2d":
            sys.exit(f"--native needs NAME=existing .sc2d path: {item}")
        native[name] = source

    godot = run_tests.find_godot()
    entries = []
    with tempfile.TemporaryDirectory(prefix="sincity-bundled-") as temporary:
        output = Path(temporary)
        convert(godot, classic, output)
        for name in classic:
            built = output / f"{name}.sc2d"
            if not built.is_file():
                sys.exit(f"missing converted city: {name}")
            shutil.copyfile(built, CITIES / built.name)
            source = CITIES / f"{name}.sc2"
            entries.append({"name": name, "file": built.name, "bytes": built.stat().st_size,
                            "sha256": sha256(CITIES / built.name),
                            "source": {"file": source.name, "bytes": source.stat().st_size, "sha256": sha256(source),
                                       "conversion": "imported with GameHost.import_city, given its catalog city name, "
                                                     "then saved paused with SaveFormat.save"}})
    for name, source in native.items():
        target = CITIES / f"{name}.sc2d"
        shutil.copyfile(source, target)
        if sha256(target) != sha256(source):
            sys.exit(f"copy of {name} differs from its source")
        entries.append({"name": name, "file": target.name, "bytes": target.stat().st_size, "sha256": sha256(target),
                        "source": {"file": source.name, "conversion": "native save copied byte-for-byte"}})
    provenance_path = CITIES / "provenance.json"
    provenance = json.loads(provenance_path.read_text())
    rebuilt = {entry["name"] for entry in entries}
    entries += [entry for entry in provenance.get("cities", [])
                if entry["name"] not in rebuilt and entry.get("file", "").endswith(".sc2d")]
    entries.sort(key=lambda entry: entry["name"].lower())
    provenance["format"] = "sc2d"
    provenance["engine"] = engine_version(godot)
    provenance["inclusion_authorization"] = (
        "Supplied for inclusion by the project owner: the eight classic .sc2 cities on 2026-10-05 and "
        "the owner's own city Adaven on 2026-10-06. Every included city ships as a fully imported "
        "native .sc2d save.")
    provenance["sources_note"] = ("Classic .sc2 sources remain in this directory as conversion inputs and test "
                                  "fixtures; export presets include only the .sc2d files and this provenance.")
    provenance["license"] = "CC-BY-NC-SA-4.0; see LICENSING.md"
    provenance["cities"] = entries
    provenance_path.write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"wrote {len(entries)} included cities")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
