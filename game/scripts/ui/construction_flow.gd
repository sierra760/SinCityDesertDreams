# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Building with the selected tool: applying it over a drag, the cursor
## preview of that drag, the bridge/tunnel, neighbor-link and objection
## prompts, signs, facility names and demolition from the inspector.
class_name ConstructionFlow
extends RefCounted

var _host: GameHost
## The drag waiting on the construction choice dialog: kind, tool, from, to.
var _pending_choice: Dictionary = {}
## The tool a live map drag was started with, and its first tile. Holding B
## during a drag makes it a Bulldoze drag; releasing B before the mouse
## button keeps it one, so a demolition never turns into a paid build.
var _drag_tool := GameHost.NO_TOOL
var _drag_from := Vector2i(-1, -1)
var _presentation_id := 0


func _init(host: GameHost) -> void:
	_host = host


## Remember the tool at the start of a map drag. Main may call this from its
## drag-start handler; the presentation signal also reaches it.
func begin_drag(from: Vector2i) -> void:
	_drag_tool = _host.tool
	_drag_from = from


## Forget the latched drag tool (cancelled or finished gesture).
func end_drag() -> void:
	_drag_tool = GameHost.NO_TOOL
	_drag_from = Vector2i(-1, -1)


func _bind_presentation() -> void:
	var presentation: Object = _host.presentation
	if not is_instance_valid(presentation) or presentation.get_instance_id() == _presentation_id:
		return
	_presentation_id = presentation.get_instance_id()
	presentation.connect(&"drag_started", _on_presentation_drag_started)
	presentation.connect(&"drag_cancelled", end_drag)


func _on_presentation_drag_started(from: Vector2i, _to: Vector2i) -> void:
	if bool(_host.get(&"_drag_active")):
		begin_drag(from)
	else:
		end_drag()


## The tool a drag from `from` works with: the latched one while that drag is
## live (promoted to Bulldoze once B is held), otherwise the selected tool.
func _tool_for_drag(from: Vector2i, live: bool) -> int:
	_bind_presentation()
	if not live:
		end_drag()
		return _host.tool
	if _drag_tool == GameHost.NO_TOOL or _drag_from != from:
		begin_drag(from)
	elif _host.tool == Tools.Kind.BULLDOZE:
		_drag_tool = Tools.Kind.BULLDOZE
	return _drag_tool


## Apply the selected tool over a drag. In the editing stage this shapes the
## land; Query and Sign act on the first tile.
func handle_drag(from: Vector2i, to: Vector2i) -> Dictionary:
	var tool := _host.tool
	if _drag_tool != GameHost.NO_TOOL and _drag_from == from and _host.stage == GameHost.Stage.PLAY:
		tool = _drag_tool
	end_drag()
	if _host.is_exploring():
		return {"ok":false,"cost":0,"tiles":[],"reason":"Return to Build to construct.","applied":false}
	if not _host.in_game or _host.builder == null or tool == GameHost.NO_TOOL:
		return {"ok": false, "cost": 0, "tiles": [], "reason": "no tool", "applied": false}
	if _host.stage == GameHost.Stage.EDITING:
		return _edit_terrain(from, to)
	if tool == Tools.Kind.QUERY:
		_host.open_query(from)
		return {"ok": true, "cost": 0, "tiles": [from], "reason": "", "applied": false}
	if tool == Tools.Kind.SIGN:
		prompt_sign(from)
		return {"ok": true, "cost": 0, "tiles": [from], "reason": "", "applied": false}
	var end := _drag_end(tool, from, to)
	var quote := _host.builder.preview(tool, from, end)
	var kind := StringName(String(quote.get("choice_kind", "")))
	if bool(quote["ok"]) and bool(quote.get("needs_confirmation", false)) and (kind == &"bridge" or kind == &"tunnel"):
		_open_choice(quote, from, end, tool)
		quote["applied"] = false
		return quote
	return _finish_apply(_host.builder.apply(tool, from, end), from, end, tool)


## Apply a whole-map tool (the sea level) once, as its button is pressed:
## free through the terrain editor before founding, paid through the
## Builder in play. The selected map tool stays selected.
func apply_immediate(tool: int) -> Dictionary:
	if _host.is_exploring():
		return {"ok":false,"cost":0,"tiles":[],"reason":"Return to Build to construct.","applied":false}
	if not _host.in_game or _host.builder == null or not Tools.is_immediate(tool):
		return {"ok": false, "cost": 0, "tiles": [], "reason": "no tool", "applied": false}
	if _host.stage == GameHost.Stage.EDITING:
		return _edit_terrain(Vector2i.ZERO, Vector2i(-1, -1), tool)
	return _finish_apply(_host.builder.apply(tool, Vector2i.ZERO), Vector2i.ZERO, Vector2i(-1, -1), tool)


