# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The city's books: yearly accounts accrued monthly, settled at the January
## review, plus the bond market, the prime rate and the crisis flags.
## Rules are in docs/simulation/budget.md.
class_name BudgetSystem
extends SimSystem

## Accounts this system books itself. Other systems may add their own keys
## (the neighbor system writes &"neighbor_trade"); settlement reads them all.
const OWN_KEYS: Array[StringName] = [&"taxes_residential", &"taxes_commercial",
	&"taxes_industrial", &"taxes_agricultural", &"taxes_occupancy", &"taxes_gaming", &"transit_fares", &"ordinance_income", &"ordinance_cost",
	&"police", &"fire", &"health", &"education", &"transport", &"bond_interest", &"other"]

## Twelfths of a yearly cent; the ledger shows this divided by 1200.
const TWELFTH_CENTS_PER_DOLLAR := 1200

var _ctx: SimContext
## Exact year-to-date amount per account, in twelfths of yearly cents.
var _twelfths: Dictionary = {}
var _settled_year := -1
## Tourism completed periods are booked independently of ordinary annual rates.
var _tourism_booked_month := -1
var _tourism_booking: Dictionary = {}
var _tourism_program_booking: Dictionary = {}
## Separate exact expense fractions; ordinary ordinance fractions still reset annually.
var _tourism_program_carry := 0
var _tourism_money_profile := ""
var _tourism_residue := {"occupancy":0,"gaming":0}
var _deficit_reported := false
var _bankruptcy_reported := false
## Residential, commercial and industrial rates the newspaper last saw; a
## change by the next booking day is reported as tax news.
var _reported_rates := Vector3i(-1, -1, -1)
## Assessed value per building id (0 when the id is not taxed).
var _assessment: PackedInt32Array = PackedInt32Array()
## Tax category per building id: 0 none, 1 residential, 2 commercial, 3 industrial.
var _tax_class: PackedByteArray = PackedByteArray()
var _transport_keys: Array[StringName] = []
var _service_keys: Array[StringName] = []
## The last map survey and the exact layers it read. The budget window asks
## for several estimates per slider tick; an unchanged map reuses one survey.
var _survey_city: City
var _survey_buildings := PackedInt32Array()
var _survey_zones := PackedByteArray()
var _survey_result: Dictionary = {}


func _init() -> void:
	key = &"budget"


func setup(ctx: SimContext) -> void:
	_ctx = ctx
	_build_lookups()
	ctx.stats.prime_rate = clampi(ctx.stats.prime_rate, BudgetParams.PRIME_MIN, BudgetParams.PRIME_MAX)
	_ensure_ledger_keys(ctx.stats)
	if _settled_year < 0:
		_settled_year = ctx.year() - 1
	if _reported_rates.x < 0:
		_reported_rates = _player_rates(ctx.stats)


# ── Schedule ─────────────────────────────────────────────────────────────

func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_report_tax_change(ctx)
	var yearly := _yearly_cents(ctx)
	for k in yearly:
		_twelfths[k] = int(_twelfths.get(k, 0)) + int(yearly[k])
	# Fares are collected for the month just gone, not spread over a year.
	var fares := _monthly_fare_cents(ctx)
	if fares != 0:
		_twelfths[&"transit_fares"] = int(_twelfths.get(&"transit_fares", 0)) + fares * 12
	_book_tourism(ctx)
	_publish_ledger(ctx.stats)
	ctx.stats.city_value = _city_value(ctx.city)
	_check_bankruptcy(ctx)


func yearly(ctx: SimContext) -> void:
	_settle(ctx)


# ── Public queries for the budget window ─────────────────────────────────

## Twelve months of income at the current settings and counts, in dollars.
func estimated_income() -> int:
	var totals := _estimated_totals()
	return int(totals[0])


## Twelve months of expenses at the current settings and counts, in dollars.
func estimated_expenses() -> int:
	var totals := _estimated_totals()
	return int(totals[1])


## Yearly dollars per account at the current settings, for the estimate column.
func estimated_ledger() -> Dictionary:
	var out := {}
	if _ctx == null:
		return out
	var yearly := _estimated_yearly_cents(_ctx)
	for k in yearly:
		out[k] = int(yearly[k]) / 100
	return out


