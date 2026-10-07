# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Invented desert town names for new cities and the four neighbours.
class_name CityNames
extends RefCounted

const NAMES: Array[String] = [
	"Alkali Springs", "Bitter Creek", "Bonanza Gap", "Buckhorn Wash", "Burro Springs",
	"Cinder Ridge", "Copper Wash", "Coyote Wells", "Creosote Flats", "Dry Gulch",
	"Dustdevil", "Ember Junction", "Furnace Bend", "Gila Crossing", "Glasswater",
	"Greasewood", "Halfmoon Mesa", "Hardpan", "Heliograph Hill", "Ironwood Station",
	"Jackpot Wash", "Kestrel Flats", "Lantern Rock", "Lone Butte", "Lucky Strike",
	"Mesquite Hollow", "Mirage Flats", "Nine Mile Well", "Nugget City", "Ocotillo Crossing",
	"Old Bottle", "Paydirt", "Pinyon Ridge", "Playa Springs", "Prospect Hill",
	"Quicksilver Bend", "Rattler Bend", "Redrock Station", "Rimrock", "Roadrunner Flats",
	"Sagehen", "Salt Cedar", "Sandglass", "Scorpion Wells", "Sidewinder",
	"Silver Mesa", "Slot Canyon City", "Snakebite Springs", "Sunstroke Junction", "Tailings",
	"Tinhorn", "Tortoise Hollow", "Twin Buttes", "Vermilion Wash", "Vulture Gulch",
	"Wagon Rut", "Whiskey Flat", "Windmill Crossing", "Yucca Point", "Zephyr Wells",
]


static func count() -> int:
	return NAMES.size()


## One name at random.
static func random_name(rng: SimRng) -> String:
	return NAMES[rng.below(NAMES.size())]


## `n` distinct names at random, none of them in `exclude`.
static func pick(rng: SimRng, n: int, exclude: Array = []) -> Array[String]:
	var pool: Array[String] = []
	for name in NAMES:
		if not (name in exclude):
			pool.append(name)
	var out: Array[String] = []
	while out.size() < n and not pool.is_empty():
		var i := rng.below(pool.size())
		out.append(pool[i])
		pool.remove_at(i)
	return out


## The four neighbouring towns, distinct from each other and from the city.
static func neighbors(rng: SimRng, city_name: String) -> Array[String]:
	return pick(rng, 4, [city_name])
