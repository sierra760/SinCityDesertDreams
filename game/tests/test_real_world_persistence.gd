# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const Fixtures := preload("res://tests/real_world/terrain_source_fixtures.gd")

func _candidate() -> Dictionary:
 return RealWorldTerrain.convert(Fixtures.conversion_packet("provenance"), Fixtures.controls(), Fixtures.metadata())

func test_origin_roundtrip_deep_copy_and_old_city() -> void:
 check_eq(SaveFormat.VERSION, 1)
 var candidate := _candidate()
 check(candidate.ok)
 var city: City = candidate.city
 if not "terrain_origin" in city:
  check(false, "City needs optional owned terrain_origin")
  return
 city.set("terrain_origin", candidate.origin)
 candidate.origin.controls.trees=99
 check_eq(city.get("terrain_origin").controls.trees, 0, "assignment owns nested origin")
 var document := SaveFormat.encode_city(city)
 var loaded := SaveFormat.decode_city(JSON.parse_string(JSON.stringify(document)))
 check_eq(loaded.error, "")
 check_eq(loaded.city.get("terrain_origin"), city.get("terrain_origin"))
 document.terrain_origin.controls.trees=23
 check_eq(city.get("terrain_origin").controls.trees, 0, "encoded metadata is independent")
 loaded.city.get("terrain_origin").controls.trees=42
 check_eq(city.get("terrain_origin").controls.trees, 0)
 document.erase("terrain_origin")
 check_eq(SaveFormat.decode_city(document).city.get("terrain_origin"), {})

func test_unknown_oversized_and_url_origin_ignored() -> void:
 var candidate := _candidate()
 var document := SaveFormat.encode_city(candidate.city)
 for invalid in [{"version":999,"source":"real_world"}, {"version":1,"source":"https://bad.example"}, {"version":1,"source":"real_world","acquired_utc":"x".repeat(262145)}]:
  document.terrain_origin=invalid
  var loaded := SaveFormat.decode_city(document)
  check_eq(loaded.error, "", "bad optional origin does not corrupt terrain")
  check_eq(loaded.city.get("terrain_origin"), {})
  check_eq(loaded.city.terrain_surface.vertices, candidate.city.terrain_surface.vertices)
 var origin: Dictionary=candidate.origin.duplicate(true)
 origin.url="https://bad.example/body"
 origin.controls.url="https://bad.example/other"
 origin.sources[0].url="https://bad.example/source"
 document.terrain_origin=origin
 var sanitized: Variant=SaveFormat.decode_city(document).city.get("terrain_origin")
 check(sanitized is Dictionary and not sanitized.is_empty(), "recognized primitive fields survive")
 if sanitized is Dictionary:
  check(not JSON.stringify(sanitized).contains("https://"), "fetch URLs cannot persist")

func test_native_editing_origin_is_sanitized_in_city_and_generator() -> void:
 var candidate := _candidate()
 var city: City=candidate.city
 city.terrain_origin=candidate.origin
 var settings := RealWorldManifest.editing_settings(candidate)
 settings.terrain_origin.url="https://bad.example/private-source"
 var path := "user://saves/real-terrain-origin.sc2d"
 check_eq(SaveFormat.save(path, city, {}, SaveFormat.STAGE_EDITING, settings), OK)
 var bytes := FileAccess.get_file_as_bytes(path)
 check(not bytes.get_string_from_utf8().contains("https://"), "optional editing origin stores no URLs")
 var restored := SaveFormat.load(path)
 check(restored.ok)
 check_eq(restored.city.terrain_origin, candidate.origin)
 check_eq(restored.generator.terrain_origin, candidate.origin)
 var document: Dictionary=JSON.parse_string(bytes.get_string_from_utf8())
 document.generator.terrain_origin.version=999
 var file := FileAccess.open(path, FileAccess.WRITE)
 file.store_string(JSON.stringify(document))
 file.close()
 restored=SaveFormat.load(path)
 check(restored.ok, "corrupt optional generator origin cannot prevent native terrain load")
 check_eq(restored.generator.terrain_origin, {})
 check_eq(restored.city.terrain_surface.vertices, candidate.city.terrain_surface.vertices)
 DirAccess.remove_absolute(path)

func test_duplicate_city_owns_nested_terrain_origin() -> void:
 var candidate := _candidate()
 var city: City=candidate.city
 city.terrain_origin=candidate.origin
 var copy := city.duplicate_city()
 check_eq(copy.terrain_origin,city.terrain_origin,"City duplication retains full nested provenance")
 if copy.terrain_origin.is_empty(): return
 copy.terrain_origin.controls.trees=73
 copy.terrain_origin.sources[0].source="copy-only"
 check_eq(city.terrain_origin.controls.trees,0)
 check_ne(city.terrain_origin.sources[0].source,"copy-only")
 city.terrain_origin.selection.latitude=12.5
 check_ne(copy.terrain_origin.selection.latitude,12.5)
