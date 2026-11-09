# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func test_casino_effects_follow_surface_visibility_in_either_toggle_order() -> void:
	var city := flat_city(50000000)
	city.founded_year = 2010
	var builder := Builder.new(city,CityStats.new())
	check(builder.apply(Tools.Kind.ARCOLOGY_ORBIT,Vector2i(30,30),Vector2i(30,30)).get("ok",false))
	var encoded := SaveFormat.encode_city(city)
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	view.bind_city(city)
	view.set_active(true)
	view.refresh(true)
	for underground_first: bool in [false,true]:
		view.set_night_mode(false,true)
		view.set_underground(underground_first)
		view.set_night_mode(true,true)
		var lights := view.night.casinos
		check_eq(lights.lots.size(),1,"casino effects exist for the actual model")
		if lights.lots.is_empty(): continue
		var neon: MeshInstance3D = lights.lots[0].neon
		check_eq(neon.is_visible_in_tree(),not underground_first,"night honours the current view")
		view.set_underground(true)
		check(not neon.is_visible_in_tree(),"underground hides detached casino neon")
		for mesh: Node in lights.find_children("*","GeometryInstance3D",true,false):
			check(not (mesh as Node3D).is_visible_in_tree(),"panes, features and searchlights hide too")
		view.refresh(true)
		await process_frame
		await process_frame
		check(not lights.is_visible_in_tree(),"rebuilding underground cannot reveal casino effects")
		view.set_overlay(&"crime")
		view.set_underground(false)
		check(not lights.is_visible_in_tree(),"a data overlay also hides surface effects")
		view.set_overlay(&"none")
		check(lights.is_visible_in_tree(),"returning to the surface restores the lights")
		check(lights.lots[0].neon.is_visible_in_tree(),"the restored neon draws again")
		check(view.is_night_mode(),"changing view preserves the night preference")
	check_eq(SaveFormat.encode_city(city),encoded,"view changes never alter the city")
	view.free()

func test_hidden_surface_lighting_tables_are_dark_on_the_renderer() -> void:
	if DisplayServer.get_name() == "headless":
		print("  SKIP lighting-table pixels: requires a native renderer")
		return
	OS.low_processor_usage_mode = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var city := flat_city(50000000)
	city.founded_year = 2010
	var builder := Builder.new(city,CityStats.new())
	check(builder.apply(Tools.Kind.ARCOLOGY_ORBIT,Vector2i(30,30),Vector2i(30,30)).get("ok",false))
	check(builder.apply(Tools.Kind.ROAD,Vector2i(26,24),Vector2i(26,40)).get("ok",false))
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	view.bind_city(city)
	view.set_active(true)
	view.refresh(true)
	view.set_night_mode(true,true)
	await process_frame
	await process_frame
	check_gt(view.street_lamps.placements.size(),0,"real road lamps populate their lighting table")
	var probe := SubViewport.new()
	probe.size = Vector2i(128,128)
	probe.disable_3d = true
	probe.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(probe)
	var rect := ColorRect.new()
	rect.size = Vector2(128,128)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
render_mode unshaded;
global uniform sampler2D scdd_night_lamps;
global uniform sampler2D scdd_night_wash;
void fragment() {
	COLOR = vec4(texture(scdd_night_lamps,UV).a,texture(scdd_night_wash,UV).a,0.0,1.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	probe.add_child(rect)
	await _check_lighting_pixels(probe,true,"surface")
	view.set_underground(true)
	await _check_lighting_pixels(probe,false,"underground")
	view.refresh(true)
	await process_frame
	await _check_lighting_pixels(probe,false,"rebuild underground")
	view.set_overlay(&"crime")
	view.set_underground(false)
	await _check_lighting_pixels(probe,false,"data overlay")
	view.set_overlay(&"none")
	await _check_lighting_pixels(probe,true,"restored surface")
	view.free()
	probe.free()

func _check_lighting_pixels(probe: SubViewport, lit: bool, context: String) -> void:
	await process_frame
	await process_frame
	# Force a frame even when another editor/test window obscures this one.
	RenderingServer.force_draw(false)
	var image := probe.get_texture().get_image()
	var lamps := 0.0
	var wash := 0.0
	for y: int in 128:
		for x: int in 128:
			var pixel := image.get_pixel(x,y)
			lamps = maxf(lamps,pixel.r)
			wash = maxf(wash,pixel.g)
	check_eq(lamps > .1,lit,context+": street-lamp pools")
	check_eq(wash > .1,lit,context+": casino ground wash")
