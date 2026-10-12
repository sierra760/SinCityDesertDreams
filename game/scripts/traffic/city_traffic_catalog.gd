# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name CityTrafficCatalog
extends RefCounted
## Authored low-poly traffic models, shared by ambient batches and player-driven vehicles.
## Runtime tile units (1 tile = 16 metres); y=0 feet/waterline; forward -Z.
## Editable Blender masters use metres. Scaling is applied once during compilation.
const PEDESTRIAN_SHADER := preload("res://scripts/traffic/pedestrian_gait.gdshader")
const METRES_PER_TILE := 16.0
const ASSET_ROOT := "res://assets/desert-dreams-traffic/"
const KINDS: Array[StringName] = [&"car", &"compact", &"sedan", &"taxi", &"pickup", &"van", &"bus", &"truck", &"police", &"fire_engine", &"ambulance", &"military", &"train", &"subway", &"ship", &"sailboat", &"helicopter", &"plane"]
const NAMES := {&"car": "Desert Cruiser", &"compact": "Compact", &"sedan": "Sedan", &"taxi": "Taxi", &"pickup": "Pickup", &"van": "Delivery Van", &"bus": "City Bus", &"truck": "Freight Truck", &"police": "Police Cruiser", &"fire_engine": "Fire Engine", &"ambulance": "Ambulance", &"military": "Military Transport", &"train": "Rail Locomotive", &"subway": "Subway Car", &"ship": "Harbor Ship", &"sailboat": "Sailboat", &"helicopter": "Helicopter", &"plane": "Airplane", &"pedestrian": "Pedestrian"}
const TRANSIT_PARTS: Array[StringName] = [&"passenger_carriage", &"passenger_door", &"platform", &"stairs", &"tunnel"]
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static var _metadata: Dictionary = {}

static func vehicle_kinds() -> Array[StringName]:
	return KINDS.duplicate()

## Queries used in per-frame record routing do not need a detached list.
static func is_vehicle_kind(kind: StringName) -> bool:
	return kind in KINDS

static func vehicle_kind_index(kind: StringName) -> int:
	return KINDS.find(kind)

static func is_drivable(kind: StringName) -> bool:
	return kind in KINDS and kind != &"plane"

static func domain(kind: StringName) -> StringName:
	if kind in [&"train", &"subway"]:
		return &"rail"
	if kind in [&"ship", &"sailboat"]:
		return &"water"
	if kind in [&"helicopter", &"plane"]:
		return &"air"
	return &"road"

static func pedestrian_variants() -> int:
	return 16

static func display_name(kind: StringName) -> String:
	return NAMES.get(kind, String(kind).capitalize())

static func dimensions(kind: StringName) -> Vector3:
	if _metadata.is_empty():
		var file := FileAccess.open(ASSET_ROOT + "catalog.json", FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_metadata = parsed
	var key := "pedestrian_00" if kind == &"pedestrian" else String(kind)
	if kind in TRANSIT_PARTS:
		key = "transit/" + String(kind)
	var entry: Dictionary = _metadata.get("models", {}).get(key, {})
	var size: Array = entry.get("size_godot", [1.8, 1.7, 4.4])
	return Vector3(float(size[0]), float(size[1]), float(size[2])) / METRES_PER_TILE

## Conservative authored envelope at feet/waterline, without compiling a mesh.
static func visual_bounds(kind: StringName) -> AABB:
	var size := dimensions(kind)
	var bottom := 0.0
	if domain(kind)==&"water":
		var entry: Dictionary=_metadata.get("models",{}).get(String(kind),{})
		var minimum: Array=entry.get("min_godot",[0.0,0.0,0.0])
		bottom=float(minimum[1])/METRES_PER_TILE
	return AABB(Vector3(-size.x*.5,bottom,-size.z*.5),size)

static func mesh_for(kind: StringName, variant: int = 0, low_detail: bool = false) -> Mesh:
	if kind != &"pedestrian" and kind not in KINDS and kind not in TRANSIT_PARTS:
		return null
	var stem := "pedestrian_%02d" % posmod(variant, pedestrian_variants()) if kind == &"pedestrian" else String(kind)
	if kind in TRANSIT_PARTS:
		stem = "transit/" + String(kind)
	var key := stem + ("_far" if low_detail and kind not in TRANSIT_PARTS else "")
	if _meshes.has(key):
		return _meshes[key]
	var path := ASSET_ROOT + key + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate()
	var groups: Dictionary = {}
	_collect(instance, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE / METRES_PER_TILE), Vector3.ZERO), groups, kind == &"pedestrian")
	var result := ArrayMesh.new()
	for group: Dictionary in groups.values():
		var surface: SurfaceTool = group["surface"]
		surface.set_material(group["material"])
		surface.commit(result)
	instance.free()
	# Polygonal tires have different lowest vertices in near/far exports.
	# Compile ground vehicles to actual contact, retaining source masters and dimensions.
	if kind in KINDS and domain(kind) in [&"road",&"rail"]:
		var bottom := result.get_aabb().position.y
		if absf(bottom)>.0000001:
			var grounded := ArrayMesh.new()
			for index: int in result.get_surface_count():
				var arrays := result.surface_get_arrays(index)
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				for i: int in vertices.size(): vertices[i].y-=bottom
				arrays[Mesh.ARRAY_VERTEX]=vertices
				grounded.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
				grounded.surface_set_material(index,result.surface_get_material(index))
			result=grounded
	_meshes[key] = result
	return result

