# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for the disaster system. See docs/simulation/disasters.md.
class_name DisasterParams
extends RefCounted

## Every disaster kind the system knows.
const KINDS: Array[StringName] = [&"fire", &"flood", &"riot", &"hazard", &"earthquake",
	&"tornado", &"monster", &"meltdown", &"microwave", &"volcano", &"firestorm",
	&"mass_riots", &"major_flood", &"chemical_spill", &"hurricane", &"plane_crash"]

## Kinds that only light fires; they never block another disaster.
const FIRE_ONLY_KINDS: Array[StringName] = [&"fire", &"firestorm"]

## Player-facing names that differ from the capitalised saved key.
const DISPLAY_NAMES: Dictionary = {
	&"monster": "Tsawhawbitts",
	&"hazard": "Toxic Contamination",
	&"microwave": "Microwave Beam",
	&"meltdown": "Nuclear Meltdown",
}

## The name players see for a disaster kind.
static func display_name(kind: StringName) -> String:
	if DISPLAY_NAMES.has(kind):
		return String(DISPLAY_NAMES[kind])
	return String(kind).replace("_", " ").capitalize()

# ── Natural selection ────────────────────────────────────────────────────
## Grace period in months and the monthly denominator of the roll, per difficulty.
const NATURAL_ODDS_BY_DIFFICULTY := {
	City.Difficulty.EASY: 100,
	City.Difficulty.MEDIUM: 60,
	City.Difficulty.HARD: 30,
}
## Every this many residents adds one more chance to the monthly roll.
const POPULATION_PER_EXTRA_CHANCE := 40000
## Relative weight of each kind once its precondition holds.
const NATURAL_WEIGHTS := {
	&"fire": 30, &"flood": 15, &"riot": 10, &"hazard": 8, &"earthquake": 10,
	&"tornado": 15, &"monster": 4, &"meltdown": 3, &"microwave": 3, &"volcano": 2,
	&"firestorm": 4, &"mass_riots": 3, &"major_flood": 4, &"chemical_spill": 6,
	&"hurricane": 8, &"plane_crash": 6,
}
## Riots need crime this high (0..255) or approval this low (percent).
const RIOT_CRIME := 150
const RIOT_APPROVAL := 25
const MASS_RIOT_POPULATION := 30000
## A pollution cell this high can suffer an accident.
const HAZARD_POLLUTION := 150
const MONSTER_POPULATION := 45000
## A city this large can suffer a plane crash without an airport.
const PLANE_CRASH_POPULATION := 45000
## Ground this high somewhere on the map lets a volcano erupt naturally.
const VOLCANO_MIN_PEAK := 24

# ── Fire ─────────────────────────────────────────────────────────────────
## Chance out of SPREAD_DENOMINATOR that a burning neighbor ignites a tile.
const SPREAD_ODDS_BY_CATEGORY := {
	Buildings.Category.TREE: 8,
	Buildings.Category.RESIDENTIAL: 6,
	Buildings.Category.COMMERCIAL: 4,
	Buildings.Category.INDUSTRIAL: 5,
	Buildings.Category.CONSTRUCTION: 6,
	Buildings.Category.ABANDONED: 7,
	Buildings.Category.PLANT: 3,
	Buildings.Category.CIVIC: 2,
	Buildings.Category.UTILITY: 2,
	Buildings.Category.TRANSIT: 3,
	Buildings.Category.PORT: 3,
	Buildings.Category.MILITARY: 2,
	Buildings.Category.REWARD: 2,
	Buildings.Category.ARCOLOGY: 1,
}
const SPREAD_DENOMINATOR := 16
## Larger footprints are sturdier: odds drop by this per tile of width above one.
const SPREAD_FOOTPRINT_PENALTY := 1
## Days a tile burns before it is destroyed, by footprint width.
const FUEL_DAYS_BY_FOOTPRINT := {1: 3, 2: 4, 3: 5, 4: 6}
const FUEL_DAYS_TREES := 3
## Base chance out of 256 per day that a fire goes out untended.
const FIRE_SELF_EXTINGUISH := 5
## Fire coverage (0..255) divided by this is added to the chance out of 256.
const FIRE_COVER_DIVISOR := 2

# ── Emergency crews ──────────────────────────────────────────────────────
const MAX_CREWS := 10
const MILITARY_CREWS := 5
## Tiles from a crew within which it acts.
const CREW_RADIUS := 3
## Chance out of 256 per day that a crew clears a hazard in its radius.
const CREW_FIRE_ODDS := 160
const CREW_POLICE_ODDS := 160
const CREW_MILITARY_ODDS := 112