## Shape the land through the terrain editor: free, no simulation involved.
## The 3D view and minimap refresh after a successful edit.
func _edit_terrain(from: Vector2i, to: Vector2i, tool: int = -2) -> Dictionary:
	if tool == -2:
		tool = _host.tool
	if not Tools.is_terrain_tool(tool) or _host.terrain_editor == null:
		return {"ok": false, "cost": 0, "tiles": [], "rect": Rect2i(), "reason": "found the city first", "applied": false}
	var result := _host.terrain_editor.apply_tool(tool, from, _drag_end(tool, from, to))
	result["cost"] = 0
	result["applied"] = bool(result["ok"])
	if not bool(result["ok"]):
		_host.status_bar.set_message(sentence(String(result.get("reason", ""))))
		return result
	_host.city_view_3d.queue_refresh()
	_host.mini_map.generate_image()
	_host.status_bar.set_message("")
	return result


## Act on a Builder result: report a refusal, ask about an objection, or
## record the build and ask about a neighbor link at the city limit.
func _finish_apply(result: Dictionary, from: Vector2i, end: Vector2i, tool: int = -2) -> Dictionary:
	if tool == -2:
		tool = _host.tool
	if not bool(result["ok"]):
		_host.show_message(refusal_text(result))
		return result
	if bool(result.get("needs_confirmation", false)) and StringName(String(result.get("choice_kind", ""))) == &"opposition":
		_prompt_opposition(from, end, tool)
		return result
	_after_build(result, tool)
	if result.has("neighbor"):
		_prompt_neighbor(result["neighbor"], tool)
	return result


## Show the bridge or tunnel quote for a drag and hold the drag until the
## player answers.
func _open_choice(quote: Dictionary, from: Vector2i, end: Vector2i, tool: int) -> void:
	var kind := StringName(String(quote.get("choice_kind", "")))
	var options: Array = []
	for entry in quote.get("choices", []):
		var option: Dictionary = entry
		var key := StringName(String(option.get("key", "")))
		options.append({"key": key, "label": NoticeLines.option_label(key), "cost": int(option.get("cost", 0))})
	var lines := _host.notices.lines(kind, {"count": int(quote.get("span", 0))})
	_pending_choice = {"kind": kind, "tool": tool, "from": from, "to": end}
	_host.push_modal()
	_host.choice_dialog.open(String(lines["title"]), String(lines["body"]), options, _host.sim.city.funds)


## Offer the link to the town beyond the city limit for the tile the drag
## ended on.
func _prompt_neighbor(neighbor: Dictionary, tool: int) -> void:
	var tile: Vector2i = neighbor.get("tile", Vector2i(-1, -1))
	if tile.x < 0:
		return
	var name := String(neighbor.get("name", ""))
	if name.is_empty():
		name = "the town beyond the %s edge" % ["north", "east", "south", "west"][clampi(int(neighbor.get("edge", 0)), 0, 3)]
	var cost := int(neighbor.get("cost", 0))
	var lines := _host.notices.lines(&"neighbor", {"neighbor": name, "cost": cost, "kind": String(neighbor.get("kind", "road"))})
	_pending_choice = {"kind": &"neighbor", "tool": tool, "from": tile, "to": tile}
	_host.push_modal()
	_host.choice_dialog.open(String(lines["title"]), String(lines["body"]),
		[{"key": &"connect", "label": "Link to %s" % name, "cost": cost}], _host.sim.city.funds, "Connect")


func _on_choice_made(key: StringName) -> void:
	var pending := _pending_choice
	_pending_choice = {}
	_host.pop_modal()
	if pending.is_empty() or not _host.in_game or _host.builder == null:
		return
	var options := {"connect": true} if pending["kind"] == &"neighbor" else {"choice": key}
	var from: Vector2i = pending["from"]
	var end: Vector2i = pending["to"]
	_finish_apply(_host.builder.apply(int(pending["tool"]), from, end, options), from, end, int(pending["tool"]))


func _on_choice_cancelled() -> void:
	var pending := _pending_choice
	_pending_choice = {}
	_host.pop_modal()
	if _host.in_game:
		# The run up to the border is already built and paid for; only the
		# link was declined.
		var neighbor: bool = not pending.is_empty() and pending.get("kind") == &"neighbor"
		_host.show_message("Built up to the city limit; no link made." if neighbor else "Nothing built.")


