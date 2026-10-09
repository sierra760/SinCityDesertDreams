# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Building with the selected tool: applying it over a drag, the cursor
## preview of that drag, the bridge/tunnel, neighbor-link, on-ramp and
## objection prompts, signs, facility names and demolition from the inspector.
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
## On-ramp sites the player turned down, per city, so the same spot is not
## offered again after every nearby edit.
var _declined_ramps: Dictionary = {}
## City-limit links the player declined, per city: a later drag to the same
## border tile does not ask again unless it starts on that tile.
var _declined_links: Dictionary = {}
var _declined_city_id := 0


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
		_host.show_message(sentence(String(result.get("reason", ""))))
		return result
	_host.city_view_3d.queue_refresh()
	_host.mini_map.generate_image()
	_host.status_bar.set_message("")
	return result


## Act on a Builder result: report a refusal, ask about an objection, or
## record the build and ask about a neighbor link at the city limit and an
## on-ramp where a new road meets a highway. `earlier` lists tiles the same
## drag already built before this result (the run up to a neighbor link), so
## ramps along the whole segment are offered.
func _finish_apply(result: Dictionary, from: Vector2i, end: Vector2i, tool: int = -2, earlier: Array = [], ramp_from := Vector2i(-1, -1)) -> Dictionary:
	if tool == -2:
		tool = _host.tool
	if _host.audio != null:
		_host.audio.on_construction(result, tool)
	if not bool(result["ok"]):
		_host.show_message(refusal_text(result))
		return result
	if bool(result.get("needs_confirmation", false)) and StringName(String(result.get("choice_kind", ""))) == &"opposition":
		_prompt_opposition(from, end, tool)
		return result
	_after_build(result, tool)
	var built: Array = []
	if bool(result.get("applied", false)) and (tool == Tools.Kind.ROAD or tool == Tools.Kind.HIGHWAY):
		built = earlier + result.get("tiles", [])
	var toward := end if end.x >= 0 else from
	var drag_from := ramp_from if ramp_from.x >= 0 else from
	if result.has("neighbor"):
		# The ramp offer for this segment follows the link question.
		_prompt_neighbor(result["neighbor"], tool, built, toward, drag_from)
	elif not built.is_empty():
		_offer_onramp(built, toward, tool, drag_from)
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
## ended on. `ramp_tiles` are the tiles the drag built, whose on-ramp offer
## follows once the link is answered.
func _prompt_neighbor(neighbor: Dictionary, tool: int, ramp_tiles: Array = [], toward := Vector2i(-1, -1), drag_from := Vector2i(-1, -1)) -> void:
	var tile: Vector2i = neighbor.get("tile", Vector2i(-1, -1))
	if tile.x < 0:
		return
	var name := String(neighbor.get("name", ""))
	if name.is_empty():
		name = "the town beyond the %s edge" % ["north", "east", "south", "west"][clampi(int(neighbor.get("edge", 0)), 0, 3)]
	_bind_declines(_host.sim.city)
	if _declined_links.has(_link_key(tool, tile)) and drag_from != tile:
		# Declined before at this tile: no second question. A drag that starts
		# on the border tile itself asks again.
		_host.show_message("Built up to the city limit. To link to %s, start a drag on the edge tile." % name)
		if not ramp_tiles.is_empty():
			_offer_onramp(ramp_tiles, toward if toward.x >= 0 else tile, tool, drag_from)
		return
	var cost := int(neighbor.get("cost", 0))
	var lines := _host.notices.lines(&"neighbor", {"neighbor": name, "cost": cost, "kind": String(neighbor.get("kind", "road"))})
	_pending_choice = {"kind": &"neighbor", "tool": tool, "from": tile, "to": tile,
		"ramp_tiles": ramp_tiles, "ramp_toward": toward if toward.x >= 0 else tile, "ramp_from": drag_from}
	_host.push_modal()
	_host.choice_dialog.open(String(lines["title"]), String(lines["body"]),
		[{"key": &"connect", "label": "Link to %s" % name, "cost": cost}], _host.sim.city.funds, "Connect")


