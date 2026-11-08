# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Bake the fixed model-space rooflines and searchlight roofs before shipping.
## Run after changing a casino GLB, the mesh compiler or casino_neon_edges.gd:
## godot --headless --path game --script res://tools/bake_casino_night_geometry.gd
extends SceneTree

const Edges := preload("res://scripts/view/casino_neon_edges.gd")
const Signatures := preload("res://scripts/view/casino_night_signatures.gd")
const OUTPUT := "res://assets/desert-dreams-3d/casino-night-geometry.res"

func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	var catalog := CityModelCatalog.new()
	catalog.compiled_cache_enabled = false
	if catalog.load_manifest(CityModelCatalog.ROOT+"catalog.json") != OK:
		quit(1)
		return
	var entries := {}
	for code: int in catalog.entries:
		if not Signatures.has(code): continue
		var wrapper := catalog.instantiate_model(code)
		if wrapper == null:
			quit(1)
			return
		root.add_child(wrapper)
		entries[code] = {"source":str(catalog.entries[code].glb_sha256)+":"+str(CityModelCatalog.RuntimeCompiler.VERSION),
			"edges":Edges._extract(wrapper.get_child(0))}
		wrapper.free()
	var resource := Resource.new()
	resource.set_meta("version",Edges.PREPARED_VERSION)
	resource.set_meta("extractor_sha256",FileAccess.get_sha256("res://scripts/view/casino_neon_edges.gd"))
	resource.set_meta("entries",entries)
	var error := ResourceSaver.save(resource,OUTPUT,ResourceSaver.FLAG_COMPRESS)
	print("BAKED_CASINO_NIGHT_GEOMETRY: ",entries.size()," models; error=",error)
	quit(0 if error == OK and entries.size() == 15 else 1)
