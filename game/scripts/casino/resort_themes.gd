# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The ten gaming resorts: names, casino floors, dealer voices, palettes,
## fonts, reel symbols, money-wheel emblems and the names of their games.
##
## Keys are the building keys of the resorts. Every resort offers the five
## shared games and one signature game. Palette entries are colors keyed
## felt, accent, wood, metal, stone, glass, lamp, carpet, ink and paper; the
## table chrome and the interior finishes both read them.
class_name ResortThemes
extends RefCounted

## Games every resort offers, in display order.
const SHARED_GAMES: Array[StringName] = [&"blackjack", &"roulette", &"slots", &"money_wheel", &"video_poker"]
## The signature game kinds; multiple themed resorts may offer a kind.
const SIGNATURE_GAMES: Array[StringName] = [&"faro", &"chuck_a_luck", &"baccarat", &"trajectory", &"vault_circuit", &"alibi_route", &"velvet_encore", &"afterglow_forecast", &"last_bank", &"dust_pool"]
## Every game kind.
const KINDS: Array[StringName] = [&"blackjack", &"roulette", &"slots", &"money_wheel", &"video_poker",
	&"faro", &"chuck_a_luck", &"baccarat", &"trajectory", &"vault_circuit", &"alibi_route", &"velvet_encore", &"afterglow_forecast", &"last_bank", &"dust_pool"]

## Font keys to bundled font files.
const FONTS := {
	"fontdiner": "res://assets/fonts/fontdiner-swanky/FontdinerSwanky-Regular.ttf",
	"biorhyme": "res://assets/fonts/biorhyme/BioRhyme-Medium.ttf",
	"biorhyme_expanded": "res://assets/fonts/biorhyme-expanded/BioRhymeExpanded-Regular.ttf",
	"atomic_age": "res://assets/fonts/atomic-age/AtomicAge-Regular.ttf",
}

