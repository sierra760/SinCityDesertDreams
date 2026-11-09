# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The actual landmark must light across compiled/cached surfaces, follow lot
## transforms and construction, and leave its authored daytime materials intact.
extends "res://tests/exploration/async_test_case.gd"

class Host extends Node:
	signal geometry_rebuilt(revision: int)
	var world := Node3D.new()
	var buildings := Node3D.new()
	func exploration_camera() -> Camera3D: return null

func _host() -> Host:
	var host := Host.new()
	host.add_child(host.world)
	host.world.add_child(host.buildings)
	root.add_child(host)
	return host

func _catalog(compiled: bool = true) -> CityModelCatalog:
	var catalog := CityModelCatalog.new()
	catalog.runtime_compilation_enabled = compiled
	catalog.compiled_cache_enabled = false
	check_eq(catalog.load_manifest(CityModelCatalog.ROOT+"catalog.json"),OK)
	return catalog

func _lot(host: Host, catalog: CityModelCatalog, facing: int = 0) -> Node3D:
	var lot := catalog.instantiate_model(Buildings.NEON_DOME)
	lot.set_meta("code",Buildings.NEON_DOME)
	lot.position = Vector3(10+facing*6,2.5,14)
	lot.rotation.y = facing*PI/2.0
	host.buildings.add_child(lot)
	return lot

func _night(host: Host) -> CityNightMode:
	var night := CityNightMode.new()
	host.add_child(night)
	night.bind(host)
	return night

func _show(host: Host) -> Node:
	return host.world.get_node_or_null("SpheroidNightShow")