## Ask about on-ramps where the tiles just built let a road meet a highway:
## one question per build. Several sites are offered together (Add All /
## Choose… / Skip All) with every site highlighted; Choose… then asks about
## each in turn. One site is asked about on its own (Add Ramp / Skip).
## Nothing is built unless the player accepts it. A road carried over the
## highway is asked about like any other (Skip All declines every site at
## once); sites skipped before are not asked about again, and a treasury that
## cannot pay for one ramp gets a status line instead of a question.
## Settings → General can turn the offer off.
func _offer_onramp(built: Array, toward: Vector2i, tool: int = Tools.Kind.ROAD, _from := Vector2i(-1, -1)) -> void:
	if _host.builder == null or _host.choice_dialog == null or _host.choice_dialog.is_open():
		return
	if not bool(_host.preferences.get("offer_ramps", true)):
		return
	var city := _host.sim.city
	_bind_declines(city)
	var sites: Array[Vector2i] = []
	for site: Vector2i in _host.builder.onramp_sites(built, toward):
		if not _declined_ramps.has(_ramp_key(site)):
			sites.append(site)
	if sites.is_empty():
		return
	var cost := Tools.cost(Tools.Kind.ONRAMP)
	if cost > city.funds:
		# Never a question the player cannot say yes to; nothing is recorded,
		# so the sites are offered again once there is money.
		_host.show_message(_unaffordable_ramp_text())
		return
	var pending := {"kind": &"onramp", "tool": tool, "sites": sites, "index": 0,
		"city": city.get_instance_id(), "built": 0, "unaffordable": false}
	if sites.size() == 1:
		_ask_ramp(pending)
	else:
		pending["kind"] = &"onramp_batch"
		_ask_ramp_batch(pending)


func _bind_declines(city: City) -> void:
	if city.get_instance_id() != _declined_city_id:
		_declined_city_id = city.get_instance_id()
		_declined_ramps.clear()
		_declined_links.clear()


## A skipped ramp is remembered by the road and highway tiles it would join,
## so the same junction is not asked about again but a different one at the
## same tile is.
func _ramp_key(site: Vector2i) -> Vector4i:
	var junction := _host.builder.onramp_junction(site)
	if junction.is_empty():
		return Vector4i(site.x, site.y, -1, -1)
	var road: Vector2i = junction["road"]
	var highway: Vector2i = junction["highway"]
	return Vector4i(road.x, road.y, highway.x, highway.y)


func _unaffordable_ramp_text() -> String:
	return "Ramp sites available — %s costs %s" % [Tools.display_name(Tools.Kind.ONRAMP),
		UIFactory.format_signed_amount(Tools.cost(Tools.Kind.ONRAMP))]


## Highlight `sites` (the one at `selection` as the current question, or
## every one when `selection` is -1), bring them into view, and return the
## screen point the dialog should keep clear of.
func _show_ramp_sites(pending: Dictionary, sites: Array, selection: int) -> Vector2:
	var view := _host.city_view_3d
	if view == null:
		return Vector2(-1, -1)
	if view.ramp_highlight != null:
		view.ramp_highlight.show_sites(_host.sim.city, sites, selection, selection < 0)
	var focus: Vector2i = sites[maxi(selection, 0)]
	if not view.active:
		return Vector2(-1, -1)
	var visible_rect := _host.display_layout.logical_rect().grow(-48.0)
	var any_visible := false
	for site: Vector2i in ([focus] if selection >= 0 else sites):
		if visible_rect.has_point(view.project_cell(site)):
			any_visible = true
			break
	if not any_visible:
		# Bring the site into view before the dialog opens; the framing comes
		# back if the player builds nothing.
		if not pending.has("camera"):
			pending["camera"] = view.center
		view.set_center_cell(focus)
	return view.project_cell(focus)


## The single question for several sites at once.
func _ask_ramp_batch(pending: Dictionary) -> void:
	var sites: Array = pending["sites"]
	var total := Tools.cost(Tools.Kind.ONRAMP) * sites.size()
	var tool := int(pending.get("tool", Tools.Kind.ROAD))
	var lines := _host.notices.lines(&"onramp_batch_highway" if tool == Tools.Kind.HIGHWAY else &"onramp_batch",
		{"count": sites.size(), "cost": total})
	_pending_choice = pending
	_host.push_modal()
	var clear := _show_ramp_sites(pending, sites, -1)
	var dialog := _host.choice_dialog
	dialog.open(String(lines["title"]), String(lines["body"]),
		[{"key": &"all", "label": "%d Highway Ramps" % sites.size(), "cost": total}],
		_host.sim.city.funds, "Add All", "Skip All", "Choose…")
	if clear.x >= 0.0:
		dialog.keep_clear_of(clear)


