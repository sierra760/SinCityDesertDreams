# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Four affordable neighborhood casino themes.
extends RefCounted

const RESORTS := {
	&"arcology_boddy": {
		"building": 262, "name": "Boddy's", "floor": "The Neighborhood Floor",
		"voice": &"assayer", "signature": &"faro", "font": "fontdiner", "body_font": "biorhyme",
		"games": {&"blackjack": "Counter Twenty-One", &"roulette": "Neighborhood Roulette", &"slots": "Lucky Regular", &"money_wheel": "Corner Wheel", &"video_poker": "Coffee Break Draw", &"faro": "Boddy's Faro"},
		"palette": {"stone": Color("f0dbc3ff"), "metal": Color("ba7749ff"), "wood": Color("493429ff"), "glass": Color("a58c91ff"), "lamp": Color("ffe9bbff"), "carpet": Color("642d38ff"), "felt": Color("8b4c5aff"), "accent": Color("bc7883ff"), "ink": Color("30261fff"), "paper": Color("f7efdcff")},
		"reels": ["Coffee Cup", "Rose Bouquet", "Ceramic Cat", "Table Lamp", "Cherries", "BODDY"],
		"wheel_emblems": ["The Neighborhood Floor", "Boddy's"]},
	&"arcology_woolier": {
		"building": 263, "name": "Woolier Days", "floor": "The Family Table",
		"voice": &"conductor", "signature": &"chuck_a_luck", "font": "biorhyme", "body_font": "biorhyme",
		"games": {&"blackjack": "Family Table Twenty-One", &"roulette": "Shepherd Roulette", &"slots": "Woolly Luck", &"money_wheel": "Harvest Wheel", &"video_poker": "Supper Club Draw", &"chuck_a_luck": "Shepherd's Chuck-a-Luck"},
		"palette": {"stone": Color("ead9bdff"), "metal": Color("a77c43ff"), "wood": Color("5a3427ff"), "glass": Color("599e7cff"), "lamp": Color("ffedbeff"), "carpet": Color("81312eff"), "felt": Color("487a58ff"), "accent": Color("cf5844ff"), "ink": Color("34271fff"), "paper": Color("f5ecd4ff")},
		"reels": ["Sheep", "Bread Loaf", "Grapes", "Shepherd Crook", "Supper Pot", "WOOLIER"],
		"wheel_emblems": ["The Family Table", "Woolier Days"]},
	&"arcology_stockgrowers": {
		"building": 264, "name": "Stockgrowers", "floor": "The Auction Hall",
		"voice": &"foreman", "signature": &"faro", "font": "biorhyme_expanded", "body_font": "biorhyme",
		"games": {&"blackjack": "Brand Twenty-One", &"roulette": "Roundup Roulette", &"slots": "Prize Stock", &"money_wheel": "Auction Wheel", &"video_poker": "Ranch Hand Draw", &"faro": "Stockgrowers Faro"},
		"palette": {"stone": Color("c9b18bff"), "metal": Color("ad8b4cff"), "wood": Color("573824ff"), "glass": Color("609284ff"), "lamp": Color("ffe5aeff"), "carpet": Color("5d4934ff"), "felt": Color("4d745cff"), "accent": Color("c39853ff"), "ink": Color("30291fff"), "paper": Color("f2e4c9ff")},
		"reels": ["Hereford", "Saddle", "Auction Gavel", "Water Tank", "Hay Bale", "STOCK"],
		"wheel_emblems": ["The Auction Hall", "Stockgrowers"]},
	&"arcology_fremont": {
		"building": 265, "name": "Fremont Palace", "floor": "The Salvaged Salon",
		"voice": &"assayer", "signature": &"baccarat", "font": "fontdiner", "body_font": "biorhyme",
		"games": {&"blackjack": "Palace Twenty-One", &"roulette": "Grand Salon Roulette", &"slots": "Secondhand Splendor", &"money_wheel": "Crown Wheel", &"video_poker": "Salvaged Draw", &"baccarat": "Palace Baccarat"},
		"palette": {"stone": Color("e9d2acff"), "metal": Color("c5a34fff"), "wood": Color("4a2b30ff"), "glass": Color("508c84ff"), "lamp": Color("ffe7afff"), "carpet": Color("65263eff"), "felt": Color("476e69ff"), "accent": Color("c88f54ff"), "ink": Color("322331ff"), "paper": Color("f8ecd3ff")},
		"reels": ["Chandelier", "Crown", "Velvet Chair", "Marble Column", "Neon Star", "PALACE"],
		"wheel_emblems": ["The Salvaged Salon", "Fremont Palace"]},
}