## Latest completed actual booking, in twelfths of a cent; never a forecast.
func tourism_booking() -> Dictionary:
	return _tourism_booking.duplicate(true)


## Read-only annual pace for advisors, using their single current map scan.
## Unlike the Budget window's estimate this never forecasts tourism, surveys
## the city, reconciles agriculture/wear, or claims transit-fare counters.
## Visitor receipts/program costs use the latest completed booking, so this
## is a settings-and-recent-business outlook, not a season/event forecast.
@warning_ignore("integer_division")
func advisor_outlook(counts: PackedInt32Array, tiles: PackedInt32Array, wear_counts: PackedInt32Array) -> Dictionary:
	if _ctx == null: return {}
	var stats := _ctx.stats
	var income := 0
	var expenses := 0
	var rates := [0, stats.tax_residential, stats.tax_commercial, stats.tax_industrial]
	for id in Buildings.COUNT:
		income += counts[id] * _assessment[id] * int(rates[_tax_class[id]])
		var key := _service_keys[id]
		if key != &"":
			var route: Array = BudgetParams.SERVICE_ACCOUNT[key]
			expenses += counts[id] * int(BudgetParams.SERVICE_UPKEEP[key]) * stats.funding_of(route[1])
	# The authoritative jobs share is already published; assessed_value() would
	# reconcile agricultural simulation state on a read.
	income += stats.agricultural_jobs * AgricultureParams.ASSESSMENT_PER_JOB * stats.tax_agricultural
	if _ctx.system(&"wear") != null:
		for cat in TransportParams.CATEGORY_KEYS.size():
			var key: StringName = TransportParams.CATEGORY_KEYS[cat]
			expenses += (wear_counts[cat] * int(TransportParams.UPKEEP_CENTS[key]) / 100) * stats.funding_of(key)
	else:
		for id in Buildings.COUNT:
			var key := _transport_keys[id]
			if key != &"": expenses += tiles[id] * int(BudgetParams.TRANSPORT_UPKEEP_CENTS[key]) * stats.funding_of(key) / 100
	var ordinances := _ctx.system(&"ordinances")
	if ordinances != null:
		var totals: Dictionary = ordinances.call("yearly_totals", false)
		income += int(totals.get("income", 0)) * 100
		expenses += int(totals.get("cost", 0)) * 100
	for bond in stats.bonds: expenses += int(bond.get("principal", 0)) * int(bond.get("rate", 0))
	income += int(_tourism_booking.get("occupancy_units", 0)) + int(_tourism_booking.get("gaming_units", 0))
	if bool(stats.ordinances.get(&"casino_safety", false)):
		expenses += int(_tourism_program_booking.get("half_cents", 0)) * 6
	var transport := _ctx.system(&"transport")
	if transport != null and transport.has_method("monthly_ridership"):
		income += int(transport.call("monthly_ridership")) * BudgetParams.FARE_CENTS * 12
	return {"income": income / 100, "expenses": expenses / 100, "net": (income - expenses) / 100, "visitor_month": int(_tourism_booking.get("month_id", -1))}


## Everything the January review shows.
func review_summary() -> Dictionary:
	if _ctx == null:
		return {}
	var stats := _ctx.stats
	var actual := _split_ledger(stats.last_year_ledger)
	# One set of yearly amounts feeds the estimate column and both totals.
	var yearly := _estimated_yearly_cents(_ctx)
	var estimate := {}
	for k in yearly:
		estimate[k] = int(yearly[k]) / 100
	var totals := _totals_of(yearly)
	return {
		"year": _ctx.year(),
		"settled_year": _settled_year,
		"funds": _ctx.city.funds,
		"last_year_ledger": stats.last_year_ledger.duplicate(),
		"income": actual[0],
		"expenses": actual[1],
		"net": actual[0] - actual[1],
		"estimated_ledger": estimate,
		"estimated_income": int(totals[0]),
		"estimated_expenses": int(totals[1]),
		"bonds": stats.bonds.duplicate(true),
		"total_debt": total_debt(),
		"prime_rate": stats.prime_rate,
		"bond_quote": bond_quote(BudgetParams.BOND_DEFAULT),
		"auto_budget": stats.auto_budget,
		"bankrupt": stats.bankrupt,
	}


