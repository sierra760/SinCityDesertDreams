#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regenerate the four original neighborhood-resort tool silhouettes."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INK = '#382c32'
PAPER = '#f4efdf'
SHAPES = {
    'boddy': ('#bc7883', '<path d="M9 51V33H48V51Z"/><path d="M6 32H51L46 23H11Z"/><path d="M17 50V38H26V50 M33 39H42" fill="none"/><path d="M21 10H34V22H21Z"/><path d="M34 12H39V18H34" fill="none"/><path d="M26 5V7 M31 5V7" fill="none"/>'),
    'woolier': ('#cf5844', '<path d="M9 52V32L30 20 51 32V52Z"/><path d="M21 51V38H31V51 M38 37H45V45H38Z" fill="none"/><path d="M21 13C16 9 22 4 27 7C30 1 36 4 36 8C43 5 47 12 42 16H24Z"/><path d="M20 14L16 18 M36 15L38 20" fill="none"/>'),
    'stockgrowers': ('#c39853', '<path d="M9 52V31L18 23H45L54 31V52Z"/><path d="M24 51V36H40V51 M15 35V41 M48 35V41" fill="none"/><path d="M22 13L16 9 12 11 17 17H23 M39 13L46 9 50 11 44 17H38" fill="none"/><path d="M23 9H38L40 15 34 23H27L21 15Z"/><path d="M27 16H34" fill="none"/>'),
    'fremont': ('#c88f54', '<path d="M9 52V29H54V52Z"/><path d="M14 29V24H49V29 M15 33V49 M23 33V49 M41 33V49 M49 33V49" fill="none"/><path d="M27 52V39A5 5 0 0 1 37 39V52" fill="none"/><path d="M21 20L17 8 27 13 32 4 37 13 47 8 43 20Z"/>'),
}


def main():
    target = ROOT / 'game/assets/ui/tool-icons'
    for slug, (color, shapes) in SHAPES.items():
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 64 64">\n<rect x="1" y="1" width="62" height="62" rx="11" fill="{PAPER}"/>\n<g fill="{color}" stroke="{INK}" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round">{shapes}<path d="M7 55H56" fill="none"/></g>\n</svg>\n'
        (target / f'arcology_{slug}.svg').write_text(svg)


if __name__ == '__main__':
    main()
