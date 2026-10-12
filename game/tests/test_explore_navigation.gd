# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"

func command(kind: String, args: Dictionary, owner: String = "test.pack") -> Dictionary:
	return {"kind":kind,"args":args,"owner":owner,"generation":4,"request_id":1}

func test_marker_locations_update_remove_and_owner_cleanup() -> void:
	var api := ExploreModApi.new()
	api.generation = 4
	api.actors = ExploreActorRegistry.new()
	var point := ExploreWorldQueries.copied_point(Vector3(20,1,30),0)
	check_eq(api.apply(command("marker.set",{"key":"stop","options":{"target":point,"label":"Delivery","icon":"objective"}})).code,"ok")
	var markers: RefCounted = api.get("markers")
	check(markers != null,"host exposes marker registry")
	if markers == null: return
	var entries: Array = markers.call("visible_markers",Vector3(20,1,29))
	check_eq(entries.size(),1)
	point.x = 99
	check_eq(entries[0].position,Vector3(20,1,30),"targets copied from script data")
	check_eq(api.apply(command("marker.set",{"key":"stop","options":{"target":{"x":21,"y":1,"z":30},"label":"Next"}})).code,"ok")
	check_eq(markers.call("visible_markers",Vector3(20,1,29)).size(),1,"same key replaces")
	check_eq(api.apply(command("marker.remove",{"key":"stop"},"other.pack")).code,"ok")
	check_eq(markers.call("visible_markers",Vector3(20,1,29)).size(),1,"other owner cannot remove marker")
	api.clear_owner("test.pack")
	check_eq(markers.call("visible_markers",Vector3(20,1,29)).size(),0)

func test_marker_range_validation_and_quotas() -> void:
	var api := ExploreModApi.new()
	api.generation = 4
	api.actors = ExploreActorRegistry.new()
	var options := {"target":{"x":20,"y":1,"z":30},"label":"Hidden target","max_distance":2.0,"map":false}
	check_eq(api.apply(command("marker.set",{"key":"hidden","options":options})).code,"ok")
	var markers: RefCounted = api.get("markers")
	if markers == null: return
	check_eq(markers.call("visible_markers",Vector3(20,1,27)).size(),0,"range hides map and world target")
	check_eq(markers.call("visible_markers",Vector3(20,1,29)).size(),1)
	for bad in [{"target":{}},{"target":{"id":42}},{"target":{"x":INF,"y":0,"z":0}},{"target":{"x":-2,"y":0,"z":0}},{"target":options.target,"icon":"unknown"},{"target":options.target,"max_distance":-1},{"target":options.target,"map":"yes"}]:
		check_eq(api.apply(command("marker.set",{"key":"bad","options":bad})).code,"invalid_argument")
	for i in 15:
		check_eq(api.apply(command("marker.set",{"key":str(i),"options":{"target":options.target}})).code,"ok")
	check_eq(api.apply(command("marker.set",{"key":"extra","options":{"target":options.target}})).code,"quota_exceeded")

func test_lua_marker_bindings_copy_commands() -> void:
	var vm := ExploreLuaBridge.new()
	var context := {"owner":"test.pack","generation":4,"progress":{},"queries":{}}
	check(vm.start("return {on_start=function(api) api.marker.set('stop',{target={x=20,y=1,z=30},label='Delivery'}); api.marker.remove('stop') end}",{},context,7).ok)
	var result := vm.dispatch("on_start",{},context,{})
	check(result.ok,"native marker functions available")
	check_eq(result.commands.size(),2)
	if result.commands.size() == 2:
		check_eq(result.commands[0].kind,"marker.set")
		check_eq(result.commands[0].owner,"test.pack")
		check_eq(result.commands[1].kind,"marker.remove")
	vm.close()

func test_explore_hud_has_navigation_map() -> void:
	var hud := ExploreHUD.new()
	root.add_child(hud)
	check(hud.get("navigation") != null,"Explore has its own expandable navigation")
	hud.free()