## Whether the January review needs the player's attention.
func needs_review() -> bool:
	return _ctx != null and not _ctx.stats.auto_budget


func total_debt() -> int:
	if _ctx == null:
		return 0
	var debt := 0
	for b in _ctx.stats.bonds:
		debt += int(b.get("principal", 0))
	return debt


## Terms the bank offers right now for a bond of `amount`.
func bond_quote(amount: int) -> Dictionary:
	if _ctx == null:
		return {"eligible": false, "reason": "no city"}
	var stats := _ctx.stats
	var clamped := clampi(amount, BudgetParams.BOND_MIN, BudgetParams.BOND_MAX)
	var value := stats.city_value
	var debt := total_debt()
	var credit := int(float(debt) * BudgetParams.DEBT_WEIGHT / float(value + 1))
	var rate := stats.prime_rate + credit + 1
	var reason := ""
	if stats.bonds.size() >= BudgetParams.MAX_BONDS:
		reason = "too many bonds outstanding"
	elif credit >= BudgetParams.CREDIT_LIMIT:
		reason = "debt too high for the city's value"
	elif amount != clamped:
		reason = "amount must be between %s and %s" % [NoticeLines.money(BudgetParams.BOND_MIN),
			NoticeLines.money(BudgetParams.BOND_MAX)]
	return {
		"amount": clamped,
		"rate": rate,
		"yearly_interest": clamped * rate / 100,
		"eligible": reason == "",
		"reason": reason,
		"city_value": value,
		"credit_index": credit,
		"bonds_outstanding": stats.bonds.size(),
		"max_bonds": BudgetParams.MAX_BONDS,
	}


## Borrow `amount` at the quoted rate. Returns false when the bank refuses.
func issue_bond(amount: int = BudgetParams.BOND_DEFAULT) -> bool:
	if _ctx == null:
		return false
	_ctx.stats.city_value = _city_value(_ctx.city)
	var quote := bond_quote(amount)
	if not bool(quote["eligible"]):
		return false
	_ctx.stats.bonds.append({
		"principal": int(quote["amount"]),
		"rate": int(quote["rate"]),
		"age": 0,
		"issued_year": _ctx.year(),
	})
	_ctx.city.funds += int(quote["amount"])
	_ctx.events.report(&"bond_issued", {"amount": int(quote["amount"]), "rate": int(quote["rate"])}, 2)
	return true


## Repay the oldest bond (index 0) when the treasury can cover it.
func repay_bond(index: int = 0) -> bool:
	if _ctx == null or index != 0 or _ctx.stats.bonds.is_empty():
		return false
	var principal := int(_ctx.stats.bonds[0].get("principal", 0))
	if _ctx.city.funds < principal:
		return false
	_ctx.stats.bonds.remove_at(0)
	_ctx.city.funds -= principal
	return true


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	var carry := {}
	for k in _twelfths:
		carry[String(k)] = int(_twelfths[k])
	if _tourism_program_carry > 0:
		carry["ordinance_cost"] = int(carry.get("ordinance_cost", 0)) + _tourism_program_carry
	return {
		"carry": carry,
		"tourism_program_carry": _tourism_program_carry,
		"tourism_money_profile":_tourism_money_profile,"tourism_residue":_tourism_residue.duplicate(),
		"settled_year": _settled_year,
		"tourism_booked_month": _tourism_booked_month,
		"tourism_booking": _tourism_booking.duplicate(true),
		"tourism_program_booking": _tourism_program_booking.duplicate(),
		"deficit_reported": _deficit_reported,
		"bankruptcy_reported": _bankruptcy_reported,
		"reported_rates": [_reported_rates.x, _reported_rates.y, _reported_rates.z],
	}


