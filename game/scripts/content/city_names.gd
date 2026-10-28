# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Town names for new cities and the four neighbours: our own invented desert
## names together with every real Nevada place name in NevadaPlaceNames.
class_name CityNames
extends RefCounted

## Invented desert town names.
const INVENTED: Array[String] = [
	"Agate Bluff", "Alkali Springs", "Antler Wash", "Ashfall", "Badwater Bend",
	"Basalt Hollow", "Beacon Butte", "Big Thirst", "Bitter Creek", "Blackjack Flats",
	"Blister Rock", "Bonanza Gap", "Boneyard Junction", "Borax Bend", "Brimstone Gulch",
	"Broken Spur", "Buckhorn Wash", "Burro Springs", "Cactus Corners", "Calico Wash",
	"Canteen Springs", "Caprock", "Cardsharp", "Chuckwalla", "Cinder Ridge",
	"Cloudburst", "Comet Flats", "Copper Wash", "Coyote Wells", "Creosote Flats",
	"Crooked Mile", "Crow Wing Mesa", "Desert Rose", "Dice Hollow", "Double Down",
	"Drifting Sands", "Dry Gulch", "Dune Harbor", "Dustdevil", "Dutch Oven Flat",
	"Eagle Tail", "Echo Basin", "Ember Junction", "Fandango", "Fata Morgana",
	"Firefly Mesa", "Flash Flood", "Fool's Gold", "Furnace Bend", "Ghost Mesa",
	"Gila Crossing", "Gilded Wash", "Glasswater", "Gold Dollar", "Greasewood",
	"Greenfelt", "Hackberry Hollow", "Halfmoon Mesa", "Hardpan", "Hatpin Butte",
	"Heat Shimmer", "Heliograph Hill", "High Roller", "Horned Toad", "Hourglass",
	"Ironwood Station", "Jackpot Wash", "Jackrabbit Junction", "Jimson Flats", "Jojoba Flats",
	"Juniper Gap", "Kestrel Flats", "Kiln Hill", "Lantern Rock", "Lariat",
	"Last Chance Wash", "Lodestone", "Lone Butte", "Long Odds", "Lucky Seven",
	"Lucky Strike", "Marquee", "Mesquite Hollow", "Mirage Flats", "Moonshadow",
	"Motor Court", "Neon Wells", "Nickel Slot", "Nine Mile Well", "Nugget City",
	"Oasis Bend", "Ocotillo Crossing", "Old Bottle", "Ore Cart", "Owl Canyon",
	"Packrat Flats", "Painted Dunes", "Paydirt", "Pick and Shovel", "Pinyon Ridge",
	"Playa Springs", "Poker Flat Wash", "Pronghorn", "Prospect Hill", "Quail Run",
	"Quicksilver Bend", "Rainmaker", "Rattler Bend", "Rawhide Wash", "Redrock Station",
	"Rimrock", "Roadrunner Flats", "Rockhound", "Roulette", "Royal Flush",
	"Saddle Notch", "Sagehen", "Salt Cedar", "Sand Dollar", "Sandglass",
	"Scorpion Wells", "Sidewinder", "Silver Dollar Flat", "Silver Mesa", "Skylark Mesa",
	"Slot Canyon City", "Snake Eyes", "Snakebite Springs", "Solar Flats", "Spur Junction",
	"Starlight Wells", "Stovepipe Wash", "Sun Dog", "Sunstroke Junction", "Sweetwater Bend",
	"Tailings", "Tinhorn", "Tortoise Hollow", "Tumbleweed", "Turquoise Trail",
	"Twin Buttes", "Two Bits", "Vermilion Wash", "Vulture Gulch", "Wagon Rut",
	"Whiskey Flat", "Wildcat Wash", "Windmill Crossing", "Wishbone", "Yucca Point",
	"Zephyr Wells",
]

static var _all: Array[String] = []


## Every name, invented ones first, without repeats.
static func all() -> Array[String]:
	if _all.is_empty():
		var seen := {}
		for name in INVENTED + NevadaPlaceNames.NAMES:
			if not seen.has(name):
				seen[name] = true
				_all.append(name)
	return _all


static func count() -> int:
	return all().size()


## One name at random.
static func random_name(rng: SimRng) -> String:
	var names := all()
	return names[rng.below(names.size())]


## Every name except those in `exclude`, in a fresh array.
static func pool(exclude: Array = []) -> Array[String]:
	var out: Array[String] = []
	for name in all():
		if not (name in exclude):
			out.append(name)
	return out


## `n` distinct names at random, none of them in `exclude`.
static func pick(rng: SimRng, n: int, exclude: Array = []) -> Array[String]:
	var names := pool(exclude)
	var out: Array[String] = []
	while out.size() < n and not names.is_empty():
		var i := rng.below(names.size())
		out.append(names[i])
		names.remove_at(i)
	return out


## The four neighbouring towns, distinct from each other and from the city.
static func neighbors(rng: SimRng, city_name: String) -> Array[String]:
	return pick(rng, 4, [city_name])
