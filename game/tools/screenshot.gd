# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Boot the game, start a seeded city, lay out a few blocks, run a couple of
## years and write a screenshot. Needs a display.
##
##   godot --path game -s res://tools/screenshot.gd -- out.png [seed] [years] [zoom]
extends SceneTree

var out_path := "screenshot.png"
var seed_value := 1234
var years := 2
var zoom_level := 1


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		out_path = args[0]
	if args.size() >= 2:
		seed_value = int(args[1])
	if args.size() >= 3:
		years = int(args[2])
	if args.size() >= 4:
		zoom_level = int(args[3])
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var host: Node = scene.instantiate()
	root.add_child(host)
	await process_frame
	await process_frame
	var city: City = host.call("start_new_city", {
		"hills": 15, "water": 30, "trees": 35, "coast": "east", "river": true,
		"name": "Comstock Flats", "founded_year": 1950, "seed": seed_value,
	})
	host.call("found_city")
	var sim: Simulation = host.get("sim")
	sim.stats.auto_budget = true
	var b := Builder.new(city, sim.stats, sim)
	var o := _find_flat(city, 26, 26)
	if o.x >= 0:
		b.apply(Tools.Kind.COAL_PLANT, Vector2i(o.x, o.y))
		b.apply(Tools.Kind.WATER_PUMP, Vector2i(o.x + 4, o.y + 3))
		for i in 3:
			var y := o.y + 5 + i * 6
			b.apply(Tools.Kind.ROAD, Vector2i(o.x + 6, y), Vector2i(o.x + 24, y))
			b.apply(Tools.Kind.WATER_PIPE, Vector2i(o.x + 5, y), Vector2i(o.x + 24, y))
		b.apply(Tools.Kind.ROAD, Vector2i(o.x + 6, o.y + 4), Vector2i(o.x + 6, o.y + 24))
		b.apply(Tools.Kind.WATER_PIPE, Vector2i(o.x + 5, o.y + 3), Vector2i(o.x + 5, o.y + 24))
		b.apply(Tools.Kind.POWER_LINE, Vector2i(o.x + 4, o.y + 4), Vector2i(o.x + 5, o.y + 4))
		b.apply(Tools.Kind.POWER_LINE, Vector2i(o.x + 5, o.y + 4), Vector2i(o.x + 5, o.y + 24))
		for i in 3:
			var y := o.y + 6 + i * 6
			b.apply(Tools.Kind.POWER_LINE, Vector2i(o.x + 5, y), Vector2i(o.x + 7, y))
		b.apply(Tools.Kind.ZONE_RES_HIGH, Vector2i(o.x + 7, o.y + 6), Vector2i(o.x + 24, o.y + 10))
		b.apply(Tools.Kind.ZONE_COM_HIGH, Vector2i(o.x + 7, o.y + 12), Vector2i(o.x + 15, o.y + 16))
		b.apply(Tools.Kind.ZONE_RES_LOW, Vector2i(o.x + 16, o.y + 12), Vector2i(o.x + 24, o.y + 16))
		b.apply(Tools.Kind.ZONE_IND_LOW, Vector2i(o.x + 7, o.y + 18), Vector2i(o.x + 24, o.y + 22))
		b.apply(Tools.Kind.POLICE, Vector2i(o.x + 8, o.y + 23))
		b.apply(Tools.Kind.FIRE, Vector2i(o.x + 14, o.y + 23))
	sim.advance_days(GameClock.DAYS_PER_YEAR * years)
	sim.finish_budget_review()
	var view: CityView3D = host.get("city_view_3d")
	view.refresh()
	view.set_zoom_level(zoom_level)
	await process_frame
	if o.x >= 0:
		var focus := Vector2i(o.x + 14, o.y + 12)
		view.set_camera_state(Vector3(focus.x + 0.5, CityGeometry3D.surface_height(city, focus), focus.y + 0.5), view.quarter_turn, view.camera_size)
	for _i in 12:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(out_path)
	print("saved %s (%dx%d), population %d, funds %d" % [out_path, image.get_width(), image.get_height(), sim.stats.total_population(), city.funds])
	quit(0)


func _find_flat(city: City, w: int, h: int) -> Vector2i:
	for radius in range(0, 60):
		for y in range(64 - radius, 64 + radius):
			for x in range(64 - radius, 64 + radius):
				if _flat_rect(city, x, y, w, h):
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func _flat_rect(city: City, x: int, y: int, w: int, h: int) -> bool:
	if x < 2 or y < 2 or x + w >= City.WIDTH - 2 or y + h >= City.HEIGHT - 2:
		return false
	var height := city.ground_height(x, y)
	for dy in h:
		for dx in w:
			if not city.is_flat(x + dx, y + dy) or city.is_water(x + dx, y + dy):
				return false
			if city.ground_height(x + dx, y + dy) != height:
				return false
			var id := city.building_at(x + dx, y + dy)
			if id != Buildings.NONE and not Buildings.is_tree(id):
				return false
	return true
