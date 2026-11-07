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

enum Effect { STEADY, CHASE, RAYS, PULSE }

## Each casino's signature features, lit specially at night. A feature is the
## authored geometry of the named materials inside a box in model metres
## (x, height, depth: the GLB axes); `center` and `axis` (model metres) orient
## its chase or rays; `colour` null keeps the material's own colour and an
## optional `strength` scales the feature's glow.
const FEATURES := {
	# Comstock Grand: the mining headframe's winding wheel turns in light.
	251: [{"materials": ["copper"], "box": [-20.5, 77.5, -5.0, -5.5, 92.5, 1.0], "center": [-13.0, 85.0, -2.0], "axis": [0, 0, 1], "colour": Color("ffc84a"), "effect": Effect.CHASE}],
	# Silver Junction: the station clock lit from within, its copper case chasing.
	252: [{"materials": ["clock_face"], "box": [], "center": [18.15, 45.4, -4.0], "axis": [1, 0, 0], "colour": Color("ffe6b0"), "effect": Effect.STEADY, "strength": .8},
		{"materials": ["copper"], "box": [16.5, 37.0, -12.5, 21.0, 54.0, 4.5], "center": [18.15, 45.4, -4.0], "axis": [1, 0, 0], "colour": Color("2bff8c"), "effect": Effect.CHASE}],
	# Boulder Crown: the turbine wheel between the pylons spins with light.
	253: [{"materials": ["copper"], "box": [-7.5, 43.0, 7.0, 7.5, 59.0, 11.0], "center": [0.0, 51.0, 8.7], "axis": [0, 0, 1], "colour": Color("7fd8ff"), "effect": Effect.CHASE}],
	# Desert Orbit: the rocket's copper crown rings and nose cone.
	254: [{"materials": ["copper"], "box": [-8.0, 108.5, -8.0, 8.0, 128.5, 8.0], "center": [0.0, 115.0, 0.0], "axis": [0, 1, 0], "colour": Color("ff5fc4"), "effect": Effect.CHASE}],
	# The Fix: the vault medallion above the lobby.
	256: [{"materials": ["resort_wood", "resort_metal"], "box": [-3.0, 6.5, 28.0, 3.0, 12.5, 29.2], "center": [0.0, 9.4, 28.6], "axis": [0, 0, 1], "colour": Color("ffd23f"), "effect": Effect.CHASE}],
	# Six-Week Alibi: the two open wedding rings.
	257: [{"materials": ["resort_metal"], "box": [-11.5, 64.0, -2.2, 11.5, 78.0, 0.2], "center": [0.0, 71.0, -1.0], "axis": [0, 0, 1], "colour": Color("ffd6e6"), "effect": Effect.CHASE}],
	# Velvet Wardrobe: the warm keyhole and the fan crown's ribs.
	258: [{"materials": ["resort_lamp"], "box": [-1.0, 55.5, 5.5, 5.0, 68.0, 6.5], "center": [2.0, 62.0, 6.0], "axis": [0, 0, 1], "colour": Color("ffc66b"), "effect": Effect.PULSE},
		{"materials": ["resort_metal"], "box": [-8.5, 59.5, -21.0, 12.5, 70.0, 7.0], "center": [2.0, 60.0, -7.0], "axis": [0, 0, 1], "colour": Color("ff2a55"), "effect": Effect.RAYS}],
	# The Afterglow: the sunburst, rays pulsing outward.
	259: [{"materials": ["resort_metal", "resort_ceiling"], "box": [-16.0, 43.0, -9.0, 16.0, 59.0, -7.0], "center": [0.0, 43.5, -7.6], "axis": [0, 0, 1], "colour": Color("ff8a2a"), "effect": Effect.RAYS}],
	# Last Resort: the brass-edged diamond.
	260: [{"materials": ["resort_metal", "resort_glass"], "box": [-4.0, 69.0, -7.0, 7.0, 83.0, -5.0], "center": [1.5, 76.0, -6.0], "axis": [0, 0, 1], "colour": Color("2fffd6"), "effect": Effect.PULSE}],
	# Dust Republic: the open prism and the art car.
	261: [{"materials": ["resort_metal", "resort_glass"], "box": [-5.0, 5.9, 22.5, 5.0, 24.5, 31.5], "center": [0.0, 15.0, 27.0], "axis": [0, 1, 0], "colour": Color("c27bff"), "effect": Effect.CHASE},
		{"materials": ["resort_glass", "resort_metal"], "box": [-23.0, 0.0, 23.0, -13.0, 6.5, 29.0], "center": [-18.0, 3.0, 26.0], "axis": [0, 1, 0], "colour": Color("ffc94a"), "effect": Effect.PULSE}],
	# Boddy's: the scalloped tavern awnings.
	262: [{"materials": ["resort_carpet"], "box": [-10.6, 3.6, 12.0, 10.6, 4.25, 13.6], "center": [0.0, 3.9, 13.0], "axis": [0, 0, 1], "colour": null, "effect": Effect.STEADY}],
	# Woolier Days: the floodlit ikurriña and the sheep sign.
	263: [{"materials": ["flag_red", "flag_green", "flag_white"], "box": [], "center": [-12.6, 7.6, 14.35], "axis": [0, 0, 1], "colour": null, "effect": Effect.STEADY},
		{"materials": ["resort_wood", "resort_ceiling", "resort_sign"], "box": [9.0, 5.2, 13.9, 12.0, 6.8, 14.8], "center": [10.5, 6.0, 14.3], "axis": [0, 0, 1], "colour": Color("fff3d6"), "effect": Effect.STEADY}],
	# Stockgrowers: the water tank and the auction circles.
	264: [{"materials": ["resort_metal", "wood", "roof"], "box": [-19.5, 8.0, -20.5, -14.5, 12.2, -15.5], "center": [-17.0, 10.0, -18.0], "axis": [0, 1, 0], "colour": Color("ffd25a"), "effect": Effect.CHASE},
		{"materials": ["resort_metal"], "box": [-11.2, 4.4, 15.0, 11.2, 6.8, 15.4], "center": [0.0, 5.6, 15.2], "axis": [0, 0, 1], "colour": Color("ff5a2e"), "effect": Effect.PULSE}],
	# Fremont Palace: the Deco crown, the chandelier relief and the name band.
	265: [{"materials": ["resort_metal"], "box": [-4.6, 9.0, 20.6, 4.6, 11.4, 21.2], "center": [0.0, 9.25, 20.9], "axis": [0, 0, 1], "colour": Color("ffd84a"), "effect": Effect.RAYS},
		{"materials": ["resort_sign", "resort_metal", "resort_lamp"], "box": [-2.9, 4.9, 20.0, 2.9, 7.0, 20.5], "center": [0.0, 6.0, 20.3], "axis": [0, 0, 1], "colour": Color("fff0c8"), "effect": Effect.PULSE},
		{"materials": ["resort_carpet", "carpet"], "box": [-13.5, 8.0, 21.2, 13.5, 9.4, 21.8], "center": [0.0, 8.65, 21.5], "axis": [0, 0, 1], "colour": null, "effect": Effect.STEADY}],
}

static func features(code: int) -> Array:
	return FEATURES.get(code, [])
