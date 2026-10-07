# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Additional palm planting in geometry-checked perimeter pockets.
## Kept separate from authored buildings so the same palm style serves the city.
extends RefCounted

const Palm := preload("res://scripts/view/city_palm_3d.gd")
const PATH := "res://assets/desert-dreams-3d/landscaping.json"
static var _profiles: Dictionary = {}
static var _loaded := false


static func add_to(model: Node3D, code: int, entry: Dictionary) -> void:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(PATH):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if data is Dictionary and data.get("entries") is Array:
				for profile: Variant in data.entries:
					if profile is Dictionary:
						_profiles[int(profile.get("code", -1))] = profile
	var profile: Dictionary = _profiles.get(code, {})
	# A model replacement needs its planting pockets checked again.
	if profile.get("glb_sha256", "") != entry.get("glb_sha256", "missing"):
		return
	var planted := Node3D.new()
	planted.name = "LotPalms"
	for row: Array in profile.get("palms", []):
		if row.size() != 5:
			continue
		var palm := Palm.create(float(row[3]), float(row[4]))
		palm.position = Vector3(float(row[0]), float(row[1]), float(row[2]))
		planted.add_child(palm)
	if planted.get_child_count() > 0:
		model.add_child(planted)
	else:
		planted.free()