# ── Riots ────────────────────────────────────────────────────────────────
## Police strength (0..255) that lets a riot disperse on its own.
const RIOT_POLICE_SUPPRESS := 160
## Chance out of 256 per day that a well-policed riot disperses.
const RIOT_DISPERSE_ODDS := 96
const RIOT_WRECK_ODDS := 8
const RIOT_IGNITE_ODDS := 12
const RIOT_SPLIT_ODDS := 6
const RIOT_FADE_ODDS := 40
const RIOT_DAYS := 30
const MASS_RIOT_DAYS := 45
const MASS_RIOT_SEEDS := 6
## Half-width of the square in which mass riots are seeded.
const MASS_RIOT_SPREAD := 16

# ── Earthquake ───────────────────────────────────────────────────────────
## Half-width of the shaken square.
const EARTHQUAKE_RADIUS := 32
const EARTHQUAKE_HIT_ODDS := 6
const EARTHQUAKE_FIRE_ODDS := 4
const EARTHQUAKE_AFTERSHOCK_DAYS := 3

# ── Tornado ──────────────────────────────────────────────────────────────
const TORNADO_STEP := 3
const TORNADO_DAYS := 30
const TORNADO_VANISH_ODDS := 48

# ── Monster ──────────────────────────────────────────────────────────────
const MONSTER_STEP := 3
const MONSTER_HOVER_RADIUS := 6
const MONSTER_WRECK_ODDS := 2
const MONSTER_IGNITE_ODDS := 8
const MONSTER_DAYS := 40
const MONSTER_LEAVE_ODDS := 30

# ── Floods ───────────────────────────────────────────────────────────────
const FLOOD_SEEDS := 4
const MAJOR_FLOOD_SEEDS := 12
const FLOOD_DAYS := 30
const MAJOR_FLOOD_DAYS := 50
const FLOOD_RECEDE_DAYS := 10
const FLOOD_SPREAD_ODDS := 2
const FLOOD_WRECK_ODDS := 6
const FLOOD_DRAIN_ODDS := 3

# ── Hurricane ────────────────────────────────────────────────────────────
const HURRICANE_DAYS := 20
const HURRICANE_RADIUS := 4
const HURRICANE_WRECK_ODDS := 16
const HURRICANE_FLOOD_RADIUS := 6
const HURRICANE_FLOOD_SEEDS := 3
const HURRICANE_FLOOD_DAYS := 40

# ── Plant accidents and contamination ────────────────────────────────────
const MELTDOWN_RADIUS := 24
const MELTDOWN_HIT_ODDS := 24
const MELTDOWN_FIRE_ODDS := 4
const MELTDOWN_DAYS := 12
const SPILL_RADIUS := 4
const SPILL_SCATTER := 8
## Days a freshly contaminated tile keeps spreading.
const CONTAMINATION_SPREAD_DAYS := 6
## Yearly chance (1 in N) that a contaminated tile clears.
const CONTAMINATION_CLEAR_ODDS := 8
## Microwave beam.
const BEAM_STEP := 4
const BEAM_DAYS := 10

# ── Volcano ──────────────────────────────────────────────────────────────
## Levels the vent rises; the cone reaches this many tiles out at one level per ring.
const VOLCANO_RISE := 5
const VOLCANO_DAYS := 10
const VOLCANO_FIRES_PER_DAY := 4
const VOLCANO_EMBER_RADIUS := 16

# ── Plane crash and firestorm ────────────────────────────────────────────
const PLANE_STEP := 8
const FIRESTORM_FIRES := 65

# ── Advisor ──────────────────────────────────────────────────────────────
const USAGE_WARNING_PERCENT := 98
const TRANSIT_PER_RESIDENT := 200
const ADVICE_POPULATION_1 := 1000
const ADVICE_POPULATION_2 := 3000
const ADVICE_POPULATION_3 := 8000
const POLICE_PER_RESIDENT := 20000
const FIRE_PER_RESIDENT := 20000
const HOSPITAL_PER_RESIDENT := 25000
const SCHOOL_PER_RESIDENT := 20000
const SEAPORT_INDUSTRY_TILES := 200
const AIRPORT_COMMERCE_TILES := 150
const RECREATION_PER_RESIDENT := 1000
