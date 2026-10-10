# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Player tools must be identifiable before hovering, including similar actions.
extends "res://tests/test_case.gd"

func test_every_tool_has_a_distinct_icon_and_visible_caption() -> void:
	var toolbar := Toolbar.new()
	var seen: Dictionary = {}
	for tool in Tools.all():
		var button := toolbar.button_for(tool)
		check(not button.text.strip_edges().is_empty(), "visible name for " + Tools.display_name(tool))
		var key := Tools.icon(tool)
		check(not seen.has(key), "distinct icon for " + Tools.display_name(tool))
		seen[key] = true
		check(button.icon != null, "loaded icon for " + Tools.display_name(tool))
	toolbar.free()

func test_resort_player_copy() -> void:
	check_eq(Toolbar.GROUP_NAMES[Tools.Group.ARCOLOGY], "Gaming Resorts")
	for key in [&"arcology_comstock", &"arcology_junction", &"arcology_boulder", &"arcology_orbit"]:
		check(EconomyParams.TECHNOLOGY_NAMES[key].ends_with("Gaming Resort"), "resort invention announcement")

func test_gaming_resorts_are_listed_by_ascending_cost() -> void:
	var toolbar := Toolbar.new()
	var position := {}
	for tool in Tools.all():
		if Tools.group(tool) != Tools.Group.ARCOLOGY:
			continue
		var node: Node = toolbar.button_for(tool)
		while not (node.get_parent() is GridContainer):
			node = node.get_parent()
		position[tool] = node.get_index()
	var listed: Array = position.keys()
	listed.sort_custom(func(a: int, b: int) -> bool: return position[a] < position[b])
	check_eq(listed, [Tools.Kind.ARCOLOGY_LAST, Tools.Kind.ARCOLOGY_DUST, Tools.Kind.ARCOLOGY_COMSTOCK,
		Tools.Kind.ARCOLOGY_JUNCTION, Tools.Kind.ARCOLOGY_ALIBI, Tools.Kind.ARCOLOGY_BOULDER,
		Tools.Kind.ARCOLOGY_ORBIT, Tools.Kind.ARCOLOGY_VELVET, Tools.Kind.ARCOLOGY_FIX,
		Tools.Kind.ARCOLOGY_AFTERGLOW])
	for i in range(1, listed.size()):
		check(Tools.cost(listed[i - 1]) <= Tools.cost(listed[i]), "resort prices never decrease")
	toolbar.free()
