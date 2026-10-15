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

## Arcology designs: the year each becomes buildable and its overnight guest capacity.
const ARCOLOGIES: Dictionary = {
	&"arcology_comstock": {"year": 2000, "capacity": 1000},
	&"arcology_junction": {"year": 2050, "capacity": 1200},
	&"arcology_boulder": {"year": 2100, "capacity": 1500},
	&"arcology_orbit": {"year": 2150, "capacity": 2000},
	&"arcology_fix": {"technology": &"arcology_comstock", "year": 2000, "capacity": 3200},
	&"arcology_alibi": {"technology": &"arcology_comstock", "year": 2000, "capacity": 1400},
	&"arcology_velvet": {"technology": &"arcology_comstock", "year": 2000, "capacity": 2200},
	&"arcology_afterglow": {"technology": &"arcology_comstock", "year": 2000, "capacity": 5000},
	&"arcology_last": {"technology": &"arcology_comstock", "year": 2000, "capacity": 600},
	&"arcology_dust": {"technology": &"arcology_comstock", "year": 2000, "capacity": 950},
	&"arcology_boddy": {"year": 0, "capacity": 80},
	&"arcology_woolier": {"year": 0, "capacity": 160},
	&"arcology_stockgrowers": {"year": 0, "capacity": 300},
	&"arcology_fremont": {"year": 0, "capacity": 450},
}

## Pollution and crime produced per thousand current tourists.
const POLLUTION_PER_THOUSAND := 2
const CRIME_PER_THOUSAND := 1

## Exodus: the design that launches, how many must stand, the earliest year and
## the compensation credited for every inhabited arcology.
const LAUNCH_KEY := &"arcology_orbit"
const LAUNCH_COUNT := 300
const LAUNCH_YEAR := 2250
const LAUNCH_REFUND := 100000