func load(data: Dictionary) -> void:
	_twelfths.clear()
	var carry: Dictionary = data.get("carry", {})
	for k in carry:
		_twelfths[StringName(k)] = int(carry[k])
	_tourism_money_profile = String(data.get("tourism_money_profile",""))
	var residue: Dictionary = data.get("tourism_residue",{})
	_tourism_residue = {"occupancy":int(residue.get("occupancy",0)),"gaming":int(residue.get("gaming",0))}
	_tourism_program_carry = int(data.get("tourism_program_carry", 0))
	if _tourism_program_carry > 0:
		_twelfths[&"ordinance_cost"] = int(_twelfths.get(&"ordinance_cost", 0)) - _tourism_program_carry
	_settled_year = int(data.get("settled_year", _settled_year))
	_tourism_booked_month = int(data.get("tourism_booked_month", -1))
	_tourism_program_booking = {}
	var program: Dictionary = data.get("tourism_program_booking", {})
	if not program.is_empty():
		_tourism_program_booking = {"month_id": int(program.get("month_id", -1)), "half_cents": int(program.get("half_cents", 0))}
	_tourism_booking = {}
	var booking: Dictionary = data.get("tourism_booking", {})
	if not booking.is_empty():
		_tourism_booking = booking.duplicate(true)
		if _tourism_booking.has("activity"): _tourism_booking.activity = TourismMarkets.integer_activity(_tourism_booking.activity)
		for field in _tourism_booking:
			if field not in ["profile","activity"]: _tourism_booking[field] = int(_tourism_booking[field])
	_deficit_reported = bool(data.get("deficit_reported", false))
	_bankruptcy_reported = bool(data.get("bankruptcy_reported", false))
	var rates: Array = data.get("reported_rates", [])
	if rates.size() == 3:
		_reported_rates = Vector3i(int(rates[0]), int(rates[1]), int(rates[2]))
	elif _ctx != null:
		_reported_rates = _player_rates(_ctx.stats)
	if _ctx != null:
		_ensure_ledger_keys(_ctx.stats)
		_publish_ledger(_ctx.stats)


# ── Settlement ───────────────────────────────────────────────────────────

func _settle(ctx: SimContext) -> void:
	# Simulation closes on December's last day, then advances before review.
	# Both sides of that clock boundary refer to the same completed year.
	var settlement_year := ctx.year()
	if ctx.clock.day > 0 and ctx.clock.is_year_start():
		settlement_year -= 1
	if settlement_year <= _settled_year:
		return
	var stats := ctx.stats
	_publish_ledger(stats)
	var totals := _split_ledger(stats.ledger)
	ctx.city.funds += int(totals[0]) - int(totals[1])
	stats.last_year_ledger = stats.ledger.duplicate()
	stats.ledger = {}
	# Ordinary annual estimates reset; exact tourism fractions span years.
	var tourism_carry := {}
	for k in BudgetParams.TOURISM_KEYS:
		tourism_carry[k] = int(_twelfths.get(k, 0)) % TWELFTH_CENTS_PER_DOLLAR
	_tourism_program_carry %= TWELFTH_CENTS_PER_DOLLAR
	_twelfths = tourism_carry
	_ensure_ledger_keys(stats)
	for b in stats.bonds:
		b["age"] = int(b.get("age", 0)) + 1
	_settled_year = settlement_year
	stats.city_value = _city_value(ctx.city)
	_drift_prime(ctx)
	if ctx.city.funds < 0:
		stats.auto_budget = false
		if not _deficit_reported:
			_deficit_reported = true
			ctx.events.report(&"treasury_deficit", {"funds": ctx.city.funds, "year": ctx.year()})
			ctx.events.notify(&"fiscal_crisis", {"funds": ctx.city.funds, "year": ctx.year()})
	else:
		_deficit_reported = false
	_check_bankruptcy(ctx)


func _drift_prime(ctx: SimContext) -> void:
	var step := 0
	match clampi(ctx.stats.economy_phase, 0, 3):
		0: step = -1
		3: step = 1
		_: step = ctx.rng.below(3) - 1
	ctx.stats.prime_rate = clampi(ctx.stats.prime_rate + step, BudgetParams.PRIME_MIN, BudgetParams.PRIME_MAX)


