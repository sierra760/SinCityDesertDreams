# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Structural bridge spans must stay straight; roads carry the curved grades.
extends "res://tests/test_case.gd"
const Banks := preload("res://tests/test_bridge_approaches.gd")
const Uneven := preload("res://tests/test_highway_smoothness.gd")
func _span_bend(networks: CityNetworks3D, city: City, start: Vector2i) -> float:
	var profile: Dictionary = networks._deck_profiles[start]
	var direction := Vector2i.RIGHT if profile.ew else Vector2i.DOWN
	var minimum := INF
	var maximum := -INF
	for i: int in int(profile.length)*8+1:
		var index := mini(i/8,int(profile.length)-1)
		var cell := start+direction*index
		var along := i/8.0-index
		for across: float in [.15,.35,.5,.65,.85]:
			var offset := Vector2(along,across) if profile.ew else Vector2(across,along)
			var p := networks._point(city,cell,offset,.65)
			minimum = minf(minimum,p.y)
			maximum = maxf(maximum,p.y)
	return maximum-minimum
func test_level_rigid_spans_on_sloping_and_unequal_banks() -> void:
	for ew: bool in [false,true]:
		for length: int in [1,2,6,19]:
			var city := Banks.bank_city(ew,length,87,true)
			var networks := CityNetworks3D.new()
			networks._prepare_bridge_decks(city)
			check_lt(_span_bend(networks,city,Vector2i(22,22)),.00001,"bridge structure stays level across all banked widths and short/long spans")
			networks.free()
		var city := Uneven.uneven_bridge_city(ew)
		var networks := CityNetworks3D.new()
		networks._prepare_bridge_decks(city)
		check_lt(_span_bend(networks,city,Vector2i(22,22)),.00001,"unequal banks must not bend the bridge")
		networks.free()
func test_every_imported_city_bridge_stays_level_and_straight() -> void:
	var total := 0
	for path: String in Banks.bridge_cities():
		var loaded := Sc2Import.load(path)
		check(loaded.ok,"read-only import of "+path)
		if not loaded.ok: continue
		var city: City = loaded.city
		var networks := CityNetworks3D.new()
		networks._prepare_bridge_decks(city)
		var count := 0
		var maximum := .0
		for cell: Vector2i in networks._deck_profiles:
			var p: Dictionary = networks._deck_profiles[cell]
			if p.index!=0 or city.building.atv(cell)==92:continue
			count += 1
			var bend := _span_bend(networks,city,cell)
			maximum = maxf(maximum,bend)
			check_lt(bend,.00001,"rigid bridge %s %s"%[path.get_file(),cell])
		print("STRAIGHT_SPANS %s count=%d maximum_height_change=%.8f"%[path.get_file(),count,maximum])
		total += count
		networks.free()
	check_gt(total,0,"the checked cities contain road or rail bridge spans")
