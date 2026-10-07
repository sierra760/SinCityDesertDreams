# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Region layers rebuilt by copying the spans of cells whose inputs did not
## change must equal a fresh projection exactly: every visible, tunnel and
## physical array, every box and obstacle, the used box sizes and every child
## node (class, transform, layers, mesh, material, collision shapes), after
## palms, rubble, parks, roads, rail, power, highway removal, terrain and
## flood edits on real bundled cities.
extends "res://tests/test_case.gd"

var _reused := 0
var _emitted := 0


func after_all() -> void:
	CityNetworks3D.cell_reuse = true


static func _regions() -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for y: int in range(0, City.HEIGHT, 16):
		for x: int in range(0, City.WIDTH, 16): result.append(Rect2i(x, y, 16, 16))
	return result


static func _project(root: CityNetworks3D, city: City) -> Array[Rect2i]:
	var sampling := CityGeometry3D.begin_ground_sampling(city)
	var changed := root.update_regions(city, _regions(), 16)
	CityGeometry3D.end_ground_sampling(sampling)
	return changed


static func _resource(value: Resource) -> Variant:
	if value == null: return null
	if value is BoxMesh: return ["BoxMesh", value.size]
	if value is CylinderMesh: return ["CylinderMesh", value.top_radius, value.bottom_radius, value.height, value.radial_segments]
	if value is ArrayMesh:
		var surfaces: Array = []
		for i: int in value.get_surface_count(): surfaces.append([value.surface_get_arrays(i), _resource(value.surface_get_material(i))])
		return ["ArrayMesh", surfaces]
	if value is StandardMaterial3D: return ["StandardMaterial3D", value.albedo_color, value.roughness, value.metallic, value.shading_mode, value.transparency]
	if value is ShaderMaterial: return ["ShaderMaterial", value.shader.resource_path if value.shader != null else ""]
	if value is Shape3D:
		var properties: Array = [value.get_class()]
		for property: Dictionary in value.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE: properties.append([property.name, value.get(property.name)])
		return properties
	return [value.get_class()]


static func _node(node: Node) -> Array:
	var result: Array = [node.get_class(), "" if String(node.name).begins_with("@") or String(node.name).begins_with("Palm") else String(node.name)]
	if node is Node3D: result.append_array([node.transform, node.visible])
	if node is VisualInstance3D: result.append(node.layers)
	if node is MeshInstance3D: result.append_array([_resource(node.mesh), _resource(node.material_override)])
	if node is CollisionShape3D: result.append_array([_resource(node.shape), node.disabled])
	if node is CollisionObject3D: result.append_array([node.collision_layer, node.collision_mask])
	var children: Array = []
	for child: Node in node.get_children(): children.append(_node(child))
	result.append(children)
	return result


static func _layer(part: CityNetworks3D) -> Array:
	var nodes: Array = []
	for child: Node in part.get_children(): nodes.append(_node(child))
	var sizes: Array = part._box_sizes_used.keys()
	sizes.sort()
	return [part._faces, part._colors, part._cells, part._tunnel_faces, part._tunnel_colors, part._tunnel_cells, part._tunnel_shell_faces, part._tunnel_shell_colors,
		part._tunnel_shell_cells, part._physical_cells, part._physical_groups, part._physical_roles, part._physical_depths, part._physical_triangles,
		part._physical_boxes, part._physical_obstacles, sizes, nodes, part._span_index, part._span_ends, part._span_states, part._node_specs]


func _compare(root: CityNetworks3D, city: City, label: String) -> void:
	var fresh := CityNetworks3D.new()
	_project(fresh, city)
	var same := true
	for origin: Vector2i in fresh._regions:
		var a := _layer(root._regions[origin])
		var b := _layer(fresh._regions[origin])
		if var_to_bytes(a) != var_to_bytes(b):
			same = false
			for k: int in a.size():
				if var_to_bytes(a[k]) != var_to_bytes(b[k]):
					print("    %s region %s differs in field %d" % [label, origin, k])
					break
	check(same, label + " every region equals a fresh projection")
	check(var_to_bytes([root._physical_cells, root._physical_groups, root._physical_roles, root._physical_depths, root._physical_triangles, root._physical_boxes, root._physical_obstacles]) == \
		var_to_bytes([fresh._physical_cells, fresh._physical_groups, fresh._physical_roles, fresh._physical_depths, fresh._physical_triangles, fresh._physical_boxes, fresh._physical_obstacles]), label + " aggregated physical inputs equal")
	fresh.free()


