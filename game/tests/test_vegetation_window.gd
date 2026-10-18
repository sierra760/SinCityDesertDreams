# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The Vegetation Zones window through the full game host: View menu entry,
## histogram of the city's elevations, dragging a boundary with the pointer
## and the keyboard, switching zones (never all of them), Automatic, the 3D
## view replanting only the trees whose zone changed, Inspect names, unsaved
## changes and the city's simulation staying untouched.
extends "res://tests/exploration/async_test_case.gd"
const MAIN := preload("res://scenes/main.tscn")
var host: GameHost


static func _slope_city() -> City:
	var city := flat_city(50000)
	city.name = "Vegetation Test"
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			city.set_heights(x, y, 2 + x * 24 / (City.WIDTH - 1))
	for x: int in range(6, 122, 6):
		for y: int in range(60, 66, 2): city.building.put(x, y, Buildings.TREES_1 + (x / 6) % 7)
	return city


func before_each() -> void:
	host = MAIN.instantiate()
	host.preferences_path = "user://vegetation-main.cfg"
	root.add_child(host)
	host.begin_city(_slope_city(), {}, 4242, CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	await process_frame


func after_each() -> void:
	host.free()
	await process_frame


static func _count(node: Node, trunk: String) -> int:
	var total := 0
	for child: Node in node.get_children():
		if child.has_node(trunk): total += 1
		elif not child is MeshInstance3D: total += _count(child, trunk)
	return total


func _preserved() -> Array:
	var encoded := SaveFormat.encode_city(host.sim.city)
	encoded.erase("vegetation")
	return [encoded, host.sim.snapshot(), host.sim.rng.state(), host.sim.city.funds]


func test_window_sets_zones_and_replants() -> void:
	check(host.menu_bar.is_enabled(&"vegetation"), "View → Vegetation Zones… is available in a city")
	host.files.mark_saved()
	var before := _preserved()
	host.city_view_3d.refresh()
	var networks: Node = host.city_view_3d.networks
	var automatic := VegetationZones.resolve(host.sim.city)
	var relief := VegetationZones.relief_range(VegetationZones.histogram(host.sim.city)[0])
	var span := relief.y - relief.x
	check(automatic.automatic and automatic.cutoffs == [relief.x + ceili(span * 0.5), relief.x + ceili(span * 0.78)], "automatic zones follow the slope: %s" % str(automatic.cutoffs))
	check_gt(_count(networks, "TreeTrunk"), 0, "upland trees planted on the high ground")
	check_gt(_count(networks, "PalmTrunk"), 0, "palms remain low down")
	host.menu_bar.press(&"vegetation")
	var window := host.window_manager.window("vegetation") as VegetationWindow
	check(window != null and window.visible, "the menu opens the window")
	await process_frame
	var chart := window.histogram
	check_eq([chart.low, chart.high], [1, 27], "chart spans the city's relief with a margin")
	check_eq(chart.boundaries(), [0, 1], "two boundaries with all zones on")
	check(window.status_label.text.contains("Automatic"), "status says automatic")
	check(window.automatic_button.disabled, "Automatic already in effect")
	check((window.zone_rows[0][1] as Label).text.begins_with("Below "), "palm range text: " + (window.zone_rows[0][1] as Label).text)
	check((window.zone_rows[2][1] as Label).text.begins_with("From "), "pine range text: " + (window.zone_rows[2][1] as Label).text)
	# Drag the palm boundary all the way down with the pointer: no palms remain.
	var at := chart.level_x(int(automatic.cutoffs[0]))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(at, chart.size.y * 0.5)
	chart._gui_input(press)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(chart.level_x(chart.low) - 30.0, chart.size.y * 0.5)
	chart._gui_input(move)
	check_eq(host.sim.city.vegetation, {}, "mid-drag the city keeps its zones; only the chart previews")
	check_eq(int(chart.settings.cutoffs[0]), chart.low, "the chart shows the dragged line")
	check(not host.city_view_3d._refresh_queued, "no replanting while dragging")
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	chart._gui_input(release)
	check(host.city_view_3d._refresh_queued or not host.city_view_3d.active, "the change queues a redraw")
	var custom := VegetationZones.sanitize(host.sim.city.vegetation)
	check(not custom.is_empty() and int(custom.cutoffs[0]) == chart.low, "dragging moved the palm line to the bottom: %s" % str(custom))
	check(host.files.has_unsaved_changes(), "the choice is an unsaved change")
	check(not window.automatic_button.disabled, "Automatic can be restored")
	host.city_view_3d.refresh()
	check_eq(_count(networks, "PalmTrunk"), 0, "every palm became woodland or forest")
	var low_tree := Vector2i(6, 60)
	check_eq(QueryPanel.describe(host.sim.city, host.sim, low_tree)["Building"],
		VegetationZones.NAMES[VegetationZones.Zone.PINYON_JUNIPER][host.sim.city.building_at(6, 60) - Buildings.TREES_1], "Inspect names the woodland tree")
	# Keyboard: Up selects the pine line; Left lowers it one level.
	chart.grab_focus()
	var up := InputEventKey.new()
	up.keycode = KEY_UP
	up.pressed = true
	chart._gui_input(up)
	check_eq(chart.selected, 1, "Up selects the higher boundary")
	var pine_line := int(VegetationZones.resolve(host.sim.city).cutoffs[1])
	var left := InputEventKey.new()
	left.keycode = KEY_LEFT
	left.pressed = true
	chart._gui_input(left)
	check_eq(int(window.pending.cutoffs[1]), pine_line - 1, "Left previews the pine line one level lower")
	check_eq(int(VegetationZones.resolve(host.sim.city).cutoffs[1]), pine_line, "the city waits for the keys to settle")
	await create_timer(VegetationWindow.KEY_SETTLE + 0.15).timeout
	check(window.pending.is_empty(), "the keyboard step is applied after a pause")
	check_eq(int(VegetationZones.resolve(host.sim.city).cutoffs[1]), pine_line - 1, "Left lowers the pine line one level")
	# Switch zones off; the last one cannot be.
	(window.zone_rows[0][0] as CheckBox).button_pressed = false
	(window.zone_rows[2][0] as CheckBox).button_pressed = false
	var only := VegetationZones.resolve(host.sim.city)
	check_eq(only.enabled, [false, true, false], "two zones switched off")
	check((window.zone_rows[1][0] as CheckBox).disabled, "the last zone's switch is locked on")
	window.set_zone_enabled(VegetationZones.Zone.PINYON_JUNIPER, false)
	check_eq(VegetationZones.resolve(host.sim.city).enabled, [false, true, false], "and cannot be switched off")
	check_eq(chart.boundaries(), [], "a single zone has no boundary")
	check_eq((window.zone_rows[1][1] as Label).text, "All heights", "the woodland covers every height")
	host.city_view_3d.refresh()
	check_eq(_count(networks, "PalmTrunk"), 0, "no palms")
	var woodland := _count(networks, "TreeTrunk")
	var expected := 0
	for x: int in range(6, 122, 6):
		for y: int in range(60, 66, 2):
			expected += preload("res://scripts/view/city_conifer_3d.gd").grove(Vector2i(x, y), host.sim.city.building_at(x, y), VegetationZones.Zone.PINYON_JUNIPER).size()
	check_eq(woodland, expected, "every tree tile planted as woodland")
	# Saved with the city; Automatic goes back.
	var loaded: City = SaveFormat.decode_city(JSON.parse_string(JSON.stringify(SaveFormat.encode_city(host.sim.city)))).city
	check_eq(loaded.vegetation, host.sim.city.vegetation, "saved and loaded with the city")
	window.automatic_button.pressed.emit()
	check_eq(host.sim.city.vegetation, {}, "Automatic clears the choice")
	host.city_view_3d.refresh()
	check_gt(_count(networks, "PalmTrunk"), 0, "palms return")
	check_eq(_preserved(), before, "map, simulation, randomness and funds untouched")
	check(not host.files.has_unsaved_changes(), "back to the saved state")
	window.close()
	check(not window.visible, "Done closes the window")
