# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A house developing somewhere must not rebuild every casino's night lights;
## a change to a casino or landmark lot must, and the lights kept across an
## unrelated change are exactly what a full rebuild would make.
extends "res://tests/exploration/async_test_case.gd"

const Signatures := preload("res://scripts/view/casino_night_signatures.gd")

class Host extends Node:
	signal geometry_rebuilt(revision: int)
	var world := Node3D.new()
	var buildings := Node3D.new()
	func exploration_camera() -> Camera3D: return null

var _catalog: CityModelCatalog

func _host() -> Host:
	var host := Host.new()
	host.add_child(host.world)
	host.world.add_child(host.buildings)
	root.add_child(host)
	return host

func _lot(host: Host, code: int, at: Vector3, cell: Vector2i) -> Node3D:
	if _catalog == null:
		_catalog = CityModelCatalog.new()
		_catalog.compiled_cache_enabled = false
		check_eq(_catalog.load_manifest(CityModelCatalog.ROOT+"catalog.json"),OK)
	var lot := _catalog.instantiate_model(code)
	lot.set_meta("code",code)
	lot.set_meta("cell",cell)
	lot.position = at
	host.buildings.add_child(lot)
	return lot

func _frames(count: int = 3) -> void:
	for _i: int in count: await process_frame

func _arrays(instance: Variant) -> Array:
	if not is_instance_valid(instance): return []
	var node := instance as MeshInstance3D
	var out: Array = [node.global_transform]
	for surface: int in node.mesh.get_surface_count():
		var arrays := node.mesh.surface_get_arrays(surface)
		out.append_array([arrays[Mesh.ARRAY_VERTEX],arrays[Mesh.ARRAY_NORMAL],arrays[Mesh.ARRAY_COLOR]])
	return out

## Everything the casino lights show, by value.
func _picture(casinos: CityCasinoLights3D) -> Array:
	var out: Array = []
	for record: Dictionary in casinos.lots:
		out.append_array([record.code,record.cell,record.bounds,record.door,_arrays(record.get("panes")),_arrays(record.get("neon"))])
		for feature: Variant in record.get("features",[]): out.append(_arrays(feature))
	for beam: Dictionary in casinos._beams: out.append((beam.pivot as Node3D).position)
	out.append(casinos._image.get_data() if casinos._image != null else PackedByteArray())
	return out

func _show_picture(show: Node) -> Array:
	var out: Array = []
	for wrapper: Node in show.get_children():
		out.append((wrapper as Node3D).global_transform)
		for mesh: Node in wrapper.find_children("*","MeshInstance3D",true,false): out.append(_arrays(mesh))
	return out

func _ids(casinos: CityCasinoLights3D) -> Array:
	var out: Array = []
	for record: Dictionary in casinos.lots:
		for key: String in ["panes","neon"]:
			if is_instance_valid(record.get(key)): out.append((record[key] as Node).get_instance_id())
	return out

func _child_ids(node: Node) -> Array:
	var out: Array = []
	for child: Node in node.get_children(): out.append(child.get_instance_id())
	return out

