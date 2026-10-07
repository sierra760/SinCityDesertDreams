# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Touched lots with identical complete inputs keep their nodes; changed inputs rebuild them exactly.
extends "res://tests/exploration/async_test_case.gd"
func _lot(view: CityView3D, cell: Vector2i) -> Node:
	for child: Node in view.buildings.get_children():
		if child.get_meta("cell", Vector2i(-1,-1)) == cell: return child
	return null
static func _shape(shape: Shape3D) -> Variant:
	if shape is ConcavePolygonShape3D: return shape.get_faces()
	if shape is BoxShape3D: return shape.size
	if shape is CylinderShape3D or shape is CapsuleShape3D: return [shape.radius, shape.height]
	if shape is SphereShape3D: return shape.radius
	return shape.get_debug_mesh().get_faces()
## Every lot's code, placement and physical shells, independent of node identity.
func _models(view: CityView3D) -> Dictionary:
	var out: Dictionary = {}
	for child: Node3D in view.buildings.get_children():
		var shells: Array = []
		for body: Node in child.find_children("*", "StaticBody3D", true, false):
			for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
				shells.append([body.name, body.collision_layer, shape.global_transform, _shape(shape.shape)])
		var meshes: Array = []
		for mesh: MeshInstance3D in child.find_children("*", "MeshInstance3D", true, false):
			var geometry: Variant = null
			if mesh.mesh is ArrayMesh and mesh.mesh.get_surface_count() > 0: geometry = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			elif mesh.mesh != null: geometry = [mesh.mesh.get_class(), mesh.mesh.get_aabb(), mesh.mesh.get_faces().size()]
			meshes.append([mesh.name if not String(mesh.name).begins_with("@") else "", mesh.global_transform, mesh.visible, geometry])
		out[child.get_meta("cell")] = [child.get_meta("code"), child.transform, shells, meshes]
	return out
func test_identical_lots_keep_nodes_and_changed_lots_rebuild() -> void:
	var loaded := Sc2Import.load("res://assets/cities/La Presa.sc2")
	check(loaded.ok, "La Presa imports")
	var city: City = loaded.city
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lots: Array[Vector2i] = []
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			if Buildings.is_zone_building(city.building.at(x, y)) and city.anchor_of(x, y) == Vector2i(x, y) and Buildings.size(city.building.at(x, y)) == Vector2i.ONE:
				lots.append(Vector2i(x, y))
	check(lots.size() > 200, "fixture has many one-cell lots")
	var retained_total := 0
	for step: int in 12:
		var cell: Vector2i = lots[rng.randi_range(0, lots.size() - 1)]
		var code := city.building.at(cell.x, cell.y)
		if not Buildings.is_zone_building(code): continue
		var neighbors: Dictionary = {}
		for dy: int in range(-2, 3):
			for dx: int in range(-2, 3):
				var other := cell + Vector2i(dx, dy)
				if other == cell: continue
				var lot := _lot(view, other)
				if lot != null: neighbors[other] = lot.get_instance_id()
		city.building.put(cell.x, cell.y, Buildings.RES_1X1_FIRST + (code - Buildings.RES_1X1_FIRST + 1) % 8)
		view.refresh()
		retained_total += int(view.refresh_statistics.retained_lots)
		var changed := _lot(view, cell)
		check(changed != null and int(changed.get_meta("code")) == city.building.at(cell.x, cell.y), "step %d: the changed lot is rebuilt with its new code" % step)
		for other: Vector2i in neighbors:
			var lot := _lot(view, other)
			var local := not CityBuildings3D._reads_neighbors(int(lot.get_meta("code"))) if lot != null else false
			if local: check(lot.get_instance_id() == neighbors[other], "step %d: untouched neighbour %s keeps its node" % [step, str(other)])
	check(retained_total > 0, "growth retained neighbouring lots (" + str(retained_total) + ")")
	var incremental := _models(view)
	view.refresh(true)
	var full := _models(view)
	check(full == incremental, "retained and rebuilt lots equal a forced full rebuild")
	if full != incremental:
		for cell: Vector2i in full:
			if full[cell] != incremental.get(cell):
				var a: Array = full[cell]
				var b: Array = incremental.get(cell, [null, null, [], []])
				print("MISMATCH ", cell, " code ", a[0] == b[0], " transform ", a[1] == b[1], " shells ", a[2] == b[2], " meshes ", a[3] == b[3], " counts ", a[2].size(), "/", b[2].size(), " ", a[3].size(), "/", b[3].size())
				for i: int in mini(a[3].size(), b[3].size()):
					if a[3][i] != b[3][i] or str(a[3][i]) != str(b[3][i]):
						print("  mesh ", i, " full=", str(a[3][i]).left(400))
						print("  mesh ", i, " incr=", str(b[3][i]).left(400))
				print("  full meshes=", str(a[3]).left(900))
				print("  incr meshes=", str(b[3]).left(900))
				for i: int in mini(a[2].size(), b[2].size()):
					if a[2][i] != b[2][i]:
						print("  shell ", i, " full=", str(a[2][i]).left(200), " incremental=", str(b[2][i]).left(200))
						break
				break
	# Ground under a neighbour changes: that lot rebuilds even though its code did not.
	var target: Vector2i = lots[rng.randi_range(0, lots.size() - 1)]
	var before_id := _lot(view, target).get_instance_id()
	city.altitude.data[(target.y + 1) * City.WIDTH + target.x + 1] += 1
	view.refresh()
	var after := _lot(view, target)
	check(after != null and after.get_instance_id() != before_id, "a shared-vertex height change rebuilds the adjacent lot")
	incremental = _models(view)
	view.refresh(true)
	check(_models(view) == incremental, "terrain-driven lot rebuild equals a forced full rebuild")
	# A flag change on the lot's own cell still rebuilds it (orientation inputs).
	before_id = _lot(view, target).get_instance_id()
	city.flags.put(target.x, target.y, city.flags.at(target.x, target.y) ^ RotationMapper.AXIS_FLAG)
	view.refresh()
	check(_lot(view, target).get_instance_id() != before_id, "an orientation flag change rebuilds the lot")
	view.queue_free()
	await process_frame
