#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Generate sound effects with the ElevenLabs API from tools/audio/sfx_prompts.json.

The downloaded masters are kept in assets/audio/sfx/ and processed into game
files under game/assets/audio/sfx/: one-shots are trimmed and peak-normalized,
loops keep their length and are loudness-normalized, voice lines get a radio
filter, and "steps" clips are sliced into single footsteps that are also laid
out at an even stride as a seamless walking loop. Each result's prompt, settings, date and hashes are recorded in
game/assets/audio/provenance.json.

The API key comes from ELEVENLABS_API_KEY or --key-file and is never written
anywhere. Existing masters are skipped unless --force is given.

Requires numpy, ffmpeg and oggenc.

Usage:
    ELEVENLABS_API_KEY=... python3 tools/generate_sfx.py            # missing sounds
    python3 tools/generate_sfx.py --key-file ~/.elevenlabs bulldoze  # one sound
    python3 tools/generate_sfx.py --process-only                     # rebuild game files
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "audio"))
from instruments import SR, bandpass, highpass, lowpass, spectral_filter  # noqa: E402

PROMPTS = ROOT / "tools" / "audio" / "sfx_prompts.json"
MASTERS = ROOT / "assets" / "audio" / "sfx"
OUT_DIR = ROOT / "game" / "assets" / "audio" / "sfx"
PROVENANCE = ROOT / "game" / "assets" / "audio" / "provenance.json"
API = "https://api.elevenlabs.io/v1"
SFX_MODEL = "eleven_text_to_sound_v2"
VOICE_MODEL = "eleven_v3"
FORMAT = "mp3_44100_192"


def _post(url: str, key: str, body: dict) -> tuple[bytes, dict]:
    request = urllib.request.Request(
        url, data=json.dumps(body).encode(), method="POST",
        headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                return response.read(), dict(response.headers)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace")[:400]
            if error.code in (429, 500, 502, 503) and attempt < 3:
                time.sleep(5 * (attempt + 1))
                continue
            raise RuntimeError(f"HTTP {error.code}: {detail}") from None
    raise RuntimeError("request failed")


def generate(entry: dict, key: str) -> dict:
    if entry["kind"] == "voice":
        body = {"text": entry["text"], "model_id": VOICE_MODEL,
                "voice_settings": {"stability": 0.3, "similarity_boost": 0.75}}
        url = f"{API}/text-to-speech/{entry['voice']}?output_format={FORMAT}"
        model = VOICE_MODEL
    else:
        body = {"text": entry["prompt"], "model_id": SFX_MODEL,
                "duration_seconds": entry.get("seconds"),
                "prompt_influence": entry.get("influence", 0.3),
                "loop": entry["kind"] == "loop"}
        url = f"{API}/sound-generation?output_format={FORMAT}"
        model = SFX_MODEL
    audio, headers = _post(url, key, body)
    master = MASTERS / f"{entry['name']}.mp3"
    master.write_bytes(audio)
    lowered = {k.lower(): v for k, v in headers.items()}
    return {"model": model, "request": {k: v for k, v in body.items() if k != "model_id"},
            "generated": dt.date.today().isoformat(),
            "cost": lowered.get("character-cost") or lowered.get("x-character-count"),
            "request_id": lowered.get("request-id")}


def _decode(path: Path, stereo: bool) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac",
                          "2" if stereo else "1", "-ar", str(SR), "-"],
                         check=True, capture_output=True).stdout
    data = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    return data.reshape(-1, 2).T if stereo else data[None, :]


