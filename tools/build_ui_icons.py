#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

"""Author the game's original, editable SVG tool pictograms. No external artwork.

64-unit grid, rounded four-unit strokes, warm paper badges and semantic accents.
SVG sources are shipped at 128px so 32px icons stay sharp at doubled UI scale.
Run from any directory. Only the SVG files in game/assets/ui/tool-icons are written.
"""
import math
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / 'game/assets/ui/tool-icons'
INK, PAPER, TEAL, BLUE, GOLD, RED, GREEN = (
    '#293e3b', '#f4efdf', '#258873', '#487cac', '#cd9c42', '#b95b40', '#659452')

def path(d, fill='none', stroke=INK, width=4):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{width}"/>'

def rect(x, y, w, h, fill=PAPER, r=2):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{INK}" stroke-width="3"/>'

def circle(x, y, r, fill=PAPER, stroke=INK, width=3):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{width}"/>'

def group(body, transform):
    return f'<g transform="{transform}">{body}</g>'

def arrow(x, y, up=True, color=TEAL):
    return group(path('M0 14 V-10 M-7 -3 L0 -10 7 -3', stroke=color, width=5),
                 f'translate({x} {y})' + ('' if up else ' rotate(180)'))

def waves(y=43):
    return path(f'M8 {y}q6 -6 12 0 t12 0 t12 0 t12 0 M8 {y+9}q6 -6 12 0 t12 0 t12 0 t12 0', stroke=BLUE, width=3)

def tree(x=32, y=30, scale=1):
    return group(path('M0 9 V23') + path('M0 -19 C-20 -19 -21 10 -7 11 H7 C21 10 20 -19 0 -19Z', GREEN),
                 f'translate({x} {y}) scale({scale})')

def bolt():
    return path('M35 9 L20 34 H30 L27 54 45 27 H34Z', GOLD, INK, 3)

def drop():
    return path('M32 9 C29 19 17 29 17 39 a15 15 0 0 0 30 0 C47 29 35 19 32 9Z', BLUE)

def flame():
    return path('M34 9 C38 24 20 22 23 35 L16 29 C8 54 47 61 49 36 50 27 43 21 43 21 44 36 30 34 34 9Z', RED)

def shield():
    return path('M32 9 L51 16 V30 Q51 45 32 55 13 45 13 30 V16Z', BLUE) + path('M24 31 L30 37 41 24', stroke=PAPER)

def train():
    return rect(20, 13, 24, 32, TEAL, 7) + rect(24, 19, 16, 12) + path('M24 46 L19 53 M40 46 L45 53') + circle(26, 38, 2, PAPER) + circle(38, 38, 2, PAPER)

def rails():
    return path('M23 9 L17 55 M41 9 L47 55') + path('M21 17 H43 M20 28 H44 M19 39 H45 M17 50 H47', stroke=GOLD)

def house():
    return path('M12 30 L32 12 52 30', stroke=GREEN, width=5) + path('M18 27 V52 H46 V27', PAPER) + rect(28, 36, 9, 16, GREEN)

def tower(x=20, y=10, w=26, h=44, fill=BLUE):
    return rect(x, y, w, h, fill) + path(f'M{x+7} {y+9}h{w-14}m-{w-14} 10h{w-14}m-{w-14} 10h{w-14}', stroke=PAPER, width=3)

def star():
    return path('M32 11 L38 25 54 25 42 35 46 51 32 42 18 51 22 35 10 25 26 25Z', GOLD, INK, 3)

def station(symbol):
    return path('M8 54 H56 M12 54 V30 L32 12 52 30 V54', PAPER) + group(symbol, 'translate(12 17) scale(.63)')

def dispatch(symbol):
    return group(symbol, 'translate(0 0) scale(.8)') + path('M30 49 H55 M46 40 L55 49 46 58', stroke=RED, width=5)

def resort_roof():
    return path('M9 54 H55', stroke=GOLD, width=5)