static func _collect(node: Node, parent_transform: Transform3D, groups: Dictionary, animate_pedestrian: bool = false) -> void:
	var current := parent_transform
	if node is Node3D:
		current *= (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		if part.mesh != null:
			for index in part.mesh.get_surface_count():
				var material := part.get_active_material(index)
				if material is StandardMaterial3D:
					var original := material as StandardMaterial3D
					# Coarse exports preserve material semantics after joining parts.
					# Only skin outside the head/neck bounds belongs to the right arm.
					var wave_skin := animate_pedestrian and String(part.name).ends_with("crowd_skin")
					var elbow := 0.0
					if wave_skin:
						var arrays := part.mesh.surface_get_arrays(index)
						for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
							var point: Vector3=current*vertex
							if point.x>.009 and point.y<.095: elbow=maxf(elbow,point.y)
					var material_key := "%s/%s/%s/%s/%s/%s" % [original.albedo_color, original.roughness, original.metallic, animate_pedestrian,wave_skin,elbow]
					if not _materials.has(material_key):
						_materials[material_key] = material
						if animate_pedestrian:
							var gait := ShaderMaterial.new()
							gait.shader = PEDESTRIAN_SHADER
							gait.set_shader_parameter("tint", original.albedo_color)
							gait.set_shader_parameter("wave_skin",1.0 if wave_skin else 0.0)
							gait.set_shader_parameter("wave_elbow",elbow)
							_materials[material_key] = gait
					material = _materials[material_key]
				var key := material.get_instance_id() if material != null else 0
				if not groups.has(key):
					var surface := SurfaceTool.new()
					surface.begin(Mesh.PRIMITIVE_TRIANGLES)
					groups[key] = {"surface": surface, "material": material}
				var tool: SurfaceTool = groups[key]["surface"]
				tool.append_from(part.mesh, index, current)
	for child in node.get_children():
		_collect(child, current, groups, animate_pedestrian)

static func make_visual(kind: StringName, variant: int = 0) -> Node3D:
	var result := Node3D.new()
	result.name = String(kind).to_pascal_case()
	var mesh := mesh_for(kind, variant)
	if mesh != null:
		var part := MeshInstance3D.new()
		part.mesh = mesh
		result.add_child(part)
	return result

## Detail assets retain their authored scene and one meters-to-tiles conversion.
## Kinds without accepted detail art keep the current catalog appearance.
static func make_detailed_visual(kind: StringName, variant: int = 0) -> ExploreActorVisual:
	var path := "res://assets/desert-dreams-exploration/" + String(kind) + ".tscn"
	if kind != &"pedestrian" and ResourceLoader.exists(path):
		return (load(path) as PackedScene).instantiate() as ExploreActorVisual
	var fallback := TrafficActorVisual.new()
	fallback.name = String(kind).to_pascal_case()
	fallback.configure(kind,variant)
	return fallback

## Nearby pool always uses the authored catalog detail (including crowd rigs).
static func make_nearby_visual(kind: StringName, variant: int = 0) -> ExploreActorVisual:
	var visual := TrafficActorVisual.new()
	visual.configure_nearby(kind,variant)
	if kind == &"pedestrian": visual.set_meta("nearby_pedestrian",true)
	return visual
