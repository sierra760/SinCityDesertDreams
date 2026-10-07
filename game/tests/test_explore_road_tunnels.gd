# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/exploration/road_tunnel_fixture.gd")

func floor_y(faces: PackedVector3Array, p: Vector2) -> float:
	for i: int in range(0,faces.size(),3):
		var hit = Geometry3D.segment_intersects_triangle(Vector3(p.x,2.53,p.y),Vector3(p.x,2.45,p.y),faces[i],faces[i+1],faces[i+2])
		if hit != null: return hit.y
	return NAN

func test_connected_bores_have_continuous_normal_road_floor() -> void:
	for vertical: bool in [false,true]:
		var city: City = Fixture.city(vertical)
		var before := var_to_bytes(SaveFormat.encode_city(city))
		var layer := CityNetworks3D.new()
		layer.rebuild(city)
		var physical := layer.physical_data()
		for i: int in 57:
			var t := 20.0+i*.125
			var p := Vector2(20.5,t) if vertical else Vector2(t,20.5)
			check(not is_nan(floor_y(physical.physical_floor_faces,p)),"entire bore joins the road at ground level 4 plus .04")
			var a := Vector3(p.x,2.60,p.y)
			var b := a+(Vector3.BACK if vertical else Vector3.RIGHT)*.1
			for j: int in range(0,physical.physical_obstacle_faces.size(),3):
				check(Geometry3D.segment_intersects_triangle(a,b,physical.physical_obstacle_faces[j],physical.physical_obstacle_faces[j+1],physical.physical_obstacle_faces[j+2])==null,"no cap or internal fence crosses the lane")
		var asphalt := false
		var stripe := false
		for i: int in layer._faces.size():
			var p: Vector3 = layer._faces[i]
			if (p.z if vertical else p.x)<22 or (p.z if vertical else p.x)>24: continue
			asphalt = asphalt or (layer._colors[i]==Color(.34,.38,.40) and absf(p.y-2.48948974)<.00001)
			stripe = stripe or (layer._colors[i]==Color(.86,.72,.36) and absf(p.y-2.49548974)<.00001)
		check(asphalt,"buried road shares surface asphalt")
		check(stripe,"buried road shares yellow dashed center")
		check_eq(var_to_bytes(SaveFormat.encode_city(city)),before,"render and physical extraction preserve encoded city")
		layer.free()

func test_terrain_over_bore_stays_visible_and_query_stays_closed() -> void:
	var city: City = Fixture.city()
	var data := CityGeometry3D.build_chunk(city,Rect2i(19,19,10,3))
	var visible: PackedVector3Array = data.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var high := false
	for p: Vector3 in visible: high = high or (p.x>=22 and p.x<=24 and p.y>4.5)
	check(high,"hill above tunnel is preserved")
	var canonical := CityGeometry3D.build_chunk(city,Rect2i(20,20,1,1))
	check_eq(canonical.faces.size(),6,"construction mouth query retains full two triangles")
	var cut: PackedVector3Array = canonical.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(cut != canonical.faces,"only displayed/physical mouth uses the cutout")

func test_imported_marker_convention_and_invalid_bore() -> void:
	var city: City = Fixture.city(true)
	for y: int in range(20,27): city.set_tunnel_bits(20,y,1 if y in [20,26] else 2)
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	check_eq(layer.physical_data().road_tunnels.size(),7,"imported tunnel markers span both mouths")
	city.set_tunnel_bits(20,23,0)
	layer.update_regions(city,[Rect2i(16,16,16,16)])
	check(layer.physical_data().road_tunnels.is_empty(),"broken run cannot open a fictitious through route")
	layer.free()

func test_distant_mouth_change_rebuilds_all_bore_regions() -> void:
	var city: City = Fixture.city()
	# A long imported-style run crosses the 16/32/48 chunk boundaries.
	city.building.put(26,20,0)
	for x: int in range(21,46):
		city.set_tunnel_bits(x,20,2)
		city.set_heights(x,20,8,0)
	city.building.put(45,20,63)
	city.terrain.put(45,20,1)
	city.set_heights(45,20,4,0)
	city.building.put(46,20,30)
	var layer := CityNetworks3D.new()
	layer.update_regions(city,[Rect2i(16,16,16,16)])
	check_eq(layer.physical_data().road_tunnels.size(),26,"long bore initial projection")
	var view := CityView3D.new()
	view.city = city
	view._changed_regions(true)
	city.building.put(45,20,0)
	check(view._changed_regions(false).has(Rect2i(16,16,16,16)),"lost distant exit restores terrain at entrance too")
	view.free()
	var changed := layer.update_regions(city,[Rect2i(32,16,16,16)])
	check(changed.has(Rect2i(16,16,16,16)),"lost distant exit closes entrance region")
	check(layer.physical_data().road_tunnels.is_empty(),"no stale interior remains after lost exit")
	layer.free()

func test_surface_road_above_bore_keeps_both_floors() -> void:
	var city: City = Fixture.city()
	city.building.put(23,20,30)
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	var floor: PackedVector3Array = layer.physical_data().physical_floor_faces
	check(not is_nan(floor_y(floor,Vector2(23.5,20.5))),"lower road remains support under a surface road")
	var upper := false
	for i: int in range(0,floor.size(),3):
		var hit = Geometry3D.segment_intersects_triangle(Vector3(23.5,5,20.5),Vector3(23.5,4.8,20.5),floor[i],floor[i+1],floor[i+2])
		upper = upper or hit!=null
	check(upper,"surface road above tunnel retains independent support")
	layer.free()

func test_smallest_builder_tunnel_is_a_through_road() -> void:
	var city := flat_city()
	city.terrain.put(20,20,Terrain.SLOPE_E)
	city.terrain.put(21,20,Terrain.SLOPE_W)
	var builder := Builder.new(city,CityStats.new())
	var plan: Dictionary = builder.preview(Tools.Kind.TUNNEL,Vector2i(20,20))
	check(plan.ok,"native builder accepts adjacent opposite hillsides")
	if not plan.ok: return
	builder.apply(Tools.Kind.TUNNEL,Vector2i(20,20))
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	check_eq(layer.physical_data().road_tunnels.size(),2,"smallest legal bore is not two capped recesses")
	layer.free()

func test_neighbor_bridge_keeps_outdoor_lighting_layer() -> void:
	var city: City = Fixture.city()
	city.building.put(27,20,87)
	city.flags.put(27,20,RotationMapper.AXIS_FLAG)
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	var checked := 0
	for child: Node in layer.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh and child.position.x>=27:
			check_eq(child.layers,1,"bridge after tunnel uses outdoor scene lighting")
			checked += 1
	check(checked>0,"fixture exercises neighboring bridge beams")
	layer.free()