## Ask about the site at `pending.index`, skipping sites an answer before it
## has made unbuildable and sites the treasury cannot pay for (those are not
## recorded as skipped). The other sites still to be asked about stay
## outlined so the player sees what is coming. When several were offered,
## Skip moves on, while Skip All (and Escape or closing) ends the queue.
func _ask_ramp(pending: Dictionary) -> void:
	if not _host.in_game or _host.builder == null or _host.sim.city.get_instance_id() != int(pending["city"]):
		return
	var sites: Array = pending["sites"]
	var index := int(pending["index"])
	while index < sites.size():
		var quote := _host.builder.preview(Tools.Kind.ONRAMP, sites[index])
		if bool(quote["ok"]):
			break
		if String(quote.get("reason", "")) == Builder.REASON_FUNDS:
			pending["unaffordable"] = true
		index += 1
	if index >= sites.size():
		_end_ramp_queue(pending)
		return
	pending["index"] = index
	var site: Vector2i = sites[index]
	var cost := Tools.cost(Tools.Kind.ONRAMP)
	var tool := int(pending.get("tool", Tools.Kind.ROAD))
	var lines := _host.notices.lines(&"onramp_highway" if tool == Tools.Kind.HIGHWAY else &"onramp", {"cost": cost})
	var title := String(lines["title"])
	var several := sites.size() > 1
	if several:
		title += " (%d of %d)" % [index + 1, sites.size()]
	_pending_choice = pending
	_host.push_modal()
	var clear := _show_ramp_sites(pending, sites.slice(index), 0)
	var dialog := _host.choice_dialog
	dialog.open(title, String(lines["body"]),
		[{"key": &"onramp", "label": "%s at %d, %d" % [Tools.display_name(Tools.Kind.ONRAMP), site.x, site.y], "cost": cost}],
		_host.sim.city.funds, "Add Ramp", "Skip All" if several else "Skip", "Skip" if several else "")
	if clear.x >= 0.0:
		dialog.keep_clear_of(clear)


func _clear_ramp_highlight() -> void:
	var view := _host.city_view_3d
	if view != null and view.ramp_highlight != null:
		view.ramp_highlight.clear()


## The next ramp site after this one was answered, if any.
func _ask_next_ramp(pending: Dictionary) -> void:
	var next := pending.duplicate()
	next["index"] = int(pending["index"]) + 1
	_ask_ramp(next)


## Every site from `start` on is remembered as skipped.
func _decline_ramps(pending: Dictionary, start: int) -> void:
	var sites: Array = pending["sites"]
	for i in range(maxi(start, 0), sites.size()):
		_declined_ramps[_ramp_key(sites[i])] = true


## The ramp questions are over: put the camera back if the player built
## nothing, and say so when sites were passed over for lack of money.
func _end_ramp_queue(pending: Dictionary) -> void:
	var view := _host.city_view_3d
	if int(pending.get("built", 0)) == 0 and pending.has("camera") and view != null \
			and view.city == _host.sim.city:
		# The exact framing from before the questions, not a snapped cell.
		view.set_camera_state(pending["camera"], view.quarter_turn, view.camera_size)
	if bool(pending.get("unaffordable", false)):
		_host.show_message(_unaffordable_ramp_text())


## Build a ramp at `site`; true when it was built.
func _build_ramp(site: Vector2i) -> bool:
	var result := _finish_apply(_host.builder.apply(Tools.Kind.ONRAMP, site), site, Vector2i(-1, -1), Tools.Kind.ONRAMP)
	return bool(result.get("applied", false))


