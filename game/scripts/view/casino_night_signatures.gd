# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Each casino's look after dark: its coloured glass, two neon colours, a
## neon style and how many searchlights sweep the sky above it. Chosen so
## that no two neighbouring resorts read alike from the air or the street.
extends RefCounted

enum Style { BANDS, FINS, GRID, CHASE, PULSE }

const SIGNATURES := {
	# Comstock Grand: silver-mine riches, gold and ruby.
	251: {"glass": Color("ffb347"), "a": Color("ffcf3a"), "b": Color("ff2e3c"), "style": Style.BANDS, "beams": 2},
	# Silver Junction: railroad silver and signal green.
	252: {"glass": Color("cfe8ff"), "a": Color("2bff8c"), "b": Color("f2f6ff"), "style": Style.CHASE, "beams": 2},
	# Boulder Crown: dam-turbine electric blue.
	253: {"glass": Color("35e6ff"), "a": Color("2a8cff"), "b": Color("e8fbff"), "style": Style.FINS, "beams": 2},
	# Desert Orbit: space-age hot pink and cyan.
	254: {"glass": Color("a06bff"), "a": Color("ff3fb4"), "b": Color("3ff0ff"), "style": Style.GRID, "beams": 3},
	# The Fix: vault green and gold.
	256: {"glass": Color("3cff8f"), "a": Color("ffd23f"), "b": Color("2bff8c"), "style": Style.FINS, "beams": 2},
	# Six-Week Alibi: wedding-chapel rose.
	257: {"glass": Color("ff7aa8"), "a": Color("ff4fa0"), "b": Color("fff0f6"), "style": Style.PULSE, "beams": 1},
	# Velvet Wardrobe: crimson velvet and gold.
	258: {"glass": Color("e0206e"), "a": Color("ff2a55"), "b": Color("ffcf5a"), "style": Style.BANDS, "beams": 2},
	# The Afterglow: sunset orange into pink.
	259: {"glass": Color("ff8a3a"), "a": Color("ff6a1a"), "b": Color("ff4fa0"), "style": Style.CHASE, "beams": 3},
	# Last Resort: turquoise and amber.
	260: {"glass": Color("2fffd6"), "a": Color("16e0c8"), "b": Color("ffb43a"), "style": Style.BANDS, "beams": 1},
	# Dust Republic: desert-dusk violet and gold.
	261: {"glass": Color("b07cff"), "a": Color("a64dff"), "b": Color("ffc94a"), "style": Style.GRID, "beams": 2},
	# Boddy's: blush pink and mint.
	262: {"glass": Color("ffb0c8"), "a": Color("ff6fae"), "b": Color("6dffc4"), "style": Style.PULSE, "beams": 0},
	# Woolier Days: Basque red and green.
	263: {"glass": Color("ff5a40"), "a": Color("2bd96b"), "b": Color("ff3a2e"), "style": Style.FINS, "beams": 0},
	# Stockgrowers: cattle-brand yellow and red.
	264: {"glass": Color("ffbe55"), "a": Color("ffe14a"), "b": Color("ff4a2a"), "style": Style.CHASE, "beams": 1},
	# Fremont Palace: old-downtown red and gold.
	265: {"glass": Color("ffcc66"), "a": Color(1.0, .188, .188), "b": Color("ffd84a"), "style": Style.GRID, "beams": 2},
	# Despicable's: a corner store's red and teal.
	126: {"glass": Color("25d6c6"), "a": Color("ff4a3a"), "b": Color("25d6c6"), "style": Style.PULSE, "beams": 0},
}

static func has(code: int) -> bool:
	return SIGNATURES.has(code)

static func of(code: int) -> Dictionary:
	return SIGNATURES.get(code, {})
