#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Re-encode a public domain film for the drive-in theater screens.

The drive-ins play an Ogg Theora film on their screens at night. This script
takes the film as published by the Internet Archive, decodes it to grayscale
still frames with ffmpeg at the size and frame rate the screens need, then
shows those frames one per tick in a throwaway Godot project recorded by
Godot's own movie writer, then copies the picture alone into the game. No
Theora encoder beyond Godot is required.

The recording window opens briefly on the desktop: the movie writer needs a
real renderer, so it cannot run headless.

Usage:
    python3 tools/build_drive_in_film.py SOURCE.ogv
    python3 tools/build_drive_in_film.py SOURCE.ogv --godot /path/to/Godot

Requires ffmpeg (decoding and stream copy only) and Godot 4.5 or later.

Writes game/assets/drive-in/the-great-train-robbery.ogv and updates
game/assets/drive-in/provenance.json.
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

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "game" / "assets" / "drive-in"
PROVENANCE = OUT_DIR / "provenance.json"

FILM = {
    "file": "the-great-train-robbery.ogv",
    "title": "The Great Train Robbery",
    "year": 1903,
    "credits": "Written, produced, directed and photographed by Edwin S. Porter (1870-1941) for the Edison Manufacturing Company",
    "status": "Public domain worldwide: published in 1903; its maker died in 1941",
    "source": "https://archive.org/details/TheGreatTrainRobbery1903_201307",
    "source_file": "The Great Train Robbery (1903).ogv",
    "source_sha256": "45f21c8920a3083df92c78b53b7ed0fc8aabdb7ed61a653ca044f367c3c0f123",
}
# The source repeats frames to fill 29.92 fps; it has about 18 distinct
# frames a second, close to the film's original hand-cranked rate.
FPS = 18
WIDTH, HEIGHT = 320, 240
VIDEO_QUALITY = 0.4
KEYFRAME_INTERVAL = 72

PROJECT = """config_version=5

[application]
run/main_scene="res://record.tscn"

[display]
window/size/viewport_width={w}
window/size/viewport_height={h}
window/size/resizable=false

[editor]
movie_writer/video_quality={quality}
movie_writer/ogv/keyframe_interval={keyframes}
movie_writer/ogv/audio_quality=0.0
movie_writer/mix_rate=22050
"""

SCENE = """[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://record.gd" id="1"]

[node name="Record" type="TextureRect"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
expand_mode = 1
script = ExtResource("1")
"""

# Playing the source through VideoStreamPlayer under the movie writer stops
# early, or never stops when the source has no audio, so feed frames instead.
SCRIPT = """extends TextureRect

var _frame := 1

func _ready() -> void:
	_show()

func _show() -> bool:
	var path := "res://frames/%06d.png" % _frame
	if not FileAccess.file_exists(path): return false
	texture = ImageTexture.create_from_image(Image.load_from_file(path))
	return true

func _process(_delta: float) -> void:
	_frame += 1
	if not _show(): get_tree().quit()
"""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def find_tool(name: str, explicit: str | None, fallback: str) -> str:
    for candidate in [explicit, shutil.which(name), fallback]:
        if candidate and Path(candidate).exists():
            return candidate
    sys.exit(f"{name} not found")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source", type=Path)
    parser.add_argument("--godot")
    args = parser.parse_args()
    source = args.source.resolve()
    if sha256(source) != FILM["source_sha256"]:
        sys.exit(f"{source} is not the expected archive.org file ({FILM['source_file']})")
    godot = find_tool("godot", args.godot, "/Applications/Godot.app/Contents/MacOS/Godot")
    ffmpeg = find_tool("ffmpeg", None, "/opt/homebrew/bin/ffmpeg")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / FILM["file"]
    with tempfile.TemporaryDirectory(prefix="drive-in-film-") as temp:
        project = Path(temp)
        (project / "project.godot").write_text(PROJECT.format(
            w=WIDTH, h=HEIGHT, quality=VIDEO_QUALITY, keyframes=KEYFRAME_INTERVAL))
        (project / "record.tscn").write_text(SCENE)
        (project / "record.gd").write_text(SCRIPT)
        (project / "frames").mkdir()
        # The film is black and white; gray frames keep the encoder from
        # spending bits on colour noise in the scan.
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(source), "-an",
                        "-vf", f"fps={FPS},scale={WIDTH}:{HEIGHT}:flags=lanczos,format=gray",
                        str(project / "frames" / "%06d.png")], check=True)
        # Keep Godot from importing thousands of frames as textures.
        (project / "frames" / ".gdignore").write_text("")
        recording = project / "recording.ogv"
        subprocess.run([godot, "--path", str(project), "--write-movie", str(recording),
                        "--fixed-fps", str(FPS), "--resolution", f"{WIDTH}x{HEIGHT}",
                        "--disable-vsync"], check=True)
        if not recording.exists() or recording.stat().st_size == 0:
            sys.exit("Godot wrote no recording")
        # The movie writer always records a soundtrack; the film is silent,
        # so drop it (a stream copy, the picture is untouched). A video-only
        # file spares the game a Vorbis decoder and an audio mix every frame.
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(recording),
                        "-map", "0:v", "-c", "copy", str(out)], check=True)
    record = dict(FILM)
    record.update({"width": WIDTH, "height": HEIGHT, "fps": FPS,
                   "encoding": "decoded to grayscale frames by ffmpeg and re-encoded with Godot's movie writer by tools/build_drive_in_film.py; picture unchanged apart from size and frame rate; silent, as released, with no audio track",
                   "bytes": out.stat().st_size, "sha256": sha256(out)})
    # Keep the other records (the baked audience) and replace only the film.
    existing = json.loads(PROVENANCE.read_text()) if PROVENANCE.exists() else {}
    existing["films"] = {FILM["file"]: record}
    PROVENANCE.write_text(json.dumps(existing, indent=2, sort_keys=True) + "\n")
    print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
