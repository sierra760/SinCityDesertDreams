# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Agricultural presentation consumes scalar stats and selection-time inspection.
extends "res://tests/exploration/async_test_case.gd"
const HostFixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost

func before_each() -> void:
	host = HostFixture.make_host(self, "agriculture-ui-tests")
	host.sim.set_process(false)

func after_each() -> void:
	host.free()
	await process_frame

func test_two_tools_and_independent_tax_controls() -> void:
	for tool: int in [Tools.Kind.ZONE_AGR_LOW, Tools.Kind.ZONE_AGR_HIGH]:
		check(host.toolbar.buttons.has(tool), "agriculture tool is discoverable")
		var button := host.toolbar.buttons[tool] as Button
		check(button.icon != null)
		check_ge(button.custom_minimum_size.y,44)
	check(host.toolbar.get_combined_minimum_size().x <= float(Toolbar.WIDTH),"farm captions retain existing sidebar width")
	var budget := host.open_window("budget") as BudgetWindow
	await HostFixture.settle(self,4)
	check(budget._tax_spinners.has(&"agricultural"), "independent Agriculture tax row")
	check(not budget.ledger_text(&"taxes_agricultural").is_empty(), "separate tax income account")
	if not budget._tax_spinners.has(&"agricultural"): return
	var spinner := budget._tax_spinners[&"agricultural"] as TouchNumberField
	check_eq(spinner.value,7.0)
	var rci := Vector3i(host.sim.stats.tax_residential,host.sim.stats.tax_commercial,host.sim.stats.tax_industrial)
	for rate in [0,20]:
		budget.set_tax(&"agricultural",rate)
		check_eq(host.sim.stats.tax_agricultural,rate)
		check_eq(Vector3i(host.sim.stats.tax_residential,host.sim.stats.tax_commercial,host.sim.stats.tax_industrial),rci)
	budget.set_tax(&"agricultural",-1)
	check_eq(host.sim.stats.tax_agricultural,0)
	budget.set_tax(&"agricultural",21)
	check_eq(host.sim.stats.tax_agricultural,20)

func test_fourth_demand_binding_preserves_vector_api() -> void:
	host.sim.stats.demand = Vector3i(100,-200,300)
	host.sim.stats.demand_agricultural = 456
	host.status_bar.refresh(host.sim)
	check_eq(host.status_bar.demand_meter.demand,Vector3i(100,-200,300))
	check(host.status_bar.has_method("set_agricultural_demand"), "additive independent demand setter")
	if not host.status_bar.has_method("set_agricultural_demand"): return
	check_eq(host.status_bar.demand_meter.get("agricultural_demand"),456)
	check(host.status_bar.demand_meter.tooltip_text.contains("Agriculture 456"))
	host.status_bar.call("set_agricultural_demand",-999)
	check_eq(host.status_bar.demand_meter.get("agricultural_demand"),-999)
	host.status_bar.show_editing("New land")
	check_eq(host.status_bar.demand_meter.get("agricultural_demand"),0, "editing clears earlier farm demand")

func test_olive_palette_density_maps_overlay_and_transport_precedence() -> void:
	check_eq(Zones.COLORS[Zones.AGR_LOW],Color("b7c985"))
	check_eq(Zones.COLORS[Zones.AGR_HIGH],Color("71884a"))
	var city := host.sim.city
	for kind: int in [Zones.AGR_LOW,Zones.AGR_HIGH]:
		var map := MiniMap.new()
		map.city = city
		var tint: Color = Zones.COLORS[kind]
		city.stamp_building(20,20,AgricultureParams.building_id(&"vegetables"),kind)
		check_eq(MiniMap.tile_color(city,20,20),tint,"developed agriculture retains density")
		for state_id: int in [AgricultureParams.state_id(&"prepared",1),AgricultureParams.state_id(&"dormant",1)]:
			city.stamp_building(22,20,state_id,kind)
			check_eq(MiniMap.tile_color(city,22,20),tint,"prepared/dormant retain density")
			check_eq(CityGeometry3D.cell_sand_color(city,22,20),Color(.75,.633,.49).lerp(tint,.65),"visible farm ground uses density tint")
		map.generate_image()
		await HostFixture.settle(self,2)
		var build_pixel := map.get_image().get_pixel(20,20)
		check(build_pixel.is_equal_approx(Color(Color(tint).to_rgba32())), "Build map canonical tint")
		var texture := map.navigation_texture()
		check(texture != null)
		if texture != null:
			check(texture.get_image().get_pixel(20,20).is_equal_approx(build_pixel),"Explore consumes same north-up map tint")
		var overlay := CityOverlaySampler.cell_color(&"zones",kind)
		check_eq(Color(overlay.r,overlay.g,overlay.b),tint)
		var names: Array = CityOverlaySampler.legend_entries(&"zones").map(func(entry: Array) -> String: return entry[1])
		check(String(Zones.NAMES[kind]) in names,"zone key identifies both densities")
		city.building.put(20,20,Buildings.NONE)
		var sand := CityGeometry3D.cell_sand_color(city,20,20)
		check_eq(sand,Color(.75,.633,.49).lerp(tint,.65))
		city.building.put(20,20,Buildings.POWER_LINE_FIRST)
		check_eq(CityGeometry3D.cell_sand_color(city,20,20),sand,"power retains zoned ground")
		city.building.put(20,20,Buildings.ROAD_FIRST)
		check_eq(MiniMap.tile_color(city,20,20),MiniMap.COLOR_ROAD,"road symbol precedes farm zoning")
		check_eq(CityGeometry3D.cell_sand_color(city,20,20),Color(.75,.633,.49),"road ground remains unchanged")
		map.free()

