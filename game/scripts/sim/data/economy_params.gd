# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for the economy system: the national phase cycle, the
## eleven industry sectors, building values and technology years.
class_name EconomyParams
extends RefCounted

# ── National economy ─────────────────────────────────────────────────────

const PHASE_NAMES: Array[String] = ["Recession", "Slow Growth", "Growth", "Boom"]
## Divisor turning a phase rate into a monthly growth fraction.
const GROWTH_SCALE := 1200
## Monthly rate of the national product in each phase (per GROWTH_SCALE).
const PRODUCT_RATE: Array[int] = [6, 3, 0, -3]
## Above these the national figures shrink at the same rate instead.
const NATION_POPULATION_CAP := 5000000
const NATION_PRODUCT_CAP := 3500000
## One national review per this many months on average.
const REVIEW_CHANCE := 10
## Reviews per phase re-evaluation on average.
const PHASE_CHANGE_CHANCE := 3
## Product-per-head bands: below RATIO_SLOW is recession, below RATIO_GROWTH
## slow growth, below RATIO_BOOM growth, otherwise boom.
const RATIO_SLOW := 45
const RATIO_GROWTH := 60
const RATIO_BOOM := 75
## Starting national population by founding era: [first year, population].
const NATION_START_POPULATION: Array[Array] = [
	[0, 10000], [1951, 25000], [2001, 60000], [2051, 150000],
]

# ── Sectors ──────────────────────────────────────────────────────────────

const SECTOR_KEYS: Array[StringName] = [
	&"steel_mining", &"textiles", &"petrochemical", &"food_processing",
	&"construction", &"automotive", &"aerospace", &"finance", &"media",
	&"electronics", &"tourism",
]
const SECTOR_NAMES: Array[String] = [
	"Steel & Mining", "Textiles", "Petrochemical", "Food Processing",
	"Construction", "Automotive", "Aerospace", "Finance", "Media",
	"Electronics", "Tourism",
]
const SECTOR_COUNT := 11
## Sectors that pollute and suffer under pollution controls.
const HEAVY_SECTORS: Array[int] = [0, 1, 2, 5]
## Sectors that prefer an educated workforce, and those that require one.
const TECH_SECTORS: Array[int] = [2, 5, 7, 8, 6, 9]
const HIGH_TECH_SECTORS: Array[int] = [6, 9]
## Sector that benefits from a growing city.
const CONSTRUCTION_SECTOR := 4

## First row year of the era curve and years between rows.
const ERA_START := 1900
const ERA_LENGTH := 50
## Baseline appeal of each sector per era row; heavy industry gives way to
## electronics, aerospace and tourism as the decades pass.
const ERA_DEMAND: Array[Array] = [
	[24, 22, 8, 14, 16, 4, 0, 12, 6, 0, 8],
	[28, 18, 36, 12, 22, 38, 18, 18, 14, 8, 18],
	[30, 16, 26, 10, 26, 36, 32, 26, 26, 72, 32],
	[18, 14, 18, 10, 22, 28, 42, 32, 42, 78, 44],
	[8, 10, 8, 10, 20, 18, 52, 32, 24, 84, 54],
]

const POLLUTION_CONTROL_SCALE := 0.9
const GROWTH_CONSTRUCTION_SCALE := 1.1
## Education thresholds and the weight scales they apply.
const EQ_HIGH_TECH := 130
const EQ_TECH := 100
const EQ_LOW := 60
const HIGH_TECH_SCALE := 1.2
const TECH_SCALE := 1.1
const LOW_EQ_SCALE := 0.8
## Highest sector tax the Industries window accepts.
const SECTOR_TAX_MAX := 20

## Heavy-industry percent below which the mix counts as clean, and the
## percent per point of pollution modifier above it.
const HEAVY_CLEAN_PERCENT := 20
const HEAVY_DIRTY_STEP := 30
## Largest-sector percent below which there is no demand bonus, and the
## percent per point of bonus above it.
const DOMINANT_PERCENT := 20
const DOMINANT_STEP := 5

# ── City value ───────────────────────────────────────────────────────────