func test_actual_dome_gets_cell_display_and_ribs_for_all_facings() -> void:
	for compiled: bool in [false,true]:
		var host := _host()
		var catalog := _catalog(compiled)
		for facing: int in 4: _lot(host,catalog,facing)
		var night := _night(host)
		check(_show(host)==null,"no daytime show")
		night.set_enabled(true,true)
		var show := _show(host)
		check(show!=null,"night creates the Spheroid display")
		if show!=null:
			check_eq(show.get_child_count(),4,"one show per landmark")
			for facing: int in 4:
				var lit := show.get_child(facing) as Node3D
				check_eq(lit.global_transform,(host.buildings.get_child(facing) as Node3D).global_transform,"show follows elevation and facing")
				var display := lit.get_node("Display") as MeshInstance3D
				var ribs := lit.get_node("Ribs") as MeshInstance3D
				check_eq(display.mesh.get_faces().size(),660,"all 220 glass triangles carry the screen, once")
				check_gt(ribs.mesh.get_faces().size(),1000,"the structural ribs carry neon")
				check(display.mesh.get_aabb().position.y>.4,"no show on the stone base or doors")
				check_lt(display.mesh.get_aabb().end.y,2.20,"screen follows authored dome, without shadow duplicates")
				check_eq(display.cast_shadow,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				check_eq(ribs.cast_shadow,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		host.free()
		await process_frame

func test_new_landmark_demolition_and_day_cleanup() -> void:
	var host := _host()
	var catalog := _catalog()
	var night := _night(host)
	night.set_enabled(true,true)
	var lot := _lot(host,catalog)
	await process_frame
	await process_frame
	var show := _show(host)
	check(show!=null,"night watches newly placed landmarks")
	if show!=null:
		check_eq(show.get_child_count(),1)
		lot.free()
		host.geometry_rebuilt.emit(1)
		await process_frame
		await process_frame
		check_eq(show.get_child_count(),0,"demolition leaves no floating show")
	_lot(host,catalog)
	await process_frame
	await process_frame
	night.set_enabled(false,true)
	show=_show(host)
	if show!=null:
		check_eq(show.get_child_count(),0,"day removes all show geometry")
		check(not show.is_processing(),"day does no animation work")
	host.free()
	await process_frame

func test_authored_materials_and_persistent_cache_remain_daytime() -> void:
	var host := _host()
	var catalog := _catalog()
	catalog.compiled_cache_enabled=true
	var lot := _lot(host,catalog)
	var saved: Array = []
	for node: Node in lot.find_children("*","MeshInstance3D",true,false):
		for surface: int in node.mesh.get_surface_count():
			var material := node.get_active_material(surface) as BaseMaterial3D
			if material!=null: saved.append([material,material.albedo_color,CityNightMode._save(material)])
	var night := _night(host)
	night.set_enabled(true,true)
	check(_show(host)!=null,"cached model also gets a show")
	night.set_enabled(false,true)
	for snapshot: Array in saved:
		check_eq(snapshot[0].albedo_color,snapshot[1])
		check_eq(CityNightMode._save(snapshot[0]),snapshot[2],"day state restored exactly")
	var reader := _catalog()
	reader.compiled_cache_enabled=true
	var cached := _lot(host,reader,1)
	check_eq(reader.compiled_cache_hits,1,"fresh catalog reads the disk scene")
	night.set_enabled(true,true)
	var show := _show(host)
	if show!=null: check_eq(show.get_child_count(),2,"disk-cached and in-memory models both light")
	check(cached!=null)
	host.free()
	await process_frame

func test_actual_city_batches_overlays_refresh_and_save_isolation() -> void:
	var city := flat_city(50000000)
	city.stamp_building(40,40,Buildings.NEON_DOME)
	city.stamp_building(50,40,Buildings.NEON_DOME)
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	view.bind_city(city)
	view.set_active(true)
	view.refresh(true)
	var encoded := SaveFormat.encode_city(city)
	view.set_night_mode(true,true)
	var show := view.world.get_node_or_null("SpheroidNightShow")
	check(show!=null,"actual city view has the show")
	if show!=null:
		check_eq(show.get_child_count(),2,"batched landmarks both have visible display copies")
		for lot: Node in show.get_children():
			check((lot.get_node("Display") as MeshInstance3D).is_visible_in_tree(),"screen is outside hidden batch sources")
		check(not show.is_processing(),"the seasonal display has no per-frame callback")
		view.set_overlay(&"crime")
		check(not show.is_visible_in_tree(),"data overlay hides the complete show with buildings")
		view.set_overlay(&"")
		check(show.is_visible_in_tree(),"return to normal restores the show")
		view.set_underground(true)
		check(not show.is_visible_in_tree(),"Underground hides the complete show")
		view.set_underground(false)
	view.set_night_mode(false,true)
	check_eq(SaveFormat.encode_city(city),encoded,"night mode and animation never alter save bytes")
	view.set_overlay(&"crime")
	view.set_night_mode(true,true)
	if show!=null: check(not show.is_visible_in_tree(),"entering night in an overlay stays hidden")
	view.set_overlay(&"")
	city.clear_footprint(40,40)
	view.refresh()
	await process_frame
	await process_frame
	if show!=null: check_eq(show.get_child_count(),1,"actual regional demolition removes its display")
	city.stamp_building(60,40,Buildings.NEON_DOME)
	view.refresh()
	await process_frame
	await process_frame
	if show!=null: check_eq(show.get_child_count(),2,"actual regional construction adds its display")
	view.free()
	await process_frame

func test_cells_hold_one_whole_colour_and_calendar_month_updates_only_uniforms() -> void:
	var city := flat_city(50000000)
	city.stamp_building(40,40,Buildings.NEON_DOME)
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	view.bind_city(city)
	view.set_active(true)
	view.refresh(true)
	view.set_night_mode(true,true)
	var show := view.world.get_node("SpheroidNightShow")
	check(not show.is_processing(),"the seasonal display has no per-frame callback")
	var display := show.get_child(0).get_node("Display") as MeshInstance3D
	var mesh := display.mesh
	var material := mesh.surface_get_material(0) as ShaderMaterial
	var arrays := mesh.surface_get_arrays(0)
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
	check_eq(colours.size(),660,"each of the 220 authored triangular cells has its own colour channel")
	var channels := {}
	for i: int in range(0,colours.size(),3):
		check_eq(colours[i],colours[i+1],"no within-cell gradient")
		check_eq(colours[i],colours[i+2],"all corners of a cell agree")
		channels[colours[i]]=true
	check_gt(channels.size(),3,"horizontal bands use the dome height, not three fixed labels")
	var rows: Array[Vector2]=[]
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	for i: int in range(0,colours.size(),3):
		rows.append(Vector2((points[i].y+points[i+1].y+points[i+2].y)/3.0,colours[i].r))
	rows.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.x<b.x)
	for i: int in range(1,rows.size()):
		check(rows[i].y+0.005>=rows[i-1].y,"cell phase rises monotonically with height, without irregular or diagonal offsets")
		if absf(rows[i].x-rows[i-1].x)<.001:
			check(absf(rows[i].y-rows[i-1].y)<.005,"cells at the same level change together")
	check_gt(rows[-1].y-rows[0].y,.75,"bands cover the height of the dome")
	var grid_levels := {}
	for i: int in range(0,colours.size(),3):
		var level := roundi(colours[i].g*255.0)
		grid_levels[level]=true
	check_gt(grid_levels.size(),3,"actual cell levels are encoded for one-row Explore steps")
	for level: int in grid_levels.size(): check(grid_levels.has(level),"grid levels are consecutive from the bottom upward")
	# Literal month start/end days catch calendar and year-wrap mistakes. These
	# are presentation choices; the behavioural contract is selecting each at
	# its exact simulation boundary, without changing or rebuilding the city.
	var cases := [[0,"457d9cff"],[24,"457d9cff"],[25,"a93652ff"],
		[50,"23704dff"],[75,"b5a1c9ff"],[100,"6e9b75ff"],[125,"d3a654ff"],
		[150,"ad3943ff"],[175,"bc7850ff"],[200,"b97842ff"],[225,"cc752aff"],
		[250,"a65c3dff"],[274,"a65c3dff"],[275,"ae3b42ff"],[299,"ae3b42ff"],
		[300,"457d9cff"],[325,"a93652ff"]]
	for entry: Array in cases:
		city.day=entry[0]
		var encoded := SaveFormat.encode_city(city)
		view.refresh_analytics()
		await process_frame
		check_eq(material.get_shader_parameter("palette_a"),Color(entry[1]),"simulation day %d chooses its calendar palette"%city.day)
		check_eq(display.mesh,mesh,"calendar change never rebuilds the cell geometry")
		check_eq(mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR],colours,"the arrangement stays steady as months change")
		check_eq(SaveFormat.encode_city(city),encoded,"show never writes city/save data")
	var held: Variant = material.get_shader_parameter("palette_a")
	for frame: int in 4: await process_frame
	check_eq(material.get_shader_parameter("palette_a"),held,"rendered frames cannot advance the seasonal pattern")
	city.day=24
	view.refresh_analytics()
	city.day=25
	await process_frame
	check_eq(material.get_shader_parameter("palette_a"),Color("a93652ff"),"day notification before the simulation advances is read after the batch completes")
	view.set_overlay(&"crime")
	city.day=275
	view.set_overlay(&"")
	check_eq(material.get_shader_parameter("palette_a"),Color("ae3b42ff"),"returning from an overlay immediately catches up to the simulation month")
	view.set_night_mode(false,true)
	view.set_night_mode(true,true)
	display=show.get_child(0).get_node("Display") as MeshInstance3D
	material=display.mesh.surface_get_material(0) as ShaderMaterial
	check_eq(material.get_shader_parameter("palette_a"),Color("ae3b42ff"),"entering night in December does not flash January")
	view.free()
	await process_frame

