# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## City ordinances: the switches, their yearly fees and costs, the demand-side
## tax adjustments and the council's occasional enactment.
## Rules are in docs/simulation/ordinances.md.
class_name OrdinanceSystem
extends SimSystem

var _ctx: SimContext


func _init() -> void:
	key = &"ordinances"


func setup(ctx: SimContext) -> void:
	_ctx = ctx
	_ensure_flags(ctx.stats)
	_refresh_totals(ctx.stats)


# ── Schedule ─────────────────────────────────────────────────────────────

func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_ensure_flags(ctx.stats)
	_council_enactment(ctx)
	_refresh_totals(ctx.stats)


# ── Public queries and controls ──────────────────────────────────────────

## Every ordinance in display order.
func catalog() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in OrdinanceParams.CATALOG:
		var k: StringName = row[0]
		out.append({
			"key": k,
			"name": row[2],
			"group": row[1],
			"description": row[3],
			"estimated_yearly": estimated_yearly(k),
			"enabled": is_enabled(k),
		})
	return out


func is_known(k: StringName) -> bool:
	return OrdinanceParams.YEARLY_RATE.has(k)


func is_enabled(k: StringName) -> bool:
	if _ctx == null:
		return false
	return bool(_ctx.stats.ordinances.get(k, false))


## Flip one ordinance. Unknown keys are ignored.
func set_enabled(k: StringName, on: bool) -> void:
	if _ctx == null or not is_known(k):
		return
	_ctx.stats.ordinances[k] = on
	_refresh_totals(_ctx.stats)


## Yearly dollars for one ordinance at the current population; negative is a cost.
func estimated_yearly(k: StringName) -> int:
	if _ctx == null or not is_known(k):
		return 0
	return _yearly_amount(k, _ctx.stats.total_population())


## {income, cost} in yearly dollars for the enabled ordinances. Read by the budget.
func yearly_totals() -> Dictionary:
	if _ctx == null:
		return {"income": 0, "cost": 0}
	return _totals(_ctx.stats)


## Demand-side tax rates after ordinance adjustments (residential, commercial, industrial).
func effective_tax_rates() -> Vector3i:
	if _ctx == null:
		return Vector3i(7, 7, 7)
	return effective_rates(_ctx.stats)


## The tax rates residents, shops and industry feel: the player's rates shifted
## one point by each enabled ordinance in `DEMAND_TAX_SHIFT`, never below zero.
## Zone demand and the March vote read these; property tax uses the player's rates.
static func effective_rates(stats: CityStats) -> Vector3i:
	var rates := Vector3i(stats.tax_residential, stats.tax_commercial, stats.tax_industrial)
	for k in OrdinanceParams.DEMAND_TAX_SHIFT:
		if not bool(stats.ordinances.get(k, false)):
			continue
		var shift: Array = OrdinanceParams.DEMAND_TAX_SHIFT[k]
		rates += Vector3i(int(shift[0]), int(shift[1]), int(shift[2]))
	return Vector3i(maxi(rates.x, 0), maxi(rates.y, 0), maxi(rates.z, 0))


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	return {}


func load(_data: Dictionary) -> void:
	if _ctx != null:
		_ensure_flags(_ctx.stats)
		_refresh_totals(_ctx.stats)


# ── Rules ────────────────────────────────────────────────────────────────

func _ensure_flags(stats: CityStats) -> void:
	for k in OrdinanceParams.YEARLY_RATE:
		if not stats.ordinances.has(k):
			stats.ordinances[k] = false
		else:
			stats.ordinances[k] = bool(stats.ordinances[k])


func _yearly_amount(k: StringName, population: int) -> int:
	var rate := int(OrdinanceParams.YEARLY_RATE.get(k, 0))
	return population * rate / OrdinanceParams.PER_CAPITA_UNIT


func _totals(stats: CityStats) -> Dictionary:
	var population := stats.total_population()
	var income := 0
	var cost := 0
	for k in OrdinanceParams.YEARLY_RATE:
		if not bool(stats.ordinances.get(k, false)):
			continue
		var amount := _yearly_amount(k, population)
		if amount >= 0:
			income += amount
		else:
			cost -= amount
	return {"income": income, "cost": cost}


func _refresh_totals(stats: CityStats) -> void:
	var totals := _totals(stats)
	stats.ordinance_income = int(totals["income"])
	stats.ordinance_cost = int(totals["cost"])


## A rich city's council sometimes enacts a policy that is not yet in force.
func _council_enactment(ctx: SimContext) -> void:
	if not ctx.stats.disasters_enabled:
		return
	if not ctx.rng.chance(1, OrdinanceParams.COUNCIL_CHANCE_DENOMINATOR):
		return
	if ctx.city.funds <= OrdinanceParams.COUNCIL_RICH_FUNDS + ctx.rng.below(OrdinanceParams.COUNCIL_RICH_SPREAD):
		return
	var open: Array[Array] = []
	for row in OrdinanceParams.CATALOG:
		if not bool(ctx.stats.ordinances.get(row[0], false)):
			open.append(row)
	if open.is_empty():
		return
	var row: Array = open[ctx.rng.below(open.size())]
	var k: StringName = row[0]
	ctx.stats.ordinances[k] = true
	ctx.events.report(&"ordinance_enacted", {"key": k, "name": row[2]})
