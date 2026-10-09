#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Synthesize the interface sounds, casino stingers and a few in-world chimes.

Everything is generated from oscillators and shaped noise; chimes and stingers
reuse the music's instrument voices so the interface and the score share one
palette. Interface sounds go to game/assets/audio/ui/, in-world chimes (the
elevator and station announcements) to game/assets/audio/sfx/.

Usage: python3 tools/build_ui_sounds.py
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "audio"))
from instruments import (SR, bandpass, brass_section, decay, glockenspiel,  # noqa: E402
                         highpass, lowpass, marimba, muted_trumpet, spectral_filter, vibraphone)

OUT_DIR = ROOT / "game" / "assets" / "audio" / "ui"
PROVENANCE = ROOT / "game" / "assets" / "audio" / "provenance.json"
RNG = np.random.default_rng(2026)


def t_of(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * SR)) / SR


def note(p: int) -> float:
    return 440.0 * 2 ** ((p - 69) / 12)


def place(out: np.ndarray, sound: np.ndarray, at: float, gain: float = 1.0) -> None:
    start = int(at * SR)
    end = min(len(out), start + len(sound))
    out[start:end] += gain * sound[:end - start]


def click() -> np.ndarray:
    """Soft bakelite tick for buttons."""
    t = t_of(0.05)
    body = np.sin(2 * np.pi * 1850 * t) * decay(t, 0.018) + 0.5 * np.sin(2 * np.pi * 3400 * t) * decay(t, 0.008)
    grit = spectral_filter(RNG.standard_normal(len(t)), bandpass(5000, 1.5)) * decay(t, 0.006)
    return body + 0.4 * grit / np.abs(grit).max()


def toggle() -> np.ndarray:
    """Two quick ticks, like a rocker switch."""
    out = np.zeros(int(0.09 * SR))
    place(out, click(), 0.0, 0.8)
    place(out, click(), 0.035, 0.55)
    return out


def tool_select() -> np.ndarray:
    """Short rising two-note blip."""
    out = np.zeros(int(0.32 * SR))
    for at, p in ((0.0, 84), (0.06, 91)):
        t = t_of(0.24)
        tone = np.sin(2 * np.pi * note(p) * t) * decay(t, 0.16) * np.minimum(1, t / 0.003)
        place(out, tone, at, 0.6)
    return out


def place_zone() -> np.ndarray:
    """A round 'plop' as a zone or building lands."""
    t = t_of(0.22)
    sweep = 520 * np.exp(-t / 0.035) + 150
    body = np.sin(2 * np.pi * np.cumsum(sweep) / SR) * decay(t, 0.16) * np.minimum(1, t / 0.002)
    thump = spectral_filter(RNG.standard_normal(len(t)), lowpass(400, 2)) * decay(t, 0.05)
    return body + 0.25 * thump / np.abs(thump).max()


def build_network() -> np.ndarray:
    """Gravel crunch and tamp for laying roads, rails, pipes and lines."""
    t = t_of(0.28)
    crunch = spectral_filter(RNG.standard_normal(len(t)), bandpass(1400, 0.8))
    crunch = crunch / np.abs(crunch).max() * decay(t, 0.09) * np.minimum(1, t / 0.004)
    tamp = np.sin(2 * np.pi * (90 + 60 * np.exp(-t / 0.02)) * t) * decay(t, 0.12)
    return 0.6 * crunch + 0.8 * tamp


def error() -> np.ndarray:
    """Low, polite double buzz: the action did not happen."""
    out = np.zeros(int(0.42 * SR))
    for at, f in ((0.0, 196.0), (0.16, 155.6)):
        t = t_of(0.2)
        wave_ = np.zeros_like(t)
        for k in range(1, 16, 2):
            wave_ += np.sin(2 * np.pi * f * k * t) / k
        wave_ = spectral_filter(wave_, lowpass(1600, 2))
        place(out, wave_ * np.minimum(1, t / 0.01) * decay(t, 0.3) * np.clip((0.2 - t) / 0.03, 0, 1), at, 0.5)
    return out


