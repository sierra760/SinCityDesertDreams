# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The scheduled simulation passes update the analysis overlays without
## map_dirty events. Each test runs a single Environment or Water day rather
## than a long city run.
extends "res://tests/exploration/async_test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
const PREFS := "user://test_city_analytics_live.cfg"
var host: GameHost
var map_events := 0


func test_scheduled_updates_refresh_analytics_without_map_events() -> void:
	root.size = Vector2i(1280, 800)
	ViewPreferences.write({}, PREFS)
	host = MainScene.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)
	var city: City = flat_city()
	city.building.put(24, 24, Buildings.RES_1X1_FIRST)
	city.underground.put(12, 12, 15)
	host.begin_city(city, {}, 157, null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	await process_frame
	await process_frame
	host.sim.map_changed.connect(func(_rect: Rect2i) -> void: map_events += 1)
	var view := host.city_view_3d
	var geometry_before := _geometry_identity(view)

	# The scheduled Power day clears a seeded service bit on the lone unserved
	# residential lot. Its warning must update at the same completed-day boundary.
	city.flags.set_bits(24, 24, TileFlags.POWERED, true)
	view.feedback.sync_power()
	check(view.feedback.power_warning_count() == 0, "powered baseline has no outage warning")
	host.sim.clock.day = 0
	city.day = 0
	host.sim.advance_day()
	check(not city.is_powered(24, 24), "scheduled Power pass clears power on the unserved residence")
	check(map_events == 0, "Power day emits no map_changed")
	check(view.feedback.power_warning_count() == 1, "scheduled power change updates current warning immediately")
	check(_geometry_identity(view) == geometry_before, "power flags preserve terrain/model/network mesh identities")

	# Seed a visible high crime layer. The monthly Environment pass must
	# replace it on scheduled day 10 without a map event.
	city.crime.data.fill(255)
	host.presentation.set_overlay(&"crime")
	var overlay_builds := view.overlay.rebuild_count
	var overlay_mesh := view.overlay.mesh_instance.mesh
	var crime_before := city.crime.data.duplicate()
	host.sim.clock.day = 9
	city.day = 9
	host.sim.advance_day()
	check(city.crime.data != crime_before, "scheduled Environment pass rewrites crime")
	check(map_events == 0, "Environment day emits no map_changed")
	check(view.overlay.rebuild_count == overlay_builds + 1, "scheduled data change refreshes selected analytical mesh")
	check(view.overlay.mesh_instance.mesh != overlay_mesh, "crime mesh is replaced without a map event")
	_check_overlay_color(view.overlay, city, &"crime")
	check(_geometry_identity(view) == geometry_before, "analytical data change preserves terrain/model/network mesh identities")

	# The scheduled Water day clears a seeded WATERED flag on this unserved pipe.
	# Surface Water and underground pipe color must both update while coexisting.
	city.flags.set_bits(12, 12, TileFlags.WATERED, true)
	host.presentation.set_overlay(&"water")
	host.presentation.set_view_mode(CityPresentationController.ViewMode.UNDERGROUND)
	check(view.overlay.visible and view.underground.visible, "surface water layer and utilities coexist")
	var utility_builds := view.underground.rebuild_count
	var utility_mesh := view.underground.mesh_instance.mesh
	overlay_builds = view.overlay.rebuild_count
	overlay_mesh = view.overlay.mesh_instance.mesh
	host.sim.clock.day = 2
	city.day = 2
	host.sim.advance_day()
	check(not city.is_watered(12, 12), "scheduled Water pass clears water on the unserved pipe")
	check(map_events == 0, "Water day emits no map_changed")
	check(view.overlay.rebuild_count == overlay_builds + 1, "scheduled service flag refreshes Water overlay")
	check(view.overlay.mesh_instance.mesh != overlay_mesh, "Water overlay mesh replaced without a map event")
	check(view.underground.rebuild_count == utility_builds + 1, "scheduled service flag refreshes utility colors")
	check(view.underground.mesh_instance.mesh != utility_mesh, "utility mesh replaced without a map event")
	_check_overlay_color(view.overlay, city, &"water")
	var pipe_colors: PackedColorArray = view.underground.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(_near_color(pipe_colors[0], CityUnderground3D.PIPE_DRY), "pipe mesh shows current unwatered color")
	check(_geometry_identity(view) == geometry_before, "service flags preserve terrain/model/network mesh identities")

	# Repeated presentation refresh is read-only and doesn't rebuild unchanged data.
	var numerical_before := var_to_bytes([SaveFormat.encode_city(city), host.sim.snapshot()])
	overlay_builds = view.overlay.rebuild_count
	utility_builds = view.underground.rebuild_count
	view.refresh_analytics()
	view.feedback.sync_power()
	check(var_to_bytes([SaveFormat.encode_city(city), host.sim.snapshot()]) == numerical_before, "analytics refresh preserves encoded city, systems, clock and RNG bytes")
	check(view.overlay.rebuild_count == overlay_builds and view.underground.rebuild_count == utility_builds, "unchanged analytics reuse cached meshes")
	check(_geometry_identity(view) == geometry_before, "repeated analytics never rebuild terrain or models")
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	root.remove_child(host)
	host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	await process_frame
	await process_frame


func _check_overlay_color(overlay: CityOverlay3D, city: City, kind: StringName) -> void:
	var expected := Color.TRANSPARENT
	for y in City.HEIGHT:
		for x in City.WIDTH:
			expected = CityOverlaySampler.cell_color(kind, CityOverlaySampler.value_at(city, kind, Vector2i(x, y)))
			if expected.a > 0.003: break
		if expected.a > 0.003: break
	var mesh: ArrayMesh = overlay.mesh_instance.mesh
	if expected.a <= 0.003:
		check(mesh.get_surface_count() == 0, "transparent canonical values leave no analytical faces")
	else:
		check(mesh.get_surface_count() == 1, "visible canonical values have one analytical surface")
		if mesh.get_surface_count() != 1: return
		var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		check(_near_color(colors[0], expected), "analytical mesh color matches current canonical city grid")


func _near_color(actual: Color, expected: Color) -> bool:
	for component in 4:
		if absf(actual[component] - expected[component]) >= 1.0 / 255.0: return false
	return true


func _geometry_identity(view: CityView3D) -> Array:
	var ids: Array = [view._geometry_revision]
	for owner: Node3D in [view.chunks, view.buildings, view.networks, view.mesh_batches]:
		ids.append(owner.get_instance_id())
		for child in owner.find_children("*", "", true, false):
			ids.append(child.get_instance_id())
			if child is MeshInstance3D and child.mesh != null: ids.append(child.mesh.get_instance_id())
	return ids
