#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Install the official Godot editor and selected export templates for CI.

Usage: python3 tools/ci/setup_godot.py --dir DIR [--version 4.8-beta3] [--template NAME ...]

VERSION is a godot-builds release name without "-stable" for stable releases
(4.7.2) or with its status for previews (4.8-beta3). Downloads the standard
(non-.NET) editor for this host from the official godot-builds release, checks it against the release's SHA-512 checksum list and
unpacks it into DIR. Each --template (a file name inside the .tpz, such as
macos.zip or windows_release_x86_64.exe) is unpacked into DIR/templates and
copied into the editor's export template directory; the 1.2 GB .tpz is deleted
afterwards. Files already in DIR are reused, so DIR can be cached between runs.
Prints the editor path and, under GitHub Actions, exports it as GODOT.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import platform
import shutil
import subprocess
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

RELEASES = "https://github.com/godotengine/godot-builds/releases/download"
CHECKSUMS = "SHA512-SUMS.txt"


def release_tag(version: str) -> str:
    """godot-builds tag: 4.7.2 -> 4.7.2-stable, 4.8-beta3 unchanged."""
    return version if "-" in version else f"{version}-stable"


def engine_name(version: str) -> str:
    """How the engine names itself: 4.7.2.stable, 4.8.beta3."""
    return release_tag(version).replace("-", ".")


def host_editor(version: str, available: set[str] | None = None) -> tuple[str, str]:
    """Return the editor archive name and the binary path inside it."""
    stem = f"Godot_v{release_tag(version)}"
    if sys.platform == "win32":
        # The console wrapper keeps stdout and stderr attached to the runner.
        return f"{stem}_win64.exe.zip", f"{stem}_win64_console.exe"
    if sys.platform == "darwin":
        # 4.7 published one universal app; 4.8 publishes one per architecture.
        universal = f"{stem}_macos.universal.zip"
        if available is None or universal in available:
            return universal, "Godot.app/Contents/MacOS/Godot"
        arch = "arm64" if platform.machine() in ("arm64", "aarch64") else "x86_64"
        return f"{stem}_macos.{arch}.zip", "Godot.app/Contents/MacOS/Godot"
    return f"{stem}_linux.x86_64.zip", f"{stem}_linux.x86_64"


def template_directory(version: str) -> Path:
    if sys.platform == "win32":
        base = Path(os.environ["APPDATA"]) / "Godot"
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support" / "Godot"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))) / "godot"
    return base / "export_templates" / engine_name(version)


def download(url: str, destination: Path) -> None:
    partial = destination.with_name(destination.name + ".part")
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=60) as response, open(partial, "wb") as out:
                shutil.copyfileobj(response, out, 1 << 20)
            partial.replace(destination)
            return
        except OSError as exc:
            if attempt == 3:
                raise
            print(f"download failed ({exc}); retrying", flush=True)
            time.sleep(2 ** (attempt + 1))


def verify(path: Path, sums: dict[str, str]) -> None:
    digest = hashlib.sha512()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    expected = sums.get(path.name)
    if expected is None:
        raise SystemExit(f"{path.name} is not listed in {CHECKSUMS}")
    if digest.hexdigest() != expected:
        path.unlink()
        raise SystemExit(f"{path.name} does not match its published SHA-512")


def release_sums(base: str, directory: Path) -> dict[str, str]:
    path = directory / CHECKSUMS
    if not path.exists():
        download(base + "/" + CHECKSUMS, path)
    sums = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) == 2:
            sums[parts[1].lstrip("*")] = parts[0].lower()
    return sums


def install_editor(base: str, directory: Path, version: str) -> Path:
    sums = release_sums(base, directory)
    archive_name, binary = host_editor(version, set(sums))
    editor = directory / binary
    if editor.exists():
        return editor
    archive = directory / archive_name
    download(base + "/" + archive_name, archive)
    verify(archive, sums)
    if sys.platform == "darwin":
        # ditto keeps the app bundle's permissions and signature intact.
        subprocess.run(["ditto", "-x", "-k", str(archive), str(directory)], check=True)
    else:
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(directory)
        editor.chmod(0o755)
    archive.unlink()
    if not editor.exists():
        raise SystemExit(f"{archive_name} did not contain {binary}")
    return editor


def install_templates(base: str, directory: Path, version: str, names: list[str]) -> None:
    cached = directory / "templates"
    wanted = ["version.txt"] + names
    missing = [name for name in wanted if not (cached / name).exists()]
    if missing:
        archive_name = f"Godot_v{release_tag(version)}_export_templates.tpz"
        archive = directory / archive_name
        download(base + "/" + archive_name, archive)
        verify(archive, release_sums(base, directory))
        cached.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as bundle:
            available = set(bundle.namelist())
            for name in missing:
                member = "templates/" + name
                if member not in available:
                    raise SystemExit(f"{archive_name} has no {member}")
                with bundle.open(member) as source, open(cached / name, "wb") as out:
                    shutil.copyfileobj(source, out, 1 << 20)
        archive.unlink()
    installed = template_directory(version)
    installed.mkdir(parents=True, exist_ok=True)
    for name in wanted:
        shutil.copy2(cached / name, installed / name)
    print(f"export templates: {', '.join(names)} -> {installed}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dir", type=Path, required=True)
    parser.add_argument("--version", default="4.8-beta3")
    parser.add_argument("--template", action="append", default=[])
    args = parser.parse_args(argv)
    directory = args.dir.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    base = f"{RELEASES}/{release_tag(args.version)}"
    editor = install_editor(base, directory, args.version)
    if args.template:
        install_templates(base, directory, args.version, args.template)
    version = subprocess.run([str(editor), "--version"], capture_output=True, text=True, timeout=120)
    print(f"Godot {version.stdout.strip()} at {editor}")
    if version.returncode != 0 or not version.stdout.startswith(engine_name(args.version) + "."):
        raise SystemExit(f"{editor} did not report Godot {engine_name(args.version)}")
    environment = os.environ.get("GITHUB_ENV")
    if environment:
        with open(environment, "a", encoding="utf-8") as out:
            out.write(f"GODOT={editor}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
