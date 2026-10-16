# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Pure validation shared by local/cloud saves and detached restoration.
class_name TourismSaveCodec
extends RefCounted

static func problem(snapshot: Dictionary, city: City = null) -> String:
	var systems: Variant = snapshot.get("systems", {})
	var stats: Variant = snapshot.get("stats", {})
	if not systems is Dictionary or not stats is Dictionary:
		return "Invalid tourism snapshot containers."
	for field in ["tax_occupancy", "tax_gaming"]:
		if stats.has(field) and not TourismState._integer(stats[field], TourismParams.TAX_MIN, TourismParams.TAX_MAX):
			return "Invalid tourism tax rate: " + field
	for field in ["tourists", "tourist_guests", "tourist_day_visitors", "tourist_capacity", "tourist_lodging_cents", "tourist_gaming_cents"]:
		if stats.has(field) and not TourismState._integer(stats[field], 0, TourismState.MAX_INSTANCE):
			return "Invalid tourism aggregate: " + field
	if stats.has("tourist_occupancy") and not TourismState._integer(stats.tourist_occupancy, 0, 100):
		return "Invalid tourism occupancy percentage."
	if stats.has("tourist_reputation_milli") and not TourismState._integer(stats.tourist_reputation_milli,0,100000):
		return "Invalid destination reputation score."
	var histories: Variant=stats.get("history",{})
	if histories is Dictionary and histories.has("tourist_reputation"):
		var samples: Variant=histories["tourist_reputation"]
		if not (samples is Array or samples is PackedInt32Array) or samples.size()>StatisticsParams.KEEP_MONTHS:
			return "Invalid destination reputation history."
		for sample: Variant in samples:
			if not TourismState._integer(sample,0,100000): return "Invalid destination reputation history score."
	var budget: Variant = systems.get("budget", {})
	if not budget is Dictionary:
		return "Invalid tourism budget."
	var current: bool = systems.has("tourism")
	# Legacy files have no completed tourism activity and never earn back taxes.
	if not current:
		if budget.get("tourism_program_booking", {}) != {} or budget.get("tourism_program_carry", 0) != 0:
			return "Tourism program expense has no attendance history."
		if budget.get("tourism_money_profile", "") != "":
			return "Tourism residue has no attendance history."
		var residue: Variant = budget.get("tourism_residue",{"occupancy":0,"gaming":0})
		if not residue is Dictionary or residue.size()!=2 or not TourismState._integer(residue.get("occupancy"),0,0) or not TourismState._integer(residue.get("gaming"),0,0): return "Tourism residue has no attendance history."
		if budget.get("tourism_booked_month", -1) != -1 or budget.get("tourism_booking", {}) != {}:
			return "Tourism booking has no attendance history."
		var carry: Variant = budget.get("carry", {})
		if not carry is Dictionary:
			return "Invalid budget carry."
		for key in BudgetParams.TOURISM_KEYS:
			if carry.get(String(key), 0) != 0:
				return "Tourism carry has no attendance history."
		return ""
	var day: Variant = snapshot.get("clock_day", city.day if city != null else null)
	if not TourismState._integer(day, 0, TourismParams.MAX_COUNT):
		return "Invalid tourism calendar day."
	var closing_review := bool(snapshot.get("budget_review_pending", false)) and int(day) % GameClock.DAYS_PER_YEAR == GameClock.DAYS_PER_YEAR - 1
	if city != null and city.day != int(day) and not (closing_review and city.day == int(day) + 1):
		return "Tourism snapshot and city calendars disagree."
	@warning_ignore("integer_division")
	var month: int = int(day) / GameClock.DAYS_PER_MONTH
	var block: Variant = systems.tourism
	if not block is Dictionary or block.is_empty():
		return "Invalid tourism block."
	var period := TourismSystem.validate_period(block, month, budget)
	if not period.ok:
		return "Invalid tourism period, activity, or pending business."
	if int(block.last_month) == month and int(day) % GameClock.DAYS_PER_MONTH < TourismParams.MONTHLY_DAY - 1:
		return "Tourism activity predates its scheduled monthly calculation."
	var state: Variant = block.get("state")
	if not state is Dictionary or not TourismState._integer(state.get("schema"), 1, TourismState.SCHEMA):
		return "Unsupported tourism state schema."
	if not TourismState._integer(state.get("next_instance"), 1, TourismState.MAX_INSTANCE):
		return "Invalid tourism instance counter."
	var rows := TourismState._validate_rows(state.get("records"), true, int(state.schema) == 1)
	if not rows.ok:
		return rows.error
	var identities := {}
	for row: Dictionary in rows.rows:
		identities[row.instance] = [row.anchor.x, row.anchor.y, String(row.key), row.code]
		if row.instance >= int(state.next_instance):
			return "Tourism instance counter does not cover attendance."
	for row: Dictionary in block.get("activity", {}).get("rows", []):
		if int(row.instance) >= int(state.next_instance):
			return "Tourism instance counter does not cover earned activity."
		var identity := [int(row.anchor[0]), int(row.anchor[1]), String(row.key), int(row.code)]
		if identities.has(int(row.instance)) and identities[int(row.instance)] != identity:
			return "Tourism attendance and activity disagree about a lot instance."
		# Earned activity remains authoritative for its token after attendance
		# has been pruned; a replacement cannot reuse that historical identity.
		identities[int(row.instance)] = identity
	if city != null:
		var decoded := TourismState.decode(state, city, month)
		if not decoded.ok:
			return decoded.error
		var used := {}
		for anchor: Vector2i in city.facilities:
			var facility: Dictionary = city.facilities[anchor]
			if not facility.has("tourism_instance"): continue
			var token: Variant = facility.tourism_instance
			if not TourismState._integer(token, 1, int(state.next_instance) - 1) or used.has(int(token)):
				return "Invalid or duplicate facility tourism identity."
			used[int(token)] = true
			var code := city.building_at(anchor.x, anchor.y)
			if code > 0 and TourismState._standing(city, anchor, code) and identities.has(int(token)):
				# Use the standing lot's actual roster identity, not metadata that
				# could still describe the demolished venue. Missing old lots are
				# allowed: their completed business remains valid earned revenue.
				var identity := [anchor.x, anchor.y, String(Buildings.key(code)), code]
				if identities[int(token)] != identity:
					return "Live facility reuses another tourism lot's identity."
	return _budget_problem(budget, block, int(day), city, bool(snapshot.get("budget_review_pending", false)))