func test_inspector_uses_live_active_and_dormant_reasons_and_loads() -> void:
	var city := host.sim.city
	city.stamp_building(20,20,AgricultureParams.building_id(&"greenhouse"),Zones.AGR_HIGH)
	city.stamp_building(24,20,AgricultureParams.state_id(&"dormant",1),Zones.AGR_HIGH)
	host.sim.networks_changed(Rect2i(19,19,7,3))
	var agriculture := host.sim.get_system(&"agriculture") as AgricultureSystem
	var dormant_anchor := Vector2i(24,20)
	check_eq(agriculture.inspect_tile(dormant_anchor)["state"],&"dormant")
	check(not str(agriculture.inspect_tile(dormant_anchor)["blocked_reason"]).is_empty())
	for at: Vector2i in [Vector2i(20,20),dormant_anchor]:
		var expected := agriculture.inspect_tile(at)
		var info := QueryPanel.describe(city,host.sim,at)
		check_eq(info.get("Agricultural state"),String(expected.state).capitalize())
		check_eq(info.get("Agricultural density"),"High")
		check_eq(info.get("Agricultural jobs"),expected.jobs)
		check_eq(info.get("Water requested"),expected.water_required)
		check_eq(info.get("Power requested"),expected.power_required)
		check_eq(info.get("Water supply"),"Fully supplied" if expected.water_supplied else "Not fully supplied")
		check_eq(info.get("Power supply"),"Fully supplied" if expected.power_supplied else "Not fully supplied")
		check_eq(info.get("Development reason"),expected.blocked_reason)

func test_graph_identity_and_history_values_are_stable() -> void:
	var graph := host.open_window("graphs") as GraphsWindow
	for name: StringName in [&"agricultural_jobs",&"agricultural_lots",&"demand_agricultural",&"taxes_agricultural"]:
		host.sim.stats.history[name] = PackedInt32Array([1,3,7])
		check(graph._series_boxes.has(name),"history is selectable")
		graph.set_series_enabled(name,true)
		check(GraphsWindow.ZONE_SERIES_COLORS.has(name),"farm histories keep stable olive identity")
	graph.set_series_enabled(&"population",false)
	graph.refresh()
	check_eq(graph.canvas().series.size(),4)
	check_eq(GraphsWindow.GraphCanvas.value_text(&"taxes_agricultural",7),NoticeLines.money(7))
	for row: Dictionary in graph.canvas().series:
		check_eq(row.values,PackedInt32Array([1,3,7]))
		check_eq(row.color,Zones.COLOR_AGR_HIGH)

