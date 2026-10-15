# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"


func test_capacity_roster_and_exact_activity() -> void:
	for key: StringName in RewardParams.ARCOLOGIES:
		check_eq(TourismParams.guest_capacity(key), int(RewardParams.ARCOLOGIES[key]["capacity"]))
		check_between(TourismParams.day_capacity(key), 16, 300)
	check_eq(TourismParams.guest_capacity(&"com_corner_store"), 0)
	check_eq(TourismParams.day_capacity(&"com_corner_store"), 24)
	check_eq(TourismParams.day_capacity(&"arcology_boddy"), 16)
	check_eq(TourismParams.day_capacity(&"missing"), 0)
	check_eq(TourismDemand.business_bases(1, 2, 3), {"lodging_cents": 150, "gaming_cents": 225})


func test_integer_allocation_conserves_pool() -> void:
	check_eq(TourismDemand.allocate(PackedInt64Array([1, 1, 1]), 2), PackedInt64Array([1, 1, 0]))
	check_eq(TourismDemand.allocate(PackedInt64Array([3, 7]), 0), PackedInt64Array([0, 0]))
	check_eq(TourismDemand.allocate(PackedInt64Array([3, 7]), 100), PackedInt64Array([3, 7]))
	for a in 9:
		for b in 9:
			for pool in 20:
				var result := TourismDemand.allocate(PackedInt64Array([a, b]), pool)
				check_eq(result[0] + result[1], mini(pool, a + b))
				check_between(result[0], 0, a)
				check_between(result[1], 0, b)


func test_turnover_is_temporary_and_bounded() -> void:
	check_eq(TourismDemand.turnover(10, 8), {"guests": 8, "departures": 5, "arrivals": 3})
	check_eq(TourismDemand.turnover(0, 9)["guests"], 5)
	check_eq(TourismDemand.turnover(1, 2)["guests"], 1, "even targets have a one-person rounding equilibrium")
	check_eq(TourismDemand.turnover(2, 2)["guests"], 2)
	for opening in 40:
		for target in 40:
			var result := TourismDemand.turnover(opening, target)
			check_eq(result["guests"], opening - result["departures"] + result["arrivals"])
			check_between(result["arrivals"], 0, (target + 1) / 2)
			check_eq(result["departures"], (opening + 1) / 2)
			var current := opening
			for month in 12:
				current = TourismDemand.turnover(current, target)["guests"]
			check_between(current, maxi(0, target - 1), target, "turnover converges within integer rounding")
			check_eq(TourismDemand.turnover(current, target)["guests"], current, "settled attendance stays stable")


func _venue(key: StringName = &"arcology_comstock", x: int = 0) -> Dictionary:
	return {"key": key, "anchor": Vector2i(x % City.WIDTH, x / City.WIDTH), "operating": true,
		"land_value": 240, "crime": 0, "pollution": 0, "guests": 17}


func _inputs() -> Dictionary:
	return {"permanent_population": 19500, "neighbor_populations": [], "economy_phase": 2,
		"average_land_value": 240, "average_crime": 0, "average_pollution": 0, "average_traffic": 0}


func test_oversupply_cannot_cancel_tax_response() -> void:
	var rows: Array[Dictionary] = []
	for x in 2000:
		rows.append(_venue(&"arcology_comstock", x))
	var free := TourismDemand.forecast(rows, _inputs(), 0, 0)
	var taxed := TourismDemand.forecast(rows, _inputs(), 20, 20)
	check_eq(free["guests"], 10000)
	check_eq(taxed["guests"], 800)
	check_eq(taxed["day_visitors"], 1333)
	check_lt(taxed["guests"], free["guests"])
	check_lt(taxed["day_visitors"], free["day_visitors"])


func test_zero_and_extreme_inputs_are_finite() -> void:
	check_eq(TourismDemand.forecast([], {}, 0, 0)["guests"], 0)
	check_eq(TourismDemand.allocate(PackedInt64Array([-2, 8]), -1), PackedInt64Array([0, 0]))
	var inputs := _inputs()
	inputs["permanent_population"] = 9223372036854775807
	inputs["neighbor_populations"] = [9223372036854775807, INF, NAN, -200]
	inputs["average_land_value"] = INF
	inputs["average_crime"] = NAN
	inputs["average_pollution"] = -100
	for rates in [Vector2i(-100, -100), Vector2i(999, 999)]:
		var result := TourismDemand.forecast([_venue()], inputs, rates.x, rates.y)
		check_between(result["guests"], 0, TourismParams.guest_capacity(&"arcology_comstock"))
		check_between(result["day_visitors"], 0, TourismParams.day_capacity(&"arcology_comstock"))
		check_ge(result["lodging_cents"], 0)
	check_eq(TourismDemand.business_bases(-5, -2, -1), {"lodging_cents": 0, "gaming_cents": 0})


func test_forecast_is_pure() -> void:
	var rows: Array[Dictionary] = [_venue(&"arcology_boddy", 5), _venue(&"com_corner_store", 1)]
	rows[0]["custom"] = {"array": [1, 2]}
	var inputs := _inputs()
	var before_rows := rows.duplicate(true)
	var before_inputs := inputs.duplicate(true)
	var result := TourismDemand.forecast(rows, inputs, 7, 7)
	check_eq(rows, before_rows)
	check_eq(inputs, before_inputs)
	check_eq(result["rows"][0]["anchor"], Vector2i(1, 0))
	check_eq(result["rows"][1]["guests"], 17, "current attendance remains distinct from projection")
	result["rows"][1]["custom"]["array"].append(3)
	check_eq(rows, before_rows, "returned nested data does not alias inputs")


