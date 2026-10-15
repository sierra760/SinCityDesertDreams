# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"

const PATH := "res://assets/agriculture/enclosures.json"
const CATALOG := "res://scripts/view/agriculture_asset_catalog.gd"

func _catalog() -> RefCounted:
	check(ResourceLoader.exists(CATALOG), "missing livestock catalog and manifest")
	if not ResourceLoader.exists(CATALOG):
		return null
	return load(CATALOG).new()

func _source() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))

func _reject(data: Variant, message: String) -> void:
	var catalog := _catalog()
	if catalog == null:
		return
	check_eq(catalog.load_manifest(PATH), OK)
	var file := FileAccess.open("user://bad_enclosures.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	check(catalog.load_manifest("user://bad_enclosures.json") != OK, message)
	check(catalog.profile(&"cattle_range").is_empty(), "failure clears previously accepted profiles")
	var animal: Node3D = catalog.make_animal(&"beef_cattle")
	check(animal == null, "failure blocks animal creation")
	if animal != null: animal.free()

func test_accepts_exact_counts_and_separate_feedlot_pens() -> void:
	var catalog := _catalog()
	if catalog == null: return
	check_eq(catalog.load_manifest(PATH), OK)
	for pair: Array in [[&"cattle_range",8],[&"sheep_pasture",10],[&"dairy",8],[&"feedlot",12]]:
		check_eq(catalog.profile(pair[0])["animal_count"],pair[1])
	var pens: Array = catalog.profile(&"feedlot")["pens"]
	check_eq(pens.size(),2)
	check_eq(pens[0]["spawns"].size(),6)
	check_eq(pens[1]["spawns"].size(),6)
	var copy: Dictionary = catalog.profile(&"feedlot")
	copy["pens"].clear()
	check_eq(catalog.profile(&"feedlot")["pens"].size(),2,"returned profiles cannot corrupt validated state")

func test_rejects_stale_animal_or_static_hash() -> void:
	if _catalog() == null: return
	for group: String in ["species","profiles"]:
		var data := _source()
		var key: String = "beef_cattle" if group == "species" else "cattle_range"
		data[group][key]["model_sha256"] = "0".repeat(64)
		_reject(data,"stale model hash")

func test_rejects_malformed_and_nonfinite_or_negative_dimensions() -> void:
	if _catalog() == null: return
	for bad: Variant in [[],null,{"schema_version":1},"oops"]:
		_reject(bad,"malformed root")
	for value: Variant in [-1,0,"NaN",null,1e300]:
		var data := _source()
		data["species"]["beef_cattle"]["body_radius"] = value
		_reject(data,"invalid whole body radius")
	var data := _source()
	data["profiles"]["cattle_range"]["pens"][0]["obstacles"][0]["size"][0] = -1
	_reject(data,"negative obstacle dimension")

func test_rejects_unsupported_species_and_excess_count() -> void:
	if _catalog() == null: return
	var data := _source()
	data["profiles"]["cattle_range"]["species"] = "horse"
	_reject(data,"unsupported species")
	data = _source()
	data["profiles"]["feedlot"]["animal_count"] = 13
	_reject(data,"more than twelve animals")

func test_rejects_whole_body_fence_clearance_and_spawn_overlap() -> void:
	if _catalog() == null: return
	var data := _source()
	data["profiles"]["cattle_range"]["pens"][0]["spawns"][0] = [-20,0]
	_reject(data,"centre in pen but body intersects fence")
	data = _source()
	var spawns: Array = data["profiles"]["cattle_range"]["pens"][0]["spawns"]
	spawns[1] = spawns[0].duplicate()
	_reject(data,"overlapping bodies")

func test_rejects_unreachable_target_and_open_gate() -> void:
	if _catalog() == null: return
	var data := _source()
	data["profiles"]["cattle_range"]["pens"][0]["drink_targets"][0] = [14,-14]
	_reject(data,"target inside trough")
	data = _source()
	data["profiles"]["cattle_range"]["pens"][0]["fences"].pop_back()
	_reject(data,"open fence")
	data = _source()
	# A wall across the yard separates otherwise individually clear positions.
	data["profiles"]["cattle_range"]["pens"][0]["obstacles"].append({"kind":"feed_bunk","bounds":[-21,-1,21,1],"center":[0,1,0],"size":[42,2,2]})
	data["profiles"]["cattle_range"]["pens"][0]["feed_targets"] = [[0,-8]]
	_reject(data,"disconnected feed target")

func test_animals_have_independent_rest_preserving_quadruped_skins() -> void:
	var catalog := _catalog()
	if catalog == null: return
	check_eq(catalog.load_manifest(PATH),OK)
	for species: StringName in [&"beef_cattle",&"dairy_cattle",&"sheep"]:
		var a: Node3D = catalog.make_animal(species)
		var b: Node3D = catalog.make_animal(species)
		check(a != null and b != null)
		if a == null or b == null: continue
		var rig := _rig(a)
		var other := _rig(b)
		check(rig != null and other != null,"imported independent skeletons")
		if rig != null and other != null:
			check_eq(rig.get_bone_count(),13)
			for bone: String in ["Root","Body","Neck","Head","Tail","FrontLeftUpper","FrontLeftLower","FrontRightUpper","FrontRightLower","RearLeftUpper","RearLeftLower","RearRightUpper","RearRightLower"]:
				check(rig.find_bone(bone)>=0,"required joint "+bone)
			var leg := rig.find_bone("FrontLeftLower")
			var rest := rig.get_bone_rest(leg)
			var other_pose := other.get_bone_pose_rotation(leg)
			rig.set_bone_pose_rotation(leg,rig.get_bone_pose_rotation(leg)*Quaternion(Vector3.RIGHT,.3))
			check_eq(rig.get_bone_rest(leg),rest,"pose preserves imported rest")
			check_eq(other.get_bone_pose_rotation(leg),other_pose,"separate animal pose")
		a.free()
		b.free()

func _rig(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child: Node in node.get_children():
		var found := _rig(child)
		if found != null: return found
	return null

func test_rejects_nonfinite_nested_geometry_and_invalid_rig_metadata() -> void:
	var catalog := _catalog()
	if catalog == null: return
	for value: float in [NAN,INF,-INF]:
		var data := _source()
		data["species"]["sheep"]["bounds_metres"][1][0]=value
		check(not catalog._validate(data),"nonfinite exported dimension")
	for field: String in ["triangles","bones","pose_limits_degrees"]:
		var data := _source()
		data["species"]["sheep"][field] = null
		_reject(data,"malformed rig metadata")

func test_path_validation_rejects_clear_points_in_disconnected_areas() -> void:
	var catalog := _catalog()
	if catalog == null: return
	var pen := {"bounds":[-10,-10,10,10],"navigation_bounds":[-8.92,-8.92,8.92,8.92],"obstacles":[{"bounds":[-10,-.2,10,.2]}]}
	var points: Array[Vector2] = [Vector2(0,-5),Vector2(0,5)]
	check(catalog._clear(points[0],pen,1.0) and catalog._clear(points[1],pen,1.0),"endpoints individually clear")
	check(not catalog._connected(points,pen,1.0),"whole body cannot cross blocking divider")
	pen["obstacles"].clear()
	check(catalog._connected(points,pen,1.0),"open yard is reachable")

func test_malformed_scalar_types_fail_without_runtime_errors() -> void:
	var catalog := _catalog()
	if catalog == null: return
	for field: String in ["schema_version","meters_per_tile","units"]:
		var data := _source()
		data[field]=["wrong type"]
		check(not catalog._validate(data),"malformed root scalar "+field)
	for field: String in ["animal_count","species","body_radius","turn_margin","scale","ground_y","units","model","model_sha256"]:
		var data := _source()
		data["profiles"]["cattle_range"][field]=["wrong type"]
		check(not catalog._validate(data),"malformed profile scalar "+field)