func test_unrelated_geometry_keeps_the_lights_and_real_changes_rebuild_them() -> void:
	var host := _host()
	var orbit := _lot(host,Buildings.ARCOLOGY_ORBIT,Vector3(30,2.5,30),Vector2i(30,30))
	_lot(host,Buildings.NEON_DOME,Vector3(50,2.5,30),Vector2i(50,30))
	var night := CityNightMode.new()
	host.add_child(night)
	night.bind(host)
	night.set_enabled(true,true)
	await _frames()
	var casinos := night.casinos
	var show: Node = night.spheroid
	check_eq(casinos.lots.size(),1,"the casino is lit")
	check_gt(show.get_child_count(),0,"the landmark is lit")
	var ids := _ids(casinos)
	var show_ids := _child_ids(show)
	check_gt(ids.size(),0)
	var picture := _picture(casinos)
	var show_picture := _show_picture(show)

	# A house develops somewhere else.
	var house := _lot(host,Buildings.RES_1X1_FIRST,Vector3(80,2.5,80),Vector2i(80,80))
	host.geometry_rebuilt.emit(2)
	await _frames()
	check_eq(_ids(casinos),ids,"the casino's lights are the same nodes")
	check_eq(_child_ids(show),show_ids,"the landmark's show is the same nodes")
	check(not night._casinos_dirty,"the change was looked at")
	# What was kept is what a full rebuild makes.
	casinos.rebuild()
	show.rebuild()
	check(_picture(casinos) == picture,"kept casino lights equal a full rebuild")
	check(_show_picture(show) == show_picture,"the kept show equals a full rebuild")
	ids = _ids(casinos)
	show_ids = _child_ids(show)
	house.free()
	host.geometry_rebuilt.emit(3)
	await _frames()
	check_eq(_ids(casinos),ids,"a demolished house changes nothing either")

	# A second casino is built.
	var second := _lot(host,251,Vector3(40,2.5,60),Vector2i(40,60))
	host.geometry_rebuilt.emit(4)
	await _frames()
	check_eq(casinos.lots.size(),2,"the new casino is lit")
	var both := _picture(casinos)
	casinos.rebuild()
	check(_picture(casinos) == both,"and matches a full rebuild")

	# The first casino turns to face another street.
	ids = _ids(casinos)
	orbit.rotation.y = PI/2.0
	host.geometry_rebuilt.emit(5)
	await _frames()
	check_ne(_ids(casinos),ids,"a turned casino is relit")
	var turned := _picture(casinos)
	casinos.rebuild()
	check(_picture(casinos) == turned,"and matches a full rebuild")

	# A casino is demolished.
	second.free()
	host.geometry_rebuilt.emit(6)
	await _frames()
	check_eq(casinos.lots.size(),1,"a demolished casino goes dark")
	check_eq(casinos.lots[0].code,Buildings.ARCOLOGY_ORBIT)

	# A second landmark.
	var dome := _lot(host,Buildings.NEON_DOME,Vector3(70,2.5,30),Vector2i(70,30))
	host.geometry_rebuilt.emit(7)
	await _frames()
	check_eq(show.get_child_count(),show_ids.size()*2,"the new landmark is lit")
	dome.free()
	host.geometry_rebuilt.emit(8)
	await _frames()
	check_eq(show.get_child_count(),show_ids.size(),"and goes dark when demolished")

	night.set_enabled(false,true)
	check(casinos.lots.is_empty(),"day removes the lights")
	check(not CityNightMode.materials_modified())
	host.free()

func _glass_mesh(material: StandardMaterial3D) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,material)
	return mesh

func _batch(mesh: Mesh) -> MultiMeshInstance3D:
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh = mesh
	batch.multimesh.instance_count = 2
	return batch

## The batcher draws a casino's glass from a node outside its lot. That glass
## is lit pane by pane and must never also get the generic window pattern.
func test_batched_casino_glass_is_not_lit_as_ordinary_glass() -> void:
	for batch_first: bool in [false,true]:
		for late: bool in [false,true]:
			var host := _host()
			var glass := StandardMaterial3D.new()
			glass.resource_name = "resort_glass"
			var house_glass := StandardMaterial3D.new()
			house_glass.resource_name = "glass"
			var mesh := _glass_mesh(glass)
			var batch := _batch(mesh)
			var house_batch := _batch(_glass_mesh(house_glass))
			var lot := Node3D.new()
			lot.set_meta("code",Buildings.ARCOLOGY_ORBIT)
			var own := MeshInstance3D.new()
			own.mesh = mesh
			lot.add_child(own)
			if batch_first and not late:
				host.world.add_child(batch)
				host.world.move_child(batch,0)
			host.buildings.add_child(lot)
			if not batch_first and not late: host.world.add_child(batch)
			var night := CityNightMode.new()
			host.add_child(night)
			night.bind(host)
			night.set_enabled(true,true)
			await _frames()
			if late:
				# A growth day rebuilds the batch chunk while it is night.
				host.world.add_child(batch)
				host.world.add_child(house_batch)
				await _frames()
				check(house_glass.emission_enabled,"ordinary batched glass is still lit")
			var where := "batch %s the lot%s" % ["before" if batch_first else "after", ", added at night" if late else ""]
			check(not night._prepared.has(glass.get_instance_id()),"casino glass is not prepared as a window (%s)" % where)
			check(not glass.emission_enabled,"casino glass keeps its daytime material (%s)" % where)
			check(glass.emission_texture == null,"no window pattern on casino glass (%s)" % where)
			night.set_enabled(false,true)
			check(not CityNightMode.materials_modified(),"materials restored")
			if not house_batch.is_inside_tree(): house_batch.free()
			host.free()
