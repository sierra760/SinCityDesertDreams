# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Typed cheat codes. They only run when the player enters one, never from the
## daily schedule. Effects use ordinary city, stats and system state, so they
## persist through saves.
extends RefCounted

const Lines := preload("res://scripts/content/cheat_lines.gd")

## DOUBLEDOWN stakes this share of the treasury, clamped to the table limits.
const BET_PERCENT := 10
const BET_MINIMUM := 100
const BET_MAXIMUM := 25000
## Out of 100: rolls below FIRE_ROLLS start a firestorm, the next WIN_ROLLS
## double the stake and the rest lose it. The house keeps a small edge.
const FIRE_ROLLS := 3
const WIN_ROLLS := 47

const MARKER_PRINCIPAL := 25000
const MARKER_RATE := 20
const JACKPOT_FUNDS := 500000

static func redeem(ctx: SimContext, code: String) -> Dictionary:
	if ctx == null or ctx.city == null:
		return Lines.result(false, "The casino isn't open yet", "Found or load a city before you place a bet.")
	var kind: StringName = Lines.CODES.get(code.strip_edges().to_lower(), &"")
	match kind:
		&"bet":
			return _double_down(ctx)
		&"jackpot":
			ctx.city.funds += JACKPOT_FUNDS
			for tech in EconomyParams.TECHNOLOGIES:
				ctx.stats.inventions[tech] = ctx.year()
			for tool in Tools.all():
				var tech := Tools.invention_key(tool)
				if tech != &"": ctx.stats.inventions[tech] = ctx.year()
			var rewards: SimSystem = ctx.systems.get(&"rewards")
			if rewards != null: rewards.call("unlock_for_cheat")
			return Lines.result(true, "The whale has landed", "A high roller lost big at your tables and tipped the city %s, every invention and every gift permit. Place the gifts yourself; gifts already standing stay claimed." % Lines.money(JACKPOT_FUNDS))
		&"marker":
			if ctx.stats.bonds.size() >= BudgetParams.MAX_BONDS:
				return Lines.result(false, "Marker declined", "The cage says you already have the maximum number of outstanding bonds. Pay one off first.")
			ctx.stats.bonds.append({"principal": MARKER_PRINCIPAL, "rate": MARKER_RATE, "age": 0, "issued_year": ctx.year()})
			ctx.city.funds += MARKER_PRINCIPAL
			return Lines.result(true, "Your marker is good here", "The cashier's cage advanced %s at %d%% a year: %s a year until you repay it in Budget. They know where City Hall is." % [Lines.money(MARKER_PRINCIPAL), MARKER_RATE, Lines.money(MARKER_PRINCIPAL * MARKER_RATE / 100)])
		&"chapel":
			return Lines.result(true, "Little Neon Chapel of the Desert", Lines.CHAPEL)
	return Lines.result(false, "No such game", "No such game at this casino. The pit boss is watching you.")


## What a DOUBLEDOWN roll of 0..99 means: &"fire", &"win" or &"lose".
static func bet_outcome(roll: int) -> StringName:
	if roll < FIRE_ROLLS: return &"fire"
	if roll < FIRE_ROLLS + WIN_ROLLS: return &"win"
	return &"lose"


## Stake for a treasury, or 0 when it can't cover the table minimum.
static func bet_stake(funds: int) -> int:
	if funds < BET_MINIMUM: return 0
	return clampi(funds * BET_PERCENT / 100, BET_MINIMUM, BET_MAXIMUM)


static func _double_down(ctx: SimContext) -> Dictionary:
	var stake := bet_stake(ctx.city.funds)
	if stake == 0:
		return Lines.result(false, "Table minimum", "The table minimum is %s. Come back when the treasury can cover it." % Lines.money(BET_MINIMUM))
	match bet_outcome(ctx.rng.below(100)):
		&"fire":
			var disaster: SimSystem = ctx.systems.get(&"disasters")
			if disaster != null and bool(disaster.call("request", ctx, &"firestorm")):
				return Lines.result(true, "Hot streak", "The tables got so hot the casino caught fire. No chips changed hands, and the fire department is comping nobody.")
			return Lines.result(false, "Hot streak, cold town", "The dice came up firestorm, but nothing in town would burn. The pit boss slides your %s back across the felt." % Lines.money(stake))
		&"win":
			ctx.city.funds += stake
			return Lines.result(true, "Dealer busts", "The city bet %s of the treasury and doubled it. The council is already planning a second trip." % Lines.money(stake))
	ctx.city.funds -= stake
	return Lines.result(true, "House rules", "The dealer had 21. %s of the treasury stays at the table." % Lines.money(stake))
