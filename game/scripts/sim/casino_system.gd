# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The mayor's casino play: table limits, treasury transactions, a ledger per
## resort and the Dispatch stories about it.
##
## The only writer of `city.funds` for play. Game logic lives in
## scripts/casino/ and never touches the city; it draws from its own
## CasinoRng, so the simulation's random stream is untouched.
## See docs/simulation/casino.md.
class_name CasinoSystem
extends SimSystem

const LEDGER_FIELDS: Array[String] = ["rounds", "staked", "returned", "best_win", "worst_loss",
	"month_net", "year_net", "last_day"]

## resort key -> ledger (see LEDGER_FIELDS)
var _ledgers: Dictionary = {}
var _debut_reported := false


func _init() -> void:
	key = &"casino"
	_reset_ledgers()


## Day 22, before the newspaper prints: month stories, then month nets reset.
func monthly(ctx: SimContext, _phase: int = 0) -> void:
	for resort in ResortThemes.keys():
		var row: Dictionary = _ledgers[resort]
		var net := int(row["month_net"])
		if net >= CasinoParams.STORY_NET:
			ctx.events.report(&"casino_windfall", {"place": ResortThemes.resort_name(resort), "amount": net})
		elif net <= -CasinoParams.STORY_NET:
			ctx.events.report(&"casino_losses", {"place": ResortThemes.resort_name(resort), "amount": -net})
		row["month_net"] = 0


func yearly(_ctx: SimContext) -> void:
	for resort in _ledgers:
		_ledgers[resort]["year_net"] = 0


# ── Limits ───────────────────────────────────────────────────────────────

## {minimum, maximum}: the table minimum, and the smaller of the table maximum
## and the treasury. Zeros for an unknown resort.
func limits(resort: StringName, funds: int) -> Dictionary:
	var table := CasinoParams.table_limits(resort)
	if not ResortThemes.has(resort):
		return {"minimum": 0, "maximum": 0}
	return {"minimum": int(table["minimum"]), "maximum": clampi(funds, 0, int(table["maximum"]))}


## {ok, reason}: refuses an unknown resort and a treasury below the minimum
## (the reason names the minimum and the treasury).
func can_play(resort: StringName, funds: int) -> Dictionary:
	if not ResortThemes.has(resort):
		return {"ok": false, "reason": CasinoLines.UNKNOWN_RESORT}
	var minimum := int(CasinoParams.table_limits(resort)["minimum"])
	if funds < minimum:
		return {"ok": false, "reason": CasinoLines.no_credit(minimum, funds)}
	return {"ok": true, "reason": ""}


# ── Transactions ─────────────────────────────────────────────────────────

## Debit `staked` from the treasury. False, with nothing changed, for an
## unknown resort or game, a stake of zero or less, or one over the treasury.
func commit_round(ctx: SimContext, resort: StringName, game: StringName, staked: int) -> bool:
	if ctx == null or ctx.city == null:
		return false
	if not ResortThemes.offers(resort, game):
		return false
	if staked <= 0 or staked > ctx.city.funds:
		return false
	ctx.city.funds -= staked
	return true


## Credit `returned` and record the round (`staked` is the round total).
func settle_round(ctx: SimContext, resort: StringName, game: StringName, staked: int, returned: int) -> void:
	if ctx == null or ctx.city == null or not ResortThemes.offers(resort, game):
		return
	var paid := maxi(0, returned)
	var stake := maxi(0, staked)
	ctx.city.funds += paid
	var row: Dictionary = _ledgers[resort]
	var net := paid - stake
	row["rounds"] = int(row["rounds"]) + 1
	row["staked"] = int(row["staked"]) + stake
	row["returned"] = int(row["returned"]) + paid
	row["month_net"] = int(row["month_net"]) + net
	row["year_net"] = int(row["year_net"]) + net
	row["best_win"] = maxi(int(row["best_win"]), net)
	row["worst_loss"] = mini(int(row["worst_loss"]), net)
	row["last_day"] = ctx.clock.day if ctx.clock != null else 0
	if not _debut_reported:
		_debut_reported = true
		ctx.events.report(&"casino_debut", {"place": ResortThemes.resort_name(resort), "amount": net})


## Credit `staked` back without a ledger entry (a round abandoned mid-play).
func refund_round(ctx: SimContext, resort: StringName, game: StringName, staked: int) -> void:
	if ctx == null or ctx.city == null or not ResortThemes.offers(resort, game) or staked <= 0:
		return
	ctx.city.funds += staked


# ── Ledger ───────────────────────────────────────────────────────────────

## A copy of a resort's ledger; zeros for an unknown resort.
func ledger(resort: StringName) -> Dictionary:
	if _ledgers.has(resort):
		var row: Dictionary = _ledgers[resort]
		return row.duplicate()
	return _empty_ledger()


## All resorts together: sums, the best win, the worst loss, the latest day.
func total_ledger() -> Dictionary:
	var total := _empty_ledger()
	for resort in _ledgers:
		var row: Dictionary = _ledgers[resort]
		for field in ["rounds", "staked", "returned", "month_net", "year_net"]:
			total[field] = int(total[field]) + int(row[field])
		total["best_win"] = maxi(int(total["best_win"]), int(row["best_win"]))
		total["worst_loss"] = mini(int(total["worst_loss"]), int(row["worst_loss"]))
		total["last_day"] = maxi(int(total["last_day"]), int(row["last_day"]))
	return total


## True once the first round has been settled and reported.
func has_debuted() -> bool:
	return _debut_reported


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	var rows := {}
	for resort in _ledgers:
		var row: Dictionary = _ledgers[resort]
		rows[String(resort)] = row.duplicate()
	return {"ledgers": rows, "debut": _debut_reported}


func load(data: Dictionary) -> void:
	_reset_ledgers()
	var rows: Variant = data.get("ledgers", {})
	if typeof(rows) == TYPE_DICTIONARY:
		var saved: Dictionary = rows
		for resort in ResortThemes.keys():
			var item: Variant = saved.get(String(resort), {})
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var source: Dictionary = item
			var row: Dictionary = _ledgers[resort]
			for field in LEDGER_FIELDS:
				row[field] = int(source.get(field, 0))
	_debut_reported = bool(data.get("debut", false))


func _reset_ledgers() -> void:
	_ledgers.clear()
	for resort in ResortThemes.keys():
		_ledgers[resort] = _empty_ledger()


static func _empty_ledger() -> Dictionary:
	var row := {}
	for field in LEDGER_FIELDS:
		row[field] = 0
	return row
