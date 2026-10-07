# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for rewards, arcologies and the military base.
##
## See docs/simulation/rewards.md for the rules these tune.
class_name RewardParams
extends RefCounted

## Gifts in the order they are earned, with the ordinary population that
## unlocks each. Keys are building keys, except the military milestone.
const MILESTONES: Array[Dictionary] = [
	{"key": &"mayors_residence", "population": 2000},
	{"key": &"city_hall", "population": 10000},
	{"key": &"monument", "population": 30000},
	{"key": &"military_base", "population": 60000},
	{"key": &"neon_dome", "population": 120000},
]

## The milestone that proposes a base instead of a gift.
const MILITARY_KEY := &"military_base"

## Side of the square site sought for land and naval bases.
const MILITARY_SITE_SIZE := 8
## Random origins tried before giving up on a square site.
const MILITARY_SITE_ATTEMPTS := 24
## Usable tiles a square site must contain.
const MILITARY_SITE_MIN_USABLE := 40
## Usable tiles touching open water that a naval site must contain.
const MILITARY_NAVAL_MIN_SHORE := 6
## Silo squares sought for a missile base, and their side.
const MILITARY_MISSILE_SITES := 6
const MILITARY_MISSILE_SITE_SIZE := 3
## Random origins tried while collecting silo squares.
const MILITARY_MISSILE_ATTEMPTS := 40

## Arcology designs: the year each becomes buildable and its resident capacity.
const ARCOLOGIES: Dictionary = {
	&"arcology_comstock": {"year": 2000, "capacity": 55000},
	&"arcology_junction": {"year": 2050, "capacity": 30000},
	&"arcology_boulder": {"year": 2100, "capacity": 45000},
	&"arcology_orbit": {"year": 2150, "capacity": 65000},
}

## Condition (desirability) scale: base value and how many map points move it
## by one.
const DESIRABILITY_BASE := 12
const DESIRABILITY_DIVISOR := 32

## Tax factor: (TAX_FACTOR_BASE - sum of the three tax rates) / TAX_FACTOR_DIVISOR.
const TAX_FACTOR_BASE := 60
const TAX_FACTOR_DIVISOR := 6

## Yearly intake caps: a share of capacity, and a share of the ordinary
## population divided among all arcologies.
const INTAKE_CAPACITY_SHARE := 10
const INTAKE_CITY_SHARE := 20
## Intake per point of (tax factor + condition), less a fixed deduction.
const INTAKE_PER_POINT := 200
const INTAKE_OFFSET := 2000
## Existing residents grow by this share each year.
const RETENTION_GROWTH_SHARE := 50
## Random residents (0 .. JITTER-1) added to every growing arcology.
const INTAKE_JITTER := 64

## Pollution and crime produced per thousand arcology residents.
const POLLUTION_PER_THOUSAND := 2
const CRIME_PER_THOUSAND := 1

## Exodus: the design that launches, how many must stand, the earliest year and
## the compensation credited for every inhabited arcology.
const LAUNCH_KEY := &"arcology_orbit"
const LAUNCH_COUNT := 300
const LAUNCH_YEAR := 2250
const LAUNCH_REFUND := 100000