static func _budget_problem(budget: Dictionary, block: Dictionary, day: int, city: City, review: bool) -> String:
	var booked := int(budget.get("tourism_booked_month", -1))
	var booking: Variant = budget.get("tourism_booking", {})
	if not booking is Dictionary:
		return "Invalid latest tourism booking."
	if (booked == -1) != booking.is_empty():
		return "Tourism booking and booked-month guard disagree."
	var money_profile: Variant = budget.get("tourism_money_profile", "")
	if money_profile not in ["",TourismMarkets.PROFILE]: return "Invalid tourism money profile."
	var segmented: bool = money_profile == TourismMarkets.PROFILE
	var residue: Variant = budget.get("tourism_residue",{"occupancy":0,"gaming":0})
	if not residue is Dictionary or residue.size() != 2: return "Invalid tourism subunit residue."
	for name in ["occupancy","gaming"]:
		if not TourismState._integer(residue.get(name),0,TourismMarkets.TAX_DENOMINATOR-1): return "Invalid tourism subunit residue."
		if not segmented and int(residue[name]) != 0: return "Legacy tourism cannot carry segmented residue."
	if segmented != (booking.get("profile","") == TourismMarkets.PROFILE): return "Tourism money profile has no matching booking."
	if not segmented and (booking.has("profile") or booking.has("activity")): return "Invalid legacy tourism booking profile."
	var program: Variant = budget.get("tourism_program_booking", {})
	if not program is Dictionary: return "Invalid tourism program booking."
	var safety: Dictionary = block.get("features", {}).get("safety", {})
	if not program.is_empty():
		if program.size() != 2 or booked < 0 or not TourismState._integer(program.get("month_id"), booked, booked) or not TourismState._integer(program.get("half_cents"), 0, TourismState.MAX_INSTANCE / 12):
			return "Invalid tourism program booking."
		if booked == int(block.last_month) and int(program.half_cents) != int(safety.get("cost_half_cents", 0)):
			return "Tourism program booking disagrees with completed protection."
	elif booked == int(safety.get("period_month", -1)) and int(safety.get("cost_half_cents", 0)) > 0:
		return "Completed tourism program has no booking."
	var program_carry: Variant = budget.get("tourism_program_carry", 0)
	if not TourismState._integer(program_carry, 0, TourismState.MAX_INSTANCE / 12) or int(program_carry) % 6 != 0:
		return "Invalid exact tourism program residue."
	if int(program_carry) > 0 and (program.is_empty() or booked < 0):
		return "Tourism program residue has no booking history."
	var largest_capacity := 0
	for key in RewardParams.ARCOLOGIES:
		largest_capacity = maxi(largest_capacity, TourismParams.profile_guest_capacity(key, TourismParams.PREVIOUS_PROFILE))
	# A conservative whole-map bound, including the maximum rate, twelve months
	# and a prior-year sub-dollar residue. All intermediate arithmetic is int64.
	var maximum_base := City.WIDTH * City.HEIGHT * (largest_capacity * 100 + TourismParams.MAX_DAY_CAPACITY * 50)
	@warning_ignore("integer_division")
	var maximum_booking := maximum_base * TourismParams.TAX_MAX * 12 / 100
	if not booking.is_empty():
		if not TourismState._integer(booking.get("month_id"), booked, booked):
			return "Latest tourism booking has a different month."
		for field in ["occupancy_units", "gaming_units"]:
			if not TourismState._integer(booking.get(field), 0, maximum_booking):
				return "Invalid latest tourism booking amount."
		# The saved rates are prospective; a historical booking may use any legal
		# integer rate. Its amounts must nevertheless fit its completed business.
		if segmented:
			if booking.size() != 11: return "Invalid segmented booking fields."
			var bases := TourismSystem.validate_activity(booking.get("activity"),booked,TourismMarkets.PROFILE)
			if not bases.ok: return "Invalid segmented booking activity."
			var known := {}
			for current: Dictionary in block.state.records + block.get("activity",{}).get("rows",[]):
				known[int(current.instance)] = [int(current.anchor[0]),int(current.anchor[1]),String(current.key),int(current.code)]
			for historical: Dictionary in booking.activity.rows:
				var instance := int(historical.instance)
				if instance >= int(block.state.next_instance): return "Booking identity exceeds the saved instance counter."
				var identity := [int(historical.anchor[0]),int(historical.anchor[1]),String(historical.key),int(historical.code)]
				if known.has(instance) and known[instance] != identity: return "Booking reuses another venue identity."
			if booked == int(block.last_month) and (TourismSystem.activity_profile(block) != TourismMarkets.PROFILE or TourismMarkets.integer_activity(booking.activity) != TourismMarkets.integer_activity(block.get("activity",{}))): return "Latest booking activity differs from completed activity."
			for pair in [["occupancy","lodging_numerator"],["gaming","gaming_numerator"]]:
				var name: String = pair[0]
				if not TourismState._integer(booking.get(name+"_rate"),0,20): return "Invalid historical tourism tax rate."
				for suffix in ["_opening_residue","_closing_residue"]:
					if not TourismState._integer(booking.get(name+suffix),0,TourismMarkets.TAX_DENOMINATOR-1): return "Invalid tourism residue proof."
				var exact := TourismMarkets.tax(int(bases[pair[1]]),int(booking[name+"_rate"]),int(booking[name+"_opening_residue"]))
				if int(booking[name+"_units"]) != int(exact.units) or int(booking[name+"_closing_residue"]) != int(exact.residue) or int(residue[name]) != int(exact.residue): return "Tourism booking fails its exact residue transition."
		elif booked == int(block.last_month):
			if TourismSystem.activity_profile(block) == TourismMarkets.PROFILE: return "Segmented business requires exact residue booking."
			var bases := TourismSystem.validate_activity(block.get("activity", {}), booked, TourismSystem.activity_profile(block))
			for pair in [["occupancy_units", "lodging_cents"], ["gaming_units", "gaming_cents"]]:
				var valid_amount := false
				for rate in range(TourismParams.TAX_MIN, TourismParams.TAX_MAX + 1):
					@warning_ignore("integer_division")
					var units: int = int(bases[pair[1]]) * rate * 12 / 100
					if units == int(booking[pair[0]]): valid_amount = true
				if not valid_amount: return "Tourism booking does not match completed business at any legal rate."
	var carry: Variant = budget.get("carry", {})
	if not carry is Dictionary: return "Invalid budget carry."
	if not TourismState._integer(carry.get("ordinance_cost", 0), 0, TourismState.MAX_INSTANCE / 12):
		return "Invalid ordinance expense carry."
	if int(carry.get("ordinance_cost", 0)) < int(program_carry):
		return "Ordinance carry omits exact tourism program residue."
	for key in BudgetParams.TOURISM_KEYS:
		if not TourismState._integer(carry.get(String(key), 0), 0, maximum_booking * 12 + 1199):
			return "Invalid tourism fractional carry."
		var units := int(carry.get(String(key), 0))
		var quantum := 6 if key == &"taxes_occupancy" else 3
		if (not segmented and units % quantum != 0) or (booked == -1 and units != 0):
			return "Tourism carry has no matching booked activity."
	if not TourismState._integer(budget.get("settled_year", -1), -1, TourismParams.MAX_COUNT):
		return "Invalid budget settlement year."
	if city != null:
		@warning_ignore("integer_division")
		var year := city.founded_year + day / GameClock.DAYS_PER_YEAR
		var latest := year - 1
		if day == 0 or day % GameClock.DAYS_PER_YEAR == GameClock.DAYS_PER_YEAR - 1: latest = year
		var settled := int(budget.get("settled_year", -1))
		if settled < year - 1 or settled > latest:
			return "Budget settlement year disagrees with the tourism calendar."
		if booked >= 0:
			@warning_ignore("integer_division")
			var booking_year := city.founded_year + booked / GameClock.MONTHS_PER_YEAR
			if not program.is_empty() and ((settled < booking_year and int(program_carry) < int(program.half_cents) * 6) or (settled >= booking_year and int(program_carry) >= BudgetSystem.TWELFTH_CENTS_PER_DOLLAR)):
				return "Tourism program charge is absent from expense carry."
			for pair in [["taxes_occupancy", "occupancy_units"], ["taxes_gaming", "gaming_units"]]:
				var units := int(carry.get(pair[0], 0))
				if (settled < booking_year and units < int(booking[pair[1]])) or (settled >= booking_year and units >= BudgetSystem.TWELFTH_CENTS_PER_DOLLAR):
					return "Tourism carry disagrees with the settlement year."
		if review and day % GameClock.DAYS_PER_YEAR == GameClock.DAYS_PER_YEAR - 1 and settled != year:
			return "Year-end review has an unsettled budget."
	return ""