const CLASSIC_RESORTS: Dictionary = {
	&"arcology_comstock": {
		"building": 251, "name": "Comstock Grand", "floor": "The Assay Office",
		"voice": &"assayer", "signature": &"faro", "font": "fontdiner", "body_font": "biorhyme",
		"games": {
			&"blackjack": "Assay Twenty-One", &"roulette": "Winding Wheel Roulette",
			&"slots": "Silver Strike", &"money_wheel": "Prospector's Wheel",
			&"video_poker": "Bonanza Draw", &"faro": "Faro at the Assay Office",
		},
		"palette": {
			"stone": Color("c9a878"), "metal": Color("b06b3a"), "wood": Color("4a2e1c"),
			"glass": Color("1f6e68"), "lamp": Color("ffd9a0"), "carpet": Color("5a1f1a"),
			"felt": Color("2e5e4e"), "accent": Color("b06b3a"), "ink": Color("2b1d14"),
			"paper": Color("f2e6cf"),
		},
		"reels": ["Pickaxe", "Lantern", "Mule", "Silver Nugget", "Dynamite", "COMSTOCK"],
		"wheel_emblems": ["Assay Office", "Silver Dollar"],
	},
	&"arcology_junction": {
		"building": 252, "name": "Silver Junction", "floor": "The Roundhouse",
		"voice": &"conductor", "signature": &"chuck_a_luck", "font": "biorhyme", "body_font": "biorhyme",
		"games": {
			&"blackjack": "Dining Car Twenty-One", &"roulette": "Turntable Roulette",
			&"slots": "Timetable", &"money_wheel": "Roundhouse Wheel",
			&"video_poker": "Sleeper Car Draw", &"chuck_a_luck": "Birdcage",
		},
		"palette": {
			"stone": Color("dccdae"), "metal": Color("c49a50"), "wood": Color("5b3a21"),
			"glass": Color("4f8f6a"), "lamp": Color("ffe2b0"), "carpet": Color("1e4f4a"),
			"felt": Color("2b4a6f"), "accent": Color("4f8f6a"), "ink": Color("1f2a30"),
			"paper": Color("f4eedc"),
		},
		"reels": ["Locomotive", "Lantern", "Bell", "Semaphore", "Ticket", "JUNCTION"],
		"wheel_emblems": ["Roundhouse", "Golden Spike"],
	},
	&"arcology_boulder": {
		"building": 253, "name": "Boulder Crown", "floor": "The Powerhouse",
		"voice": &"foreman", "signature": &"baccarat", "font": "biorhyme_expanded", "body_font": "biorhyme",
		"games": {
			&"blackjack": "Intake Twenty-One", &"roulette": "Turbine Roulette",
			&"slots": "Powerhouse", &"money_wheel": "Penstock Wheel",
			&"video_poker": "High Scaler Draw", &"baccarat": "Spillway Baccarat",
		},
		"palette": {
			"stone": Color("b99b6b"), "metal": Color("b06b3a"), "wood": Color("1c1a17"),
			"glass": Color("2fa6a0"), "lamp": Color("f6f1e4"), "carpet": Color("1d5f63"),
			"felt": Color("1e8a86"), "accent": Color("2fa6a0"), "ink": Color("15201f"),
			"paper": Color("f2e8d5"),
		},
		"reels": ["Turbine", "Hard Hat", "Dynamo", "Lightning Bolt", "Concrete Bucket", "CROWN"],
		"wheel_emblems": ["Powerhouse", "High Scaler"],
	},
	&"arcology_orbit": {
		"building": 254, "name": "Desert Orbit", "floor": "Mission Control",
		"voice": &"flight_director", "signature": &"trajectory", "font": "atomic_age", "body_font": "biorhyme",
		"games": {
			&"blackjack": "Countdown Twenty-One", &"roulette": "Orbital Roulette",
			&"slots": "Launch Pad", &"money_wheel": "Gravity Wheel",
			&"video_poker": "Mission Draw", &"trajectory": "Static Fire",
		},
		"palette": {
			"stone": Color("f4ead6"), "metal": Color("c97a45"), "wood": Color("3b2a22"),
			"glass": Color("2e8c85"), "lamp": Color("fff1d0"), "carpet": Color("13203a"),
			"felt": Color("1f7f7a"), "accent": Color("c97a45"), "ink": Color("0f1a33"),
			"paper": Color("f7f0df"),
		},
		"reels": ["Rocket", "Satellite", "Planet", "Helmet", "Atom", "ORBIT"],
		"wheel_emblems": ["Mission Control", "Launch Window"],
	},
}


static var RESORTS: Dictionary = CLASSIC_RESORTS.merged(preload("res://scripts/casino/resort_expansion_themes.gd").RESORTS)

## The early-game convenience-store venue; the four resort keys stay separate.
const STORE_KEY := &"com_corner_store"
const STORE_THEME := {
	"building": 126, "name": "Despicable's", "floor": "Low-Down Lounge",
	"voice": &"shopkeeper", "font": "biorhyme", "body_font": "biorhyme",
	"games": {&"slots": "Low-Down Luck", &"video_poker": "Five-Finger Draw"},
	"palette": {"stone": Color("f2e6cf"), "metal": Color("c49a50"), "wood": Color("4a3025"),
		"glass": Color("237f78"), "lamp": Color("ffe2b0"), "carpet": Color("b7443e"),
		"felt": Color("237f78"), "accent": Color("df6b59"), "ink": Color("29221f"), "paper": Color("f8eedc")},
	"reels": ["Cherries", "Coffee", "Soda", "Horseshoe", "Black Hat", "DESPICABLE"],
}

## All playable venues, including the store, for treasury history and saves.
static func venues() -> Array[StringName]:
	var result := keys()
	result.append(STORE_KEY)
	return result


## Every resort key, in building-code order.
static func keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in RESORTS:
		out.append(k)
	return out


## The resort key for a building code, or &"" when it is not a resort.
static func key_for_building(code: int) -> StringName:
	if code == 126: return STORE_KEY
	for k in RESORTS:
		if int(RESORTS[k]["building"]) == code:
			return k
	return &""


