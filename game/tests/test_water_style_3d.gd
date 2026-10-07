# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Water presentation must pause, survive edits and preserve the physical city.
extends "res://tests/exploration/async_test_case.gd"

func test_options_exposes_saved_water_animation_preference() -> void:
	var options := OptionsWindow.new()
	check(options.checks.has(&"water_animation"), "Options exposes Animate water")
	if options.checks.has(&"water_animation"):
		options.set_values({"water_animation": false})
		check_eq(options.values().water_animation, false)
		var emitted: Array = []
		options.option_changed.connect(func(key: StringName, value: Variant) -> void: emitted.append([key,value]))
		options.checks[&"water_animation"].button_pressed = true
		check_eq(emitted, [[&"water_animation",true]], "checkbox applies the actual preference")
	options.free()

func test_pause_and_quality_changes_preserve_city_and_geometry() -> void:
	var city := flat_city()
	city.terrain.put(15,16,Terrain.SURFACE)
	city.set_heights(15,16,2,5)
	var encoded := SaveFormat.encode_city(city)
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	var style: RefCounted = view.get("water_style")
	var revision: int = view.traversal_snapshot().revision
	var faces: PackedVector3Array = view.traversal_snapshot().chunks[8].faces.duplicate()
	view.set_water_animation(false)
	var frozen: float = style.get("elapsed")
	style.call("advance",1.0)
	check_eq(style.get("elapsed"),frozen,"paused shader clock does not move")
	view.set_water_animation(true)
	style.call("advance",0.5)
	check_eq(style.get("elapsed"),frozen+0.5,"resume continues the clock without a time jump")
	for quality: String in ["high","balanced","performance"]:
		view.set_render_options(quality,100)
		check_eq(view.traversal_snapshot().revision,revision,"quality cannot rebuild physical water")
		check_eq(view.traversal_snapshot().chunks[8].faces,faces,"picking faces stay fixed")
	check_eq(SaveFormat.encode_city(city),encoded,"presentation cannot change saved city bytes")
	view.free()

func test_shore_metadata_is_live_across_chunks_and_city_replacement() -> void:
	var path := "res://scripts/view/city_water_style_3d.gd"
	check(ResourceLoader.exists(path),"water style provides geometry-derived shore metadata")
	if not ResourceLoader.exists(path): return
	var style: RefCounted = load(path).new()
	var city := flat_city()
	for x: int in [15,16]:
		city.terrain.put(x,16,Terrain.SURFACE)
		city.set_heights(x,16,2,5)
	city.terrain.put(16,16,Terrain.SHORE|Terrain.SLOPE_E)
	var encoded := SaveFormat.encode_city(city)
	style.call("update_city",city)
	var image: Image = style.get("image")
	check(is_equal_approx(image.get_pixel(15,16).r,3.0868621785),"water uses the corrected visible height")
	check(is_equal_approx(image.get_pixel(15,16).g,1.2247448714),"depth retains its seabed height")
	check_eq(image.get_pixel(15,16).b,0.0,"no shore is invented on a chunk edge")
	check_eq(image.get_pixel(16,16).b,3.0,"eastern shelf retains NE and SE authored corners")
	var texture: Texture2D = style.get("texture")
	var rid := texture.get_rid()
	city.set_heights(16,16,2,7)
	style.call("update_city",city)
	check_eq((style.get("texture") as Texture2D).get_rid(),rid,"edits reuse the metadata texture")
	check(is_equal_approx((style.get("image") as Image).get_pixel(16,16).r,4.3116070499),"edited water height reaches the material")
	style.call("update_city",flat_city())
	check_lt((style.get("image") as Image).get_pixel(15,16).r,0.0,"replacement cannot retain previous shores")
	city.set_heights(16,16,2,5)
	check_eq(SaveFormat.encode_city(city),encoded,"metadata never writes to the city")

func test_main_applies_and_reloads_animation_preference() -> void:
	var path := "user://water-style-display.cfg"
	check_eq(ViewPreferences.write({"water_animation":false},path),OK)
	var scene := load("res://scenes/main.tscn") as PackedScene
	var host := scene.instantiate() as GameHost
	host.preferences_path = path
	root.add_child(host)
	check_eq(host.city_view_3d.water_style.enabled,false,"Main restores the saved pause")
	var options := host.open_window("options") as OptionsWindow
	options.set_values(host.prefs.option_values())
	check_eq(options.values().water_animation,false,"Options shows the restored value")
	options.checks[&"water_animation"].button_pressed = true
	check_eq(host.city_view_3d.water_style.enabled,true,"real option signal reaches rendered water")
	check_eq(ViewPreferences.read(path).water_animation,true,"Main persists the changed value")
	host.set_option(&"water_animation",false)
	check_eq(host.city_view_3d.water_style.enabled,false,"Main can pause again")
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	host.free()
	DirAccess.remove_absolute(path)