def cash() -> np.ndarray:
    """Two bright bell strikes and a coin rattle for money coming in."""
    out = np.zeros(int(0.9 * SR))
    for at, p in ((0.0, 91), (0.09, 96)):
        t = t_of(0.8)
        bell = np.sin(2 * np.pi * note(p) * t + 1.8 * decay(t, 0.15) * np.sin(2 * np.pi * note(p) * 3.5 * t))
        place(out, bell * decay(t, 0.6), at, 0.45)
    t = t_of(0.25)
    rattle = spectral_filter(RNG.standard_normal(len(t)), highpass(6000, 2))
    rattle *= (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 38 * t))) * decay(t, 0.2)
    place(out, rattle / np.abs(rattle).max(), 0.12, 0.25)
    return out


def notice() -> np.ndarray:
    """Vibraphone arpeggio: something new in the newspaper or an advisor note."""
    out = np.zeros(int(1.9 * SR))
    for i, p in enumerate((72, 76, 79, 84)):
        place(out, vibraphone(note(p), 0.4, 0.7, RNG), i * 0.085, 0.5)
    return out


def alert() -> np.ndarray:
    """Insistent marimba figure for disasters and emergencies."""
    out = np.zeros(int(1.3 * SR))
    for i, p in enumerate((76, 82, 76, 82, 76)):
        place(out, marimba(note(p), 0.15, 0.9, RNG), i * 0.11, 0.55)
    return out


def reward() -> np.ndarray:
    """Major-seventh bloom for milestones and gifts."""
    out = np.zeros(int(2.6 * SR))
    for i, p in enumerate((65, 69, 72, 76, 81)):
        place(out, vibraphone(note(p), 1.2, 0.75, RNG), i * 0.06, 0.4)
    return out


def swoosh(rising: bool) -> np.ndarray:
    """Filtered-air swish for opening and closing windows."""
    t = t_of(0.16)
    centre = np.linspace(900, 3200, len(t)) if rising else np.linspace(3200, 900, len(t))
    out = np.zeros_like(t)
    chunk = 256
    noise = RNG.standard_normal(len(t) + chunk)
    for start in range(0, len(t), chunk):
        piece = spectral_filter(noise[start:start + chunk * 2], bandpass(centre[start], 1.4))[:chunk]
        out[start:start + chunk] = piece[:len(out[start:start + chunk])]
    env = np.sin(np.pi * np.clip(t / 0.16, 0, 1)) ** 2
    return out / np.abs(out).max() * env * 0.35


def casino_win() -> np.ndarray:
    """Quick bright arpeggio for an ordinary win."""
    out = np.zeros(int(1.4 * SR))
    for i, p in enumerate((79, 84, 88, 91)):
        place(out, vibraphone(note(p), 0.3, 0.8, RNG), i * 0.07, 0.5)
    place(out, glockenspiel(note(103), 0.2, 0.6, RNG), 0.21, 0.25)
    return out


def casino_lose() -> np.ndarray:
    """Two muted-trumpet notes sagging down: a polite 'aw'."""
    out = np.zeros(int(1.1 * SR))
    place(out, muted_trumpet(note(67), 0.22, 0.6, RNG), 0.0, 0.5)
    place(out, muted_trumpet(note(66), 0.5, 0.5, RNG), 0.28, 0.5)
    return out


def casino_big_win() -> np.ndarray:
    """Brass fanfare with glockenspiel for a large payout."""
    out = np.zeros(int(2.6 * SR))
    for at, p, held in ((0.0, 70, 0.1), (0.12, 74, 0.1), (0.24, 77, 0.1), (0.36, 82, 1.1)):
        for interval in (0, -4, -9):
            place(out, brass_section(note(p + interval), held, 0.9, RNG), at, 0.3)
    for i, p in enumerate((94, 98, 101, 106)):
        place(out, glockenspiel(note(p), 0.2, 0.7, RNG), 0.36 + i * 0.09, 0.25)
    return out


