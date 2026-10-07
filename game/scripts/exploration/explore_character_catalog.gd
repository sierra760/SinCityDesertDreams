# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The complete authored pedestrian roster. Stable IDs are player preferences.
class_name ExploreCharacterCatalog
extends RefCounted

const IDS := ["woman", "man", "pedestrian_00", "pedestrian_01", "pedestrian_02", "pedestrian_03",
	"pedestrian_04", "pedestrian_05", "pedestrian_06", "pedestrian_07", "pedestrian_08", "pedestrian_09",
	"pedestrian_10", "pedestrian_11", "pedestrian_12", "pedestrian_13", "pedestrian_14", "pedestrian_15"]
const NAMES := ["Woman", "Man", "Teal shirt · sunhat", "Copper shirt · cap", "Gold shirt · backpack",
	"Cream shirt · shoulder bag", "Blue shirt · sunhat", "Red shirt · cap", "Olive shirt · backpack",
	"Plum shirt · shoulder bag", "Teal shirt · sunhat & sunglasses", "Copper shirt · cap & sunglasses",
	"Gold shirt · backpack & sunglasses", "Cream shirt · bag & sunglasses", "Blue shirt · sunhat & sunglasses",
	"Red shirt · cap & sunglasses", "Olive shirt · backpack & sunglasses", "Plum shirt · bag & sunglasses"]
const WOMAN := preload("res://assets/desert-dreams-exploration/pedestrian_woman.tscn")
const MAN := preload("res://assets/desert-dreams-exploration/pedestrian.tscn")

static func sanitize(value: Variant) -> String:
	return value if typeof(value)==TYPE_STRING and value in IDS else "woman"

static func display_name(character: String) -> String:
	return NAMES[IDS.find(sanitize(character))]

static func make_visual(character: String) -> ExploreActorVisual:
	var choice := sanitize(character)
	if choice == "woman": return WOMAN.instantiate()
	if choice == "man": return MAN.instantiate()
	var visual := ExploreActorVisual.new()
	visual.configure_crowd_variant(IDS.find(choice)-2)
	return visual