def _radio(mono: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    voice = spectral_filter(mono, lambda f: highpass(450, 2)(f) * lowpass(2800, 2)(f)
                            * (1 + 0.8 * bandpass(1500, 1.5)(f)))
    voice = np.tanh(3.0 * voice / max(np.abs(voice).max(), 1e-9)) * 0.8
    hiss = spectral_filter(rng.standard_normal(len(voice)), bandpass(2500, 0.6))
    voice += 0.03 * hiss / np.abs(hiss).max()
    squelch = int(0.08 * SR)
    burst = spectral_filter(rng.standard_normal(squelch), highpass(1500, 1)) * np.linspace(1, 0, squelch)
    return np.concatenate([0.25 * burst / np.abs(burst).max(), voice, 0.25 * burst[::-1] / np.abs(burst).max()])


def _write_ogg(out: Path, audio: np.ndarray) -> None:
    pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2").T.copy()
    with tempfile.TemporaryDirectory() as scratch:
        wav = Path(scratch) / "sfx.wav"
        with wave.open(str(wav), "wb") as handle:
            handle.setnchannels(audio.shape[0])
            handle.setsampwidth(2)
            handle.setframerate(SR)
            handle.writeframes(pcm.tobytes())
        subprocess.run(["oggenc", "-Q", "-q", "5", "-o", str(out), str(wav)], check=True)


def process_steps(entry: dict) -> list[tuple[Path, float]]:
    """Slice single footsteps out of the master and build an even walking loop."""
    mono = _decode(MASTERS / f"{entry['name']}.mp3", False)[0]
    window = int(0.01 * SR)
    env = np.array([np.abs(mono[i:i + window]).max() for i in range(0, len(mono) - window, window)])
    threshold = env.max() * 0.3
    onsets = [i for i in range(1, len(env)) if env[i] > threshold and env[i - 1] <= threshold]
    starts = []
    for onset in onsets:  # one onset per step: ignore heel-toe pairs closer than 0.2 s
        if not starts or onset - starts[-1] > 20:
            starts.append(onset)
    slices = []
    for index, start in enumerate(starts):
        first = max(0, start * window - int(0.005 * SR))
        end = starts[index + 1] * window - int(0.02 * SR) if index + 1 < len(starts) else len(mono)
        piece = mono[first:min(end, first + int(0.45 * SR))].copy()
        fade = min(len(piece), int(0.03 * SR))
        piece[-fade:] *= np.linspace(1, 0, fade)
        slices.append(piece)
    slices.sort(key=lambda piece: -np.abs(piece).max())
    keep = [piece / np.abs(piece).max() * 0.89 for piece in slices[:entry.get("variants", 4)]]
    if len(keep) < 2:
        raise RuntimeError(f"{entry['name']}: found only {len(keep)} footsteps")
    results = []
    for number, piece in enumerate(keep, start=1):
        out = OUT_DIR / f"{entry['name']}_step_{number}.ogg"
        _write_ogg(out, piece[None, :])
        results.append((out, len(piece) / SR))
    stride = int(entry.get("stride", 0.53) * SR)
    count = 8
    loop = np.zeros(stride * count)
    for i in range(count):
        piece = keep[i % len(keep)] * (0.85 if i % 2 else 1.0)
        for offset, sample in ((i * stride, 0),):
            span = np.arange(len(piece)) + offset
            np.add.at(loop, span % len(loop), piece)  # wrap tails so the loop is seamless
    loop *= 0.89 / np.abs(loop).max()
    out = OUT_DIR / f"{entry['name']}_loop.ogg"
    _write_ogg(out, loop[None, :])
    results.append((out, len(loop) / SR))
    return results


def process(entry: dict) -> tuple[Path, float]:
    stereo = bool(entry.get("stereo")) and entry["kind"] != "voice"
    audio = _decode(MASTERS / f"{entry['name']}.mp3", stereo)
    kind = entry["kind"]
    if kind == "voice":
        audio = _radio(audio[0], np.random.default_rng(5))[None, :]
    if kind in ("oneshot", "voice"):
        level = np.abs(audio).max(axis=0)
        loud = np.nonzero(level > level.max() * 10 ** (-50 / 20))[0]
        if len(loud):
            first = max(0, loud[0] - int(0.005 * SR))
            audio = audio[:, first:loud[-1] + 1]
        fade = min(audio.shape[1], int(0.03 * SR))
        audio[:, -fade:] *= np.linspace(1, 0, fade)
        audio *= 0.89 / max(np.abs(audio).max(), 1e-9)
    else:  # loops keep every sample so the seam stays seamless
        rms = np.sqrt(np.mean(audio ** 2)) + 1e-12
        audio *= 10 ** (-18 / 20) / rms
        peak = np.abs(audio).max()
        if peak > 0.89:
            audio *= 0.89 / peak
    out = OUT_DIR / f"{entry['name']}.ogg"
    _write_ogg(out, audio)
    return out, audio.shape[1] / SR


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("names", nargs="*", help="sound names (default: all)")
    parser.add_argument("--key-file", type=Path, help="file holding the API key")
    parser.add_argument("--force", action="store_true", help="regenerate existing masters")
    parser.add_argument("--process-only", action="store_true", help="only rebuild game files")
    args = parser.parse_args(argv)

    entries = json.loads(PROMPTS.read_text())["sounds"]
    if args.names:
        unknown = set(args.names) - {e["name"] for e in entries}
        if unknown:
            parser.error(f"unknown sounds: {', '.join(sorted(unknown))}")
        entries = [e for e in entries if e["name"] in args.names]
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if args.key_file:
        key = args.key_file.expanduser().read_text().strip()
    MASTERS.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    provenance = json.loads(PROVENANCE.read_text()) if PROVENANCE.exists() else {}
    records = provenance.setdefault("sfx", {})

    for entry in entries:
        name = entry["name"]
        master = MASTERS / f"{name}.mp3"
        record = records.get(f"{name}.ogg") or records.get(f"{name}_loop.ogg") or {}
        if not args.process_only and (args.force or not master.exists()):
            if not key:
                parser.error("set ELEVENLABS_API_KEY or pass --key-file to generate")
            print(f"generating {name} ...", flush=True)
            record = generate(entry, key)
        elif not master.exists():
            print(f"skip {name}: no master")
            continue
        outputs = process_steps(entry) if entry["kind"] == "steps" else [process(entry)]
        for out, seconds in outputs:
            entry_record = dict(record)
            entry_record.update({
                "method": "generated with ElevenLabs, processed by tools/generate_sfx.py",
                "kind": "loop" if out.stem.endswith("_loop") else (
                    "oneshot" if entry["kind"] == "steps" else entry["kind"]),
                "prompt": entry.get("prompt") or entry.get("text"),
                "master": f"assets/audio/sfx/{name}.mp3", "master_sha256": _sha256(master),
                "sha256": _sha256(out), "seconds": round(seconds, 3), "license": "CC-BY-NC-SA-4.0",
            })
            records[out.name] = entry_record
            print(f"  {out.name} {seconds:.2f}s cost={record.get('cost')}")
        PROVENANCE.write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