func _sequence(name: String) -> void:
	var loaded := Sc2Import.load("res://assets/cities/%s.sc2" % name)
	check(loaded.ok, name + " imports")
	if not loaded.ok: return
	var city: City = loaded.city
	var root := CityNetworks3D.new()
	_project(root, city)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var road := NetworkShapes.shape_id(NetworkShapes.Family.ROAD, NetworkShapes.NORTH | NetworkShapes.SOUTH)
	var power := NetworkShapes.shape_id(NetworkShapes.Family.POWER, NetworkShapes.EAST | NetworkShapes.WEST)
	var rail := NetworkShapes.shape_id(NetworkShapes.Family.RAIL, NetworkShapes.EAST | NetworkShapes.WEST)
	var networks: Array[Vector2i] = []
	var highways: Array[Vector2i] = []
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var code := city.building.at(x, y)
			if NetworkShapes.is_highway(code): highways.append(Vector2i(x, y))
			elif code >= Buildings.POWER_LINE_FIRST and code < Buildings.RES_1X1_FIRST: networks.append(Vector2i(x, y))
	# Kinds per step: ground cover only (palms, rubble on empty ground), then
	# network, terrain and flood edits; three edits per step.
	var kinds := [[0, 1], [0, 2], [1, 1], [3, 4], [0, 0], [5, 6], [1, 2], [7, 8], [0, 1], [3, 7], [2, 2], [4, 8], [0, 1], [5, 6]]
	for step: int in kinds.size():
		var label := "%s step %d" % [name, step]
		var ground_only: bool = kinds[step][0] <= 2 and kinds[step][1] <= 2
		for i: int in 3:
			var cell := Vector2i(rng.randi_range(1, City.WIDTH - 2), rng.randi_range(1, City.HEIGHT - 2))
			var near: Vector2i = networks[rng.randi_range(0, networks.size() - 1)] + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
			near = near.clamp(Vector2i.ONE, Vector2i(City.WIDTH - 2, City.HEIGHT - 2))
			match kinds[step][i % 2]:
				0: if city.building.atv(cell) == Buildings.NONE: city.building.putv(cell, Buildings.TREES_1 + rng.randi_range(0, 7))
				1: if city.building.atv(near) == Buildings.NONE: city.building.putv(near, Buildings.TREES_1 + rng.randi_range(0, 7))
				2: if city.building.atv(cell) == Buildings.NONE: city.building.putv(cell, Buildings.RUBBLE_1 + rng.randi_range(0, 3))
				3: if city.building.atv(near) < Buildings.POWER_LINE_FIRST and not city.is_water(near.x, near.y): city.building.putv(near, road)
				4: if city.building.atv(near) < Buildings.POWER_LINE_FIRST and not city.is_water(near.x, near.y): city.building.putv(near, power)
				5: if city.building.atv(near) < Buildings.POWER_LINE_FIRST and not city.is_water(near.x, near.y): city.building.putv(near, rail)
				6: if not highways.is_empty(): city.building.putv(highways[rng.randi_range(0, highways.size() - 1)], Buildings.NONE)
				7: city.altitude.put(near.x, near.y, (city.altitude.at(near.x, near.y) & ~City.ALT_MASK) | mini((city.altitude.at(near.x, near.y) & City.ALT_MASK) + 1, City.ALT_MASK))
				8:
					if city.flood_overlay.has(near): city.flood_overlay.erase(near)
					else: city.flood_overlay[near] = 1
		var changed := _project(root, city)
		for region: Rect2i in changed:
			var part: CityNetworks3D = root._regions[region.position]
			if ground_only:
				_reused += part.reused_cells
				_emitted += part.emitted_cells
		_compare(root, city, label)
	root.free()


func test_real_city_cell_reuse() -> void:
	for name: String in ["La Presa", "Foothills Ranch", "Valle del Mar"]:
		_sequence(name)
	print("    ground-cover steps: reused_cells=%d emitted_cells=%d" % [_reused, _emitted])
	check(_reused > 0 and _reused > _emitted, "ground-cover rebuilds copy most nonempty cells of their regions")