## No simulation setup, RNG, migration writes or attendance advancement here.
## The caller supplies the legacy header fallback when count_schema is zero.
static func header_counts(snapshot: Dictionary, facilities: Dictionary) -> Dictionary:
	var stats: Variant = snapshot.get("stats", {})
	if not stats is Dictionary or not TourismState._integer(stats.get("population"), 0, TourismState.MAX_INSTANCE):
		return {"population": 0, "tourists": -1, "count_schema": 0, "count_label": "Legacy population"}
	var result := {"population": int(stats.population), "tourists": 0, "count_schema": 1}
	var systems: Variant = snapshot.get("systems", {})
	if systems is Dictionary and systems.has("tourism"):
		if problem(snapshot) != "": return {"population": int(stats.population), "tourists": -1, "count_schema": 1}
		var rows := TourismState._validate_rows(systems.tourism.state.records, true, int(systems.tourism.state.schema) == 1)
		for row: Dictionary in rows.rows:
			var facility: Variant = facilities.get(row.anchor, facilities.get(SimSystem.tile_key(row.anchor), {}))
			if facility is Dictionary and facility.get("tourism_instance", 0) == row.instance and StringName(facility.get("key", "")) == row.key:
				result.tourists += int(row.guests) + int(row.day_visitors)
	else:
		var rewards: Variant = systems.get("rewards", {}) if systems is Dictionary else {}
		var legacy: Variant = rewards.get("arcologies", {}) if rewards is Dictionary else {}
		for anchor: Variant in facilities:
			var value: Variant = facilities[anchor]
			if not value is Dictionary: continue
			var raw_key: Variant = value.get("key", "")
			if not raw_key is String and not raw_key is StringName: continue
			var capacity := TourismParams.guest_capacity(StringName(raw_key))
			var residents: Variant = value.get("residents", 0)
			var tile: String = SimSystem.tile_key(anchor) if anchor is Vector2i else String(anchor)
			var restored: Variant = legacy.get(tile, {}) if legacy is Dictionary else {}
			if restored is Dictionary and restored.has("residents") and not value.get("tourism_migrated", false):
				residents = restored.residents
			result.tourists += TourismState._legacy_count(residents, capacity)
	return result