func _check_bankruptcy(ctx: SimContext) -> void:
	if ctx.city.funds >= BudgetParams.BANKRUPTCY_FUNDS:
		# A recovered treasury ends the bankruptcy; a later collapse is news again.
		ctx.stats.bankrupt = false
		_bankruptcy_reported = false
		return
	ctx.stats.bankrupt = true
	if not _bankruptcy_reported:
		_bankruptcy_reported = true
		ctx.events.notify(&"bankruptcy", {"funds": ctx.city.funds, "debt": total_debt(), "year": ctx.year()})
		ctx.events.report(&"bankruptcy", {"funds": ctx.city.funds}, 3)


static func _player_rates(stats: CityStats) -> Vector3i:
	return Vector3i(stats.tax_residential, stats.tax_commercial, stats.tax_industrial)


## The newspaper reports the first rate the player changed since last month.
func _report_tax_change(ctx: SimContext) -> void:
	var rates := _player_rates(ctx.stats)
	if rates == _reported_rates:
		return
	var families := ["residential", "commercial", "industrial"]
	for i in 3:
		if rates[i] != _reported_rates[i]:
			ctx.events.report(&"tax_change", {"count": rates[i], "family": families[i],
				"previous": _reported_rates[i]}, 1)
			break
	_reported_rates = rates


## [income, expenses] in dollars from a ledger dictionary.
func _split_ledger(ledger: Dictionary) -> Array:
	var income := 0
	var expenses := 0
	for k in ledger:
		var v := int(ledger[k])
		if StringName(k) in BudgetParams.EXPENSE_KEYS:
			expenses += v
		else:
			income += v
	return [income, expenses]


func _estimated_totals() -> Array:
	if _ctx == null:
		return [0, 0]
	return _totals_of(_estimated_yearly_cents(_ctx))


## [income, expenses] in whole dollars from yearly cents per account.
func _totals_of(yearly: Dictionary) -> Array:
	var income := 0
	var expenses := 0
	for k in yearly:
		var dollars := int(yearly[k]) / 100
		if k in BudgetParams.EXPENSE_KEYS:
			expenses += dollars
		else:
			income += dollars
	return [income, expenses]


func _ensure_ledger_keys(stats: CityStats) -> void:
	for k in OWN_KEYS:
		if not stats.ledger.has(k):
			stats.ledger[k] = 0


func _publish_ledger(stats: CityStats) -> void:
	for k in OWN_KEYS:
		stats.ledger[k] = int(_twelfths.get(k, 0)) / TWELFTH_CENTS_PER_DOLLAR
	stats.ledger[&"ordinance_cost"] += _tourism_program_carry / TWELFTH_CENTS_PER_DOLLAR


## Book only immutable completed visitor activity, synchronously with its
## acknowledgement. Property tax/fare callers may repeat without a new month.
func _book_tourism(ctx: SimContext) -> void:
	var tourism := ctx.system(&"tourism")
	if tourism == null:
		return
	var pending: Dictionary = tourism.call("pending_bases")
	if pending.is_empty():
		return
	var month := int(pending.month_id)
	if month <= _tourism_booked_month:
		tourism.call("acknowledge_booking", month)
		return
	if month > ctx.clock.day / GameClock.DAYS_PER_MONTH:
		return
	# Tax at the rates that shaped the month's demand; older pending business
	# without them books at the current rates.
	var occupancy_rate := clampi(int(pending.get("occupancy_rate", ctx.stats.tax_occupancy)),
		TourismParams.TAX_MIN, TourismParams.TAX_MAX)
	var gaming_rate := clampi(int(pending.get("gaming_rate", ctx.stats.tax_gaming)),
		TourismParams.TAX_MIN, TourismParams.TAX_MAX)
	# Completed bases are multiples of 25 cents, so rate * 12 / 100 is exact.
	var occupancy := int(pending.lodging_cents) * occupancy_rate * 12 / 100
	var gaming := int(pending.gaming_cents) * gaming_rate * 12 / 100
	var proof := {}
	if pending.get("profile","") == TourismMarkets.PROFILE:
		_tourism_money_profile = TourismMarkets.PROFILE
		proof = {"profile":TourismMarkets.PROFILE,"activity":tourism.save().activity.duplicate(true)}
		for pair in [["occupancy","lodging_numerator",occupancy_rate],["gaming","gaming_numerator",gaming_rate]]:
			var name: String = pair[0]
			var rate := clampi(int(pair[2]),TourismParams.TAX_MIN,TourismParams.TAX_MAX)
			var opening := int(_tourism_residue[name])
			var exact := TourismMarkets.tax(int(pending[pair[1]]),rate,opening)
			proof[name+"_rate"] = rate
			proof[name+"_opening_residue"] = opening
			proof[name+"_closing_residue"] = exact.residue
			_tourism_residue[name] = exact.residue
			if name == "occupancy": occupancy = exact.units
			else: gaming = exact.units
	_twelfths[&"taxes_occupancy"] = int(_twelfths.get(&"taxes_occupancy", 0)) + occupancy
	_twelfths[&"taxes_gaming"] = int(_twelfths.get(&"taxes_gaming", 0)) + gaming
	var program := int(pending.get("program_half_cents", 0)) * 6
	_tourism_program_carry += program
	_tourism_program_booking = {"month_id": month, "half_cents": int(pending.get("program_half_cents", 0))}
	_tourism_booked_month = month
	_tourism_booking = {"month_id": month, "occupancy_units": occupancy, "gaming_units": gaming}
	_tourism_booking.merge(proof)
	tourism.call("acknowledge_booking", month)


