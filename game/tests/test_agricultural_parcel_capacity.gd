# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"

const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")


func test_exact_area_units_and_stable_fractional_jobs() -> void:
	check_eq(AgriculturalParcelParams.job_units(&"alfalfa",1),54,"one alfalfa member is 54/36 job units")
	check_eq(AgriculturalParcelParams.job_units(&"cattle_range",9),216,"nine range members are six jobs")
	check_eq(AgriculturalParcelParams.job_units(&"sheep_pasture",9),180,"nine sheep members are five jobs")
	var a := F.record(1,F.mask([[20,20]]),&"alfalfa",&"active")
	var b := F.record(2,F.mask([[24,20]]),&"alfalfa",&"active")
	var allocation := AgriculturalParcelCapacity.allocate([a,b])
	check_eq(allocation.jobs,3)
	check_eq(allocation.by_id[1]+allocation.by_id[2],3)
	check_eq(AgriculturalParcelCapacity.allocate([b,a]),allocation)
	for row in [[&"cattle_range",6],[&"sheep_pasture",5]]:
		var r := F.record(3,F.square(),row[0],&"active")
		check_eq(AgriculturalParcelCapacity.allocate([r]).jobs,row[1])


func test_split_merge_and_removed_area_never_mint_jobs() -> void:
	var members := F.mask([[20,20],[21,20],[22,20],[23,20]])
	var whole := F.record(1,members,&"alfalfa",&"active")
	var left := F.record(1,F.mask([[20,20],[21,20]]),&"alfalfa",&"active")
	var right := F.record(2,F.mask([[22,20],[23,20]]),&"alfalfa",&"active")
	check_eq(AgriculturalParcelCapacity.allocate([whole]).jobs,6)
	check_eq(AgriculturalParcelCapacity.allocate([left,right]).jobs,6)
	check_eq(AgriculturalParcelCapacity.allocate([left]).jobs,3)
	var inactive := right.duplicate(true)
	inactive.state = &"prepared"
	check_eq(AgriculturalParcelCapacity.allocate([left,inactive]).jobs,3)
	check_eq(AgriculturalParcelCapacity.allocate([inactive]).jobs,0)


func test_fixed_masks_and_repeated_cuts_conserve_exact_units() -> void:
	# Literal expected totals pin the rate and final rounding independently of
	# whether the retained mask is one farm, topology components or singletons.
	var cases := [
		{"mask":F.square(),"cuts":[F.mask([[21,21]]),F.mask([[20,20]]),F.mask([[20,21],[20,22]])],
			"units":[486,432,378,270],"jobs":[13,12,10,7]},
		{"mask":F.dumbbell(),"cuts":[F.mask([[22,21]]),F.mask([[20,20]]),F.mask([[24,22]])],
			"units":[702,648,594,540],"jobs":[19,18,16,15]},
		{"mask":F.u_shape(),"cuts":[F.mask([[21,22]]),F.mask([[20,20]])],
			"units":[378,324,270],"jobs":[10,9,7]}]
	for test_case: Dictionary in cases:
		var retained: PackedInt32Array = test_case.mask.duplicate()
		for stage in test_case.units.size():
			if stage > 0:
				var next := PackedInt32Array()
				for index in retained:
					if index not in test_case.cuts[stage-1]: next.append(index)
				retained = next
			var partitions: Array = []
			partitions.append([retained])
			var components: Array[PackedInt32Array] = AgriculturalParcels.components(retained)
			partitions.append(components)
			var singles: Array[PackedInt32Array] = []
			for index in retained: singles.append(PackedInt32Array([index]))
			partitions.append(singles)
			for parts: Array in partitions:
				var records: Array[Dictionary] = []
				var units := 0
				var id := 1
				for part: PackedInt32Array in parts:
					records.append(F.record(id,part,&"alfalfa",&"active"))
					units += AgriculturalParcelParams.job_units(&"alfalfa",part.size())
					id += 1
				var allocation := AgriculturalParcelCapacity.allocate(records)
				var allocated_sum := 0
				for jobs: int in allocation.by_id.values(): allocated_sum += jobs
				check_eq(units,test_case.units[stage],"fixed cut retains exact area units")
				check_eq(allocation.jobs,test_case.jobs[stage],"city rounds retained units once")
				check_eq(allocated_sum,allocation.jobs,"parcel shares match city capacity")


