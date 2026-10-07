# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const MainScene := preload("res://scenes/main.tscn")
const Fixtures := preload("res://tests/real_world/terrain_source_fixtures.gd")
const Fake := preload("res://tests/real_world/fake_terrain_transport.gd")
const REGION := Rect2i(0,0,16,16)
const SIGNED_SEED := -9007199254740993
class CountingLayer extends CityNetworks3D:
 var builds := 0
 func _prepare_bridge_decks(city: City) -> void:
  builds+=1
  super._prepare_bridge_decks(city)
var host: GameHost
var layer: CountingLayer
var fake: RefCounted
func before_each() -> void:
 host=MainScene.instantiate()
 host.preferences_path="user://final-wave-coexistence.cfg"
 root.add_child(host)
 fake=Fake.new()
 fake.install_flat_objects()
 host.new_city_dialog.terrain_transport_factory=fake.make_transport
 layer=CountingLayer.new()
 root.add_child(layer)
func after_each() -> void:
 host.new_city_dialog.close()
 if host.new_city_dialog.terrain_importer!=null:
  while not host.new_city_dialog.terrain_importer.is_drained(): await process_frame
 layer.free()
 host.free()
 fake=null
 await process_frame
func terrain_bytes(city: City) -> PackedByteArray:
 return var_to_bytes([city.terrain_surface.vertices,city.terrain_surface.water,city.terrain_surface.salt,city.terrain_surface.feature,city.altitude.data,city.terrain.data,city.flags.data,city.building.data])
func projection(city: City) -> Dictionary:
 layer.update_regions(city,[REGION])
 var graph := CityTrafficGraph.new()
 graph.bind_city(city)
 var fresh := CityNetworks3D.new()
 root.add_child(fresh)
 fresh.update_regions(city,[REGION])
 check_eq(var_to_bytes(layer.physical_data()),var_to_bytes(fresh.physical_data()),"retained physical owner equals complete fresh projection")
 check_eq(var_to_bytes([layer._deck_profiles,layer._approach_profiles,layer._road_tunnels]),var_to_bytes([fresh._deck_profiles,fresh._approach_profiles,fresh._road_tunnels]),"retained profile inputs equal fresh current City")
 check_eq(var_to_bytes([graph._decks,graph._approaches]),var_to_bytes([fresh._deck_profiles,fresh._approach_profiles]),"current graph and render profile contracts agree")
 var result := layer.physical_data()
 fresh.free()
 return result