## The citizens object to a placement: build anyway or walk away unbilled.
func _prompt_opposition(from: Vector2i, end: Vector2i, placing: int) -> void:
	var spec := _host.notices.notice_for(&"opposition", {"name": Tools.display_name(placing)})
	_host.notices.queue(String(spec["title"]), String(spec["body"]), spec["choices"],
		func(choice: StringName) -> void:
			if choice == &"proceed" and _host.in_game and _host.builder != null:
				_finish_apply(_host.builder.apply(placing, from, end, {"proceed": true}), from, end, placing)
			elif _host.in_game:
				_host.show_message("Nothing built."))


static func _drag_end(for_tool: int, from: Vector2i, to: Vector2i) -> Vector2i:
	var mode := Tools.mode(for_tool)
	if mode == Tools.Mode.POINT or mode == Tools.Mode.GLOBAL:
		return Vector2i(-1, -1)
	return to if to.x >= 0 else from


func _after_build(result: Dictionary, tool: int = -2) -> void:
	if tool == -2:
		tool = _host.tool
	var sim := _host.sim
	var query_panel := _host.query_panel
	_host.status_bar.refresh(sim)
	var cost := int(result.get("cost", 0))
	var message := "Spent $%s" % UIFactory.commafy(cost) if cost > 0 else ""
	var stopped := String(result.get("stopped", ""))
	if not stopped.is_empty():
		message = sentence((message + " · stopped: " if not message.is_empty() else "stopped: ") + _clause(stopped))
	_host.show_message(message)
	if Tools.is_reward_tool(tool):
		var rewards := sim.get_system(&"rewards")
		if rewards != null and rewards.has_method("mark_built"):
			rewards.call("mark_built", Tools.reward_key(tool))
		_host.select_tool(Tools.Kind.QUERY)
	_host.refresh_toolbar()
	if query_panel.is_open() and query_panel.tile.x >= 0:
		query_panel.show_tile(sim.city, sim, query_panel.tile)
	for entry in result.get("notices", []):
		var notice: Dictionary = entry
		_host.notices.raise(StringName(String(notice.get("kind", ""))), notice.get("payload", {}))


## Preview the active tool over a drag on the map cursor.
func preview_drag(from: Vector2i, to: Vector2i) -> Dictionary:
	var tool := _host.tool
	var preview := _host.presentation.preview
	if _host.is_exploring(): return {}
	if _host.builder == null or tool == GameHost.NO_TOOL or tool == Tools.Kind.QUERY or tool == Tools.Kind.SIGN:
		preview.clear()
		return {}
	if _host.stage == GameHost.Stage.EDITING:
		var terrain_editor := _host.terrain_editor
		if not Tools.is_terrain_tool(tool) or terrain_editor == null:
			preview.clear()
			return {}
		var t := terrain_editor.preview_tool(tool, from, _drag_end(tool, from, to))
		var footprint: Array = t["tiles"]
		if footprint.is_empty():
			footprint = [from]
		preview.show_footprint(footprint, bool(t["ok"]), "free" if bool(t["ok"]) else String(t["reason"]))
		return t
	tool = _tool_for_drag(from, bool(_host.get(&"_drag_active")))
	var p := _host.builder.preview(tool, from, _drag_end(tool, from, to))
	var tiles: Array = p.get("tiles", []).duplicate()
	var caption := "$" + UIFactory.commafy(int(p.get("cost", 0))) if bool(p["ok"]) else refusal_text(p)
	if bool(p["ok"]) and p.has("stopped"):
		caption += " · stops: " + _clause(String(p["stopped"]))
	if bool(p["ok"]) and p.has("clears_underground") and not _host.presentation.is_underground():
		# Bare-ground bulldozing also clears what is buried there (rule 24).
		var buried: Array = p["clears_underground"]
		caption += " · also removes " + " and ".join(PackedStringArray(buried))
	if p.has("neighbor"):
		var neighbor: Dictionary = p["neighbor"]
		tiles.append(neighbor.get("tile", from))
		caption += " + link $%s?" % UIFactory.commafy(int(neighbor.get("cost", 0)))
	if tiles.is_empty():
		tiles = [from]
	preview.show_footprint(tiles, bool(p["ok"]), caption)
	return p


func prompt_sign(at: Vector2i) -> void:
	if _host.stage != GameHost.Stage.PLAY:
		return
	var existing := String(_host.sim.city.signs.get(at, ""))
	_host.notices.queue("Place Sign", "Text for the sign at %d, %d (leave empty to remove it):" % [at.x, at.y],
		[["Place", &"submit"], ["Cancel", &"ok"]],
		func(choice: StringName) -> void:
			if choice == &"submit":
				var r := _host.builder.place_sign(at, _host.notice_dialog.prompt_text())
				if bool(r.get("ok", false)):
					_host.city_view_3d.set_labels_visible(bool(_host.preferences.get("labels", true)))
					_host.city_view_3d.queue_refresh()
				else:
					_host.status_bar.set_message(sentence(String(r.get("reason", "")))),
		true, existing)


