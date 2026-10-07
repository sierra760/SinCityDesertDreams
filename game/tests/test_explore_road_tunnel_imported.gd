# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Road tunnels in bundled imported cities get dry, supported, clear bores.
extends "res://tests/exploration/async_test_case.gd"
const Tunnels := preload("res://scripts/view/city_road_tunnels_3d.gd")
# Bundled city -> number of tunnel entrance cells it contains.
const FIXTURES := {"res://assets/cities/Foothills Ranch.sc2": 8, "res://assets/cities/La Presa.sc2": 1}
var fixture: Node3D
func after_each() -> void:
	if is_instance_valid(fixture): fixture.free()
	await physics_frame
func test_imported_bores_have_clear_lower_support() -> void:
	for path: String in FIXTURES:
		var loaded := Sc2Import.load(path)
		check(loaded.ok,"load city fixture "+path)
		if not loaded.ok: continue
		var city: City = loaded.city
		var encoded := var_to_bytes(SaveFormat.encode_city(city))
		var profiles := Tunnels.profiles(city)
		var entrances := 0
		for cell: Vector2i in profiles: entrances += 1 if profiles[cell].entrance else 0
		check_eq(entrances,FIXTURES[path],"every portal pair resolves in "+path.get_file())
		fixture = Node3D.new()
		root.add_child(fixture)
		var networks := CityNetworks3D.new()
		fixture.add_child(networks)
		networks._road_tunnels = profiles
		# Build only the tunnel geometry and its physics; the rest of the city is not needed.
		for cell: Vector2i in profiles: networks._road_tunnel(city,cell,profiles[cell])
		var world := CityTraversalWorld3D.new()
		fixture.add_child(world)
		var bounds := Rect2i(profiles.keys()[0],Vector2i.ONE)
		for cell: Vector2i in profiles: bounds = bounds.expand(cell)
		var chunks: Array[Dictionary] = [CityGeometry3D.build_chunk(city,bounds.grow(1))]
		world.rebuild(city,chunks,networks.physical_data(),1)
		await physics_frame
		for cell: Vector2i in profiles:
			var profile: Dictionary = profiles[cell]
			var feet := Vector3(cell.x+.5,(profile.floor_start+profile.floor_end)*.5+.002,cell.y+.5)
			var hit := world.support_near(feet,.04,.10,[])
			check(not hit.is_empty(),"each buried cell has lower support "+str(cell))
			check(not world.touches_water(feet),"closed road bore stays dry beneath water "+str(cell))
			check(world.has_clearance(Transform3D(Basis.IDENTITY,feet+Vector3.UP*.04),ExploreActorProfile.shape(1),[]),"each buried road has vehicle clearance "+str(cell))
		check_eq(var_to_bytes(SaveFormat.encode_city(city)),encoded,"building tunnels does not modify the city")
		fixture.free()
		await physics_frame
