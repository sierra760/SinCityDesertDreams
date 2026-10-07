# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

## Reference clip: every floor triangle above the region is cut in order, with
## no spatial pre-filter. Even a disjoint cut can change quantization, winding
## or start vertices, so results are compared as complete bytes.
func _reference(regions: Array[Dictionary], floor: PackedVector3Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for region: Dictionary in regions:
		var pieces: Array[PackedVector2Array] = [region.polygon]
		for i: int in range(0,floor.size(),3):
			if minf(floor[i].y,minf(floor[i+1].y,floor[i+2].y)) <= float(region.top): continue
			var cut := PackedVector2Array()
			for j: int in 3: cut.append(Vector2(floor[i+j].x,floor[i+j].z))
			var remaining: Array[PackedVector2Array] = []
			for piece: PackedVector2Array in pieces: remaining.append_array(Geometry2D.clip_polygons(piece,cut))
			pieces = remaining
		for polygon: PackedVector2Array in pieces:
			result.append({"polygon":polygon,"top":region.top,"cell":region.cell})
	return result

func _append_cut(floor: PackedVector3Array, points: PackedVector2Array, height: float) -> void:
	for point: Vector2 in points: floor.append(Vector3(point.x,height,point.y))

func test_local_admission_is_bounded_and_preserves_original_cut_order() -> void:
	var floor := PackedVector3Array()
	for y: int in range(32):
		for x: int in range(32):
			_append_cut(floor,PackedVector2Array([Vector2(x,y),Vector2(x+1,y),Vector2(x,y+1)]),3)
	var polygon := PackedVector2Array([Vector2(16.2,16.2),Vector2(16.8,16.2),Vector2(16.2,16.8)])
	var inventory := CityGeometry3D._water_cut_inventory(floor)
	var eligible: Array[int] = []
	for i: int in 1024: eligible.append(i)
	var selected := CityGeometry3D._water_clip_candidates(polygon,inventory,eligible)
	check_lt(selected.size(),32,"a local water polygon avoids the 1024-triangle full scan")
	check_eq(selected[0],0,"the first eligible cut still normalizes the subject")
	for i: int in range(1,selected.size()): check_gt(selected[i],selected[i-1],"selected cuts stay unique and in reference order")
	var regions: Array[Dictionary] = [{"polygon":polygon,"top":1.0,"cell":Vector2i(16,16)}]
	check_eq(var_to_bytes(CityGeometry3D._dry_water_regions(regions,floor)),var_to_bytes(_reference(regions,floor)),"spatial admission retains complete ordered output")

func test_hole_contours_keep_the_next_original_normalization_operation() -> void:
	var polygon := PackedVector2Array([Vector2(.1234567,.0123456),Vector2(.9765432,.3456789),Vector2(.4567891,.9876543)])
	var interior := PackedVector2Array([Vector2(.3,.35),Vector2(.4,.4),Vector2(.35,.5)])
	var distant := PackedVector2Array([Vector2(-4,0),Vector2(-3,0),Vector2(-4,1)])
	var floor := PackedVector3Array()
	_append_cut(floor,interior,3)
	_append_cut(floor,distant,3)
	var regions: Array[Dictionary] = [{"polygon":polygon,"top":1.0,"cell":Vector2i.ZERO}]
	var once := Geometry2D.clip_polygons(polygon,interior)
	var expected := _reference(regions,floor)
	check_eq(expected.size(),2,"interior cut produces outer and hole contours")
	check(once[1]!=expected[1].polygon,"distant operation changes the new hole's vertex order")
	check_eq(var_to_bytes(CityGeometry3D._dry_water_regions(regions,floor)),var_to_bytes(expected),"hole orientation and start vertices match the full reference clip")

func test_height_admission_quantization_shared_edges_and_negative_positions_are_exact() -> void:
	for offset: Vector2 in [Vector2(-1.0,-1.0),Vector2.ZERO,Vector2(127.0,127.0)]:
		var floor := PackedVector3Array()
		for i: int in 64:
			var start := offset+Vector2(float(i%8)*.25,float(i/8)*.25)
			_append_cut(floor,PackedVector2Array([start,start+Vector2(.25,0),start+Vector2(0,.25)]),float(i%4))
		var regions: Array[Dictionary] = []
		for i: int in 12:
			var start := offset+Vector2(float(i%4)*.3333333,float(i/4)*.3333333)
			var polygon := PackedVector2Array([start,start+Vector2(.3333333,0),start+Vector2(0,.3333333)])
			if i%2==0: polygon.reverse()
			regions.append({"polygon":polygon,"top":float(i%4),"cell":Vector2i(start)})
		check_eq(var_to_bytes(CityGeometry3D._dry_water_regions(regions,floor)),var_to_bytes(_reference(regions,floor)),"precision, shared edges and strict floor-height admission: "+str(offset))

func test_no_eligible_floor_preserves_uncanonicalized_source_and_empty_inputs() -> void:
	var polygon := PackedVector2Array([Vector2(.1234567,0),Vector2(1,.2345678),Vector2(.3456789,1)])
	var regions: Array[Dictionary] = [{"polygon":polygon,"top":3.0,"cell":Vector2i.ZERO}]
	var floor := PackedVector3Array()
	_append_cut(floor,PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN]),3)
	check_eq(var_to_bytes(CityGeometry3D._dry_water_regions(regions,floor)),var_to_bytes(regions),"equal-height floor is ignored without normalization")
	check_eq(CityGeometry3D._dry_water_regions([],floor),[],"empty water is empty")
	check_eq(CityGeometry3D._dry_water_regions(regions,PackedVector3Array()),regions,"empty floor retains water")
