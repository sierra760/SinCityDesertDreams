# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const MainScene := preload("res://scenes/main.tscn")
const Fixtures := preload("res://tests/real_world/terrain_source_fixtures.gd")
class RejectTransport extends TerrainHttpTransport:
 var total_requests := 0
 func enqueue(_resource: Dictionary, _byte_range: Dictionary = {}, _generation: int = 0, _identity: Dictionary = {}, _head_only: bool = false) -> int:
  total_requests+=1
  return -1
var host: GameHost
var candidate: Dictionary
const SAVE := "user://saves/real-terrain-reset.sc2d"

func before_each() -> void:
 host=MainScene.instantiate()
 host.preferences_path="user://real-terrain-reset.cfg"
 root.add_child(host)
 candidate=RealWorldTerrain.convert(Fixtures.conversion_packet("provenance"), Fixtures.controls({"trees":50,"tree_seed":12345}), Fixtures.metadata())
 check(candidate.ok)

func after_each() -> void:
 host.free()
 DirAccess.remove_absolute(SAVE)
 await process_frame

func _start() -> City:
 var settings := RealWorldManifest.editing_settings(candidate)
 settings.merge(Fixtures.metadata())
 return host.start_new_city(settings, candidate.city)

func test_offline_editing_reset_then_found_without_cache() -> void:
 var fake := RejectTransport.new()
 root.add_child(fake)
 var offline_importer := RealWorldImporter.new()
 root.add_child(offline_importer)
 var cache := TerrainTileCache.new()
 var cache_directory := "user://terrain_tiles_v1/reset-test"
 cache.configure(cache_directory)
 offline_importer.configure(fake, cache)
 DirAccess.make_dir_recursive_absolute(cache_directory)
 var marker := cache_directory.path_join("deleted-cache-marker")
 FileAccess.open(marker, FileAccess.WRITE).store_string("discard")
 var city := _start()
 check(city==candidate.city, "imported start uses preview identity")
 check(host.terrain_editor.raise(12,12).ok)
 check(host.terrain_editor.place_water(60,60).ok)
 check(host.sim.city.building.data.count(0)<16384, "fixture has real imported trees")
 host.sim.city.building.data.fill(0)
 check_eq(SaveFormat.save(SAVE, host.sim.city, host.sim.snapshot(), SaveFormat.STAGE_EDITING, host.editing_params), OK)
 check(DirAccess.remove_absolute(marker)==OK)
 check(DirAccess.remove_absolute(cache_directory)==OK)
 check(host.load_city(SAVE))
 check_eq(host.sim.city.terrain_origin, candidate.origin)
 var old_surface=host.sim.city.terrain_surface
 var old_vertices: PackedByteArray=old_surface.vertices.duplicate()
 var reset := host.regenerate()
 check(reset!=null)
 if reset!=null:
  check_eq(reset.terrain_surface.vertices, RealWorldManifest.restore_baseline(candidate.baseline, Fixtures.metadata(), {}).city.terrain_surface.vertices)
  check(reset.terrain_surface!=old_surface, "fresh surface owner")
  check(reset.terrain_surface.vertices!=old_vertices, "edited terrain replaced")
  var baseline: City=RealWorldManifest.restore_baseline(candidate.baseline, Fixtures.metadata(), {}).city
  check_eq(reset.terrain_surface.water, baseline.terrain_surface.water)
  check_eq(reset.building.data, baseline.building.data)
  check_eq(host.editing_params.seed, 12345)
  check(host.found_city())
  check_eq(host.stage, GameHost.Stage.PLAY)
 check_eq(fake.total_requests, 0)
 offline_importer.free()
 fake.free()

func test_bad_baseline_keeps_loaded_city_and_disables_reset() -> void:
 _start()
 host.editing_params.baseline_sha256="0".repeat(64)
 check_eq(SaveFormat.save(SAVE, host.sim.city, host.sim.snapshot(), SaveFormat.STAGE_EDITING, host.editing_params), OK)
 check(host.load_city(SAVE))
 host.refresh_toolbar()
 var before := SaveFormat.encode_city(host.sim.city)
 var identity := host.sim.city
 var settings := host.editing_params.duplicate(true)
 var rng_state := host.sim.rng.state()
 check_eq(host.regenerate(), null)
 check_eq(host.sim.city, identity)
 check_eq(SaveFormat.encode_city(host.sim.city), before)
 check_eq(host.editing_params, settings)
 check_eq(host.sim.rng.state(), rng_state)
 check(host.toolbar.regenerate_button.disabled)
 check_eq(host.toolbar.regenerate_button.text, "Reset imported terrain")
 check(not host.toolbar.regenerate_button.tooltip_text.is_empty())

