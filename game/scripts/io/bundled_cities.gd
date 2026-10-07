# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Player-supplied cities included with the game, available on every platform.
## Each ships as a fully imported native save; regenerate them with
## `tools/build_bundled_cities.py` (classic sources stay out of exports).
extends RefCounted

const NAMES: Array[String] = [
	"Adaven",
	"Aliso Niguel",
	"Foothills Ranch",
	"Grant Pass - Soledad",
	"La Presa",
	"Lawndale",
	"Oro Canyon",
	"Salton Shores",
	"Valle del Mar",
]


## Resource paths let the native loader open these cities inside a package.
static func entries() -> Array[Dictionary]:
	var cities: Array[Dictionary] = []
	for city_name: String in NAMES:
		cities.append({"name":city_name, "path":"res://assets/cities/%s.%s" % [city_name, SaveFormat.EXTENSION]})
	return cities
