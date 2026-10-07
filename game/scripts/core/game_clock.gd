# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Calendar arithmetic and simulation speed.
class_name GameClock
extends RefCounted

const DAYS_PER_MONTH := 25
const MONTHS_PER_YEAR := 12
const DAYS_PER_YEAR := DAYS_PER_MONTH * MONTHS_PER_YEAR

enum Speed { PAUSED, SLOW, MEDIUM, FAST, FASTEST }

const SPEED_NAMES := {
	Speed.PAUSED: "Paused",
	Speed.SLOW: "Slow",
	Speed.MEDIUM: "Medium",
	Speed.FAST: "Fast",
	Speed.FASTEST: "Fastest",
}

## Real seconds per simulated day at each speed.
const SECONDS_PER_DAY := {
	Speed.SLOW: 1.6,
	Speed.MEDIUM: 0.8,
	Speed.FAST: 0.32,
	Speed.FASTEST: 0.08,
}

const MONTH_NAMES: Array[String] = ["January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]

var founded_year := 1900
var day := 0   ## days since founding
var speed := Speed.SLOW


func year() -> int:
	return founded_year + day / DAYS_PER_YEAR


## 1-based month.
func month() -> int:
	return (day % DAYS_PER_YEAR) / DAYS_PER_MONTH + 1


## 1-based day of month.
func day_of_month() -> int:
	return day % DAYS_PER_MONTH + 1


func is_month_end() -> bool:
	return day_of_month() == DAYS_PER_MONTH


func is_year_end() -> bool:
	return day % DAYS_PER_YEAR == DAYS_PER_YEAR - 1


func is_year_start() -> bool:
	return day % DAYS_PER_YEAR == 0


func date_text() -> String:
	return "%s %d" % [MONTH_NAMES[month() - 1], year()]


func advance() -> void:
	day += 1