func test_map_coordinates_pan_zoom_and_north_up_city_texture() -> void:
	var map := ExploreNavigationMap.new()
	root.add_child(map)
	map.size = Vector2(200,200)
	map.center = Vector2(20,30)
	map.span = 20
	check_eq(map.map_point(Vector2(20,30)),Vector2(100,100))
	check_eq(map.map_point(Vector2(22,28)),Vector2(120,80),"east right, north up")
	check_eq(map.tile_point(Vector2(120,80)),Vector2(22,28))
	map.pan_pixels(Vector2(20,0))
	check_eq(map.center,Vector2(18,30))
	map.set_span(999)
	check_eq(map.span,128.0)
	map.set_span(.01)
	check_eq(map.span,8.0)
	map.pan_pixels(Vector2(99999,-99999))
	check_eq(map.center,Vector2(0,128),"pan stays within city")
	map.free()
	var city := flat_city()
	city.building.put(20,30,Buildings.COAL_PLANT)
	var view := CityView3D.new()
	var overview := MiniMap.new()
	root.add_child(view)
	root.add_child(overview)
	view.bind_city(city)
	view.set_active(true)
	overview.bind(city,view)
	for rotation in 4:
		view.set_camera_state(view.center,rotation,32)
		var image := overview.navigation_texture().get_image()
		check(absf(image.get_pixel(20,30).r-MiniMap.COLOR_CIVIC.r)<.01,"Explore north stays independent of Build rotation")
	overview.free()
	view.free()
	await process_frame

func test_map_layout_clears_status_and_fits_expanded_phone_and_desktop() -> void:
	var navigation := ExploreNavigation.new()
	root.add_child(navigation)
	navigation.set_session_active(true)
	for area: Rect2 in [Rect2(0,44,1280,680),Rect2(0,44,640,300),Rect2(0,44,390,650),Rect2(0,44,360,450),Rect2(0,44,640,185)]:
		var status := Rect2(area.position+Vector2(8,8),Vector2(200,130))
		navigation.apply_layout(area,status,true)
		await process_frame
		await process_frame
		check(area.encloses(navigation._compact.get_global_rect()),"compact map within usable area %s" % area)
		check(not status.intersects(navigation._compact.get_global_rect()),"map clears status %s" % area)
		navigation.set_expanded(true)
		navigation.apply_layout(area,status,true)
		await process_frame
		await process_frame
		check(area.encloses(navigation._expanded.get_global_rect()),"expanded map within usable area %s: %s" % [area,navigation._expanded.get_global_rect()])
		check_ge(navigation._close_button.size.y,44,"touch close target")
		check_eq(navigation._large_map.size.x,navigation._large_map.size.y,"square map retains coordinate scale")
		navigation.set_expanded(false)
	navigation.free()

func test_older_key_profile_keeps_custom_m_binding() -> void:
	var old := ControlBindings.DEFAULTS.duplicate(true)
	old.erase("explore_map")
	old.interact = [KEY_M]
	var bindings := ControlBindings.new()
	bindings.configure(old)
	check_eq(bindings.values().interact,[KEY_M],"new map key cannot reset older custom bindings")
	check(bindings.values().explore_map != [KEY_M],"map receives a free key")

func test_touch_map_pans_and_pinches_once_and_clear_discards_contacts() -> void:
	var map := ExploreNavigationMap.new()
	root.add_child(map)
	map.size = Vector2(200,200)
	map.center = Vector2(64,64)
	map.span = 32
	map.browsing = true
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = Vector2(100,100)
	touch.pressed = true
	map._map_input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(120,100)
	map._map_input(drag)
	check_eq(map.center,Vector2(60.8,64))
	var mouse := InputEventMouseMotion.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.relative = Vector2(20,0)
	map._dragging = true
	map._map_input(mouse)
	check_eq(map.center,Vector2(60.8,64),"emulated mouse must not double a touch pan")
	touch.index = 1
	touch.position = Vector2(160,100)
	map._map_input(touch)
	drag.index = 1
	drag.position = Vector2(200,100)
	map._map_input(drag)
	check_eq(map.span,16.0,"two-finger distance doubles zoom")
	map.reset_gestures()
	check(map._touches.is_empty() and not map._dragging)
	map.free()