func test_exact_pools_local_appeal_services_and_ordinances() -> void:
	var inputs := _inputs()
	inputs["permanent_population"] = 1000
	inputs["neighbor_populations"] = [100000]
	inputs["average_land_value"] = 160
	var row := _venue(&"arcology_boddy")
	row["land_value"] = 160
	var result := TourismDemand.forecast([row], inputs, 7, 7)
	check_eq(result["guest_pool"], 895)
	check_eq(result["day_pool"], 414)
	check_eq(result["guests"], 39)
	check_eq(result["day_visitors"], 11)
	check_eq(result["lodging_cents"], 3900)
	check_eq(result["gaming_cents"], 2500)
	check_eq(result["rows"][0]["appeal"], 90)
	inputs["tourist_advertising"] = true
	inputs["annual_carnival"] = true
	var promoted := TourismDemand.forecast([row], inputs, 7, 7)
	check_eq(promoted["rows"][0]["appeal"], 100)
	check_gt(promoted["guests"], result["guests"])
	row["operating"] = false
	check_eq(TourismDemand.forecast([row], inputs, 0, 0)["guests"], 0)
	check_eq(TourismDemand.forecast([row], inputs, 0, 0)["day_visitors"], 0)
	inputs = _inputs()
	inputs["average_land_value"] = 0
	row = _venue(&"arcology_boddy")
	row["land_value"] = 0
	inputs["tourist_advertising"] = true
	check_eq(TourismDemand.forecast([row], inputs, 0, 0)["rows"][0]["appeal"], 80)
	inputs["tourist_advertising"] = false
	inputs["annual_carnival"] = true
	check_eq(TourismDemand.forecast([row], inputs, 0, 0)["rows"][0]["appeal"], 75)
	inputs["annual_carnival"] = false
	row["crime"] = 1
	check_eq(TourismDemand.forecast([row], inputs, 0, 0)["rows"][0]["appeal"], 69, "one final division retains environmental fractions")
	inputs = _inputs()
	var occupancy_zero := TourismDemand.forecast([_venue()], inputs, 0, 7)
	var occupancy_high := TourismDemand.forecast([_venue()], inputs, 20, 7)
	check_eq(occupancy_zero["day_visitors"], occupancy_high["day_visitors"], "occupancy tax only discourages overnight guests")
	inputs["economy_phase"] = 0
	check_eq(TourismDemand.forecast([_venue()], inputs, 0, 0)["guest_pool"], 7000)
	inputs["economy_phase"] = 3
	check_eq(TourismDemand.forecast([_venue()], inputs, 0, 0)["guest_pool"], 11500)


func test_independent_tax_sweeps_and_settled_receipts() -> void:
	var rows: Array[Dictionary] = [_venue()]
	for vary_occupancy in [true, false]:
		var previous := 999999
		for rate in [0, 7, 12, 20]:
			var result := TourismDemand.forecast(rows, _inputs(), rate if vary_occupancy else 7, 7 if vary_occupancy else rate)
			check_lt(result["guests"], previous, "independent higher tax reduces demand")
			previous = result["guests"]
			print("Tourism %s sweep rate=%d guests=%d day=%d lodging_cents=%d gaming_cents=%d" % ["occupancy" if vary_occupancy else "gaming", rate, result["guests"], result["day_visitors"], result["lodging_cents"], result["gaming_cents"]])
			var current := 17
			for month in 36:
				current = TourismDemand.turnover(current, result["rows"][0]["target_guests"])["guests"]
			check_eq(current, result["guests"], "forecast equals settled attendance")
			check_eq(result["rows"][0]["projected_guests"], current)
			check_eq(result["rows"][0]["guests"], 17)
	var occupancy_mid := TourismDemand.forecast(rows, _inputs(), 12, 7)
	var occupancy_max := TourismDemand.forecast(rows, _inputs(), 20, 7)
	check_gt(occupancy_mid["lodging_cents"] * 12, occupancy_max["lodging_cents"] * 20)
	var gaming_mid := TourismDemand.forecast(rows, _inputs(), 7, 17)
	var gaming_max := TourismDemand.forecast(rows, _inputs(), 7, 20)
	check_gt(gaming_mid["gaming_cents"] * 17, gaming_max["gaming_cents"] * 20)
	print("Tourism settled sweep: occupancy12=%d occupancy20=%d gaming17=%d gaming20=%d (cent-percent numerators)" % [occupancy_mid["lodging_cents"] * 12, occupancy_max["lodging_cents"] * 20, gaming_mid["gaming_cents"] * 17, gaming_max["gaming_cents"] * 20])

func test_overnight_guest_capacity_tracks_unchanged_construction_cost() -> void:
	var keys := RewardParams.ARCOLOGIES.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return Buildings.cost(Buildings.id_of(a)) < Buildings.cost(Buildings.id_of(b)))
	check_eq(keys.size(), 14)
	var previous := 0
	var previous_day := 0
	for key in keys:
		var capacity := TourismParams.guest_capacity(key)
		check_eq(capacity * 100, Buildings.cost(Buildings.id_of(key)), "guest capacity scales with unchanged cost: " + String(key))
		check_gt(capacity, previous)
		check_ge(TourismParams.day_capacity(key), previous_day)
		previous = capacity
		previous_day = TourismParams.day_capacity(key)
	check_eq(TourismParams.guest_capacity(&"com_corner_store"), 0)
	check_eq(TourismParams.day_capacity(&"com_corner_store"), 24)
