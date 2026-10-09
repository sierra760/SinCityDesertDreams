# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""The game's own instrument bank, synthesized from scratch with numpy.

Every voice is built from sine partials, frequency modulation or shaped noise;
nothing is sampled. Each melodic instrument is a function

    voice(freq, held_seconds, velocity, rng) -> mono float array

that returns the note including its release tail. Drum kits map General MIDI
percussion keys to short hits. The palette leans on mid-century lounge and
desert exotica: vibraphone, electric piano, upright bass, surf guitar, combo
organ, flute, marimba, string pad and muted trumpet, plus piano, nylon and
steel guitars, saxophones, clarinet, trumpet, trombone, brass section,
harmonica, whistler, glockenspiel and accordion for the wider score.
"""

from __future__ import annotations

import math

import numpy as np

SR = 44100
NYQUIST = SR / 2


# --- shared helpers ---------------------------------------------------------------

def _t(n: int) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / SR


def _samples(seconds: float) -> int:
    return max(1, int(round(seconds * SR)))


def decay(t: np.ndarray, t60: float) -> np.ndarray:
    """Exponential decay reaching -60 dB after t60 seconds."""
    return np.exp(-6.907755 * t / max(t60, 1e-4))


def gate(n: int, held: float, attack: float, release: float) -> np.ndarray:
    """Linear attack, hold until note-off, then an exponential release."""
    t = _t(n)
    env = np.ones(n)
    if attack > 0:
        env = np.minimum(env, t / attack)
    after = t - held
    tail = after > 0
    env[tail] *= decay(after[tail], release)
    return env


def spectral_filter(x: np.ndarray, gain) -> np.ndarray:
    """Zero-phase filtering in the frequency domain; gain(freqs) -> magnitudes."""
    if len(x) < 4:
        return x
    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(spectrum * gain(freqs), len(x))


def lowpass(cutoff: float, order: int = 2):
    return lambda f: 1 / np.sqrt(1 + (f / cutoff) ** (2 * order))


def highpass(cutoff: float, order: int = 2):
    return lambda f: 1 / np.sqrt(1 + (cutoff / np.maximum(f, 1e-3)) ** (2 * order))


def bandpass(center: float, q: float):
    def gain(f):
        f = np.maximum(f, 1e-3)
        return 1 / np.sqrt(1 + q * q * (f / center - center / f) ** 2)
    return gain


def additive(t: np.ndarray, partials, phase_mod=None) -> np.ndarray:
    """Sum (frequency, amplitude, t60) partials, skipping any above Nyquist."""
    out = np.zeros_like(t)
    for freq, amp, t60 in partials:
        if freq >= NYQUIST * 0.95 or amp <= 0:
            continue
        phase = 2 * np.pi * freq * t
        if phase_mod is not None:
            phase = phase + phase_mod * (freq / partials[0][0])
        out += amp * np.sin(phase) * decay(t, t60)
    return out


def _vibrato(t: np.ndarray, rate: float, depth: float, delay: float) -> np.ndarray:
    """Phase offset (radians per unit frequency ratio) for a delayed vibrato."""
    ramp = np.clip((t - delay) / 0.35, 0, 1)
    return ramp * depth * np.sin(2 * np.pi * rate * t)


# --- melodic voices ---------------------------------------------------------------

def vibraphone(freq, held, vel, rng):
    n = _samples(held + 2.2)
    t = _t(n)
    bright = 0.6 + 0.6 * vel
    ring = 3.4 * (262 / freq) ** 0.25
    body = additive(t, [(freq, 1.0, ring), (freq * 4.0, 0.20 * bright, ring * 0.28),
                        (freq * 10.0, 0.05 * bright, 0.22)])
    mallet = spectral_filter(rng.standard_normal(_samples(0.012)), bandpass(freq * 3, 1.5))
    body[:len(mallet)] += 0.08 * vel * mallet * np.linspace(1, 0, len(mallet))
    tremolo = 1 - 0.22 * (0.5 + 0.5 * np.sin(2 * np.pi * 5.4 * t + rng.uniform(0, 6.28)))
    damp = gate(n, held + 0.15, 0.002, 0.35)
    return body * tremolo * damp * (0.35 + 0.65 * vel)


def electric_piano(freq, held, vel, rng):
    n = _samples(held + 0.6)
    t = _t(n)
    ring = 2.8 * (220 / freq) ** 0.35
    index = (0.6 + 2.2 * vel) * decay(t, 0.9) + 0.25
    tone = np.sin(2 * np.pi * freq * t + index * np.sin(2 * np.pi * freq * t)) * decay(t, ring)
    tine_ratio = 7.0 if freq < 700 else 3.0
    tine = np.sin(2 * np.pi * freq * t + (1.4 * vel) * decay(t, 0.12)
                  * np.sin(2 * np.pi * freq * tine_ratio * t)) * decay(t, 0.18)
    sound = tone + 0.35 * vel * tine
    sound *= 1 + 0.12 * np.sin(2 * np.pi * 4.6 * t)
    return sound * gate(n, held, 0.003, 0.25) * (0.3 + 0.7 * vel)


def upright_bass(freq, held, vel, rng):
    n = _samples(held + 0.3)
    t = _t(n)
    pluck_at = 0.18
    partials = []
    for k in range(1, 26):
        amp = abs(math.sin(math.pi * k * pluck_at)) / k ** 1.25
        amp *= math.exp(-(k - 1) * (1.15 - vel) * 0.35)
        partials.append((freq * k, amp, 1.7 / (1 + 0.55 * (k - 1))))
    sound = additive(t, partials)
    sound += 0.6 * np.sin(2 * np.pi * freq * t) * decay(t, 1.4)
    thump = spectral_filter(rng.standard_normal(_samples(0.03)), lowpass(500, 2))
    sound[:len(thump)] += 0.25 * vel * thump * np.linspace(1, 0, len(thump))
    return sound * gate(n, held, 0.004, 0.09) * (0.4 + 0.6 * vel)


def surf_guitar(freq, held, vel, rng):
    n = _samples(held + 0.25)
    t = _t(n)
    pluck_at, stiffness = 0.12, 0.00008
    partials = []
    for k in range(1, 40):
        f = freq * k * math.sqrt(1 + stiffness * k * k)
        amp = abs(math.sin(math.pi * k * pluck_at)) / k ** 1.2
        amp *= math.exp(-(k - 1) * (1.1 - vel) * 0.12)
        partials.append((f, amp, 2.6 / (1 + 0.3 * (k - 1))))
    sound = additive(t, partials)
    pick = spectral_filter(rng.standard_normal(_samples(0.006)), highpass(2500, 2))
    sound[:len(pick)] += 0.15 * vel * pick
    sound = np.tanh(1.6 * sound) / np.tanh(1.6)
    # A small open-backed amplifier: no deep lows, speaker roll-off above 3 kHz.
    sound = spectral_filter(sound, lambda f: lowpass(3000, 2)(f) * highpass(110, 1)(f)
                            * (1 + 0.6 * bandpass(1100, 1.2)(f)))
    return sound * gate(n, held, 0.001, 0.07) * (0.35 + 0.65 * vel)


def marimba(freq, held, vel, rng):
    n = _samples(min(held, 0.8) + 0.9)
    t = _t(n)
    ring = 0.9 * (262 / freq) ** 0.5
    sound = additive(t, [(freq, 1.0, ring), (freq * 3.93, 0.3 * vel, ring * 0.3),
                         (freq * 9.2, 0.05 * vel, 0.06)])
    knock = spectral_filter(rng.standard_normal(_samples(0.01)), bandpass(freq * 2, 1.2))
    sound[:len(knock)] += 0.12 * vel * knock * np.linspace(1, 0, len(knock))
    return sound * gate(n, 0.0, 0.002, ring) * (0.35 + 0.65 * vel)


def drawbar_organ(freq, held, vel, rng):
    n = _samples(held + 0.12)
    t = _t(n)
    leslie = 0.0025 * np.sin(2 * np.pi * 6.2 * t + rng.uniform(0, 6.28)) * 2 * np.pi * freq / 6.2
    bars = [(0.5, 0.45), (1, 1.0), (1.5, 0.35), (2, 0.55), (3, 0.25), (4, 0.22)]
    sound = sum(amp * np.sin(2 * np.pi * freq * ratio * t + leslie * ratio)
                for ratio, amp in bars if freq * ratio < NYQUIST * 0.9)
    click = spectral_filter(rng.standard_normal(_samples(0.004)), highpass(1500, 1))
    sound[:len(click)] += 0.25 * click
    sound *= 1 + 0.08 * np.sin(2 * np.pi * 6.2 * t)
    return sound * gate(n, held, 0.006, 0.06) * (0.55 + 0.45 * vel) * 0.45


def combo_organ(freq, held, vel, rng):
    """Reedy transistor organ: odd harmonics, quick vibrato."""
    n = _samples(held + 0.1)
    t = _t(n)
    wobble = _vibrato(t, 6.8, 0.004 * 2 * np.pi * freq / 6.8, 0.0)
    sound = np.zeros(n)
    for k in range(1, 30, 2):
        if freq * k >= NYQUIST * 0.9:
            break
        sound += np.sin(2 * np.pi * freq * k * t + wobble * k) / k
    sound += 0.4 * np.sin(2 * np.pi * freq * 2 * t + wobble * 2)
    sound = spectral_filter(sound, lowpass(3200, 1))
    return sound * gate(n, held, 0.01, 0.05) * (0.55 + 0.45 * vel) * 0.4


def flute(freq, held, vel, rng):
    n = _samples(held + 0.15)
    t = _t(n)
    vib = _vibrato(t, 5.1, 0.005 * 2 * np.pi * freq / 5.1, 0.25)
    sound = (np.sin(2 * np.pi * freq * t + vib) + 0.22 * np.sin(4 * np.pi * freq * t + 2 * vib)
             + 0.07 * np.sin(6 * np.pi * freq * t + 3 * vib))
    breath = spectral_filter(rng.standard_normal(n), bandpass(freq * 2.5, 2.0))
    breath /= max(np.abs(breath).max(), 1e-9)
    chiff = 1 + 0.5 * decay(t, 0.08)
    sound = sound * chiff + 0.08 * breath * (0.5 + decay(t, 0.15))
    return sound * gate(n, held, 0.05, 0.1) * (0.4 + 0.6 * vel) * 0.7


def _saw(t, freq, limit=60, rolloff=10.0):
    out = np.zeros_like(t)
    for k in range(1, limit):
        if freq * k >= NYQUIST * 0.9:
            break
        out += np.sin(2 * np.pi * freq * k * t) / k * math.exp(-k / rolloff)
    return out


def string_pad(freq, held, vel, rng):
    n = _samples(held + 0.6)
    t = _t(n)
    sound = sum(_saw(t + rng.uniform(0, 0.01), freq * 2 ** (cents / 1200), rolloff=7.0)
                for cents in (-8, 0, 7))
    sound *= 1 + 0.04 * np.sin(2 * np.pi * 5.0 * t)
    return sound * gate(n, held, 0.28, 0.45) * (0.4 + 0.6 * vel) * 0.25


def muted_trumpet(freq, held, vel, rng):
    n = _samples(held + 0.12)
    t = _t(n)
    vib = _vibrato(t, 5.4, 0.006 * 2 * np.pi * freq / 5.4, 0.3)
    sound = np.zeros(n)
    for k in range(1, 40):
        if freq * k >= NYQUIST * 0.9:
            break
        sound += np.sin(2 * np.pi * freq * k * t + vib * k) / k
    sound = spectral_filter(sound, bandpass(1400, 1.6))
    sound *= 0.6 + 0.4 * (1 - decay(t, 0.05))
    return sound * gate(n, held, 0.025, 0.08) * (0.4 + 0.6 * vel) * 1.4


def _bend_phase(t: np.ndarray, freq: float, scoop_cents: float = 0.0, scoop_time: float = 0.05,
                vib_rate: float = 5.0, vib_depth: float = 0.0, vib_delay: float = 0.3) -> np.ndarray:
    """Running phase with an attack scoop and a delayed vibrato (depth as a ratio)."""
    ramp = np.clip((t - vib_delay) / 0.4, 0, 1)
    ratio = 2 ** (-scoop_cents / 1200 * np.exp(-t / scoop_time)) * (1 + vib_depth * ramp * np.sin(2 * np.pi * vib_rate * t))
    return 2 * np.pi * np.cumsum(freq * ratio) / SR


def _harmonics(phase: np.ndarray, freq: float, amps) -> np.ndarray:
    out = np.zeros_like(phase)
    for k, amp in enumerate(amps, start=1):
        if freq * k >= NYQUIST * 0.9:
            break
        out += amp * np.sin(k * phase)
    return out


def acoustic_piano(freq, held, vel, rng):
    ring = float(np.clip(7.0 * (130 / freq) ** 0.6, 0.6, 9.0))
    n = _samples(min(held, ring) + 0.35)
    t = _t(n)
    stiffness = 0.0004 * (freq / 261) ** 0.5
    sound = np.zeros(n)
    detunes = (0.9995, 1.0005) if freq > 120 else (1.0,)
    for detune in detunes:
        partials = []
        for k in range(1, 26):
            f = freq * detune * k * math.sqrt(1 + stiffness * k * k)
            amp = abs(math.sin(math.pi * k / 7)) / k * math.exp(-(k - 1) * (1.25 - vel) * 0.2)
            partials.append((f, amp, ring / (1 + 0.25 * (k - 1))))
        prompt = additive(t, [(f, a, d * 0.3) for f, a, d in partials])
        after = additive(t, partials)
        sound += (0.65 * prompt + 0.35 * after) / len(detunes)
    hammer = spectral_filter(rng.standard_normal(_samples(0.015)), lowpass(1500, 2))
    sound[:len(hammer)] += 0.15 * vel * hammer * np.linspace(1, 0, len(hammer))
    return sound * gate(n, held, 0.001, 0.12) * (0.25 + 0.75 * vel)


def _plucked(freq, held, vel, rng, pluck_at, slope, ring, tone):
    n = _samples(held + 0.3)
    t = _t(n)
    partials = []
    for k in range(1, 36):
        amp = abs(math.sin(math.pi * k * pluck_at)) / k ** slope
        amp *= math.exp(-(k - 1) * (1.1 - vel) * 0.15)
        partials.append((freq * k * math.sqrt(1 + 0.00005 * k * k), amp, ring / (1 + 0.35 * (k - 1))))
    sound = additive(t, partials)
    pick = spectral_filter(rng.standard_normal(_samples(0.008)), bandpass(3000, 1))
    sound[:len(pick)] += 0.12 * vel * pick
    sound = spectral_filter(sound, tone)
    return sound * gate(n, held, 0.002, 0.1) * (0.35 + 0.65 * vel)


def nylon_guitar(freq, held, vel, rng):
    return _plucked(freq, held, vel, rng, 0.22, 1.35, 2.2,
                    lambda f: lowpass(2600, 2)(f) * (1 + 0.8 * bandpass(210, 2)(f)))


def steel_guitar(freq, held, vel, rng):
    return _plucked(freq, held, vel, rng, 0.15, 1.05, 3.0,
                    lambda f: lowpass(6500, 2)(f) * (1 + 0.5 * bandpass(2500, 1)(f)) * highpass(90, 1)(f))


def _reed(freq, held, vel, rng, formants, odd_only=0.0, scoop=25.0, vibrato=0.004, bright=1.0):
    n = _samples(held + 0.09)
    t = _t(n)
    phase = _bend_phase(t, freq, scoop, 0.05, 5.2, vibrato, 0.3)
    amps = [(1 / k) * (odd_only if k % 2 == 0 else 1.0) if odd_only else 1 / k for k in range(1, 40)]
    sound = _harmonics(phase, freq, amps)
    shape = lambda f: ((0.12 + sum(g * bandpass(c, q)(f) for c, q, g in formants))
                       * lowpass(1400 + 1800 * vel * bright, 2)(f) * highpass(freq * 0.7, 2)(f))
    sound = spectral_filter(sound, shape)
    breath = spectral_filter(rng.standard_normal(n), bandpass(2200, 1.2))
    sound = sound / max(np.abs(sound).max(), 1e-9) + 0.02 * breath / max(np.abs(breath).max(), 1e-9)
    return sound * gate(n, held, 0.035, 0.07) * (0.35 + 0.65 * vel) * 0.8


def tenor_sax(freq, held, vel, rng):
    return _reed(freq, held, vel, rng, [(520, 1.6, 1.0), (1550, 2.0, 0.8), (2900, 3.0, 0.3)])


def alto_sax(freq, held, vel, rng):
    return _reed(freq, held, vel, rng, [(640, 1.6, 1.0), (1800, 2.0, 0.8), (3200, 3.0, 0.35)])


def clarinet(freq, held, vel, rng):
    return _reed(freq, held, vel, rng, [(1500, 1.5, 0.7), (3000, 2.5, 0.25)], odd_only=0.12,
                 scoop=0.0, vibrato=0.0015, bright=0.6)


def _brass(freq, held, vel, rng, formant, rolloff, attack=0.04, voices=(1.0,)):
    n = _samples(held + 0.1)
    t = _t(n)
    rise = np.clip(t / attack, 0, 1) ** 1.5
    swell = rise * (1 + 0.15 * np.exp(-np.maximum(t - attack, 0) / 0.08) * (t > attack))
    sound = np.zeros(n)
    for detune in voices:
        offset = int(abs(detune - 1) * 4000)
        phase = _bend_phase(t, freq * detune, 15.0, 0.04, 5.3, 0.005, 0.35)
        for k in range(1, 30):
            if freq * k >= NYQUIST * 0.9:
                break
            weight = swell ** (1 + (k - 1) * rolloff * (1.25 - vel))
            sound += weight * np.sin(k * phase) / k * (1.0 if offset == 0 else 0.8)
    sound = spectral_filter(sound, lambda f: (0.3 + bandpass(formant, 1.0)(f)) * lowpass(formant * 3.5, 2)(f))
    sound /= max(np.abs(sound).max(), 1e-9)
    return sound * gate(n, held, 0.0, 0.08) * (0.35 + 0.65 * vel) * 0.8


def trumpet(freq, held, vel, rng):
    return _brass(freq, held, vel, rng, 1300, 0.35)


def trombone(freq, held, vel, rng):
    return _brass(freq, held, vel, rng, 650, 0.45, attack=0.06)


def brass_section(freq, held, vel, rng):
    return _brass(freq, held, vel, rng, 1200, 0.35, voices=(0.9965, 1.0, 1.004))


def harmonica(freq, held, vel, rng):
    n = _samples(held + 0.08)
    t = _t(n)
    phase = _bend_phase(t, freq, 20.0, 0.06, 5.0, 0.003, 0.25)
    sound = _harmonics(phase, freq, [1 / k ** 0.95 for k in range(1, 30)])
    sound = spectral_filter(sound, lambda f: (0.25 + bandpass(1500, 1.2)(f) + 0.25 * bandpass(3000, 2)(f))
                            * lowpass(3200, 2)(f) * highpass(250, 1)(f))
    sound /= max(np.abs(sound).max(), 1e-9)
    breath = spectral_filter(rng.standard_normal(n), bandpass(2500, 1))
    sound += 0.05 * breath / max(np.abs(breath).max(), 1e-9)
    sound *= 1 + 0.12 * np.sin(2 * np.pi * 4.6 * t)
    return sound * gate(n, held, 0.03, 0.06) * (0.35 + 0.65 * vel) * 0.8


def whistle(freq, held, vel, rng):
    n = _samples(held + 0.1)
    t = _t(n)
    phase = _bend_phase(t, freq, 40.0, 0.04, 5.6, 0.011, 0.15)
    sound = np.sin(phase) + 0.04 * np.sin(2 * phase)
    breath = spectral_filter(rng.standard_normal(n), bandpass(freq * 1.5, 3))
    sound += 0.05 * breath / max(np.abs(breath).max(), 1e-9)
    return sound * gate(n, held, 0.04, 0.06) * (0.35 + 0.65 * vel) * 0.7


def glockenspiel(freq, held, vel, rng):
    n = _samples(1.6)
    t = _t(n)
    sound = additive(t, [(freq, 1.0, 1.5), (freq * 2.76, 0.35 * vel, 0.5), (freq * 5.4, 0.12 * vel, 0.2)])
    click = spectral_filter(rng.standard_normal(_samples(0.004)), highpass(4000, 1))
    sound[:len(click)] += 0.06 * click
    return sound * (0.35 + 0.65 * vel) * 0.6


def accordion(freq, held, vel, rng):
    n = _samples(held + 0.08)
    t = _t(n)
    sound = np.zeros(n)
    for cents in (-9, 0, 9):
        phase = 2 * np.pi * freq * 2 ** (cents / 1200) * t
        sound += _harmonics(phase, freq, [1 / k for k in range(1, 24)])
    sound = spectral_filter(sound, lambda f: (0.3 + bandpass(1100, 1.2)(f)) * lowpass(4200, 2)(f))
    sound /= max(np.abs(sound).max(), 1e-9)
    return sound * gate(n, held, 0.04, 0.06) * (0.4 + 0.6 * vel) * 0.9


# General MIDI programs mapped to our voices, with a mono flag for parts that
# should cut their previous note (plucked bass, lead guitar, horns).
VOICES = {
    "vibraphone": (vibraphone, False),
    "electric_piano": (electric_piano, False),
    "upright_bass": (upright_bass, True),
    "surf_guitar": (surf_guitar, True),
    "marimba": (marimba, False),
    "drawbar_organ": (drawbar_organ, False),
    "combo_organ": (combo_organ, False),
    "flute": (flute, True),
    "string_pad": (string_pad, False),
    "muted_trumpet": (muted_trumpet, True),
    "acoustic_piano": (acoustic_piano, False),
    "nylon_guitar": (nylon_guitar, False),
    "steel_guitar": (steel_guitar, False),
    "tenor_sax": (tenor_sax, True),
    "alto_sax": (alto_sax, True),
    "clarinet": (clarinet, True),
    "trumpet": (trumpet, True),
    "trombone": (trombone, True),
    "brass_section": (brass_section, False),
    "harmonica": (harmonica, False),
    "whistle": (whistle, True),
    "glockenspiel": (glockenspiel, False),
    "accordion": (accordion, False),
}

PROGRAMS = {
    0: "acoustic_piano", 1: "acoustic_piano", 2: "acoustic_piano", 3: "acoustic_piano",
    4: "electric_piano", 5: "electric_piano", 8: "glockenspiel", 9: "glockenspiel",
    11: "vibraphone", 12: "marimba", 13: "marimba", 16: "drawbar_organ", 17: "drawbar_organ",
    18: "combo_organ", 21: "accordion", 22: "harmonica", 23: "accordion",
    24: "nylon_guitar", 25: "steel_guitar", 26: "surf_guitar", 27: "surf_guitar",
    28: "surf_guitar", 32: "upright_bass", 33: "upright_bass", 34: "upright_bass",
    35: "upright_bass", 48: "string_pad", 49: "string_pad", 50: "string_pad",
    56: "trumpet", 57: "trombone", 58: "trombone", 59: "muted_trumpet", 60: "trombone",
    61: "brass_section", 64: "alto_sax", 65: "alto_sax", 66: "tenor_sax", 67: "tenor_sax",
    71: "clarinet", 73: "flute", 74: "flute", 78: "whistle", 79: "whistle",
}

FAMILY_FALLBACK = ["electric_piano", "vibraphone", "drawbar_organ", "surf_guitar",
                   "upright_bass", "string_pad", "string_pad", "muted_trumpet",
                   "muted_trumpet", "flute", "combo_organ", "string_pad",
                   "string_pad", "marimba", "marimba", "vibraphone"]


def voice_for_program(program: int):
    name = PROGRAMS.get(program) or FAMILY_FALLBACK[(program // 8) % 16]
    return name, VOICES[name]


# --- percussion -------------------------------------------------------------------

def _noise(n, rng):
    return rng.standard_normal(n)


def _metal(t, rng, scale=1.0):
    """Inharmonic square-wave cluster for cymbals and hats."""
    out = np.zeros_like(t)
    for f in (205.3, 304.4, 369.6, 522.7, 540.0, 800.0):
        out += np.sign(np.sin(2 * np.pi * f * scale * t + rng.uniform(0, 6.28)))
    return out / 6


def kick(rng, vel, held):
    n = _samples(0.45)
    t = _t(n)
    sweep = 48 + 120 * np.exp(-t / 0.028)
    body = np.sin(2 * np.pi * np.cumsum(sweep) / SR) * decay(t, 0.42)
    click = spectral_filter(_noise(_samples(0.004), rng), highpass(1200, 1))
    body[:len(click)] += 0.3 * click
    return body * 1.1


def snare(rng, vel, held):
    n = _samples(0.35)
    t = _t(n)
    tone = (np.sin(2 * np.pi * 185 * t) + 0.5 * np.sin(2 * np.pi * 330 * t)) * decay(t, 0.12)
    rattle = spectral_filter(_noise(n, rng), highpass(1800, 1)) * decay(t, 0.26)
    return 0.6 * tone + 0.9 * rattle / max(np.abs(rattle).max(), 1e-9)


def side_stick(rng, vel, held):
    n = _samples(0.08)
    t = _t(n)
    tick_ = spectral_filter(_noise(n, rng), bandpass(1700, 3)) * decay(t, 0.04)
    return tick_ / max(np.abs(tick_).max(), 1e-9) * 0.7


def clap(rng, vel, held):
    n = _samples(0.3)
    t = _t(n)
    burst = spectral_filter(_noise(n, rng), bandpass(1200, 1.4))
    env = sum(np.where((t >= o) & (t < o + 0.008), 1.0, 0.0) for o in (0, 0.011, 0.022))
    env = env + decay(np.maximum(t - 0.03, 0), 0.18) * (t >= 0.03)
    return burst / max(np.abs(burst).max(), 1e-9) * env * 0.8


def brush(rng, vel, held):
    """Brush tap, or a sweep when the note is held."""
    if held > 0.35:
        n = _samples(held + 0.15)
        t = _t(n)
        swirl = spectral_filter(_noise(n, rng), bandpass(4200, 0.8))
        shape = np.sin(np.pi * np.clip(t / (held + 0.15), 0, 1)) ** 1.5
        return swirl / max(np.abs(swirl).max(), 1e-9) * shape * 0.28
    n = _samples(0.3)
    t = _t(n)
    tap = spectral_filter(_noise(n, rng), bandpass(3500, 0.7)) * decay(t, 0.18)
    tap *= np.minimum(1, t / 0.004)
    return tap / max(np.abs(tap).max(), 1e-9) * 0.55


def hat(rng, vel, held, length=0.06):
    n = _samples(length + 0.05)
    t = _t(n)
    metal = spectral_filter(_metal(t, rng, 2.0) + 0.6 * _noise(n, rng), highpass(7000, 2))
    return metal / max(np.abs(metal).max(), 1e-9) * decay(t, length) * 0.5


def cymbal(rng, vel, held, length=1.8, ping=0.0):
    n = _samples(length + 0.1)
    t = _t(n)
    metal = spectral_filter(_metal(t, rng, 1.7) + 0.8 * _noise(n, rng), highpass(4500, 2))
    metal = metal / max(np.abs(metal).max(), 1e-9) * decay(t, length)
    if ping:
        bell = spectral_filter(rng.standard_normal(n), bandpass(rng.uniform(3000, 3300), 6.0))
        metal += ping * bell / max(np.abs(bell).max(), 1e-9) * decay(t, 0.3)
    return metal * 0.45


def tom(freq):
    def hit(rng, vel, held):
        n = _samples(0.5)
        t = _t(n)
        sweep = freq * (1 + 0.35 * np.exp(-t / 0.05))
        body = np.sin(2 * np.pi * np.cumsum(sweep) / SR) * decay(t, 0.45)
        skin = spectral_filter(_noise(_samples(0.02), rng), bandpass(freq * 4, 1))
        body[:len(skin)] += 0.2 * skin
        return body * 0.8
    return hit


def hand_drum(freq, ring, slap=0.25):
    def hit(rng, vel, held):
        n = _samples(ring + 0.1)
        t = _t(n)
        sweep = freq * (1 + 0.12 * np.exp(-t / 0.02))
        body = np.sin(2 * np.pi * np.cumsum(sweep) / SR) * decay(t, ring)
        body += 0.3 * np.sin(2 * np.pi * np.cumsum(sweep * 1.58) / SR) * decay(t, ring * 0.5)
        skin = spectral_filter(_noise(_samples(0.015), rng), bandpass(freq * 5, 1.2))
        body[:len(skin)] += slap * skin / max(np.abs(skin).max(), 1e-9)
        return body * 0.7
    return hit


def shaker(rng, vel, held):
    n = _samples(0.13)
    t = _t(n)
    grains = spectral_filter(_noise(n, rng), lambda f: highpass(3200, 2)(f) * lowpass(9000, 1)(f))
    env = np.minimum(1, t / 0.015) * decay(t, 0.11)
    return grains / max(np.abs(grains).max(), 1e-9) * env * 0.9


def claves(rng, vel, held):
    n = _samples(0.12)
    t = _t(n)
    return np.sin(2 * np.pi * 2480 * t) * decay(t, 0.07) * 0.5


def cowbell(rng, vel, held):
    n = _samples(0.35)
    t = _t(n)
    tone = np.sign(np.sin(2 * np.pi * 540 * t)) + np.sign(np.sin(2 * np.pi * 800 * t))
    return spectral_filter(tone, bandpass(900, 2)) * decay(t, 0.25) * 0.3


def tambourine(rng, vel, held):
    n = _samples(0.3)
    t = _t(n)
    jingle = spectral_filter(_metal(t, rng, 4.0) + _noise(n, rng), highpass(6000, 2))
    return jingle / max(np.abs(jingle).max(), 1e-9) * decay(t, 0.2) * 0.4


def triangle(rng, vel, held):
    n = _samples(1.4)
    t = _t(n)
    return (np.sin(2 * np.pi * 4100 * t) + 0.4 * np.sin(2 * np.pi * 6800 * t)) * decay(t, 1.3) * 0.15



def timbale(freq):
    def hit(rng, vel, held):
        n = _samples(0.5)
        t = _t(n)
        shell = additive(t, [(freq, 1.0, 0.35), (freq * 1.47, 0.6, 0.25), (freq * 2.09, 0.4, 0.15)])
        rim = spectral_filter(_noise(_samples(0.02), rng), bandpass(3500, 1.5))
        shell[:len(rim)] += 0.5 * rim / max(np.abs(rim).max(), 1e-9)
        return shell * 0.55
    return hit


def guiro(length):
    def hit(rng, vel, held):
        n = _samples(length)
        t = _t(n)
        scrape = spectral_filter(_noise(n, rng), bandpass(3200, 1.2))
        teeth = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 70 * t))
        env = np.minimum(1, t / 0.01) * np.clip((length - t) / 0.03, 0, 1)
        return scrape / max(np.abs(scrape).max(), 1e-9) * teeth * env * 0.4
    return hit


def wood_block(freq):
    def hit(rng, vel, held):
        n = _samples(0.15)
        t = _t(n)
        return (np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(2 * np.pi * freq * 2.7 * t)) * decay(t, 0.06) * 0.55
    return hit


def agogo(freq):
    def hit(rng, vel, held):
        n = _samples(0.6)
        t = _t(n)
        return additive(t, [(freq, 1.0, 0.5), (freq * 2.4, 0.4, 0.25), (freq * 4.1, 0.15, 0.1)]) * 0.4
    return hit


def vibraslap(rng, vel, held):
    n = _samples(1.3)
    t = _t(n)
    rattle = spectral_filter(_noise(n, rng), bandpass(2600, 2.0))
    teeth = (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 28 * t))) * decay(t, 1.1)
    return rattle / max(np.abs(rattle).max(), 1e-9) * teeth * 0.5


def gong(rng, vel, held):
    n = _samples(5.0)
    t = _t(n)
    body = additive(t, [(92, 1.0, 4.5), (139, 0.7, 4.0), (211, 0.5, 3.0), (298, 0.35, 2.5), (417, 0.25, 2.0)])
    shimmer = spectral_filter(_noise(n, rng), bandpass(1800, 0.8)) * decay(t, 3.0) * np.clip(t / 0.4, 0, 1)
    return body * 0.6 + 0.15 * shimmer / max(np.abs(shimmer).max(), 1e-9)


def castanets(rng, vel, held):
    n = _samples(0.08)
    out = np.zeros(n)
    for offset in (0, int(0.018 * SR)):
        click = spectral_filter(_noise(_samples(0.012), rng), bandpass(2800, 2))
        click *= decay(_t(len(click)), 0.008)
        out[offset:offset + len(click)] += click[:n - offset]
    return out / max(np.abs(out).max(), 1e-9) * 0.5


STANDARD_KIT = {
    35: kick, 36: kick, 37: side_stick, 38: snare, 39: clap, 40: snare,
    41: tom(82), 43: tom(98), 45: tom(118), 47: tom(140), 48: tom(165), 50: tom(196),
    42: hat, 44: lambda r, v, h: hat(r, v, h, 0.035) * 0.7,
    46: lambda r, v, h: hat(r, v, h, 0.45),
    49: cymbal, 57: cymbal, 51: lambda r, v, h: cymbal(r, v, h, 1.3, ping=0.18),
    59: lambda r, v, h: cymbal(r, v, h, 1.3, ping=0.18),
    53: lambda r, v, h: cymbal(r, v, h, 0.9, ping=0.4),
    54: tambourine, 56: cowbell, 69: shaker, 70: shaker, 82: shaker, 75: claves,
    76: claves, 81: triangle,
    60: hand_drum(420, 0.14), 61: hand_drum(310, 0.18),
    62: hand_drum(345, 0.06, 0.6), 63: hand_drum(345, 0.28), 64: hand_drum(235, 0.32),
    65: timbale(520), 66: timbale(380), 67: agogo(910), 68: agogo(620),
    73: guiro(0.12), 74: guiro(0.38), 76: wood_block(1700), 77: wood_block(1150),
    52: gong, 58: vibraslap, 85: castanets,
}

BRUSH_KIT = dict(STANDARD_KIT)
BRUSH_KIT.update({38: brush, 40: brush, 36: lambda r, v, h: kick(r, v, h) * 0.6})


def drum_kit(program: int) -> dict:
    """General MIDI percussion; program 40 selects brushes."""
    return BRUSH_KIT if program == 40 else STANDARD_KIT