func test_real_core_cut_prepares_fragment_and_removes_capacity() -> void:
	var city := flat_city()
	var members := F.square()
	F.zone(city,members)
	var record := F.record(7,members,&"alfalfa",&"active")
	check_eq(record.modules[0].key,&"farm_shed")
	check_eq(city.agricultural_parcels.put(city,record),OK)
	check_eq(AgriculturalParcelCapacity.allocate(city.agricultural_parcels.records()).jobs,13)
	var eligible_calls: Array = []
	var allow_eligible := func(_candidate: City, eligible: Array[int]) -> Array:
		eligible_calls.append(eligible.duplicate())
		return eligible
	# The original shed sits in this corner. Passing every eligible survivor
	# through the service gate means a prepared result comes from core loss.
	var result := city.agricultural_parcels.remove_cells(city,F.mask([[20,20]]),allow_eligible)
	check(result.ok)
	check_eq(result.removed_cells,F.mask([[20,20]]))
	var survivors := city.agricultural_parcels.records()
	check_eq(survivors.size(),1)
	check_eq(survivors[0].members.size(),8)
	check_eq(survivors[0].state,&"prepared")
	check(not survivors[0].modules.has(record.modules[0]),"the original required shed pose was cut away")
	check_eq(eligible_calls,[],"missing original core bypasses active service eligibility")
	check_eq(AgriculturalParcelCapacity.allocate(survivors).jobs,0)


func test_destinations_are_real_members_and_sum_to_city_jobs() -> void:
	var capacity := load("res://scripts/sim/agricultural_parcel_capacity.gd")
	if not capacity.has_method("destinations"):
		check(false,"member destination adapter is missing")
		return
	var records: Array[Dictionary] = [
		F.record(1,F.mask([[20,20]]),&"alfalfa",&"active"),
		F.record(2,F.mask([[24,20]]),&"alfalfa",&"active"),
		F.record(3,F.u_shape(),&"grain",&"prepared")]
	var allocation := AgriculturalParcelCapacity.allocate(records)
	var destinations := AgriculturalParcelCapacity.destinations(records,allocation)
	var sum := 0
	for d in destinations:
		sum += d.jobs
		var owner: Dictionary = records[d.parcel_id - 1]
		check(owner.members.has(d.tile.y * 128 + d.tile.x),"destination is an actual member")
	check_eq(sum,allocation.jobs)
	check_eq(destinations.size(),2)
	var reversed: Array[Dictionary] = [records[1],records[0],records[2]]
	check_eq(AgriculturalParcelCapacity.destinations(reversed,allocation),destinations)
	var concave := F.record(4,F.u_shape(),&"grain",&"active")
	var concave_records: Array[Dictionary] = [concave]
	var d := AgriculturalParcelCapacity.destinations(concave_records,AgriculturalParcelCapacity.allocate(concave_records))
	check_eq(d.size(),1)
	check(concave.members.has(d[0].tile.y*128+d[0].tile.x))
	check_ne(d[0].tile,Vector2i(21,20),"bounding gap is never a commute anchor")
	var empty := F.record(5,F.mask([[30,30]]),&"alfalfa",&"active")
	empty.members = PackedInt32Array()
	var empty_records: Array[Dictionary] = [empty]
	check_eq(AgriculturalParcelCapacity.destinations(empty_records,AgriculturalParcelCapacity.allocate(empty_records)),[])


func test_emissions_use_exact_member_units_and_ignore_inactive_or_livestock() -> void:
	var capacity := load("res://scripts/sim/agricultural_parcel_capacity.gd")
	if not capacity.has_method("emission_units"):
		check(false,"member emission adapter is missing")
		return
	var ring := F.record(1,F.ring(),&"alfalfa",&"active")
	var ring_records: Array[Dictionary] = [ring]
	var units := AgriculturalParcelCapacity.emission_units(ring_records)
	check_eq(units.size(),8)
	for i in ring.members: check_eq(units[i],9)
	check(not units.has(21+21*128),"concave hole has no emissions")
	var fragments: Array[Dictionary] = [
		F.record(2,F.mask([[20,20],[21,20],[22,20],[20,21]]),&"alfalfa",&"active"),
		F.record(3,F.mask([[22,21],[20,22],[21,22],[22,22]]),&"alfalfa",&"active")]
	check_eq(AgriculturalParcelCapacity.emission_units(fragments),units)
	var vegetable: Array[Dictionary] = [F.record(4,F.mask([[20,20]]),&"vegetables",&"active")]
	var grain: Array[Dictionary] = [F.record(5,F.mask([[20,20]]),&"grain",&"active")]
	var cattle: Array[Dictionary] = [F.record(6,F.square(),&"cattle_range",&"active")]
	var prepared: Array[Dictionary] = [F.record(7,F.ring(),&"alfalfa",&"prepared")]
	check_eq(AgriculturalParcelCapacity.emission_units(vegetable)[20+20*128],36)
	check_eq(AgriculturalParcelCapacity.emission_units(grain)[20+20*128],9)
	check_eq(AgriculturalParcelCapacity.emission_units(cattle),{})
	check_eq(AgriculturalParcelCapacity.emission_units(prepared),{})
