# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const Layout := preload("res://scripts/ui/display_layout.gd")

func _candidate_count(layout: Node) -> int:
	var candidates: Variant = layout.get("_popup_candidates")
	check(candidates is Array or candidates is Dictionary, "keyboard guard maintains a Window-only popup candidate index")
	return candidates.size() if candidates is Array or candidates is Dictionary else -1

func test_large_nonwindow_subtree_keeps_popup_index_sparse() -> void:
	var geometry := Node3D.new()
	root.add_child(geometry)
	for i in 256:
		geometry.add_child(Node3D.new())
	var layout := Layout.new()
	root.add_child(layout)
	layout.bind(root)
	var before := _candidate_count(layout)
	check_eq(before,0,"geometry nodes are never popup candidates")
	for i in 80:
		check(not layout.blocks_city_keyboard(),"empty city remains keyboard-active")
	check_eq(_candidate_count(layout),before,"repeated guard queries do not rebuild from scene nodes")
	layout.free()
	geometry.free()

func test_late_internal_nested_and_reparented_windows() -> void:
	var host := Window.new()
	root.add_child(host)
	var stage := Node3D.new()
	host.add_child(stage)
	var elsewhere := Node.new()
	root.add_child(elsewhere)
	var layout := Layout.new()
	root.add_child(layout)
	layout.bind(host)
	var popup := PopupPanel.new()
	stage.add_child(popup)
	popup.visible = true
	check(layout.blocks_city_keyboard(),"late popup under Node3D blocks keys")
	check_eq(_candidate_count(layout),1)
	popup.visible = false
	check(not layout.blocks_city_keyboard(),"hidden popup releases keys")
	popup.visible = true
	stage.remove_child(popup)
	elsewhere.add_child(popup)
	check(not layout._has_popup(host),"popup outside bound window no longer blocks")
	elsewhere.remove_child(popup)
	stage.add_child(popup)
	check(layout.blocks_city_keyboard(),"reparented visible popup under host blocks again")
	var option := OptionButton.new()
	stage.add_child(option)
	var internal_popup := option.get_popup()
	internal_popup.visible = true
	check(layout.blocks_city_keyboard(),"internal OptionButton PopupMenu blocks keys")
	check_eq(_candidate_count(layout),2)
	popup.free()
	internal_popup.visible = false
	check(not layout.blocks_city_keyboard(),"removed and hidden windows release keys")
	check_eq(_candidate_count(layout),1,"freed Window is removed from index")
	layout.free()
	host.free()
	elsewhere.free()

func test_rebinding_tracks_only_current_window_descendants() -> void:
	var host_a := Window.new()
	var host_b := Window.new()
	root.add_child(host_a)
	root.add_child(host_b)
	var popup_a := PopupPanel.new()
	var popup_b := PopupPanel.new()
	host_a.add_child(popup_a)
	host_b.add_child(popup_b)
	popup_a.visible = true
	popup_b.visible = true
	var layout := Layout.new()
	root.add_child(layout)
	layout.bind(host_a)
	check(layout._has_popup(host_a),"first window owns its visible descendant")
	check_eq(_candidate_count(layout),1)
	layout.bind(host_b)
	check(layout._has_popup(host_b),"second bind seeds its descendants")
	check_eq(_candidate_count(layout),1,"first window is excluded after rebind")
	popup_b.free()
	check(not layout._has_popup(host_b),"freed current popup no longer blocks")
	layout.free()
	host_a.free()
	host_b.free()