func test_reset_preserves_metadata_and_original_seed() -> void:
 for original_seed in [-9223372036854775807-1, 9223372036854775807]:
  candidate=RealWorldTerrain.convert(Fixtures.packet(), Fixtures.controls({"tree_seed":original_seed}), Fixtures.metadata())
  check(candidate.ok)
  var settings := RealWorldManifest.editing_settings(candidate)
  settings.terrain_origin={}
  settings.merge(Fixtures.metadata())
  seed(7654)
  var expected_next := randi()
  seed(7654)
  var city := host.start_new_city(settings, candidate.city)
  check_eq(randi(), expected_next, "imported start consumes no global RNG")
  city.name="Edited name"
  city.difficulty=2
  city.founded_year=2001
  city.mayor="Local Mayor"
  check_eq(SaveFormat.save(SAVE, host.sim.city, host.sim.snapshot(), SaveFormat.STAGE_EDITING, host.editing_params), OK)
  check(host.load_city(SAVE))
  check_eq(host.editing_params.seed, original_seed, "binary seed survives native JSON load")
  seed(9911)
  expected_next=randi()
  seed(9911)
  var reset := host.regenerate(999)
  check_eq(randi(), expected_next, "imported reset consumes no global RNG")
  check(reset!=null)
  if reset==null: continue
  check_eq(host.editing_params.seed, original_seed)
  check_eq(reset.name,"Edited name")
  check_eq(reset.difficulty,2)
  check_eq(reset.founded_year,2001)
  check_eq(reset.mayor,"Local Mayor")
  check(host.found_city())
  check_eq(host.sim.city.name,"Edited name")
  check_eq(host.sim.city.founded_year,2001)
  check_eq(host.sim.city.difficulty,2)
  check_eq(host.toolbar.regenerate_button.text,"Regenerate")

func test_negative_tree_seed_has_deterministic_simulation_lifecycle() -> void:
 var original_seed := -9223372036854775807-1
 candidate=RealWorldTerrain.convert(Fixtures.packet(), Fixtures.controls({"tree_seed":original_seed}), Fixtures.metadata())
 check(candidate.ok)
 _start()
 check_eq(host.editing_params.seed, original_seed)
 check_eq(host.sim.rng.seed_value(), 0, "imported simulation masks sign independently of tree seed")
 var editing_state := host.sim.rng.state()
 host.regenerate()
 check_eq(host.sim.rng.seed_value(), 0)
 check_eq(host.sim.rng.state(), editing_state, "reset deterministic initialization")
 check(host.found_city())
 check_eq(host.sim.rng.seed_value(), 0, "founding uses same imported derivation")
 var founded_state := host.sim.rng.state()
 _start()
 check(host.found_city())
 check_eq(host.sim.rng.state(), founded_state)

func test_imported_start_rejects_missing_preview_and_invalid_baseline_without_rng() -> void:
 _start()
 var active := host.sim.city
 var before := SaveFormat.encode_city(active)
 var params := RealWorldManifest.editing_settings(candidate)
 for invalid in [{}, {"baseline_version":2}, {"baseline_base64":"x".repeat(120000)}, {"baseline_sha256":"0".repeat(64)}]:
  var settings: Dictionary=params.duplicate(true)
  settings.merge(invalid,true)
  seed(1357)
  var expected := randi()
  seed(1357)
  check_eq(host.start_new_city(settings, null if invalid.is_empty() else candidate.city), null)
  check_eq(randi(), expected)
  check_eq(host.sim.city, active)
  check_eq(SaveFormat.encode_city(active), before)

func test_reset_retains_native_city_name_without_conversion_truncation() -> void:
 _start()
 var edited_name := "Imported edited city " + "x".repeat(300)
 host.sim.city.name=edited_name
 var reset := host.regenerate()
 check(reset!=null)
 if reset!=null:
  check_eq(reset.name, edited_name, "reset retains current native metadata exactly")
  check_eq(host.editing_params.name, edited_name)