static func has(key: StringName) -> bool:
	return key == STORE_KEY or RESORTS.has(key)


## The resort's full theme record, or {} for an unknown key.
static func theme(key: StringName) -> Dictionary:
	return STORE_THEME if key == STORE_KEY else RESORTS.get(key, {})


static func resort_name(key: StringName) -> String:
	return String(theme(key).get("name", ""))


static func floor_name(key: StringName) -> String:
	return String(theme(key).get("floor", ""))


static func building(key: StringName) -> int:
	return int(theme(key).get("building", -1))


## The resort's name for a game, or "" when the resort does not offer it.
static func game_name(key: StringName, game: StringName) -> String:
	var names: Dictionary = theme(key).get("games", {})
	return String(names.get(game, ""))


## The five shared games and the signature game, in display order.
static func games(key: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if not has(key):
		return out
	if key == STORE_KEY:
		out.append_array([&"slots", &"video_poker"])
		return out
	out.append_array(SHARED_GAMES)
	out.append(signature(key))
	return out


static func offers(key: StringName, game: StringName) -> bool:
	return game in games(key)


static func signature(key: StringName) -> StringName:
	return StringName(theme(key).get("signature", &""))


static func voice(key: StringName) -> StringName:
	return StringName(theme(key).get("voice", &""))


## Palette color by entry name; falls back to `fallback` when missing.
static func color(key: StringName, entry: String, fallback: Color = Color.WHITE) -> Color:
	var entries: Dictionary = theme(key).get("palette", {})
	if entries.has(entry):
		return entries[entry]
	return fallback


static func palette(key: StringName) -> Dictionary:
	var palette_entries: Dictionary = theme(key).get("palette", {})
	return palette_entries.duplicate()


## Resource path of the resort's signage font (`body` false) or text font.
static func font_path(key: StringName, body: bool = false) -> String:
	var font_key := String(theme(key).get("body_font" if body else "font", "biorhyme"))
	return String(FONTS.get(font_key, FONTS["biorhyme"]))


## Display names of the reel symbols s1..s5 and the bonus, in that order.
static func reel_names(key: StringName) -> Array[String]:
	var out: Array[String] = []
	for n in theme(key).get("reels", []):
		out.append(String(n))
	return out


## The display name of a slot symbol id (s1..s5 or B).
static func reel_name(key: StringName, symbol: String) -> String:
	var names := reel_names(key)
	var index := CasinoParams.SLOT_SYMBOLS.find(symbol)
	if index < 0 or index >= names.size():
		return symbol
	return names[index]


## The two money-wheel emblem names: [emblem_a, emblem_b].
static func wheel_emblems(key: StringName) -> Array[String]:
	var out: Array[String] = []
	for n in theme(key).get("wheel_emblems", []):
		out.append(String(n))
	return out


## A new game object for a kind, or null for an unknown kind.
static func make_game(game: StringName) -> CasinoGame:
	match game:
		&"blackjack":
			return BlackjackGame.new()
		&"roulette":
			return RouletteGame.new()
		&"slots":
			return SlotsGame.new()
		&"money_wheel":
			return MoneyWheelGame.new()
		&"video_poker":
			return VideoPokerGame.new()
		&"faro":
			return FaroGame.new()
		&"chuck_a_luck":
			return ChuckALuckGame.new()
		&"baccarat":
			return BaccaratGame.new()
		&"trajectory":
			return TrajectoryGame.new()
		&"vault_circuit":
			return preload("res://scripts/casino/games/vault_circuit_game.gd").new()
		&"alibi_route":
			return preload("res://scripts/casino/games/alibi_route_game.gd").new()
		&"velvet_encore":
			return preload("res://scripts/casino/games/velvet_encore_game.gd").new()
		&"afterglow_forecast":
			return preload("res://scripts/casino/games/afterglow_forecast_game.gd").new()
		&"last_bank":
			return preload("res://scripts/casino/games/last_bank_game.gd").new()
		&"dust_pool":
			return preload("res://scripts/casino/games/dust_pool_game.gd").new()
	return null
