# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Catalog visuals retain the same explicit, tick-owned motion interface.
class_name TrafficActorVisual
extends ExploreActorVisual

static var _detail_models: Dictionary = {}
static var _detail_catalog_loaded := false

func configure(kind: StringName, variant: int) -> void:
	if kind == &"pedestrian":
		configure_crowd_variant(variant)
	else:
		if not _detail_catalog_loaded:
			_detail_catalog_loaded = true
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CityTrafficCatalog.ASSET_ROOT+"catalog.json"))
			if parsed is Dictionary:
				var models: Variant = parsed.get("models",{})
				if models is Dictionary: _detail_models=models
		if _try_detail(_detail_models.get(String(kind),{})): return
		var part := MeshInstance3D.new()
		part.name = "CatalogModel"
		part.mesh = CityTrafficCatalog.mesh_for(kind,variant)
		add_child(part)

## Malformed or absent detail declarations retain the ordinary catalog fallback.
func _try_detail(entry: Variant) -> bool:
	if not entry is Dictionary: return false
	var path: Variant = entry.get("detail_path","")
	var animation: Variant = entry.get("animation",{})
	if not path is String or not animation is Dictionary: return false
	if not path.begins_with(CityTrafficCatalog.ASSET_ROOT) or not path.ends_with("_detail.glb"): return false
	if not ResourceLoader.exists(path,"PackedScene"): return false
	if animation.has("wheel_radius_m"):
		var default_radius: Variant = animation["wheel_radius_m"]
		if not (default_radius is float or default_radius is int) or not is_finite(float(default_radius)) or float(default_radius)<=0.0: return false
	for key in ["wheels","rotors"]:
		var parts: Variant = animation.get(key,[])
		if not parts is Array: return false
		for part: Variant in parts:
			if not part is Dictionary: return false
			if not part.get("node",null) is String or part.get("axis","") not in ["X","Y","Z"]: return false
	for wheel: Dictionary in animation.get("wheels",[]):
		var radius: Variant = wheel.get("radius_m",animation.get("wheel_radius_m",.24))
		if not (radius is float or radius is int) or not is_finite(float(radius)) or float(radius)<=0.0: return false
	for rotor: Dictionary in animation.get("rotors",[]):
		var rate: Variant = rotor.get("radians_per_second",0.0)
		if not (rate is float or rate is int) or not is_finite(float(rate)): return false
	var scene := load(path) as PackedScene
	if scene == null: return false
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return false
	var imported := instance as Node3D
	for key in ["wheels","rotors"]:
		for part: Dictionary in animation.get(key,[]):
			if imported.find_child(part.node,true,false)==null:
				imported.free()
				return false
	imported.name = "DetailedModel"
	imported.scale = Vector3.ONE/CityTrafficCatalog.METRES_PER_TILE
	add_child(imported)
	configure_animation(animation)
	return true

func configure_nearby(kind: StringName, variant: int) -> void:
	if not _detail_catalog_loaded:
		_detail_catalog_loaded=true
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(CityTrafficCatalog.ASSET_ROOT+"catalog.json"))
		if parsed is Dictionary and parsed.get("models",{}) is Dictionary: _detail_models=parsed.models
	var key := "pedestrian_%02d"%posmod(variant,16) if kind==&"pedestrian" else String(kind)
	if _try_detail(_detail_models.get(key,{})): return
	configure(kind,variant)
