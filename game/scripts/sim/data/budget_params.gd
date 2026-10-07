# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for the budget system. See docs/simulation/budget.md.
class_name BudgetParams
extends RefCounted

## Ledger accounts that subtract from the settlement. Any other account is
## treated as signed income, so a negative trade balance subtracts.
const EXPENSE_KEYS: Array[StringName] = [&"ordinance_cost", &"police", &"fire", &"health",
	&"education", &"transport", &"bond_interest", &"other"]

## Assessed base value of a zone building, by category and footprint side
## (1, 2 or 3 tiles). Taxed at the category's rate per year.
const ZONE_VALUE := {
	Buildings.Category.RESIDENTIAL: {1: 40, 2: 180, 3: 500},
	Buildings.Category.COMMERCIAL: {1: 60, 2: 240, 3: 640},
	Buildings.Category.INDUSTRIAL: {1: 50, 2: 200, 3: 560},
}
## Number of stages each footprint group is divided into for assessment.
const STAGES_PER_FOOTPRINT := 3
## Multiplier (in percent) applied to the base value at stages 1..3.
const STAGE_MULTIPLIER := {1: 100, 2: 150, 3: 200}
## Assessed residential value of one arcology.
const ARCOLOGY_VALUE := 3000

## Yearly upkeep in dollars per building at full funding, by building key.
const SERVICE_UPKEEP := {
	&"police_station": 100,
	&"fire_station": 100,
	&"hospital": 50,
	&"school": 25,
	&"college": 100,
}
## Which funding slider scales each service and which account it lands in.
const SERVICE_ACCOUNT := {
	&"police_station": [&"police", &"police"],
	&"fire_station": [&"fire", &"fire"],
	&"hospital": [&"health", &"health"],
	&"school": [&"education", &"schools"],
	&"college": [&"education", &"colleges"],
}

## Yearly upkeep in cents per tile at full funding, by transport category.
## The category names double as the funding slider keys.
const TRANSPORT_UPKEEP_CENTS := {
	&"roads": 10,
	&"highways": 20,
	&"bridges": 25,
	&"rail": 40,
	&"subway": 40,
	&"tunnels": 40,
}

## Cents earned per transit rider.
const FARE_CENTS := 25

## Smallest, largest and default bond the bank will write.
const BOND_MIN := 1000
const BOND_MAX := 100000
const BOND_DEFAULT := 10000
## How many bonds may be outstanding at once.
const MAX_BONDS := 50
## Existing debt raises the credit index by debt × DEBT_WEIGHT / city value.
const DEBT_WEIGHT := 2.5
## The bank refuses to lend once the credit index reaches this value.
const CREDIT_LIMIT := 6

## Range of the prime rate in percent.
const PRIME_MIN := 4
const PRIME_MAX := 10

## Treasury level below which the city is bankrupt.
const BANKRUPTCY_FUNDS := -100000
