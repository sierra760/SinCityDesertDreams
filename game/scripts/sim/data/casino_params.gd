# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for casino play at the gaming resorts.
##
## See docs/simulation/casino.md for the rules these tune. Returns are the
## amounts handed back for a stake of one, including the stake itself.
class_name CasinoParams
extends RefCounted

## Table minimum and table maximum per resort. The minimum keeps a small city
## out of the high-stakes rooms; the maximum caps one round's exposure (the
## treasury caps it further).
const TABLE_LIMITS := {
	&"arcology_comstock": {"minimum": 100, "maximum": 10000},
	&"arcology_junction": {"minimum": 250, "maximum": 25000},
	&"arcology_boulder": {"minimum": 500, "maximum": 50000},
	&"arcology_orbit": {"minimum": 1000, "maximum": 100000},
}

## A month's net, won or lost at one resort, that makes the Dispatch.
const STORY_NET := 25000

## Multiples of the table minimum offered as chips, plus a "Max" chip.
const CHIP_STEPS := [1, 2, 5, 10]

# ── Blackjack ────────────────────────────────────────────────────────────

## Decks in the shoe; more decks make card counting pointless.
const BLACKJACK_DECKS := 6
## Cards left in the shoe that force a reshuffle before the next round.
const BLACKJACK_RESHUFFLE := 52
## A two-card 21 wins numerator/denominator of the stake on top of the stake.
const BLACKJACK_NATURAL_NUMERATOR := 3
const BLACKJACK_NATURAL_DENOMINATOR := 2
## The dealer draws below this total and stands on it, soft or hard.
const BLACKJACK_DEALER_STANDS := 17

# ── Roulette ─────────────────────────────────────────────────────────────

## Pockets on the single-zero wheel: 0 through 36.
const ROULETTE_POCKETS := 37
## The red pockets; every other non-zero pocket is black.
const ROULETTE_RED: Array[int] = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]
## Return per stake by bet group.
const ROULETTE_RETURNS := {
	"straight": 36,
	"even_money": 2,
	"dozens": 3,
	"columns": 3,
}

# ── Slots ────────────────────────────────────────────────────────────────

## Reel strips, top to bottom. s1 is the most common symbol, s5 the rarest,
## B the bonus. With these counts (8/5/3/2/1/1, 8/5/3/2/1/1, 8/6/2/2/1/1) the
## long-run return over all 8,000 stop combinations is 7,281/8,000, about 91%.
const SLOT_STRIPS: Array = [
	["s1", "s2", "s1", "s3", "s1", "s4", "s2", "s1", "B", "s1",
		"s3", "s2", "s1", "s5", "s1", "s2", "s4", "s1", "s3", "s2"],
	["s1", "s3", "s1", "s2", "s4", "s1", "s2", "s1", "s3", "B",
		"s1", "s2", "s5", "s1", "s2", "s1", "s4", "s3", "s1", "s2"],
	["s2", "s1", "s3", "s1", "s2", "s1", "s4", "B", "s1", "s2",
		"s1", "s2", "s5", "s2", "s1", "s4", "s1", "s3", "s2", "s1"],
]
## Symbols in display order: s1..s5, then the bonus.
const SLOT_SYMBOLS: Array[String] = ["s1", "s2", "s3", "s4", "s5", "B"]
## Return for three of a symbol on the line.
const SLOT_TRIPLE_RETURNS := {"B": 200, "s5": 60, "s4": 30, "s3": 15, "s2": 10, "s1": 5}
## Return by number of bonus symbols on the line when there is no triple.
const SLOT_BONUS_RETURNS := {2: 5, 1: 2}

# ── Money wheel ──────────────────────────────────────────────────────────

## The 54 segments clockwise from the top. Emblems sit opposite each other and
## the rare numbers are spread round the rim so the wheel reads well.
const WHEEL_LAYOUT: Array[String] = [
	"emblem_a", "1", "2", "5", "1", "1", "10", "2", "1",
	"2", "5", "1", "1", "20", "2", "1", "2", "5",
	"1", "1", "10", "2", "1", "1", "5", "2", "1",
	"emblem_b", "2", "1", "5", "1", "2", "10", "1", "2",
	"1", "5", "1", "2", "20", "1", "1", "2", "1",
	"2", "1", "10", "1", "2", "1", "5", "2", "1",
]
## Return per stake when the wheel stops on a segment: its number to one.
const WHEEL_RETURNS := {"1": 2, "2": 3, "5": 6, "10": 11, "20": 21, "emblem_a": 41, "emblem_b": 41}

# ── Video poker ──────────────────────────────────────────────────────────

## Jacks or better: return per stake by hand, best first.
const POKER_RETURNS := {
	"royal_flush": 800,
	"straight_flush": 50,
	"four_of_a_kind": 25,
	"full_house": 9,
	"flush": 6,
	"straight": 4,
	"three_of_a_kind": 3,
	"two_pair": 2,
	"jacks_or_better": 1,
	"nothing": 0,
}
## Lowest rank of a pair that still pays (11 = jack); aces always pay.
const POKER_LOW_PAIR := 11

# ── Faro ─────────────────────────────────────────────────────────────────

## Reshuffle before a turn when fewer than this many cards remain.
const FARO_RESHUFFLE := 4

# ── Chuck-a-luck ─────────────────────────────────────────────────────────

## Return for the any-triple bet (30 to 1).
const CHUCK_TRIPLE_RETURN := 31

# ── Baccarat ─────────────────────────────────────────────────────────────

const BACCARAT_DECKS := 8
## Cards left in the shoe that force a reshuffle before the next coup.
const BACCARAT_RESHUFFLE := 52
## The house's cut of a winning banker bet, in percent of the stake.
const BACCARAT_COMMISSION_PERCENT := 5
## Return for a tie bet (8 to 1).
const BACCARAT_TIE_RETURN := 9

# ── Trajectory ───────────────────────────────────────────────────────────

## One launch in this many fails on the pad at 1.00x.
const TRAJECTORY_FAIL_ONE_IN := 33
## Share of the stake returned in the long run by the burn-out curve.
const TRAJECTORY_EDGE := 0.97
## The displayed multiplier climbs as exp(rate x seconds).
const TRAJECTORY_RATE := 0.12
## Highest burn-out multiplier; keeps the curve and the payout finite.
const TRAJECTORY_MAX_MULTIPLIER := 1000.0


## Table limits for a resort, or zeros when the resort is unknown.
static func table_limits(resort: StringName) -> Dictionary:
	var row: Dictionary = TABLE_LIMITS.get(resort, {})
	return {"minimum": int(row.get("minimum", 0)), "maximum": int(row.get("maximum", 0))}
