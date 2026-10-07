# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const Lettering := preload("res://scripts/view/street_sign_text_3d.gd")

func test_lettering_uses_reserved_readable_face_without_growing_depth() -> void:
	var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/street-name-signs/templates.json"))
	for id: String in ["street-blade","highway-exit"]:
		var face: Dictionary=contract.templates[id].duplicate(true)
		face.font=contract.font
		if id=="street-blade":face.layout.destination_safe_m[1]=.36
		for text: String in ["Palm Avenue","Canyon Way","Bristlecone Artists Promenade","W".repeat(48 if id=="street-blade" else 99),"i", "Élan & María"]:
			var layout:=Lettering.layout(text,face)
			var safe:=Vector2(face.layout.destination_safe_m[0],face.layout.destination_safe_m[1])
			check_eq("".join(layout.lines),text,"full spelling retained")
			check(layout.lines.size()<=2)
			check(layout.bounds.size.x<safe.x and layout.bounds.size.y<safe.y,"unchanged face inset")
			check_gt(maxf(layout.bounds.size.x/safe.x,layout.bounds.size.y/safe.y),.85,"actual glyphs use available face instead of tiny nominal font")
			check(layout.bounds.size.z<=.00101,"XY growth never grows physical text extrusion")
			if id=="highway-exit" and text=="Canyon Way":check_gt(layout.bounds.size.y,.4,"ordinary exit destination letters exceed 40cm within existing 1m reserve")

func test_grown_header_and_arrow_remain_in_separate_reserved_rectangles() -> void:
	var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/street-name-signs/templates.json"))
	var face: Dictionary=contract.templates["highway-exit"].duplicate(true)
	for kind: String in ["header","arrow"]:
		face.layout.destination_safe_m=face.layout[kind+"_safe_m"]
		face.layout.destination_center_m=face.layout[kind+"_center_m"]
		face.layout.destination_em_m=face.layout[kind+"_em_m"]
		var text: String="EXIT" if kind=="header" else "→"
		var layout:=Lettering.layout(text,face)
		var safe:=Vector2(face.layout.destination_safe_m[0],face.layout.destination_safe_m[1])
		var center:=Vector2(face.layout.destination_center_m[0],face.layout.destination_center_m[1])
		var rectangle:=Rect2(center-safe*.5,safe)
		check(rectangle.encloses(Rect2(Vector2(layout.bounds.position.x,layout.bounds.position.y),Vector2(layout.bounds.size.x,layout.bounds.size.y))))
		check_eq("".join(layout.lines),text)
		check(layout.bounds.size.z<=.00101)
