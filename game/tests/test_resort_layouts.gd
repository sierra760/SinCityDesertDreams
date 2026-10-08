# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Casino floor plans: every game present, tables inside the hall, walking
## lanes between obstacles and no overlapping props.
extends "res://tests/test_case.gd"

const LANE := .15

func _rect(obstacle: Dictionary) -> Rect2:
	var half: Vector2 = obstacle.half
	return Rect2(Vector2(obstacle.center)-half,half*2.0)

func _gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0,maxf(a.position.x-b.end.x,b.position.x-a.end.x))
	var dz := maxf(0.0,maxf(a.position.y-b.end.y,b.position.y-a.end.y))
	return Vector2(dx,dz).length()

func test_every_resort_has_its_games_and_signature() -> void:
	for key: StringName in ResortInteriorLayouts.keys():
		var plan := ResortInteriorLayouts.layout(key)
		var counts := {}
		var slots := 0
		for table: Dictionary in plan.tables:
			counts[table.game] = int(counts.get(table.game,0))+1
			if table.game == &"slots": slots += int(table.count)
			check(not String(table.prop).is_empty(),"%s: %s has a prop" % [key,table.game])
			check(not String(table.name).is_empty(),"%s: %s has a name" % [key,table.game])
		for game: StringName in [&"blackjack",&"roulette",&"money_wheel",&"video_poker",&"slots"]:
			check(counts.has(game),"%s offers %s" % [key,game])
		var signature: StringName = ResortInteriorLayouts.theme(key).signature
		check_eq(int(counts.get(signature,0)),1,"%s has its signature game" % key)
		check_eq(slots,48,"%s has 48 slot cabinets in four double-sided rows" % key)
		var pit := 0
		for table: Dictionary in plan.tables:
			if table.game != &"slots": pit += 1
		check_ge(pit,7,"%s has at least seven pit games" % key)
		check_eq(int(counts.get(&"blackjack",0)),3,"%s has three blackjack tables in the pit ring" % key)
		check(ResortInteriorLayouts.minimum(key)>0,"%s has a table minimum" % key)

func test_tables_seats_and_props_lie_inside_the_hall() -> void:
	var inner := Rect2(Vector2(-ResortInteriorLayouts.HALF,-ResortInteriorLayouts.HALF),Vector2.ONE*ResortInteriorLayouts.HALF*2.0)
	for key: StringName in ResortInteriorLayouts.keys():
		var plan := ResortInteriorLayouts.layout(key)
		for obstacle: Dictionary in plan.obstacles:
			var rect := _rect(obstacle)
			check(inner.grow(.0001).encloses(rect),"%s: %s inside the hall" % [key,obstacle.name])
		for table: Dictionary in plan.tables:
			var seat: Vector3 = table.seat
			check(inner.has_point(Vector2(seat.x,seat.z)),"%s: %s seat inside" % [key,table.game])
			check(plan.bounds.has_point(table.camera.origin),"%s: %s table view inside" % [key,table.game])
			for obstacle: Dictionary in plan.obstacles:
				check(not _rect(obstacle).grow(.018).has_point(Vector2(seat.x,seat.z)),"%s: %s seat clear of %s" % [key,table.game,obstacle.name])
		var mat: Vector3 = plan.entrance.mat.origin
		check(plan.bounds.has_point(mat),"%s: mat inside the pocket" % key)
		check_gt(mat.z,ResortInteriorLayouts.HALF,"%s: mat in the vestibule" % key)

func test_lanes_between_obstacles_and_no_overlaps() -> void:
	for key: StringName in ResortInteriorLayouts.keys():
		var obstacles: Array = ResortInteriorLayouts.layout(key).obstacles
		for i: int in obstacles.size():
			for j: int in range(i+1,obstacles.size()):
				var a: Dictionary = obstacles[i]
				var b: Dictionary = obstacles[j]
				var gap := _gap(_rect(a),_rect(b))
				# Lounge banquettes and cocktail tables form one seating group;
				# the two faces of a slot row stand back to back; the bar counter
				# and back bar enclose the bartender's aisle.
				var lounge: bool = (a.name == "lounge" and b.name == "lounge")
				var row: bool = String(a.name).begins_with("slots row") and a.name == b.name
				var aisle: bool = (a.name in ["bar counter","back bar"] and b.name in ["bar counter","back bar"])
				if lounge: continue
				if row:
					check(gap<.001,"%s: %s faces stand back to back" % [key,a.name])
					continue
				if aisle:
					check_gt(gap,.15,"%s: bartender aisle" % key)
					continue
				check_ge(gap,LANE,"%s: lane between %s and %s" % [key,a.name,b.name])
