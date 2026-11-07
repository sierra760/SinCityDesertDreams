# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Night mode is presentation only: it lights windows, neon, vehicle lamps and
## street lamps under a full moon, restores day exactly, and never changes the
## city, its saves or the model cache.
extends "res://tests/exploration/async_test_case.gd"

class StubView extends Node:
	var world := Node3D.new()
	func exploration_camera() -> Camera3D: return null

func _road(mask: int) -> int:
	return NetworkShapes.shape_id(NetworkShapes.Family.ROAD, mask)

func _stub() -> StubView:
	var view := StubView.new()
	view.add_child(view.world)
	var sun := DirectionalLight3D.new()
	view.world.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_color = CityNightMode.DAY_BACKGROUND
	environment.environment.ambient_light_color = Color.WHITE
	view.world.add_child(environment)
	root.add_child(view)
	return view

func _mesh_with(materials: Array[StandardMaterial3D]) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for material: StandardMaterial3D in materials:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(mesh.get_surface_count()-1,material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	return instance

func _named(name: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = name
	material.albedo_color = Color(.1,.3,.35)
	return material

func test_roles_follow_authored_material_names() -> void:
	check_eq(CityNightMode.role_for("glass"),CityNightMode.Role.WINDOW)
	check_eq(CityNightMode.role_for("glass.001"),CityNightMode.Role.WINDOW,"Blender suffixes are ignored")
	check_eq(CityNightMode.role_for("glass_light"),CityNightMode.Role.WINDOW)
	check_eq(CityNightMode.role_for("glass_dead"),CityNightMode.Role.NONE,"abandoned buildings stay dark")
	check_eq(CityNightMode.role_for("sign_neon_amber"),CityNightMode.Role.NEON)
	check_eq(CityNightMode.role_for("sign_gold"),CityNightMode.Role.SIGN)
	check_eq(CityNightMode.role_for("sign_ink"),CityNightMode.Role.NONE,"sign lettering ink is not a light")
	check_eq(CityNightMode.role_for("Ivory lamp"),CityNightMode.Role.HEADLIGHT)
	check_eq(CityNightMode.role_for("Red lamp"),CityNightMode.Role.TAILLIGHT)
	check_eq(CityNightMode.role_for("street_lamp_glow"),CityNightMode.Role.STREET_LAMP)
	check_eq(CityNightMode.role_for("cream • stucco"),CityNightMode.Role.NONE)

func test_preference_defaults_off_and_validates() -> void:
	check_eq(ViewPreferences.sanitize({}).get("night_mode"),false,"day is the default")
	check_eq(ViewPreferences.sanitize({"night_mode":true}).get("night_mode"),true)
	for invalid: Variant in ["true",1,null]:
		check_eq(ViewPreferences.sanitize({"night_mode":invalid}).get("night_mode"),false)
	var bindings := ControlBindings.new()
	check(bindings.keys_for("General").has(KEY_N),"N toggles night in Build and Explore")
	# An older profile that already uses N elsewhere keeps its keys.
	var older := ControlBindings.DEFAULTS.duplicate(true)
	older.erase("night_mode")
	older["query"] = [KEY_N]
	var clean := ControlBindings.sanitize(older)
	check_eq(clean.query,[KEY_N],"the player's own binding survives")
	check_ne(clean.night_mode,[KEY_N],"night mode moves to a free key")

func test_full_moon_lighting_and_exact_day_restore() -> void:
	var view := _stub()
	var night := CityNightMode.new()
	night.bind(view)
	view.add_child(night)
	var glass := _named("glass.001")
	var neon := _named("sign_neon_ivory")
	neon.emission_enabled = true
	neon.emission = Color(1,.9,.7)
	neon.emission_energy_multiplier = .8
	var stucco := _named("cream • stucco")
	view.world.add_child(_mesh_with([glass,neon,stucco]))
	var before := {}
	for material: StandardMaterial3D in [glass,neon,stucco]:
		before[material] = CityNightMode._save(material)
	var sun: DirectionalLight3D = view.world.get_child(0)
	var environment: Environment = (view.world.get_child(1) as WorldEnvironment).environment
	night.set_enabled(true,true)
	check_eq(night.amount,1.0,"instant night")
	check(CityNightMode.materials_modified(),"the model cache sees lit materials")
	check(glass.emission_enabled and glass.emission_energy_multiplier > 1.0,"windows glow")
	check(glass.uv1_world_triplanar and glass.emission_texture == CityNightMode.window_texture(),"windows vary by world position")
	check_gt(neon.emission_energy_multiplier,.8,"neon brightens after dark")
	check_eq(CityNightMode._save(stucco),before[stucco],"ordinary materials are untouched")
	check(environment.glow_enabled,"neon blooms")
	check(environment.background_color.is_equal_approx(CityNightMode.NIGHT_BACKGROUND),"night sky colour behind the aerial city")
	check(sun.light_color.b > sun.light_color.r,"silver-blue moonlight")
	check_gt(sun.light_energy,0.0,"a full moon still casts light and shadows")
	var mobile := RenderingServer.get_current_rendering_method() == "mobile"
	check(is_equal_approx(sun.light_energy,(0.7 if mobile else 0.325)*CityNightMode.SUN_NIGHT_SCALE),"moon is a fixed share of the backend's sun")
	# A material added while it is night lights up next frame.
	var late := _named("glass")
	view.world.add_child(_mesh_with([late]))
	await process_frame
	await process_frame
	check(late.emission_enabled,"newly placed buildings light up")
	night.set_enabled(false,true)
	for material: StandardMaterial3D in [glass,neon,stucco]:
		check_eq(CityNightMode._save(material),before[material],"day restores %s exactly" % material.resource_name)
	check(not late.emission_enabled,"late material restored too")
	check(not CityNightMode.materials_modified())
	check(not environment.glow_enabled)
	check(environment.background_color.is_equal_approx(CityNightMode.DAY_BACKGROUND),"day background restored")
	check_eq(environment.ambient_light_color,Color.WHITE)
	check_eq(sun.light_color,Color.WHITE)
	view.free()

func test_fade_takes_its_time_both_ways() -> void:
	var view := _stub()
	var night := CityNightMode.new()
	night.bind(view)
	view.add_child(night)
	night.set_enabled(true)
	check(night.is_transitioning(),"dusk fades rather than snapping")
	night._process(CityNightMode.FADE_SECONDS*.5)
	check_between(night.amount,.45,.55,"halfway through dusk")
	night._process(CityNightMode.FADE_SECONDS)
	check_eq(night.amount,1.0)
	night.set_enabled(false)
	night._process(CityNightMode.FADE_SECONDS*2.0)
	check_eq(night.amount,0.0,"dawn returns to day")
	view.free()

func _lamp_city() -> City:
	var city := flat_city()
	for i: int in range(10,31):
		city.building.put(i,20,_road(10))
		city.building.put(20,i,_road(5))
	city.building.put(20,20,_road(15))
	# A diagonal bend stays unlit: its strip runs through the corners.
	city.building.put(40,40,_road(3))
	return city

func test_lamps_stand_on_verges_beside_the_lanes() -> void:
	var city := _lamp_city()
	var encoded := SaveFormat.encode_city(city)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	graph.refresh()
	var lamps := CityStreetLamps3D.new()
	root.add_child(lamps)
	lamps.sync(graph)
	check_gt(lamps.placements.size(),15,"both streets and the junction get lamps")
	var lane_edge := (1.0-CityNetworks3D.ROAD_WIDTH)*.5
	var junctions := 0
	for record: Dictionary in lamps.placements:
		var cell: Vector2i = record.cell
		check(cell != Vector2i(40,40),"no lamp on the diagonal bend")
		var local := Vector2(record.transform.origin.x-cell.x,record.transform.origin.z-cell.y)
		var mask := CityNetworks3D.network_mask(city.building.atv(cell),NetworkShapes.Family.ROAD)
		if mask == 15: junctions += 1
		if mask == 5: check(local.x < lane_edge or local.x > 1.0-lane_edge,"N-S lamp clear of the lanes at %s" % cell)
		if mask == 10: check(local.y < lane_edge or local.y > 1.0-lane_edge,"E-W lamp clear of the lanes at %s" % cell)
		var ground := graph.walk_point(cell,local)
		check(absf(record.transform.origin.y-ground.y) < .021,"post seated on the verge at %s" % cell)
		var lens: Vector3 = lamps.lenses(record)[0]
		var inward := Vector2(lens.x-record.transform.origin.x,lens.z-record.transform.origin.z)
		check_gt(inward.dot(Vector2(cell)+Vector2(.5,.5)-Vector2(record.transform.origin.x,record.transform.origin.z)),0.0,"the arm leans over the road")
	check_eq(junctions,1,"one lamp per junction")
	# Pools sit beneath every lens.
	var image: Image = lamps._image
	for record: Dictionary in lamps.placements:
		for lens: Vector3 in lamps.lenses(record):
			var texel := image.get_pixel(floori(lens.x),floori(lens.z))
			check_gt(texel.a,0.0,"a pool beneath the lens over %s" % record.cell)
	var count := lamps.placements.size()
	lamps.sync(graph)
	check_eq(lamps.placements.size(),count,"unchanged roads keep their lamps")
	check_eq(SaveFormat.encode_city(city),encoded,"lamps never change the city")
	lamps.free()

func test_highway_median_lamps_pair_both_carriageways() -> void:
	var city := flat_city()
	var ns := NetworkShapes.shape_id(NetworkShapes.Family.HIGHWAY,NetworkShapes.NORTH|NetworkShapes.SOUTH)
	for y: int in range(30,50):
		city.building.put(30,y,ns)
		city.building.put(31,y,ns)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	graph.refresh()
	var lamps := CityStreetLamps3D.new()
	root.add_child(lamps)
	lamps.sync(graph)
	var doubles := lamps.placements.filter(func(r: Dictionary) -> bool: return r.kind == "street_lamp_double")
	check_gt(doubles.size(),5,"a lamp row down the median")
	for record: Dictionary in doubles:
		check(is_equal_approx(record.transform.origin.x,31.0),"median lamps stand on the line between carriageways")
		var lenses := lamps.lenses(record)
		check_eq(lenses.size(),2)
		if lenses.size() == 2: check(floori(lenses[0].x) != floori(lenses[1].x),"one lens over each carriageway")
	lamps.free()

func test_main_menu_key_and_preference() -> void:
	var path := "user://night-mode-test.cfg"
	check_eq(ViewPreferences.write({"night_mode":true},path),OK)
	var host := (load("res://scenes/main.tscn") as PackedScene).instantiate() as GameHost
	host.preferences_path = path
	root.add_child(host)
	var view := host.city_view_3d
	check(view.is_night_mode(),"Main restores a saved night")
	var view_menu: PopupMenu = host.menu_bar._menus["View"]
	var top_level := false
	for item: int in view_menu.item_count:
		if view_menu.get_item_text(item).begins_with("Night Mode"): top_level = true
	check(top_level,"Night Mode is in the View menu itself, not a submenu")
	check_eq(view.night.amount,1.0,"restored without a fade")
	host.prefs.set_option(&"night_mode",false)
	check(not view.is_night_mode(),"the menu action turns night off")
	check_eq(ViewPreferences.read(path).get("night_mode"),false,"and saves it")
	view.bind_city(flat_city())
	var encoded := SaveFormat.encode_city(view.city)
	host.prefs.set_option(&"night_mode",true)
	check_eq(SaveFormat.encode_city(view.city),encoded,"night never changes the city")
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	host.free()
	DirAccess.remove_absolute(path)
	check(not CityNightMode.materials_modified(),"leaving the game restores every material")

## A flat, indexed grid of quads (two triangles each) in the XY plane.
func _sheet(origin: Vector3, size: Vector2, columns: int, rows: int) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for y: int in rows + 1:
		for x: int in columns + 1:
			vertices.append(origin + Vector3(size.x * x / columns, size.y * y / rows, 0))
	for y: int in rows:
		for x: int in columns:
			var i := y * (columns + 1) + x
			indices.append_array(PackedInt32Array([i, i + 1, i + columns + 2, i, i + columns + 2, i + columns + 1]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays

func test_casino_neon_keeps_clear_of_lettering() -> void:
	var Edges := preload("res://scripts/view/casino_neon_edges.gd")
	var signs := {}
	# Lettering: one piece of many small faces, 1 m wide, under a roofline at 3 m.
	Edges._add_sign(signs, _sheet(Vector3(-0.5, 2.2, 0), Vector2(1, .6), 6, 3), Transform3D.IDENTITY)
	# A shutter in the sign's colour: a plain six-face board.
	Edges._add_sign(signs, _sheet(Vector3(4, 2.2, 0), Vector2(.4, .6), 1, 3), Transform3D.IDENTITY)
	check(Edges._near_sign(signs, Vector3(0, 2.8, 0), Edges.SIGN_CLEARANCE), "lettering is remembered")
	check(not Edges._near_sign(signs, Vector3(4.2, 2.8, 0), Edges.SIGN_CLEARANCE), "a plain board is not lettering")
	var roofline := [Vector3(-6, 3.0, 0), Vector3(6, 3.0, 0), Vector3(0, 0, 1)]
	var pieces := Edges._clear_of(signs, [roofline], Edges.CROWN_MIN, Edges.SIGN_CLEARANCE)
	check_eq(pieces.size(), 2, "the roofline stops either side of the lettering")
	for piece: Array in pieces:
		for t: float in [0.0, 0.5, 1.0]:
			check(not Edges._near_sign(signs, Vector3(piece[0]).lerp(piece[1], t), Edges.SIGN_CLEARANCE - .01), "no neon touches the lettering")
	# A roofline sitting on a long row of letters would be left dashed: dropped.
	var row := {}
	for i: int in 6: Edges._add_sign(row, _sheet(Vector3(-5.5 + i * 2.0, 2.6, 0), Vector2(1, .5), 6, 3), Transform3D.IDENTITY)
	check(Edges._clear_of(row, [roofline], Edges.CROWN_MIN, Edges.SIGN_CLEARANCE).is_empty(), "a dashed run is dropped")
	# A roof slab over its fascia board is one roofline, not two.
	var stepped := Edges._single([[Vector3(-5, 3.0, 0), Vector3(5, 3.0, 0), Vector3(0, 0, 1)],
		[Vector3(-5, 2.85, -.1), Vector3(5, 2.85, -.1), Vector3(0, 0, 1)]], true)
	check_eq(stepped.size(), 1, "stepped trim draws once")
	check_eq(float(Vector3(stepped[0][0]).y), 3.0, "the top edge is kept")
	# The two ridges on top of a bracket are not rooflines.
	var fins := Edges._no_fins([[Vector3(0, 3, -1), Vector3(0, 3, 1), Vector3(1, 0, 0)],
		[Vector3(-.3, 3, -1), Vector3(-.3, 3, 1), Vector3(-1, 0, 0)],
		[Vector3(-5, 3, 2), Vector3(5, 3, 2), Vector3(0, 0, 1)]])
	check_eq(fins.size(), 1, "only the real roofline is left")

## The highest visible surface of a building under a world point.
func _surface_below(lot: Node3D, point: Vector3) -> float:
	var best := -INF
	for child: Node in lot.find_children("*","MeshInstance3D",true,false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
		for surface: int in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vertices.size()))
			for t: int in range(0,indices.size()-2,3):
				var a: Vector3 = mesh.global_transform*vertices[indices[t]]
				var b: Vector3 = mesh.global_transform*vertices[indices[t+1]]
				var c: Vector3 = mesh.global_transform*vertices[indices[t+2]]
				var area := (b.x-a.x)*(c.z-a.z)-(c.x-a.x)*(b.z-a.z)
				if absf(area) < 1e-12: continue
				var u := ((b.x-point.x)*(c.z-point.z)-(c.x-point.x)*(b.z-point.z))/area
				var v := ((c.x-point.x)*(a.z-point.z)-(a.x-point.x)*(c.z-point.z))/area
				if u < -1e-5 or v < -1e-5 or u+v > 1.0+1e-5: continue
				best = maxf(best,a.y*u+b.y*v+c.y*(1.0-u-v))
	return best

func test_casinos_get_their_own_glass_neon_wash_and_searchlights() -> void:
	var city := flat_city(50000000)
	city.founded_year = 2010
	var builder := Builder.new(city,CityStats.new())
	var placed: Dictionary = builder.apply(Tools.Kind.ARCOLOGY_ORBIT,Vector2i(30,30),Vector2i(30,30))
	check(bool(placed.get("ok",false)),"a Desert Orbit stands in the test city")
	var encoded := SaveFormat.encode_city(city)
	var view := CityView3D.new()
	root.add_child(view)
	await process_frame
	view.bind_city(city)
	view.set_active(true)
	view.refresh(true)
	view.set_night_mode(true,true)
	var casinos := view.night.casinos
	check(casinos != null and casinos.lots.size() == 1,"the casino is found")
	if casinos == null or casinos.lots.is_empty():
		view.free()
		return
	var record: Dictionary = casinos.lots[0]
	var signature: Dictionary = preload("res://scripts/view/casino_night_signatures.gd").of(Buildings.ARCOLOGY_ORBIT)
	check_eq(record.code,Buildings.ARCOLOGY_ORBIT)
	var neon: MeshInstance3D = record.get("neon")
	check(is_instance_valid(neon),"neon runs along the casino's own edges")
	for mesh: Node in record.node.find_children("*","MeshInstance3D",true,false):
		check((mesh as MeshInstance3D).material_overlay == null,"nothing is painted over the building's surfaces")
	var door: Dictionary = record.door
	if is_instance_valid(neon) and not door.is_empty():
		var arrays := neon.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		check_gt(points.size(),0)
		# The rocket has no flat rooflines up high: its neon is corner fins
		# (grid style) and the entrance marquee.
		# Vertex colours come back from the mesh at 8 bits per channel.
		var close := func(x: Color, y: Color) -> bool:
			return absf(x.r - y.r) < .01 and absf(x.g - y.g) < .01 and absf(x.b - y.b) < .01
		var own := false
		for colour: Color in colours:
			if close.call(colour, Color(signature.a).srgb_to_linear()) or close.call(colour, Color(signature.b).srgb_to_linear()): own = true
		check(own,"neon takes the casino's own colours")
		var base: float = record.bounds.position.y
		var side := Vector2(door.front.y,-door.front.x)
		for point: Vector3 in points:
			check_gt(point.y-base,CityCasinoLights3D.NEON_FLOOR-.02,"no neon on planters, plinths or steps")
			var flat := Vector2(point.x,point.z)-Vector2(door.center)
			if absf(flat.dot(side)) < float(door.half_width) and absf(flat.dot(Vector2(door.front))) < .6:
				check_gt(point.y-base,CityCasinoLights3D.DOOR_TOP-.02,"nothing crosses the doorway")
	check_eq(casinos._beams.size(),int(signature.beams),"its searchlights")
	for beam: Dictionary in casinos._beams:
		var lamp: Vector3 = (beam.pivot as Node3D).position
		check_lt(absf(_surface_below(record.node,lamp)-lamp.y),.01,"each searchlight stands on the building's own top surface")
	var features: Array = record.get("features",[])
	check_eq(features.size(),preload("res://scripts/view/casino_night_signatures.gd").features(Buildings.ARCOLOGY_ORBIT).size(),"its signature feature is lit")
	for feature: Variant in features:
		var lit: PackedVector3Array = (feature as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check_gt(lit.size(),0,"the feature has its own glowing geometry")
		for point: Vector3 in lit: check_gt(point.y,record.bounds.position.y+(record.bounds.size.y*.6),"the rocket's crown, high on the building")
	var center := Vector2i(floori(record.bounds.get_center().x),floori(record.bounds.get_center().z))
	check_gt(casinos._image.get_pixelv(center).a,0.5,"its colour washes the ground")
	for prepared: Dictionary in view.night._prepared.values():
		check(not (int(prepared.code) == Buildings.ARCOLOGY_ORBIT and prepared.role in [CityNightMode.Role.WINDOW,CityNightMode.Role.WINDOW_DIM]),
			"casino glass is lit by pane, not by a world pattern on its material")
	var panes: MeshInstance3D = record.get("panes")
	check(is_instance_valid(panes),"lit panes are built from the casino's own glass")
	if is_instance_valid(panes):
		var faces: PackedVector3Array = panes.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check_gt(faces.size(),0)
		var lobby := 0
		var upper := 0
		for face: Vector3 in faces:
			if face.y-record.bounds.position.y < CityCasinoLights3D.LOBBY_HEIGHT: lobby += 1
			else: upper += 1
		check_gt(upper,0,"upper-floor panes are lit")
	check(not door.is_empty(),"the entrance is known")
	view.set_night_mode(false,true)
	check(casinos.lots.is_empty() and casinos._beams.is_empty(),"day removes the casino lights")
	check(not is_instance_valid(panes),"lit panes are removed by day")
	for feature: Variant in features: check(not is_instance_valid(feature),"signature lights are removed by day")
	check(not is_instance_valid(neon),"no neon by day")
	check(not CityNightMode.materials_modified(),"materials restored")
	check_eq(SaveFormat.encode_city(city),encoded,"casino lights never change the city")
	view.free()