func test_phone_and_ipad_controls_fit_and_keep_44_point_targets() -> void:
	for display: Dictionary in [{"size":Vector2i(390,844),"safe":Rect2i(0,60,390,750)},{"size":Vector2i(1024,768),"safe":Rect2i(0,24,1024,724)}]:
		root.size = display.size
		host.display_layout.refresh_with_mobile_metrics(root.size,1,display.safe,0)
		await HostFixture.settle(self,8)
		for window_name in ["budget","graphs","help"]:
			var window := host.open_window(window_name)
			await HostFixture.settle(self,8)
			var panel: Control = window.get("panel") if window_name == "help" else window.get("_root")
			var chrome: Dictionary = panel.get_meta("window_chrome")
			var scroll := chrome.body_scroll as ScrollContainer
			check(host.display_layout.logical_rect().grow(.1).encloses(panel.get_global_rect()),window_name+" bounds")
			check(scroll.get_h_scroll_bar().max_value<=scroll.get_h_scroll_bar().page+1.0,window_name+" text fits without horizontal pan")
			check_ge((chrome.close_button as Control).size.y,44)
			if window_name == "graphs":
				check((window as GraphsWindow).canvas().size.y <= scroll.size.y,"the chart stays within one visible report page beside the series picker")
			if window_name == "budget" and (window as BudgetWindow)._tax_spinners.has(&"agricultural"):
				var tax := (window as BudgetWindow)._tax_spinners[&"agricultural"] as TouchNumberField
				for target: Control in [tax._minus,tax._plus,tax.get_line_edit()]:
					check_ge(target.size.y,44)
					check_ge(target.size.x,44)
			host.window_manager.close_all()

		host.sim.city.stamp_building(20,20,AgricultureParams.state_id(&"dormant",1),Zones.AGR_HIGH)
		host.sim.networks_changed(Rect2i(19,19,3,3))
		host.query_panel.show_tile(host.sim.city,host.sim,Vector2i(20,20))
		await HostFixture.settle(self,8)
		check(host.display_layout.logical_rect().grow(.1).encloses(host.query_panel.get_global_rect()),"agricultural inspector fits long title on phone and iPad")
		host.query_panel.close()

func test_status_and_open_inspector_do_not_project_on_every_frame() -> void:
	var city := host.sim.city
	city.stamp_building(20,20,AgricultureParams.building_id(&"vegetables"),Zones.AGR_LOW)
	host.sim.networks_changed(Rect2i(19,19,3,3))
	host.query_panel.show_tile(city,host.sim,Vector2i(20,20))
	await HostFixture.settle(self,4)
	var agriculture := host.sim.get_system(&"agriculture") as AgricultureSystem
	var before := agriculture.projection_count()
	for frame in 6:
		host.status_bar.refresh(host.sim)
		await process_frame
	check_eq(agriculture.projection_count(),before,"status and rendering read scalars, not the expensive producer")
	city.building.put(20,19,Buildings.ROAD_FIRST)
	host.sim.networks_changed(Rect2i(20,19,1,1))
	await HostFixture.settle(self,4)
	check(str(host.query_panel.info.get("Development reason","")).contains("water"),"meaningful source event refreshes the previous access reason")

func test_power_warning_respects_actual_agricultural_load() -> void:
	var codes: Array[int] = []
	for archetype: StringName in AgricultureParams.LOW_ARCHETYPES:
		codes.append(AgricultureParams.building_id(archetype))
	for state: StringName in [&"prepared",&"dormant"]:
		for side in range(1,4): codes.append(AgricultureParams.state_id(state,side))
	for archetype: StringName in [&"greenhouse",&"dairy"]:
		codes.append(AgricultureParams.building_id(archetype))
	for code: int in codes:
		var city := flat_city()
		city.stamp_building(20,20,code,Zones.AGR_HIGH)
		var ctx := make_context(city)
		var power := PowerSystem.new()
		power.setup(ctx)
		check(city.conducts_power(20,20) and not city.is_powered(20,20),"real utility pass supplies the disconnected flags")
		var before := var_to_bytes(SaveFormat.encode_city(city))
		var feedback := CityFeedback3D.new()
		root.add_child(feedback)
		feedback.bind_city(city)
		check_eq(feedback.power_warning_count(),1 if UtilityParams.power_load(code)>0 else 0,"only positive agricultural loads warn: "+str(code))
		check_eq(var_to_bytes(SaveFormat.encode_city(city)),before,"warning filter is read-only")
		city.stamp_building(32,20,Buildings.SOLAR_PLANT)
		for x in range(20+Buildings.size(code).x,32): city.building.put(x,20,Buildings.POWER_LINE_FIRST)
		power.setup(ctx)
		check(city.is_powered(20,20),"real solar network powers the entire farm")
		feedback.sync_power()
		check_eq(feedback.power_warning_count(),0,"powered greenhouse/dairy and all zero-load farms have no outage icon")
		feedback.free()
		ctx.systems.clear()
	await process_frame
