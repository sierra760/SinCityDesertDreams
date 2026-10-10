# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later

## Six fictional Nevada-themed resort additions.
extends RefCounted

const RESORTS := {
	&"arcology_fix": {
		"building": 256, "name": "The Fix", "floor": "The Back Room",
		"voice": &"foreman", "signature": &"vault_circuit", "font": "biorhyme", "body_font": "biorhyme",
		"games": {&"blackjack": "House Twenty-One", &"roulette": "Inside Track Roulette", &"slots": "The Skim", &"money_wheel": "Silent Partner Wheel", &"video_poker": "Clean Slate Draw", &"vault_circuit": "Vault Circuit"},
		"palette": {"stone": Color("323833ff"), "metal": Color("c29b53ff"), "wood": Color("241c19ff"), "glass": Color("247a5bff"), "lamp": Color("ffe3a6ff"), "carpet": Color("153b2dff"), "felt": Color("23704eff"), "accent": Color("c29b53ff"), "ink": Color("101c15ff"), "paper": Color("f3e6c9ff")},
		"reels": ["Brass Key", "Martini", "Fedora", "Emerald", "Ledger", "VAULT"],
		"wheel_emblems": ["The Back Room", "The Fix"]},
	&"arcology_alibi": {
		"building": 257, "name": "Six-Week Alibi", "floor": "The Fresh Start",
		"voice": &"conductor", "signature": &"alibi_route", "font": "fontdiner", "body_font": "biorhyme",
		"games": {&"blackjack": "Second Chance Twenty-One", &"roulette": "Separate Ways Roulette", &"slots": "Six-Week Streak", &"money_wheel": "Turning Point Wheel", &"video_poker": "Fresh Start Draw", &"alibi_route": "Separate Ways"},
		"palette": {"stone": Color("e4b4a6ff"), "metal": Color("d2ad6bff"), "wood": Color("634238ff"), "glass": Color("70b59aff"), "lamp": Color("ffe3c2ff"), "carpet": Color("6d3249ff"), "felt": Color("4c9482ff"), "accent": Color("d88798ff"), "ink": Color("402634ff"), "paper": Color("f8ecdcff")},
		"reels": ["Wedding Ring", "Suitcase", "Cocktail", "Rose", "Courthouse", "ALIBI"],
		"wheel_emblems": ["The Fresh Start", "Six-Week Alibi"]},
	&"arcology_velvet": {
		"building": 258, "name": "Velvet Wardrobe", "floor": "The Scarlet Salon",
		"voice": &"assayer", "signature": &"velvet_encore", "font": "fontdiner", "body_font": "biorhyme",
		"games": {&"blackjack": "Encore Twenty-One", &"roulette": "Scarlet Roulette", &"slots": "After Hours", &"money_wheel": "Curtain Call Wheel", &"video_poker": "Backstage Draw", &"velvet_encore": "Encore"},
		"palette": {"stone": Color("a34a42ff"), "metal": Color("ba8a4eff"), "wood": Color("271b21ff"), "glass": Color("39766dff"), "lamp": Color("ffd899ff"), "carpet": Color("521728ff"), "felt": Color("6c2943ff"), "accent": Color("9c2546ff"), "ink": Color("24131eff"), "paper": Color("f5e5c9ff")},
		"reels": ["Keyhole", "Fan", "Spotlight", "Rose", "Velvet Curtain", "VELVET"],
		"wheel_emblems": ["The Scarlet Salon", "Velvet Wardrobe"]},
	&"arcology_afterglow": {
		"building": 259, "name": "The Afterglow", "floor": "The Observation Lounge",
		"voice": &"flight_director", "signature": &"afterglow_forecast", "font": "atomic_age", "body_font": "biorhyme",
		"games": {&"blackjack": "Daybreak Twenty-One", &"roulette": "Fallout Roulette", &"slots": "Radiant Fortune", &"money_wheel": "Sunset Wheel", &"video_poker": "Bright Side Draw", &"afterglow_forecast": "Afterglow Forecast"},
		"palette": {"stone": Color("e9debdff"), "metal": Color("cc8746ff"), "wood": Color("463831ff"), "glass": Color("80c2a5ff"), "lamp": Color("fff0b0ff"), "carpet": Color("374d43ff"), "felt": Color("61a28cff"), "accent": Color("dc874bff"), "ink": Color("233630ff"), "paper": Color("f7edd7ff")},
		"reels": ["Sunburst", "Cocktail", "Atom", "Sunglasses", "Geiger Meter", "GLOW"],
		"wheel_emblems": ["The Observation Lounge", "The Afterglow"]},
	&"arcology_last": {
		"building": 260, "name": "Last Resort", "floor": "The Last Bank",
		"voice": &"assayer", "signature": &"last_bank", "font": "biorhyme_expanded", "body_font": "biorhyme",
		"games": {&"blackjack": "Still Standing Twenty-One", &"roulette": "Boomtown Roulette", &"slots": "House Remains", &"money_wheel": "Prosperity Wheel", &"video_poker": "Ghost Town Draw", &"last_bank": "Last Bank Contracts"},
		"palette": {"stone": Color("c5a37bff"), "metal": Color("b79550ff"), "wood": Color("5d3c28ff"), "glass": Color("36aaa6ff"), "lamp": Color("ffe2acff"), "carpet": Color("55442dff"), "felt": Color("387e6aff"), "accent": Color("4fa4a0ff"), "ink": Color("342b20ff"), "paper": Color("f3e5cbff")},
		"reels": ["Bottle", "Bank Key", "Desert Owl", "Gold Coin", "Diamond", "LAST"],
		"wheel_emblems": ["The Last Bank", "Last Resort"]},
	&"arcology_dust": {
		"building": 261, "name": "Dust Republic", "floor": "The Common Ground",
		"voice": &"conductor", "signature": &"dust_pool", "font": "biorhyme", "body_font": "biorhyme",
		"games": {&"blackjack": "Open Road Twenty-One", &"roulette": "Playa Roulette", &"slots": "Dust Dividend", &"money_wheel": "Free State Wheel", &"video_poker": "Common Ground Draw", &"dust_pool": "Common Pot"},
		"palette": {"stone": Color("c78c64ff"), "metal": Color("aa643dff"), "wood": Color("4a3029ff"), "glass": Color("79629aff"), "lamp": Color("ffe5b1ff"), "carpet": Color("45325dff"), "felt": Color("886a9cff"), "accent": Color("9c6ecaff"), "ink": Color("291d35ff"), "paper": Color("f2e5cbff")},
		"reels": ["Shade Sail", "Art Car", "Compass", "Light Prism", "Dust Goggles", "DUST"],
		"wheel_emblems": ["The Common Ground", "Dust Republic"]},
}