## Value of a developed lot by footprint edge; index 0 unused.
const LOT_VALUE: Array[int] = [0, 50, 400, 1500]
## Abandoned lots keep this fraction of their developed value (1/n).
const ABANDONED_VALUE_DIVISOR := 4
## Value of a reward building, which has no purchase price.
const LANDMARK_VALUE := 5000

# ── Inventions ───────────────────────────────────────────────────────────

## Technology key → base year. The actual year adds a random offset.
const TECHNOLOGIES: Dictionary = {
	&"subway": 1910,
	&"bus": 1920,
	&"highways": 1930,
	&"water_treatment": 1935,
	&"gas_plant": 1955,
	&"nuclear_plant": 1965,
	&"solar_plant": 1990,
	&"desalination": 1990,
	&"microwave_plant": 2020,
	&"fusion_plant": 2050,
	&"arcology_comstock": 2000,
	&"arcology_junction": 2050,
	&"arcology_boulder": 2100,
	&"arcology_orbit": 2150,
}
const TECHNOLOGY_NAMES: Dictionary = {
	&"subway": "Subway",
	&"bus": "Bus Service",
	&"highways": "Highways",
	&"water_treatment": "Water Treatment",
	&"gas_plant": "Gas Power",
	&"nuclear_plant": "Nuclear Power",
	&"solar_plant": "Solar Power",
	&"desalination": "Desalination",
	&"microwave_plant": "Microwave Power",
	&"fusion_plant": "Fusion Power",
	&"arcology_comstock": "Comstock Grand Gaming Resort",
	&"arcology_junction": "Silver Junction Gaming Resort",
	&"arcology_boulder": "Boulder Crown Gaming Resort",
	&"arcology_orbit": "Desert Orbit Gaming Resort",
}
## Random years added to a base year when a city is founded.
const INVENTION_SPREAD := 20
## Building keys gated by a technology. Highway pieces and subway portals are
## matched by prefix in technology_for().
const BUILDING_TECHNOLOGY: Dictionary = {
	&"subway_station": &"subway",
	&"bus_depot": &"bus",
	&"water_treatment": &"water_treatment",
	&"plant_gas": &"gas_plant",
	&"plant_nuclear": &"nuclear_plant",
	&"plant_solar": &"solar_plant",
	&"desalination": &"desalination",
	&"plant_microwave": &"microwave_plant",
	&"plant_fusion": &"fusion_plant",
	&"arcology_comstock": &"arcology_comstock",
	&"arcology_junction": &"arcology_junction",
	&"arcology_boulder": &"arcology_boulder",
	&"arcology_orbit": &"arcology_orbit",
}


## Technology a building needs, or an empty name when it needs none.
static func technology_for(building_key: StringName) -> StringName:
	if BUILDING_TECHNOLOGY.has(building_key):
		return BUILDING_TECHNOLOGY[building_key]
	var text := String(building_key)
	if text.begins_with("highway_") or text.begins_with("onramp_"):
		return &"highways"
	if text.begins_with("subway_"):
		return &"subway"
	return &""


static func phase_name(phase: int) -> String:
	return PHASE_NAMES[clampi(phase, 0, PHASE_NAMES.size() - 1)]


## Starting national population for a city founded in `year`.
static func nation_start_population(year: int) -> int:
	var out := 0
	for row in NATION_START_POPULATION:
		if year >= int(row[0]):
			out = int(row[1])
	return out


## Baseline appeal of every sector in `year`, interpolated between era rows.
static func era_demand(year: int) -> Array[int]:
	var out: Array[int] = []
	var rows := ERA_DEMAND.size()
	var elapsed := maxi(0, year - ERA_START)
	var row := elapsed / ERA_LENGTH
	var remainder := elapsed % ERA_LENGTH
	for i in SECTOR_COUNT:
		if row >= rows - 1:
			out.append(int(ERA_DEMAND[rows - 1][i]))
		else:
			var a := int(ERA_DEMAND[row][i])
			var b := int(ERA_DEMAND[row + 1][i])
			out.append((a * (ERA_LENGTH - remainder) + b * remainder) / ERA_LENGTH)
	return out