## Estimates annualize the current-month season/event forecast at fixed settings. This dictionary must
## never feed the ordinary monthly accrual loop.
func _estimated_yearly_cents(ctx: SimContext) -> Dictionary:
	var yearly := _yearly_cents(ctx)
	var occupancy := 0
	var gaming := 0
	var tourism := ctx.system(&"tourism")
	if tourism != null:
		var forecast: Dictionary = tourism.call("supported_forecast",-1,-1,true)
		occupancy = int(forecast.get("lodging_cents", 0)) * clampi(ctx.stats.tax_occupancy,
			TourismParams.TAX_MIN, TourismParams.TAX_MAX) * 12 / 100
		gaming = int(forecast.get("gaming_cents", 0)) * clampi(ctx.stats.tax_gaming,
			TourismParams.TAX_MIN, TourismParams.TAX_MAX) * 12 / 100
		if forecast.has("lodging_numerator"):
			occupancy = int(forecast.lodging_numerator)*clampi(ctx.stats.tax_occupancy,0,20)*12/TourismMarkets.TAX_DENOMINATOR
			gaming = int(forecast.gaming_numerator)*clampi(ctx.stats.tax_gaming,0,20)*12/TourismMarkets.TAX_DENOMINATOR
	if tourism != null and bool(ctx.stats.ordinances.get(&"casino_safety", false)):
		yearly[&"ordinance_cost"] += int(tourism.call("program_estimated_annual_cents"))
	yearly[&"taxes_occupancy"] = occupancy
	yearly[&"taxes_gaming"] = gaming
	return yearly


# ── Yearly amounts at current settings ───────────────────────────────────