func test_explore_uses_one_second_grid_steps_and_camera_handoff_keeps_meshes() -> void:
	var city := flat_city(50000000)
	city.stamp_building(40,40,Buildings.NEON_DOME)
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	view.bind_city(city)
	view.set_active(true)
	view.refresh(true)
	view.set_night_mode(true,true)
	var show := view.world.get_node("SpheroidNightShow")
	var display := show.get_child(0).get_node("Display") as MeshInstance3D
	var mesh := display.mesh
	var material := mesh.surface_get_material(0) as ShaderMaterial
	check_eq(material.get_shader_parameter("explore_steps"),false,"Build keeps its existing slow bands")
	var camera := Camera3D.new()
	view.world.add_child(camera)
	view.set_exploration_camera(camera)
	check_eq(material.get_shader_parameter("explore_steps"),true,"Explore enables one-cell-row steps")
	check_eq(display.mesh,mesh,"Explore does not rebuild the dome")
	check(not show.is_processing(),"Explore animation has no CPU frame callback")
	view.clear_exploration_camera()
	check_eq(material.get_shader_parameter("explore_steps"),false,"returning to Build restores the slow mode")
	check_eq(display.mesh,mesh)
	view.set_night_mode(false,true)
	view.set_exploration_camera(camera)
	view.set_night_mode(true,true)
	display=show.get_child(0).get_node("Display") as MeshInstance3D
	material=display.mesh.surface_get_material(0) as ShaderMaterial
	check_eq(material.get_shader_parameter("explore_steps"),true,"night entry while already exploring starts in the correct mode")
	check(not show.is_processing())
	view.free()
	await process_frame
