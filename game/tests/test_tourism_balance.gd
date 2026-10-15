# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Fixed-environment balance scenarios; actual services/bookkeeping have host coverage.
extends "res://tests/test_case.gd"

func test_tax_sweeps_and_capacity_conservation() -> void:
	var evidence: Array = []
	for scenario in ["founding", "store_only", "all_tiers", "large_city", "oversupply", "service_collapse"]:
		var rows: Array[Dictionary] = []
		var keys: Array = RewardParams.ARCOLOGIES.keys() if scenario in ["all_tiers", "large_city", "service_collapse"] else [&"com_corner_store"] if scenario == "store_only" else [&"arcology_boddy"]
		var copies := 100 if scenario == "oversupply" else 1
		var cost := 0
		for copy in copies:
			for key in keys:
				var n := rows.size()
				rows.append({"anchor":Vector2i((n % 32)*4,(n/32)*4),"key":key,"guests":0,"operating":scenario != "service_collapse","land_value":240,"crime":0,"pollution":0})
				cost += Buildings.cost(Buildings.id_of(key))
		var inputs := {"permanent_population":200000 if scenario == "large_city" else 0,"neighbor_populations":[],"economy_phase":2,"average_land_value":240,"average_crime":0,"average_pollution":0,"average_traffic":0}
		for occupancy in [true,false]:
			var receipts: Array[int] = []
			var previous_guests := 2147483647
			var previous_day := 2147483647
			for rate in range(21):
				var o := rate if occupancy else 7
				var g := 7 if occupancy else rate
				var forecast := TourismDemand.forecast(rows,inputs,o,g)
				var current := PackedInt64Array()
				current.resize(rows.size())
				var lodging := 0
				var gaming := 0
				var guests := 0
				var day := 0
				for month in range(36):
					guests = 0
					day = 0
					for i in rows.size():
						var row: Dictionary = forecast.rows[i]
						var opening := current[i]
						var change := TourismDemand.turnover(opening,row.target_guests)
						current[i] = change.guests
						check_eq(current[i],opening-int(change.departures)+int(change.arrivals))
						check_between(current[i],0,int(row.capacity))
						check_between(int(row.target_day_visitors),0,int(row.day_capacity))
						guests += current[i]
						day += int(row.target_day_visitors)
						if month >= 24:
							var bases := TourismDemand.business_bases(opening,current[i],row.target_day_visitors)
							lodging += int(bases.lodging_cents)*o
							gaming += int(bases.gaming_cents)*g
					check_between(guests,0,int(forecast.guest_pool))
					check_between(day,0,int(forecast.day_pool))
				check_eq(guests,int(forecast.guests),"settled forecast matches 36 monthly steps")
				check(guests <= previous_guests,"higher independent tax never raises guests")
				check(day <= previous_day,"higher independent tax never raises day attendance")
				previous_guests = guests
				previous_day = day
				var applicable := lodging if occupancy else gaming
				receipts.append(applicable)
				if rate == 0: check_eq(applicable,0)
				if scenario in ["store_only","service_collapse"]: check_eq(lodging,0)
				if scenario == "service_collapse": check_eq(guests+day+gaming,0)
				evidence.append({"scenario":scenario,"varied":"occupancy" if occupancy else "gaming","rate":rate,"guests":guests,"day_visitors":day,"capacity":forecast.capacity,"occupancy":forecast.occupancy,"guest_pool":forecast.guest_pool,"day_pool":forecast.day_pool,"annual_lodging_tax_cent_percent":lodging,"annual_gaming_tax_cent_percent":gaming,"venue_construction_cost":cost,"tax_only_simple_payback_years":float(cost)*10000.0/float(lodging+gaming) if lodging+gaming > 0 and cost > 0 else -1})
			if scenario != "service_collapse" and (not occupancy or scenario != "store_only"):
				# Whole-person rounding can move the best intermediate point in small venues.
				# Exhaustively require at least one positive intermediate to beat 20%.
				var intermediate: int = receipts.slice(1, 20).max()
				check_gt(intermediate, 0)
				check_gt(intermediate, receipts[20], "maximum rate underperforms an intermediate after settlement")
	print("BALANCE_ROWS ",JSON.stringify(evidence))
	var path := OS.get_environment("TOURISM_BALANCE_OUTPUT")
	if not path.is_empty():
		var file := FileAccess.open(path,FileAccess.WRITE)
		check(file != null,"evidence file writable")
		if file != null: file.store_string(JSON.stringify(evidence,"  "))
