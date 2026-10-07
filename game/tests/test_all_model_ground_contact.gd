# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
func test_subway_plaza_is_supported_on_falling_terrain() -> void:
	var city := flat_city();city.terrain_surface=TerrainSurface.new(4)
	city.terrain_surface.set_vertex(21,20,5);city.terrain_surface.set_vertex(21,21,5)
	city.stamp_building(20,20,Buildings.SUBWAY_STATION)
	var catalog := CityModelCatalog.new();check_eq(catalog.load_manifest(CityModelCatalog.ROOT+"catalog.json"),OK)
	var layer := CityBuildings3D.new();layer.rebuild(city,catalog)
	check(layer.get_child(0).get_node_or_null("TerrainSupport")!=null,"plaza base reaches falling terrain; prepared Explore stations hide this entire shell")
	layer.free()
func test_all_ground_traffic_visuals_touch_their_origin_in_both_lods() -> void:
	for kind: StringName in CityTrafficCatalog.KINDS:
		if CityTrafficCatalog.domain(kind) not in [&"road",&"rail"]: continue
		for far: bool in [false,true]:
			var mesh := CityTrafficCatalog.mesh_for(kind,0,far)
			check(absf(mesh.get_aabb().position.y)<.000001,"tire contact kind=%s far=%s"%[kind,far])
	for variant: int in 16:
		for far: bool in [false,true]:
			check(absf(CityTrafficCatalog.mesh_for(&"pedestrian",variant,far).get_aabb().position.y)<.000001,"feet touch origin")
func test_ambient_actor_pose_has_no_arbitrary_vertical_lift() -> void:
	var city := flat_city()
	for x: int in range(18,24): city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	var traffic := CityTraffic3D.new();traffic.bind_city(city)
	var a := {"cell":Vector2i(20,20),"previous":Vector2i(19,20),"next":Vector2i(21,20),"t":.5,"side":1.0,"domain":&"road","type":&"road","kind":&"car"}
	check(absf(traffic.actor_pose(a).origin.y-(4*CityGeometry3D.HEIGHT+.04))<.000001,"car tires touch asphalt")
	a.type=&"pedestrian";a.erase("_pose_t")
	check(absf(traffic.actor_pose(a).origin.y-(4*CityGeometry3D.HEIGHT+.024))<.000001,"feet touch actual verge under the pedestrian lane")
	traffic.free()

func test_pedestrian_height_matches_rendered_material_on_every_road_shape() -> void:
	for sloped: bool in [false,true]:
		var city := flat_city()
		if sloped:
			city.terrain_surface=TerrainSurface.new(4);city.terrain_surface.set_vertex(21,21,5)
		for mask: int in range(1,16):
			city.building.put(20,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,mask))
			var graph := CityTrafficGraph.new();graph.bind_city(city)
			var layer := CityNetworks3D.new();layer._build_region(city,Rect2i(20,20,1,1))
			var patches := layer.physical_patches_in(Rect2i(0, 0, City.WIDTH, City.HEIGHT))
			for x: float in [.073,.173,.237,.419,.573,.827,.923]:
				for z: float in [.073,.173,.237,.419,.573,.827,.923]:
					var p := Vector2(20+x,20+z)
					var top := -INF
					for patch: Dictionary in patches:
						if patch.role not in [CityNetworks3D.PhysicalRole.FLOOR,CityNetworks3D.PhysicalRole.SHOULDER,CityNetworks3D.PhysicalRole.VERGE]: continue
						var t: PackedVector3Array=patch.triangle
						var a := Vector2(t[0].x,t[0].z);var b := Vector2(t[1].x,t[1].z);var c := Vector2(t[2].x,t[2].z)
						var area := (b-a).cross(c-a)
						if absf(area)<1e-10: continue
						var u := (p-a).cross(c-a)/area;var v := (b-a).cross(p-a)/area
						if u>=-.000001 and v>=-.000001 and u+v<=1.000001: top=maxf(top,t[0].y+u*(t[1].y-t[0].y)+v*(t[2].y-t[0].y))
					check(is_finite(top) and absf(graph.walk_point(Vector2i(20,20),Vector2(x,z)).y-top)<.000005,"feet contact actual surface mask=%s slope=%s offset=%s"%[mask,sloped,Vector2(x,z)])
			layer.free()

func test_rising_terrain_does_not_cut_through_a_rigid_lot() -> void:
	var city := flat_city();city.terrain_surface=TerrainSurface.new(4)
	for y: int in range(18,26):
		for x: int in range(21,26): city.terrain_surface.set_vertex(x,y,5)
	for code: int in [112,145,251,Buildings.SUBWAY_STATION]:
		var size := Buildings.size(code)
		var height := CityBuildings3D.base_height(city,Rect2i(Vector2i(20,20),size),code)
		for y: int in range(20,20+size.y):
			for x: int in range(20,20+size.x):
				for corner: Vector3 in CityGeometry3D.ground_corners(city,Vector2i(x,y)):
					check(height>=corner.y-.000001,"terrain stays below the rigid floor for model %s"%code)