func _on_choice_made(key: StringName) -> void:
	var pending := _pending_choice
	_pending_choice = {}
	_clear_ramp_highlight()
	_host.pop_modal()
	if pending.is_empty() or not _host.in_game or _host.builder == null:
		return
	if pending["kind"] == &"onramp_batch":
		if _host.sim.city.get_instance_id() != int(pending["city"]):
			return
		if key == ConstructionChoiceDialog.EXTRA_KEY:
			# Choose…: ask about each site in turn.
			var each := pending.duplicate()
			each["kind"] = &"onramp"
			each["index"] = 0
			_ask_ramp(each)
			return
		var built := 0
		var spent := 0
		for site: Vector2i in pending["sites"]:
			var quote := _host.builder.preview(Tools.Kind.ONRAMP, site)
			if not bool(quote["ok"]):
				if String(quote.get("reason", "")) == Builder.REASON_FUNDS:
					pending["unaffordable"] = true
				continue
			if _build_ramp(site):
				built += 1
				spent += int(quote.get("cost", 0))
		pending["built"] = built
		if built > 0:
			_host.show_message("Added %d %s · spent %s" % [built, "Highway Ramp" if built == 1 else "Highway Ramps",
				UIFactory.format_signed_amount(spent)])
		_end_ramp_queue(pending)
		return
	if pending["kind"] == &"onramp":
		var index := int(pending["index"])
		if key == ConstructionChoiceDialog.EXTRA_KEY:
			# Skip just this site; the others are still asked about.
			_declined_ramps[_ramp_key(pending["sites"][index])] = true
			if _host.in_game:
				_host.show_message("Ramp skipped.")
			_ask_next_ramp(pending)
			return
		if _build_ramp(pending["sites"][index]):
			pending["built"] = int(pending.get("built", 0)) + 1
		_ask_next_ramp(pending)
		return
	var options := {"connect": true} if pending["kind"] == &"neighbor" else {"choice": key}
	var from: Vector2i = pending["from"]
	var end: Vector2i = pending["to"]
	var ramp_tiles: Array = pending.get("ramp_tiles", [])
	var result := _finish_apply(_host.builder.apply(int(pending["tool"]), from, end, options), from, end, int(pending["tool"]), ramp_tiles,
		pending.get("ramp_from", from))
	if not bool(result["ok"]) and not ramp_tiles.is_empty():
		# The link failed (funds, say); the segment already built still meets the highway.
		_offer_onramp(ramp_tiles, pending.get("ramp_toward", end), int(pending["tool"]), pending.get("ramp_from", from))


func _on_choice_cancelled() -> void:
	var pending := _pending_choice
	_pending_choice = {}
	_clear_ramp_highlight()
	_host.pop_modal()
	if not pending.is_empty() and (pending.get("kind") == &"onramp" or pending.get("kind") == &"onramp_batch"):
		# Skip (one site), Skip All, Escape and closing the dialog all end the
		# ramp questions for this build; every site still open is remembered.
		_decline_ramps(pending, int(pending.get("index", 0)) if pending.get("kind") == &"onramp" else 0)
		if _host.in_game:
			var several := (pending["sites"] as Array).size() > 1
			_host.show_message("Ramps skipped." if several else "Ramp skipped.")
			_end_ramp_queue(pending)
		return
	if _host.in_game:
		# The run up to the border is already built and paid for; only the
		# link was declined.
		var neighbor: bool = not pending.is_empty() and pending.get("kind") == &"neighbor"
		if neighbor:
			_declined_links[_link_key(int(pending.get("tool", 0)), pending.get("from", Vector2i(-1, -1)))] = true
		_host.show_message("Built up to the city limit; no link made." if neighbor else "Nothing built.")
		if neighbor and not (pending.get("ramp_tiles", []) as Array).is_empty():
			_offer_onramp(pending["ramp_tiles"], pending["ramp_toward"], int(pending["tool"]), pending.get("ramp_from", Vector2i(-1, -1)))


## A declined city-limit link is remembered by tool and border tile.
static func _link_key(tool: int, tile: Vector2i) -> String:
	return "%d:%d,%d" % [tool, tile.x, tile.y]


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
					_host.show_message(sentence(String(r.get("reason", "")))),
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
					_host.show_message(sentence(String(r.get("reason", "")))),
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
		_host.show_message(refusal_text(quote))
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
		_host.show_message(refusal_text(result))


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
