# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for the statistics system.
class_name StatisticsParams
extends RefCounted

## Monthly samples kept per series: a century of history.
const KEEP_MONTHS := 1200

## Year spans the Graphs window offers; a request is rounded up to one of these.
const WINDOWS: Array[int] = [1, 10, 100]

## Clamp for the funds series so it fits an integer sample.
const MONEY_MIN := -2147483648
const MONEY_MAX := 2147483647

## Settlement class labels indexed by City.status; larger statuses use the last.
const STATUS_NAMES: Array[String] = [
	"Village", "Town", "City", "Capital", "Metropolis", "Megalopolis",
]

## Series names in Graphs-window order.
const SERIES: Array[StringName] = [
	&"population", &"residents", &"commercial", &"industrial", &"money",
	&"crime", &"pollution", &"land_value", &"traffic",
	&"power_percent", &"water_percent", &"unemployment", &"health", &"education",
	&"demand_residential", &"demand_commercial", &"demand_industrial",
	&"transit_riders",
]