## Yearly cents per account at the settings and counts in force now.
func _yearly_cents(ctx: SimContext) -> Dictionary:
	var stats := ctx.stats
	var survey := _survey(ctx.city)
	var assessed: PackedInt32Array = survey["assessed"]
	var out := {
		&"taxes_residential": assessed[1] * stats.tax_residential,
		&"taxes_commercial": assessed[2] * stats.tax_commercial,
		&"taxes_industrial": assessed[3] * stats.tax_industrial,
		&"ordinance_income": 0,
		&"ordinance_cost": 0,
		&"police": 0,
		&"fire": 0,
		&"health": 0,
		&"education": 0,
		&"transport": 0,
		&"bond_interest": 0,
		&"other": 0,
	}
	var agriculture := ctx.system(&"agriculture")
	var agricultural_value := 0
	if agriculture != null and agriculture.has_method("assessed_value"):
		agricultural_value = int(agriculture.call("assessed_value"))
	out[&"taxes_agricultural"] = agricultural_value * clampi(stats.tax_agricultural,
		AgricultureParams.TAX_MIN, AgricultureParams.TAX_MAX)
	var services: Dictionary = survey["services"]
	for building_key in BudgetParams.SERVICE_UPKEEP:
		var count := int(services.get(building_key, 0))
		if count == 0:
			continue
		var route: Array = BudgetParams.SERVICE_ACCOUNT[building_key]
		var account: StringName = route[0]
		var funding := stats.funding_of(route[1])
		out[account] = int(out[account]) + count * int(BudgetParams.SERVICE_UPKEEP[building_key]) * funding
	var wear := ctx.system(&"wear")
	var tiles: Dictionary = survey["transport"]
	var transport := 0
	for category in BudgetParams.TRANSPORT_UPKEEP_CENTS:
		var funding := stats.funding_of(category)
		if wear != null and wear.has_method("maintenance_cost"):
			var dollars: int = int(wear.call("maintenance_cost", category))
			transport += dollars * funding
		else:
			transport += int(tiles.get(category, 0)) * int(BudgetParams.TRANSPORT_UPKEEP_CENTS[category]) * funding / 100
	out[&"transport"] = transport
	var ordinances := ctx.system(&"ordinances")
	if ordinances != null and ordinances.has_method("yearly_totals"):
		var totals: Dictionary = ordinances.call("yearly_totals", false)
		out[&"ordinance_income"] = int(totals.get("income", 0)) * 100
		out[&"ordinance_cost"] = int(totals.get("cost", 0)) * 100
	var interest := 0
	for b in stats.bonds:
		interest += int(b.get("principal", 0)) * int(b.get("rate", 0))
	out[&"bond_interest"] = interest
	return out


func _monthly_fare_cents(ctx: SimContext) -> int:
	var transport := ctx.system(&"transport")
	if transport == null or not transport.has_method("monthly_ridership"):
		return 0
	var riders := int(transport.call("monthly_ridership"))
	var tourism := ctx.system(&"tourism")
	if tourism != null: riders += int(tourism.call("claim_transport_riders"))
	return riders * BudgetParams.FARE_CENTS


# ── Map survey ───────────────────────────────────────────────────────────

## One pass over the map: assessed value per tax class, service building
## counts by key, transport tile counts by category. The result depends only
## on the building and zone layers, so it is reused until either changes;
## callers must not modify it.
func _survey(city: City) -> Dictionary:
	var buildings := city.building.data
	var zones := city.zone.data
	if city == _survey_city and not _survey_result.is_empty() \
			and buildings == _survey_buildings and zones == _survey_zones:
		return _survey_result
	var assessed := PackedInt32Array([0, 0, 0, 0])
	var services := {}
	var transport := {&"roads": 0, &"highways": 0, &"bridges": 0, &"rail": 0, &"subway": 0, &"tunnels": 0}
	var multi := UtilityParams.multi_tile_table()
	for i: int in buildings.size():
		var id := buildings[i]
		if id == Buildings.NONE:
			continue
		var anchor: bool = not multi[id] or (zones[i] & Zones.CORNER_NW) != 0
		var tax_class := _tax_class[id]
		if tax_class != 0:
			if anchor:
				assessed[tax_class] += _assessment[id]
			continue
		var category := _transport_keys[id]
		if category != &"":
			transport[category] = int(transport[category]) + 1
			continue
		var bkey := _service_keys[id]
		if bkey != &"" and anchor:
			services[bkey] = int(services.get(bkey, 0)) + 1
	_survey_city = city
	_survey_buildings = buildings.duplicate()
	_survey_zones = zones.duplicate()
	_survey_result = {"assessed": assessed, "services": services, "transport": transport}
	return _survey_result


func _city_value(city: City) -> int:
	# The economy system assesses the city on day 16; reuse its figure so the
	# two never disagree. Fall back to a direct count before its first pass.
	if _ctx != null:
		var economy: SimSystem = _ctx.system(&"economy")
		if economy != null and economy.has_method("assessed_value"):
			var assessed: int = economy.call("assessed_value")
			if assessed > 0:
				return assessed
	var value := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var id := city.building.at(x, y)
			if id == Buildings.NONE or Buildings.is_zone_building(id) or Buildings.is_agricultural(id):
				continue
			if Buildings.is_network(id):
				value += Buildings.cost(id)
			elif Buildings.is_developed(id) and _is_anchor(city, x, y, id):
				value += Buildings.cost(id)
	if _ctx != null:
		var agriculture := _ctx.system(&"agriculture")
		if agriculture != null and agriculture.has_method("assessed_value"):
			value += int(agriculture.call("assessed_value"))
	return value