func test_import_edit_reset_found_switch_refreshes_current_projection_owners() -> void:
 host.start_new_city({"name":"Previous city","seed":7654})
 host.found_city()
 host.sim.set_speed(GameClock.Speed.PAUSED)
 var previous := host.sim.city
 var previous_bytes := SaveFormat.encode_city(previous)
 var previous_snapshot := host.sim.snapshot().duplicate(true)
 var previous_rng := host.sim.rng.state()
 var candidate := RealWorldTerrain.convert(Fixtures.packet(),Fixtures.controls({"tree_seed":SIGNED_SEED}),Fixtures.metadata())
 check(candidate.ok)
 if not candidate.ok: return
 var baseline: City=RealWorldManifest.restore_baseline(candidate.baseline,Fixtures.metadata(),{}).city
 var baseline_bytes := terrain_bytes(baseline)
 host.preferences["mayor_name"]="Current Mayor"
 host.open_new_city_dialog()
 host.new_city_dialog.accept_real_world(candidate)
 check_eq(host.sim.city,previous)
 check_eq(host.sim.snapshot(),previous_snapshot)
 check_eq(host.sim.rng.state(),previous_rng)
 seed(8172)
 var expected_rng := randi()
 seed(8172)
 host.new_city_dialog.start()
 check_eq(randi(),expected_rng,"imported handoff consumes no global RNG")
 var imported := host.sim.city
 check_eq(imported,candidate.city)
 check_eq(terrain_bytes(imported),baseline_bytes,"accepted actual baseline grids")
 check_eq(imported.mayor,"Current Mayor")
 check_eq(imported.terrain_origin,candidate.origin)
 check_eq(host.editing_params.seed,SIGNED_SEED)
 # One authored bridge makes profile and ordered physics outputs nontrivial.
 imported.building.put(8,8,Buildings.BRIDGE_FIRST)
 imported.flags.put(8,8,RotationMapper.AXIS_FLAG)
 var outer := CityGeometry3D.begin_ground_sampling(previous)
 CityGeometry3D.point_on_ground(previous,Vector2i(2,2),Vector2(.2,.3))
 CityGeometry3D.road_tunnel_profiles(previous)
 var outer_bytes := var_to_bytes([CityGeometry3D._ground_vertex_cache,CityGeometry3D._ground_corner_cache,CityGeometry3D._road_tunnel_cache])
 var initial := projection(imported)
 check_gt(initial.physical_floor_faces.size(),0,"authored bridge exercises real ordered floors")
 var ground_before := CityGeometry3D.point_on_ground(imported,Vector2i(8,8),Vector2(.5,.5))
 var count := layer.builds
 # Terrain tools require an unoccupied target. Remove the fixture bridge, edit,
 # then reinstall it before deriving, preserving the normal terrain-tool gate.
 imported.building.put(8,8,Buildings.NONE)
 check(host.terrain_editor.raise(8,8).ok)
 imported.building.put(8,8,Buildings.BRIDGE_FIRST)
 var altered := projection(imported)
 check_eq(layer.builds,count+1,"raw imported terrain edit invalidates profile inputs")
 check(var_to_bytes(altered)!=var_to_bytes(initial),"altered ground changes actual physical output")
 check(CityGeometry3D.point_on_ground(imported,Vector2i(8,8),Vector2(.5,.5))!=ground_before,"ground query sees current surface")
 check_eq(CityGeometry3D._ground_sampling_city,previous,"nested graph/mesh work restores outer owner")
 check_eq(var_to_bytes([CityGeometry3D._ground_vertex_cache,CityGeometry3D._ground_corner_cache,CityGeometry3D._road_tunnel_cache]),outer_bytes,"unrelated outer ground caches retain exact bytes")
 CityGeometry3D.end_ground_sampling(outer)
 seed(9317)
 expected_rng=randi()
 seed(9317)
 var reset := host.regenerate()
 check_eq(randi(),expected_rng,"reset consumes no global RNG")
 check(reset!=null)
 if reset==null: return
 check(reset!=imported and reset.terrain_surface!=imported.terrain_surface,"reset owns a new City and surface")
 check_eq(terrain_bytes(reset),baseline_bytes,"reset restores all actual baseline grids, removing authored bridge")
 check_eq(reset.mayor,"Current Mayor")
 check_eq(reset.terrain_origin,candidate.origin)
 check_eq(host.editing_params.seed,SIGNED_SEED)
 count=layer.builds
 var reset_projection := projection(reset)
 check_eq(layer.builds,count+1,"reset City replaces completed profile owner")
 check_eq(reset_projection.physical_floor_faces.size(),0,"no stale bridge floors survive baseline reset")
 check(host.found_city())
 host.sim.set_speed(GameClock.Speed.PAUSED)
 check_eq(host.sim.city,reset)
 check_eq(reset.mayor,"Current Mayor")
 check_eq(reset.terrain_origin,candidate.origin)
 var fresh_city := City.new()
 fresh_city.altitude.data.fill(7)
 fresh_city.building.put(8,8,Buildings.ROAD_FIRST)
 host.start_new_city({"name":"Fresh city","seed":31},fresh_city)
 count=layer.builds
 check_gt(projection(fresh_city).physical_floor_faces.size(),0)
 check_eq(layer.builds,count+1,"switching City refreshes the retained owner again")
 check_eq(SaveFormat.encode_city(previous),previous_bytes,"previous city remains exact across import/edit/reset/found/switch")
 check(CityGeometry3D._ground_sampling_city==null,"all temporary sampling scopes are closed")
 print("CURRENT_COEXISTENCE builds=",layer.builds," signed_seed=",SIGNED_SEED," initial_floor_vertices=",initial.physical_floor_faces.size()," altered_floor_vertices=",altered.physical_floor_faces.size())