def machine_blip(freq: float, length: float = 0.06) -> np.ndarray:
    t = t_of(length)
    square = np.sign(np.sin(2 * np.pi * freq * t))
    return spectral_filter(square, lowpass(3000, 2)) * np.minimum(1, t / 0.003) * decay(t, length * 0.8)


def poker_hold() -> np.ndarray:
    """Video poker hold button."""
    return machine_blip(1320.0)


def poker_deal() -> np.ndarray:
    """Video poker deal: five quick rising blips, one per card."""
    out = np.zeros(int(0.5 * SR))
    for i, p in enumerate((72, 74, 76, 79, 84)):
        place(out, machine_blip(note(p), 0.05), i * 0.075, 0.6)
    return out


def trajectory_tick() -> np.ndarray:
    """A short tick the game can raise in pitch as the multiplier climbs."""
    t = t_of(0.05)
    return np.sin(2 * np.pi * 880 * t) * decay(t, 0.04) * np.minimum(1, t / 0.002)


def bell(p: int, length: float = 1.6) -> np.ndarray:
    t = t_of(length)
    f = note(p)
    tone = np.sin(2 * np.pi * f * t + 1.2 * decay(t, 0.3) * np.sin(2 * np.pi * f * 2.0 * t))
    return tone * decay(t, length * 0.8) * np.minimum(1, t / 0.002)


def elevator_ding() -> np.ndarray:
    """Two-tone arrival chime."""
    out = np.zeros(int(2.2 * SR))
    place(out, bell(88), 0.0, 0.5)
    place(out, bell(84), 0.35, 0.5)
    return out


def station_chime() -> np.ndarray:
    """Three descending notes before a station announcement or departure."""
    out = np.zeros(int(2.4 * SR))
    for i, p in enumerate((79, 76, 72)):
        place(out, vibraphone(note(p), 0.5, 0.75, RNG), i * 0.32, 0.5)
    return out


SOUNDS = {
    "click": click, "toggle": toggle, "tool_select": tool_select, "place_zone": place_zone,
    "build_network": build_network, "error": error, "cash": cash, "notice": notice,
    "alert": alert, "reward": reward, "window_open": lambda: swoosh(True),
    "window_close": lambda: swoosh(False),
    "casino_win": casino_win, "casino_lose": casino_lose, "casino_big_win": casino_big_win,
    "poker_hold": poker_hold, "poker_deal": poker_deal, "trajectory_tick": trajectory_tick,
}

WORLD_SOUNDS = {"elevator_ding": elevator_ding, "station_chime": station_chime}


def write_ogg(path: Path, mono: np.ndarray) -> None:
    mono = mono / max(np.abs(mono).max(), 1e-9) * 0.89
    fade = min(len(mono), int(0.004 * SR))
    mono[-fade:] *= np.linspace(1, 0, fade)
    pcm = (mono * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as scratch:
        wav = Path(scratch) / "ui.wav"
        with wave.open(str(wav), "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(SR)
            out.writeframes(pcm.tobytes())
        subprocess.run(["oggenc", "-Q", "-q", "5", "-o", str(path), str(wav)], check=True)


def main() -> int:
    data = json.loads(PROVENANCE.read_text()) if PROVENANCE.exists() else {}
    data["ui"] = {}
    for folder, sounds in (("ui", SOUNDS), ("sfx", WORLD_SOUNDS)):
        out_dir = OUT_DIR.parent / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        for name, make in sounds.items():
            path = out_dir / f"{name}.ogg"
            sound = make()
            write_ogg(path, sound)
            data.setdefault(folder, {})[f"{name}.ogg"] = {
                "method": "synthesized by tools/build_ui_sounds.py",
                "kind": "oneshot",
                "seconds": round(len(sound) / SR, 3),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "license": "CC-BY-NC-SA-4.0",
            }
            print(f"{folder}/{name}.ogg {len(sound) / SR:.2f}s")
    PROVENANCE.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