static func _is_anchor(city: City, x: int, y: int, id: int) -> bool:
	if not Buildings.is_multi_tile(id):
		return true
	return (Zones.corners(city.zone.at(x, y)) & Zones.CORNER_NW) != 0


static func _transport_category(id: int) -> StringName:
	if id >= Buildings.ROAD_FIRST and id <= Buildings.ROAD_LAST:
		return &"roads"
	if id >= Buildings.CROSSING_FIRST and id <= Buildings.CROSSING_LAST:
		return &"rail" if Buildings.is_rail_like(id) and not Buildings.is_road_like(id) else &"roads"
	if id >= Buildings.RAIL_FIRST and id <= Buildings.RAIL_LAST:
		return &"rail"
	if id >= Buildings.SUBWAY_PORTAL_FIRST and id <= Buildings.SUBWAY_PORTAL_LAST:
		return &"rail"
	if id == Buildings.SUBWAY_STATION:
		return &"subway"
	if id >= Buildings.TUNNEL_FIRST and id <= Buildings.TUNNEL_LAST:
		return &"tunnels"
	if id >= Buildings.HIGHWAY_FIRST and id <= Buildings.HIGHWAY_LAST:
		return &"highways"
	if id >= Buildings.ONRAMP_FIRST and id <= Buildings.HIGHWAY_PIECE_LAST:
		return &"highways"
	if id >= Buildings.BRIDGE_FIRST and id <= Buildings.BRIDGE_LAST:
		# An elevated power line over water is a power line, not a bridge.
		if not Buildings.is_road_like(id) and not Buildings.is_rail_like(id):
			return &""
		return &"bridges"
	if id == Buildings.REINFORCED_PYLON or id == Buildings.REINFORCED_BRIDGE:
		return &"bridges"
	return &""


## Assessed value and tax class per building id, derived once from the
## roster: base value by category and footprint, times the stage multiplier.
func _build_lookups() -> void:
	_transport_keys.resize(Buildings.COUNT)
	_service_keys.resize(Buildings.COUNT)
	for id: int in Buildings.COUNT:
		_transport_keys[id] = _transport_category(id)
		var bkey := Buildings.key(id)
		_service_keys[id] = bkey if BudgetParams.SERVICE_UPKEEP.has(bkey) else &""
	_assessment.resize(Buildings.COUNT)
	_tax_class.resize(Buildings.COUNT)
	_assessment.fill(0)
	_tax_class.fill(0)
	var groups := [
		[Zones.RES_HIGH, 1, Buildings.Category.RESIDENTIAL, 1],
		[Zones.RES_HIGH, 2, Buildings.Category.RESIDENTIAL, 1],
		[Zones.RES_HIGH, 3, Buildings.Category.RESIDENTIAL, 1],
		[Zones.COM_HIGH, 1, Buildings.Category.COMMERCIAL, 2],
		[Zones.COM_HIGH, 2, Buildings.Category.COMMERCIAL, 2],
		[Zones.COM_HIGH, 3, Buildings.Category.COMMERCIAL, 2],
		[Zones.IND_HIGH, 1, Buildings.Category.INDUSTRIAL, 3],
		[Zones.IND_HIGH, 2, Buildings.Category.INDUSTRIAL, 3],
		[Zones.IND_HIGH, 3, Buildings.Category.INDUSTRIAL, 3],
	]
	for g in groups:
		var ids := Buildings.zone_stage_ids(g[0], g[1])
		var base: int = BudgetParams.ZONE_VALUE[g[2]][g[1]]
		for i in ids.size():
			var stage := 1 + i * BudgetParams.STAGES_PER_FOOTPRINT / ids.size()
			var percent: int = BudgetParams.STAGE_MULTIPLIER[stage]
			_assessment[ids[i]] = base * percent / 100
			_tax_class[ids[i]] = g[3]