## Ask for a facility's name and store it in its record.
func prompt_rename(at: Vector2i) -> void:
	if _host.stage != GameHost.Stage.PLAY or _host.builder == null:
		return
	var city := _host.sim.city
	var anchor := city.anchor_of(at.x, at.y)
	var record := city.facility(anchor)
	if record.is_empty():
		return
	var existing := String(record.get("name", ""))
	var code := city.building_at(anchor.x,anchor.y)
	var what := Buildings.display_name(code)
	var context := "Name for the %s at %d, %d (leave empty to use the standard name):" % [what,anchor.x,anchor.y]
	if code in [Buildings.RAIL_STATION,Buildings.SUBWAY_STATION]:
		context = "Current station: %s\nEnter a custom name, or leave empty for its automatic name." % StationNameResolver.display_name(city,anchor,code==Buildings.SUBWAY_STATION)
	_host.notices.queue("Rename Facility", context,
		[["Rename", &"submit"], ["Cancel", &"ok"]],
		func(choice: StringName) -> void:
			if choice == &"submit":
				var r := _host.builder.rename_facility(anchor, _host.notice_dialog.prompt_text())
				if bool(r.get("ok", false)):
					if _host.sim.city.building.atv(anchor) in [Buildings.RAIL_STATION,Buildings.SUBWAY_STATION]:
						_host.street_naming_service.refresh_station_names([anchor])
					if _host.query_panel.is_open():
						_host.query_panel.show_tile(_host.sim.city, _host.sim, _host.query_panel.tile)
				else:
					_host.status_bar.set_message(sentence(String(r.get("reason", "")))),
		true, existing)


func _on_demolish_requested(at: Vector2i) -> void:
	if _host.stage != GameHost.Stage.PLAY or _host.builder == null:
		return
	var city := _host.sim.city
	if city == null or not city.in_bounds(at.x, at.y):
		return
	var id := city.building_at(at.x, at.y)
	if not needs_demolish_confirmation(id):
		_demolish(at)
		return
	var quote := _host.builder.preview(Tools.Kind.BULLDOZE, at)
	if not bool(quote["ok"]):
		_host.status_bar.set_message(refusal_text(quote))
		return
	var anchor := city.anchor_of(at.x, at.y)
	var what := String(city.facility(anchor).get("name", ""))
	if what.is_empty():
		what = "the " + Buildings.display_name(id)
	var body := "Demolish %s? It costs %s and can't be undone." % [what, UIFactory.format_signed_amount(int(quote.get("cost", 0)))]
	# Cancel comes first so Enter and Escape both keep the building.
	_host.notices.queue("Demolish", body, [["Cancel", &"cancel"], ["Demolish", &"demolish"]],
		func(choice: StringName) -> void:
			if choice == &"demolish" and _host.in_game and _host.stage == GameHost.Stage.PLAY and _host.builder != null:
				_demolish(at))


## Developed and multi-tile buildings ask before the inspector demolishes them;
## plain roads, rails, power lines, rubble and trees go at once.
static func needs_demolish_confirmation(id: int) -> bool:
	if id == Buildings.NONE or Buildings.is_tree(id) or Buildings.is_rubble(id):
		return false
	if Buildings.is_developed(id) or Buildings.size(id) != Vector2i.ONE:
		return true
	return not Buildings.is_network(id)


func _demolish(at: Vector2i) -> void:
	var result := _host.builder.apply(Tools.Kind.BULLDOZE, at)
	if bool(result["ok"]):
		_after_build(result, Tools.Kind.BULLDOZE)
		_host.query_panel.show_tile(_host.sim.city, _host.sim, at)
		_host.sync_query_feedback()
	else:
		_host.status_bar.set_message(refusal_text(result))


## What the player reads for a refused plan: a short-funds refusal shows the
## price against the treasury, anything else becomes a sentence.
func refusal_text(plan: Dictionary) -> String:
	var reason := String(plan.get("reason", ""))
	if reason == Builder.REASON_FUNDS and _host.sim != null and _host.sim.city != null:
		return "Costs %s — treasury %s" % [UIFactory.format_signed_amount(int(plan.get("cost", 0))),
			UIFactory.format_signed_amount(_host.sim.city.funds)]
	return sentence(reason)


## A reason as a clause inside a longer line: trimmed, no full stop.
static func _clause(text: String) -> String:
	var t := text.strip_edges()
	return t.trim_suffix(".")


## A refusal reason as a sentence: first letter capitalised, full stop added.
static func sentence(text: String) -> String:
	var t := text.strip_edges()
	if t.is_empty():
		return ""
	t = t[0].to_upper() + t.substr(1)
	return t if t.ends_with(".") else t + "."
