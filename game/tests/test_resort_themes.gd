# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const PALETTE_ENTRIES: Array[String] = ["felt", "accent", "wood", "metal", "stone", "glass", "lamp",
	"carpet", "ink", "paper"]
const VOICES: Array[StringName] = [&"assayer", &"conductor", &"foreman", &"flight_director"]


func test_four_resorts_map_to_their_buildings() -> void:
	check_eq(ResortThemes.keys().size(), 4)
	var codes := {251: &"arcology_comstock", 252: &"arcology_junction", 253: &"arcology_boulder", 254: &"arcology_orbit"}
	for code in codes:
		check_eq(ResortThemes.key_for_building(code), codes[code])
		check_eq(ResortThemes.building(codes[code]), code)
		check_eq(Buildings.id_of(codes[code]), code, "keys match the building catalog")
		check_eq(ResortThemes.resort_name(codes[code]), Buildings.display_name(code))
	for code in [0, 250, 255, Buildings.NONE]:
		check_eq(ResortThemes.key_for_building(code), &"")
	check(ResortThemes.theme(&"nowhere").is_empty())
	check(ResortThemes.games(&"nowhere").is_empty())


func test_every_resort_has_five_shared_games_and_one_signature() -> void:
	var signatures := {}
	for key in ResortThemes.keys():
		var games := ResortThemes.games(key)
		check_eq(games.size(), 6, String(key))
		for i in 5:
			check_eq(games[i], ResortThemes.SHARED_GAMES[i])
		var signature := ResortThemes.signature(key)
		check(signature in ResortThemes.SIGNATURE_GAMES, "signature %s" % signature)
		check_eq(games[5], signature)
		signatures[signature] = key
		for game in games:
			check(not ResortThemes.game_name(key, game).is_empty(), "%s names %s" % [key, game])
			check(ResortThemes.make_game(game) != null, "engine for %s" % game)
			check_eq(ResortThemes.make_game(game).kind, game)
		for other in ResortThemes.SIGNATURE_GAMES:
			if other != signature:
				check(not ResortThemes.offers(key, other), "%s does not offer %s" % [key, other])
	check_eq(signatures.size(), 4, "each signature game belongs to one resort")
	check_eq(ResortThemes.signature(&"arcology_comstock"), &"faro")
	check_eq(ResortThemes.signature(&"arcology_junction"), &"chuck_a_luck")
	check_eq(ResortThemes.signature(&"arcology_boulder"), &"baccarat")
	check_eq(ResortThemes.signature(&"arcology_orbit"), &"trajectory")
	check(ResortThemes.make_game(&"pachinko") == null)


func test_names_are_unique() -> void:
	var names := {}
	for key in ResortThemes.keys():
		for text in [ResortThemes.resort_name(key), ResortThemes.floor_name(key)]:
			check(not names.has(text), "unique: %s" % text)
			names[text] = true
		for game in ResortThemes.games(key):
			var n := ResortThemes.game_name(key, game)
			check(not names.has(n), "unique game name: %s" % n)
			names[n] = true
		for e in ResortThemes.wheel_emblems(key):
			check(not e.is_empty())
	check_eq(ResortThemes.game_name(&"arcology_comstock", &"blackjack"), "Assay Twenty-One")
	check_eq(ResortThemes.floor_name(&"arcology_orbit"), "Mission Control")


func test_palettes_voices_fonts_reels() -> void:
	var voices := {}
	for key in ResortThemes.keys():
		var palette := ResortThemes.palette(key)
		for entry in PALETTE_ENTRIES:
			check(palette.has(entry), "%s palette has %s" % [key, entry])
			check_eq(typeof(palette.get(entry)), TYPE_COLOR)
		check_eq(ResortThemes.color(key, "felt"), palette["felt"])
		var voice := ResortThemes.voice(key)
		check(voice in VOICES, String(voice))
		voices[voice] = true
		check(ResourceLoader.exists(ResortThemes.font_path(key)), ResortThemes.font_path(key))
		check(ResourceLoader.exists(ResortThemes.font_path(key, true)))
		check_eq(ResortThemes.reel_names(key).size(), 6)
		check_eq(ResortThemes.wheel_emblems(key).size(), 2)
		check_eq(ResortThemes.reel_name(key, "B"), ResortThemes.reel_names(key)[5])
	check_eq(voices.size(), 4)
	check_eq(ResortThemes.color(&"arcology_comstock", "stone"), Color("c9a878"))
	check_eq(ResortThemes.reel_name(&"arcology_orbit", "B"), "ORBIT")


func test_patter_covers_every_voice_and_event() -> void:
	for voice in VOICES:
		for event in CasinoLines.EVENTS:
			var options := CasinoLines.lines(voice, event)
			check_ge(options.size(), 4, "%s/%s" % [voice, event])
			for text in options:
				check(not String(text).contains("{"), "no placeholders")
			check(not CasinoLines.line(voice, event, CasinoRng.new(1)).is_empty())
	check_eq(CasinoLines.line(&"nobody", &"win"), "")
	check_eq(CasinoLines.play_prompt("Assay Twenty-One", 100), "F to play Assay Twenty-One · $100 minimum")
	check_eq(CasinoLines.enter_prompt("Comstock Grand"), "F to enter Comstock Grand")
	check_eq(CasinoLines.enter_prompt("Comstock Grand", true), "Interact to enter Comstock Grand")
	check_eq(CasinoLines.exit_prompt(), "F to step outside")
	check_eq(CasinoLines.reaction_event("blackjack"), &"blackjack")
	check_eq(CasinoLines.reaction_event("nonsense"), &"lose")