def build():
    icons = {}
    icons['query'] = circle(27, 26, 16, PAPER, TEAL, 5) + path('M40 40 L53 53', width=6) + circle(27, 26, 3, INK)
    icons['sign'] = path('M29 29 V55') + path('M10 12 H43 L55 23 43 34 H10Z', GOLD) + path('M18 23 H39', stroke=PAPER)
    icons['bulldoze'] = rect(12, 36, 33, 16, GOLD, 8) + rect(21, 17, 17, 22, GOLD) + rect(25, 21, 9, 11) + path('M46 32 V52 H57 M45 42 H51') + circle(21, 44, 3, INK) + circle(35, 44, 3, INK)
    icons['dezone'] = rect(12, 12, 40, 40, PAPER) + path('M12 25 H52 M12 39 H52 M25 12 V52 M39 12 V52', stroke=GOLD, width=2) + path('M12 52 L52 12', stroke=RED, width=7)
    icons['road'] = path('M20 9 L12 55 H52 L44 9Z', INK) + path('M32 12 V19 M32 28 V35 M32 44 V51', stroke=PAPER, width=3)
    icons['highway'] = path('M17 9 L9 55 H55 L47 9Z', INK) + path('M29 10 V54 M35 10 V54', stroke=GOLD, width=2) + path('M20 17 V24 M18 39 V46 M44 17 V24 M46 39 V46', stroke=PAPER, width=2)
    icons['onramp'] = path('M18 10 V54 M32 10 V54', width=6) + path('M53 53 V43 Q53 30 32 25', stroke=TEAL, width=7) + path('M22 21 L32 13 42 21', stroke=TEAL)
    icons['tunnel'] = path('M9 53 V31 A23 23 0 0 1 55 31 V53Z', GOLD) + path('M20 53 V32 A12 12 0 0 1 44 32 V53Z', INK) + path('M32 39 V46 M32 51 V56', stroke=PAPER, width=3)
    icons['rail'] = rails()
    icons['subway'] = path('M9 53 V29 A23 23 0 0 1 55 29 V53', stroke=BLUE, width=4) + train()
    icons['subway_portal'] = path('M8 52 H21 V42 H31 V32 H41 V22 H55', stroke=BLUE, width=5) + arrow(18, 19, False) + path('M40 54 H56 M44 48 V57 M52 48 V57', width=3)
    icons['power_line'] = path('M22 55 L29 9 H35 L43 55 M17 22 H47 M13 34 H51 M25 36 L39 48 M39 36 L25 48 M18 22 V28 M46 22 V28', stroke=TEAL) + path('M26 13 H38', stroke=GOLD)
    icons['water_pipe'] = path('M10 18 H36 V46 H55', stroke=INK, width=15) + path('M10 18 H36 V46 H55', stroke=BLUE, width=9) + path('M11 9 V27 M25 29 H47 M53 36 V56', width=3)
    icons['zone_res_low'] = house()
    icons['zone_res_high'] = tower(12, 24, 17, 30, GREEN) + tower(29, 9, 23, 45, GREEN)
    icons['zone_com_low'] = rect(13, 23, 38, 30) + path('M10 27 L16 12 H48 L54 27Z', BLUE) + path('M24 13 V26 M40 13 V26', stroke=PAPER) + rect(19, 36, 13, 17, BLUE) + rect(37, 35, 8, 8, BLUE)
    icons['zone_com_high'] = tower(12, 22, 20, 32) + tower(31, 9, 23, 45) + path('M43 5 V9', stroke=GOLD)
    icons['zone_ind_low'] = path('M10 53 V31 L23 21 V31 L38 21 V53Z', GOLD) + rect(39, 13, 12, 40, GOLD) + path('M17 42 H30', stroke=PAPER)
    icons['zone_ind_high'] = path('M9 53 V32 L24 23 V32 L38 23 V53Z', GOLD) + rect(39, 11, 8, 42, GOLD) + rect(50, 7, 7, 46, GOLD) + path('M16 41 H30 M16 48 H30', stroke=PAPER, width=3)
    icons['airport'] = path('M29 8 H35 L38 26 55 36 V42 L37 37 36 48 43 52 V56 L32 53 21 56 V52 L28 48 27 37 9 42 V36 L26 26Z', BLUE, INK, 3)
    icons['seaport'] = path('M9 35 H55 L47 47 H18Z', TEAL) + rect(23, 21, 21, 14, GOLD) + path('M32 10 V21 M17 27 V35') + waves(53)
    icons['trees'] = tree()
    icons['small_park'] = group(tree(), 'translate(0 0) scale(.7)') + path('M28 39 H54 M28 45 H54 M31 45 V54 M50 45 V54', stroke=GOLD, width=4)
    icons['large_park'] = rect(8, 9, 48, 46, GREEN, 8) + path('M32 54 V39 Q19 33 32 24 V11', stroke=PAPER, width=6) + group(tree(), 'translate(3 8) scale(.45)') + group(tree(), 'translate(29 15) scale(.45)')
    icons['water_pump'] = path('M15 54 V29 H40 V40 H53 M15 22 H37 M27 12 V28 M17 12 H40', stroke=BLUE, width=6) + circle(27, 36, 6, PAPER) + path('M51 48 V54', stroke=BLUE, width=5)
    icons['water_tower'] = path('M23 33 L17 55 M41 33 L47 55 M21 43 H43 M21 43 L43 54 M43 43 L21 54') + rect(16, 14, 32, 21, BLUE, 6) + path('M16 14 L32 7 48 14', GOLD)
    icons['water_treatment'] = rect(10, 11, 44, 14, BLUE) + path('M17 26 L26 39 V51 H38 V39 L47 26', TEAL) + path('M24 18 L30 22 41 14', stroke=PAPER, width=3) + path('M28 56 H36', stroke=BLUE)
    icons['desalination'] = waves(13) + path('M10 29 H26 L34 39 26 48 H10', stroke=TEAL, width=3) + group(drop(), 'translate(31 25) scale(.45)') + path('M12 38 H28', stroke=BLUE)
    icons['police'] = shield()
    icons['fire'] = flame()
    icons['hospital'] = path('M24 10 H40 V24 H54 V40 H40 V54 H24 V40 H10 V24 H24Z', RED)
    icons['school'] = path('M9 52 V27 L32 10 55 27 V52Z', GOLD) + circle(32, 25, 6) + path('M32 21 V25 L35 27', width=2) + rect(26, 39, 12, 13) + path('M16 36 V43 M48 36 V43', stroke=PAPER)
    icons['college'] = path('M8 24 L32 12 56 24 32 36Z', TEAL) + path('M18 31 V44 Q32 54 46 44 V31', fill=TEAL) + path('M55 25 V44', stroke=GOLD)
    icons['library'] = path('M32 18 Q20 9 8 16 V49 Q20 42 32 50 44 42 56 49 V16 Q44 9 32 18Z', GOLD) + path('M32 18 V50 M15 24 L25 25 M15 33 L25 34 M39 25 L49 24 M39 34 L49 33', stroke=INK, width=3)
    icons['museum'] = path('M8 23 L32 9 56 23Z', GOLD) + path('M9 54 H55 M13 47 H51 M17 28 V46 M32 28 V46 M47 28 V46', width=5)
    icons['stadium'] = '<ellipse cx="32" cy="32" rx="25" ry="20" fill="'+GOLD+'" stroke="'+INK+'" stroke-width="4"/>' + rect(14, 22, 36, 20, GREEN, 8) + path('M32 23 V41 M15 32 H21 M43 32 H49', stroke=PAPER, width=2)
    icons['marina'] = path('M32 10 V45 M17 31 H47 M12 37 Q14 55 32 54 50 55 52 37 M12 37 L9 44 M52 37 L55 44', stroke=BLUE, width=5) + circle(32, 14, 6)
    icons['zoo'] = path('M19 36 Q32 24 45 36 C62 60 2 60 19 36Z', GOLD) + circle(13, 28, 6, GOLD) + circle(25, 17, 6, GOLD) + circle(41, 17, 6, GOLD) + circle(52, 28, 6, GOLD)
    icons['prison'] = rect(12, 11, 40, 43, GOLD) + rect(20, 20, 24, 24, PAPER) + path('M27 21 V44 M37 21 V44 M17 54 V58 M47 54 V58')
    icons['bus_depot'] = rect(11, 14, 42, 37, GOLD, 7) + rect(17, 20, 30, 16, BLUE) + path('M32 20 V36 M18 52 V56 M46 52 V56', width=4) + circle(20, 43, 3) + circle(44, 43, 3)
    icons['rail_station'] = station(train())
    icons['subway_station'] = path('M17 54 V33 M47 54 V33 M14 54 H50') + rect(8, 9, 48, 29, BLUE, 5) + path('M19 29 V17 L32 28 45 17 V29', stroke=PAPER, width=4)
    icons['coal_plant'] = path('M11 45 L16 26 30 17 48 22 54 42 43 53 22 53Z', INK) + path('M19 30 L29 25 38 29 M31 45 L43 39', stroke=GOLD, width=3)
    icons['hydro_plant'] = path('M13 10 H46 L53 48 H8Z', GOLD) + path('M21 12 L17 45 M36 12 L40 45', width=3) + waves(49)
    icons['wind_plant'] = path('M32 29 V56 M32 26 L24 8 30 7 36 25 M36 29 L54 36 51 42 33 33 M28 31 L14 44 10 39 26 27', TEAL) + circle(32, 28, 5, GOLD)
    icons['gas_plant'] = flame() + path('M20 53 H44', stroke=TEAL, width=5) + path('M31 37 Q21 49 32 49 43 49 31 37Z', GOLD, GOLD, 2)
    icons['oil_plant'] = rect(15, 11, 34, 44, GOLD, 6) + path('M15 20 H49 M15 46 H49', width=3) + group(drop(), 'translate(15 19) scale(.53)')
    icons['nuclear_plant'] = circle(32, 32, 23, GOLD) + path('M28 28 L15 20 A20 20 0 0 1 32 12 V27Z M36 29 L49 20 A20 20 0 0 1 51 41 L37 35Z M32 38 L40 51 A20 20 0 0 1 20 48 L28 36Z', INK, INK, 1) + circle(32, 32, 4, INK)
    icons['solar_plant'] = circle(46, 14, 8, GOLD) + path('M46 3 V1 M57 7 L60 5 M57 20 L60 22', stroke=GOLD, width=3) + path('M15 23 H43 L52 49 H7Z', BLUE) + path('M14 35 H46 M24 24 L21 49 M34 24 L38 49 M30 50 V56 H43', stroke=PAPER, width=3)
    icons['microwave_plant'] = path('M13 17 L46 47 Q11 55 13 17Z', TEAL) + path('M28 34 L44 18 M39 54 H50 M42 47 V54') + circle(45, 17, 3, GOLD) + path('M42 7 Q57 8 57 23 M43 13 Q50 13 51 22', stroke=GOLD, width=3)
    atom = '<ellipse cx="32" cy="32" rx="24" ry="9" fill="none" stroke="'+TEAL+'" stroke-width="3"/>'
    icons['fusion_plant'] = atom + group(atom, 'rotate(60 32 32)') + group(atom, 'rotate(120 32 32)') + circle(32, 32, 6, GOLD)
    icons['arcology_comstock'] = resort_roof() + path('M12 52 V31 H23 V17 H42 V31 H53 V52Z', GOLD) + path('M19 14 Q32 3 46 14 M32 11 L26 28', stroke=TEAL, width=4) + rect(27, 36, 12, 18, TEAL)
    icons['arcology_junction'] = resort_roof() + path('M9 51 V30 H20 V19 L32 9 44 19 V30 H55 V51Z', GOLD) + circle(32, 24, 6) + path('M32 20 V24 H35', width=2) + path('M22 53 L26 37 H38 L42 53 M25 42 H39 M24 48 H40', stroke=TEAL, width=3)
    icons['arcology_boulder'] = resort_roof() + path('M17 51 L22 25 H42 L47 51Z', GOLD) + path('M21 25 L18 11 28 17 32 7 37 17 46 11 43 25Z', TEAL) + path('M28 33 L26 49 M36 33 L38 49', stroke=PAPER, width=3)
    icons['arcology_orbit'] = resort_roof() + path('M25 38 L17 48 V32 L24 26 M39 38 L47 48 V32 L40 26', GOLD) + path('M24 40 V26 Q24 15 32 7 40 15 40 26 V40Z', TEAL) + circle(32, 25, 5) + path('M28 45 L32 54 36 45', stroke=RED, width=4)
    # Six added resorts: each pictogram follows its building's silhouette and emblem.
    emerald, blush, oxblood, ivory, rust, violet = '#2f7a5e', '#e2ab9e', '#7a2e3a', '#efe3c4', '#b8653f', '#7d6aa0'
    spokes = ''.join(f'M32 22 L{32+5*math.sin(i*math.pi/4):.1f} {22+5*math.cos(i*math.pi/4):.1f} ' for i in range(8))
    icons['arcology_fix'] = (resort_roof() + path('M21 52 V9 H43 V52Z', emerald)
        + path('M26 32 V38 M32 32 V38 M38 32 V38', stroke=PAPER, width=2)
        + path('M10 52 V40 H54 V52Z', '#41524a') + path('M16 43 V50 M23 43 V50 M41 43 V50 M48 43 V50', stroke=GOLD, width=2.5)
        + rect(28, 43, 8, 9, emerald, 1) + circle(32, 22, 7.5, GOLD) + path(spokes, stroke=INK, width=1.6)
        + circle(32, 22, 2, INK, INK, 1))
    icons['arcology_alibi'] = (resort_roof() + path('M10 52 V17 H24 V52Z', blush) + path('M40 52 V11 H54 V52Z', blush)
        + path('M13 24 H21 M13 31 H21 M13 38 H21 M43 18 H51 M43 25 H51 M43 32 H51 M43 39 H51', stroke=TEAL, width=3)
        + path('M24 52 V38 H40 V52Z', PAPER) + path('M22 38 L32 31 42 38Z', PAPER)
        + path('M28 41 V52 M32 41 V52 M36 41 V52', width=2)
        + '<circle cx="28" cy="14" r="5" fill="none" stroke="'+GOLD+'" stroke-width="3"/>'
        + '<circle cx="36" cy="14" r="5" fill="none" stroke="'+GOLD+'" stroke-width="3"/>')
    icons['arcology_velvet'] = (resort_roof() + path('M8 52 V28 H20 V52Z', oxblood) + path('M44 52 V32 H56 V52Z', oxblood)
        + path('M21 52 V19 A11 11 0 0 1 43 19 V52Z', oxblood)
        + path('M32 13 a4 4 0 1 1 -0.1 0Z M30 20 H34 L36 32 H28Z', GOLD, INK, 1.5)
        + path('M11 34 H17 M11 41 H17 M47 38 H53 M47 45 H53', stroke=GOLD, width=3)
        + path('M24 44 Q32 37 40 44 V52 H24Z', GOLD, INK, 2))
    icons['arcology_afterglow'] = (resort_roof() + path('M8 52 V25 H56 V52Z', ivory)
        + path('M12 31 H52 M12 37 H52 M12 43 H52', stroke=TEAL, width=3)
        + path('M18 25 A14 14 0 0 1 46 25Z', RED)
        + path('M32 4 V8 M19 9 L21 12 M45 9 L43 12 M12 18 L15 19 M52 18 L49 19', stroke=GOLD, width=3)
        + path('M24 52 V46 H40 V52', TEAL, INK, 2))
    icons['arcology_last'] = (resort_roof() + path('M30 52 V17 L35 12 H49 L54 17 V52Z', TEAL)
        + path('M37 13 V52 M44 12 V52 M30 26 H54 M30 36 H54', stroke=PAPER, width=1.6)
        + path('M8 52 V30 H34 V52Z', GOLD) + path('M7 30 H35', width=4)
        + path('M12 52 V43 A3 3 0 0 1 18 43 V52 M21 52 V43 A3 3 0 0 1 27 43 V52', PAPER, INK, 2)
        + path('M42 2 L47 7 42 12 37 7Z', GOLD, INK, 2))
    icons['arcology_dust'] = (resort_roof() + path('M8 52 V22 H20 V52Z', rust) + path('M10 22 V14 H19 V22', rust)
        + path('M44 52 V18 H56 V52Z', rust) + path('M46 18 V10 H54 V18', rust)
        + path('M20 20 Q32 30 44 16 L44 30 Q32 40 20 34Z', '#d8c9a6', INK, 2.5)
        + path('M32 36 L27 46 32 52 37 46Z M27 46 H37', violet, INK, 2)
        + path('M11 28 H17 M11 35 H17 M11 42 H17 M47 24 H53 M47 31 H53 M47 38 H53', stroke=violet, width=3))
    icons['reward_mayors_residence'] = house() + path('M39 9 V20 M39 9 H53 L49 15 H39', GOLD, INK, 2)
    icons['reward_city_hall'] = path('M8 54 H56 M13 54 V25 H51 V54', GOLD) + path('M10 25 L32 13 54 25Z', TEAL) + path('M21 34 V46 M32 34 V46 M43 34 V46 M32 13 V5 H46', width=3)
    icons['reward_monument'] = path('M12 54 H52 L47 43 H17Z', GOLD) + path('M26 42 L28 24 H36 L39 42Z', TEAL) + circle(32, 16, 7, GOLD) + path('M28 26 L19 33 M36 26 L45 17', stroke=TEAL, width=5)
    icons['reward_military_base'] = rect(10, 11, 44, 43, TEAL) + group(star(), 'translate(8 8) scale(.75)')
    icons['reward_neon_dome'] = path('M8 49 A24 24 0 0 1 56 49ZM16 49 Q18 19 32 25 46 19 48 49 M32 26 V49', TEAL) + path('M7 54 H57', stroke=GOLD, width=4) + path('M32 7 V16 M16 12 L21 18 M48 12 L43 18', stroke=GOLD, width=3)
    icons['dispatch_fire'] = dispatch(flame())
    icons['dispatch_police'] = dispatch(shield())
    icons['dispatch_military'] = dispatch(star())
    ground = path('M9 51 L23 36 38 42 55 51Z', GOLD)
    icons['raise_land'] = ground + arrow(33, 20, True)
    icons['lower_land'] = ground + arrow(33, 20, False)
    icons['level_land'] = path('M9 45 H55 M9 53 H55', stroke=GOLD, width=4) + path('M11 29 H53 M17 23 L11 29 17 35 M47 23 L53 29 47 35', stroke=TEAL, width=4)
    icons['place_water'] = group(drop(), 'translate(6 -3) scale(.82)') + waves(51)
    icons['forest'] = tree(19, 26, .65) + tree(46, 26, .65) + tree(32, 34, .8)
    icons['plant_tree'] = tree(27, 30, .9) + circle(48, 46, 9, GREEN) + path('M48 41 V51 M43 46 H53', stroke=PAPER, width=3)
    icons['raise_sea'] = waves(44) + arrow(32, 20, True)
    icons['lower_sea'] = waves(44) + arrow(32, 20, False)
    return icons

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for key, body in build().items():
        svg = '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 64 64">\n'
        svg += f'<rect x="1" y="1" width="62" height="62" rx="11" fill="{PAPER}"/>\n'
        svg += '<g stroke-linecap="round" stroke-linejoin="round">' + body + '</g>\n</svg>\n'
        (OUT / (key + '.svg')).write_text(svg)
    print(f'Wrote {len(build())} original SVG tool icons to {OUT}')

if __name__ == '__main__':
    main()
