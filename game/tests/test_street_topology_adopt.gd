# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Hosts may adopt the road projection a save decoder already validated instead
## of projecting the same City again; the result and selection tokens must match
## an ordinary rebuild.
extends "res://tests/test_case.gd"

var _city: City

func before_all() -> void:
	var loaded := Sc2Import.load("res://assets/cities/Aliso Niguel.sc2")
	check(loaded.ok, "fixture city imports")
	_city = loaded.city

func _state(topology: StreetTopology) -> PackedByteArray:
	return var_to_bytes([topology._nodes, topology._links, topology._exits, topology._bores, topology._projection_state, topology._bound_city_id])

func test_adopt_equals_rebuild_and_advances_revision() -> void:
	var source := StreetTopology.new()
	source.rebuild(_city)
	var rebuilt := StreetTopology.new()
	rebuilt.rebuild(_city)
	var adopted := StreetTopology.new()
	var changed := adopted.adopt(source, _city)
	check(changed, "adopting a projection for a new binding reports a change")
	check(adopted.is_bound_to(_city), "adopted topology is bound to the city")
	check(_state(adopted) == _state(rebuilt), "adopted projection equals a fresh rebuild")
	check_gt(adopted.revision, 0, "adoption issues a selection token")
	check_eq(adopted.segments({}).size(), rebuilt.segments({}).size(), "derived segments agree")
	check_eq(adopted.junctions({}).size(), rebuilt.junctions({}).size(), "derived junctions agree")
	var revision := adopted.revision
	check(not adopted.adopt(source, _city), "re-adopting the same structure is not a change")
	check_eq(adopted.revision, revision, "unchanged structure keeps its token")
	check(not adopted.rebuild(_city), "an ordinary rebuild after adoption sees unchanged inputs")

func test_adopt_falls_back_to_rebuild_for_other_cities() -> void:
	var other: City = Sc2Import.load("res://assets/cities/Salton Shores.sc2").city
	var source := StreetTopology.new()
	source.rebuild(other)
	var topology := StreetTopology.new()
	var expected := StreetTopology.new()
	expected.rebuild(_city)
	check(topology.adopt(source, _city), "a mismatched source still produces a projection")
	check(_state(topology) == _state(expected), "mismatched source falls back to an exact rebuild")
	check(topology.adopt(null, _city) == false, "a null source rebuilds and reports unchanged inputs")

func test_save_loader_hands_over_its_validated_projection() -> void:
	var path := "user://test-topology-adopt.scity"
	var topology := StreetTopology.new()
	topology.rebuild(_city)
	var naming := StreetNamingService.new()
	naming.bind_city(_city, topology)
	check_eq(SaveFormat.save(path, _city), OK, "fixture save succeeds")
	var result := SaveFormat.load(path)
	check(result.ok, "fixture save loads")
	var handed: StreetTopology = result.get("topology")
	check(handed != null, "a save with street naming returns its validated topology")
	if handed != null:
		check(handed.is_bound_to(result.city), "the handed topology is bound to the loaded City instance")
		var fresh := StreetTopology.new()
		fresh.rebuild(result.city)
		check(var_to_bytes([handed._nodes, handed._links, handed._exits, handed._bores]) == var_to_bytes([fresh._nodes, fresh._links, fresh._exits, fresh._bores]), "handed projection equals a fresh rebuild of the loaded city")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
