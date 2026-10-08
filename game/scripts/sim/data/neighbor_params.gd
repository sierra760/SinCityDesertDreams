# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for the neighbor system. See docs/simulation/neighbors.md.
class_name NeighborParams
extends RefCounted

## Map edges, indexed like stats.neighbor_populations.
const EDGE_NORTH := 0
const EDGE_EAST := 1
const EDGE_SOUTH := 2
const EDGE_WEST := 3
const EDGE_COUNT := 4
const EDGE_NAMES: Array[String] = ["north", "east", "south", "west"]

## Names the four neighbors are drawn from at founding, without repeats.
const NAME_POOL: Array[String] = ["Ironwood Flats", "Pahranagat", "Silverbell", "Mesquite Bend",
	"Coyote Springs", "Amargosa", "Tonopah Wells", "Goldfield Junction", "Searchlight",
	"Beatty Crossing", "Ash Meadows", "Jean Dry Lake"]

## Founding population is the smallest of three draws of MIN + below(SPREAD).
const FOUNDING_MIN := 100
const FOUNDING_SPREAD := 7400
## Founding output is population / (1 + below(OUTPUT_DIVISOR_SPREAD)).
const OUTPUT_DIVISOR_SPREAD := 3

## Monthly growth: rate = economy_phase + below(GROWTH_JITTER) + links × LINK_GROWTH_BONUS;
## change = population × rate / GROWTH_DIVISOR.
const GROWTH_JITTER := 3
const GROWTH_DIVISOR := 1200
const LINK_GROWTH_BONUS := 1
## Populations above this shrink by the change instead of growing.
const POPULATION_CEILING := 5000000
## A month with a growing neighbor brings it a newspaper note once in this many.
const NEWS_CHANCE_DENOMINATOR := 12
## Populations a neighbor makes the newspaper for passing.
const GROWTH_NEWS_MILESTONES: Array[int] = [10000, 25000, 50000, 100000, 250000, 500000, 1000000, 2500000]

## Output growth by national phase (recession .. boom), plus below(OUTPUT_JITTER).
const PHASE_OUTPUT_RATE: Array[int] = [-3, 0, 3, 6]
const OUTPUT_JITTER := 5
const OUTPUT_CEILING := 3500000

## One month in this many, on average, a random neighbor suffers a collapse.
const SHOCK_CHANCE_DENOMINATOR := 64
const SHOCK_POPULATION_PERCENT := 75
const SHOCK_OUTPUT_PERCENT := 50

## Utility trade in cents per unit per year; exports are capped per utility.
const EXPORT_CENTS := {&"power": 2, &"water": 1}
const IMPORT_CENTS := {&"power": 4, &"water": 2}
const TRADE_UNIT_CAP := 20000

## Commercial and industrial demand added each month per road or rail link to
## a neighbor, and the most all links together can add.
const DEMAND_PER_LINK := 10
const LINK_DEMAND_CAP := 40
