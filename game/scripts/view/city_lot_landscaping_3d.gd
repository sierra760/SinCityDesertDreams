# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Trees planted on building lots at each model's palm spots: geometry-checked
## perimeter pockets plus the palms split out of the models themselves
## (tools/split_model_palms.py). The lot's vegetation zone chooses the tree, as
## for natural groves: the shared grove palm in the desert, junipers and piñons
## in the woodland, pines and firs in the forest.
##
## Each model's planting for a zone is built once and packed; every lot
## instantiates it, sharing meshes, materials and collision shapes.
extends RefCounted

const Palm := preload("res://scripts/view/city_palm_3d.gd")
const Conifer := preload("res://scripts/view/city_conifer_3d.gd")
const PATH := "res://assets/desert-dreams-3d/landscaping.json"
## An upland tree stands at this share of the palm's height, scaled from its
## natural size within MIN_SCALE..MAX_SCALE and never wider than the palm's
## crown, which the planting pocket was checked to clear.
const WOODLAND_HEIGHT := 0.6
const FOREST_HEIGHT := 1.25
const MIN_SCALE := 0.5
const MAX_SCALE := 1.5
## Palms are built at one height with a few crown proportions and scaled to
## each spot, so the whole city shares a handful of palm meshes (each distinct
## mesh is a separate draw batch). A spot takes the widest proportion that does
## not exceed its own, keeping the crown inside its checked pocket.
const PALM_HEIGHT := 0.5
const PALM_PROPORTIONS := [0.1, 0.15, 0.2, 0.24, 0.28, 0.32, 0.38, 0.45]
const WOODLAND_SPECIES := [Conifer.Species.JUNIPER, Conifer.Species.PINYON]
const FOREST_SPECIES := [Conifer.Species.PINE, Conifer.Species.FIR]
static var _profiles: Dictionary = {}
static var _planted := PackedByteArray()
static var _loaded := false
static var _plantings: Dictionary = {}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_planted.resize(Buildings.COUNT)
	if not FileAccess.file_exists(PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary or not data.get("entries") is Array:
		return
	for profile: Variant in data.entries:
		if not profile is Dictionary:
			continue
		var code := int(profile.get("code", -1))
		_profiles[code] = profile
		if code >= 0 and code < _planted.size() and not (profile.get("palms", []) as Array).is_empty():
			_planted[code] = 1


## Whether lots of `code` plant trees, so their vegetation zone matters.
static func has_trees(code: int) -> bool:
	_load()
	return code >= 0 and code < _planted.size() and _planted[code] == 1


static func add_to(model: Node3D, code: int, entry: Dictionary, zone: int = VegetationZones.Zone.PALM) -> void:
	_load()
	var profile: Dictionary = _profiles.get(code, {})
	# A model replacement needs its planting pockets checked again.
	if profile.get("glb_sha256", "") != entry.get("glb_sha256", "missing"):
		return
	var key := Vector2i(code, zone)
	if not _plantings.has(key):
		_plantings[key] = _pack(profile, zone)
	var planting: PackedScene = _plantings[key]
	if planting != null:
		model.add_child(planting.instantiate())


static func _pack(profile: Dictionary, zone: int) -> PackedScene:
	var planted := Node3D.new()
	planted.name = "LotTrees"
	var index := 0
	for row: Array in profile.get("palms", []):
		if row.size() != 5:
			continue
		var tree := tree_for(zone, float(row[3]), float(row[4]), index)
		tree.position = Vector3(float(row[0]), float(row[1]), float(row[2]))
		planted.add_child(tree)
		index += 1
	if planted.get_child_count() == 0:
		planted.free()
		return null
	_own(planted, planted)
	var packed := PackedScene.new()
	packed.pack(planted)
	planted.free()
	return packed


## The tree a palm spot of `height` and `crown_radius` (tile units) carries in
## `zone`; `index` alternates the upland species and their variants.
static func tree_for(zone: int, height: float, crown_radius: float, index: int) -> Node3D:
	if zone == VegetationZones.Zone.PALM:
		var proportion: float = PALM_PROPORTIONS[0]
		for candidate: float in PALM_PROPORTIONS:
			if candidate <= crown_radius / height: proportion = candidate
		var palm := Palm.create(PALM_HEIGHT, PALM_HEIGHT * proportion)
		palm.scale = Vector3.ONE * (height / PALM_HEIGHT)
		return palm
	var forest := zone == VegetationZones.Zone.PINE
	var species: int = (FOREST_SPECIES if forest else WOODLAND_SPECIES)[index % 2]
	var variant := (index / 2) % 3
	var size: Array = Conifer.SIZES[species][variant]
	var target := height * (FOREST_HEIGHT if forest else WOODLAND_HEIGHT)
	var scale := clampf(target / float(size[0]), MIN_SCALE, MAX_SCALE)
	scale = minf(scale, crown_radius / float(size[1]))
	var tree := Conifer.create(species, variant)
	tree.scale = Vector3.ONE * scale
	# Neighboring spots face different ways, like the groves.
	tree.rotation.y = fmod(float(index) * 2.39996, TAU)
	return tree


static func _own(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		_own(child, owner)
