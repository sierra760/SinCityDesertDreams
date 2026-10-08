# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The tile inspector: what stands on a tile, its zone, height, services and
## the neighbourhood maps, plus the facility record for civic buildings:
## when it was built, its age, what it puts out, who lives or rides or is
## held there. Offers Rename for facilities and Demolish for anything built;
## the host routes both through the Builder.
class_name QueryPanel
extends PanelContainer

signal demolish_requested(tile: Vector2i)
signal rename_requested(tile: Vector2i)
signal closed

const PANEL_WIDTH := 320
## Record fields never listed as counters.
const HIDDEN_FIELDS: Array[String] = ["key", "built_day", "warned", "age_years", "name", "built_year", "imported"]

var title_label: Label
var rows: VBoxContainer
var body_scroll: ScrollContainer
var demolish_button: Button
var rename_button: Button
var close_button: Button
## The tile shown, or (-1,-1).
var tile := Vector2i(-1, -1)
## Everything shown, keyed by row label.
var info: Dictionary = {}
var _content_revision := 0


func _init() -> void:
	name = "QueryPanel"
	if MobilePlatform.is_ios(): theme = UITheme.control_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UITheme.window_stylebox())
	custom_minimum_size = Vector2.ZERO
	_build()
	visible = false


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UITheme.VSEP)
	add_child(column)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UITheme.title_bar_stylebox())
	column.add_child(bar)
	var bar_row := HBoxContainer.new()
	bar.add_child(bar_row)
	title_label = UIFactory.make_label("Inspect", UITheme.FONT_TITLE, UITheme.TITLE_TEXT)
	title_label.add_theme_font_override("font", UITheme.DISPLAY_FONT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(title_label)
	close_button = UIFactory.make_title_close_button("Close inspector [Escape]")
	close_button.pressed.connect(close)
	bar_row.add_child(close_button)
	rows = VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 2)
	body_scroll = ScrollContainer.new()
	body_scroll.name = "BodyScroll"
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.follow_focus = true
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(rows)
	column.add_child(body_scroll)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 6)
	column.add_child(actions)
	rename_button = UIFactory.make_button("Rename", "Give this facility a name")
	rename_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_button.pressed.connect(func() -> void:
		if tile.x >= 0:
			rename_requested.emit(tile))
	actions.add_child(rename_button)
	demolish_button = UIFactory.make_button("Demolish", "Bulldoze this tile")
	demolish_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	demolish_button.pressed.connect(func() -> void:
		if tile.x >= 0:
			demolish_requested.emit(tile))
	actions.add_child(demolish_button)
	WindowDrag.enable(bar,self)
	size = Vector2(PANEL_WIDTH,480)


## Fill the panel for `at` and show it.
func show_tile(city: City, sim: Simulation, at: Vector2i) -> void:
	var next := describe(city, sim, at)
	var same_tile := tile == at
	if same_tile and next == info:
		visible = true
		return
	var reading_position := body_scroll.scroll_vertical if same_tile else 0
	tile = at
	info = next
	_content_revision += 1
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	title_label.text = String(info.get("Building", "Inspect"))
	for key in info:
		var value: Variant = info[key]
		if String(key).begins_with("_"):
			continue
		if String(key).begins_with("#"):
			rows.add_child(UIFactory.make_section_header(String(key).substr(1)))
			continue
		# Label and value share a line so the details read like a short table.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var k := UIFactory.make_label(String(key), UITheme.FONT_BODY, UITheme.TEXT_MUTED)
		k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		k.custom_minimum_size.x = 120
		row.add_child(k)
		var v := UIFactory.make_label(value_text(value), UITheme.FONT_BODY)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		rows.add_child(row)
	demolish_button.disabled = not bool(info.get("_demolishable", false))
	rename_button.disabled = not bool(info.get("_renamable", false))
	visible = true
	body_scroll.scroll_vertical = reading_position
	_restore_scroll.call_deferred(reading_position, _content_revision)


## Called after completed simulation updates; a hidden inspector stays hidden.
func refresh(city: City, sim: Simulation) -> void:
	if visible and tile.x >= 0:
		show_tile(city, sim, tile)


func _restore_scroll(value: int, revision: int) -> void:
	if revision == _content_revision and visible:
		body_scroll.scroll_vertical = value


## Everything the panel shows for a tile, in display order. Keys starting
## with "#" are section headers; keys starting with "_" are hidden.
static func describe(city: City, sim: Simulation, at: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	if city == null or not city.in_bounds(at.x, at.y):
		out["Location"] = "outside the city"
		return out
	var id := city.building_at(at.x, at.y)
	var anchor := city.anchor_of(at.x, at.y)
	var zone_kind := city.zone_kind_at(at.x, at.y)
	out["#Site"] = ""
	out["Location"] = "%d, %d" % [at.x, at.y]
	out["Building"] = Buildings.display_name(id) if id != Buildings.NONE else ("Open water" if city.is_water(at.x, at.y) else "Open ground")
	if Buildings.is_multi_tile(id):
		var s := Buildings.size(id)
		out["Footprint"] = "%d×%d at %d, %d" % [s.x, s.y, anchor.x, anchor.y]
	out["Zone"] = String(Zones.NAMES.get(zone_kind, "Unzoned"))
	out["Height"] = "%d%s" % [city.ground_height(at.x, at.y), " (water)" if city.is_water(at.x, at.y) else ""]
	out["Slope"] = "Flat" if city.is_flat(at.x, at.y) else "Sloped"
	var under := city.underground.at(at.x, at.y)
	if under != Underground.NONE:
		out["Underground"] = underground_text(under)
	if city.signs.has(at):
		out["Sign"] = String(city.signs[at])
	out["#Services"] = ""
	out["Power"] = "Yes" if city.is_powered(at.x, at.y) else ("No — carries power" if city.conducts_power(at.x, at.y) else "No")
	out["Water"] = "Yes" if city.is_watered(at.x, at.y) else ("No — carries water" if city.conducts_water(at.x, at.y) else "No")
	out["#Neighborhood"] = ""
	out["Land Value"] = level_text(city.land_value_at(at.x, at.y))
	out["Pollution"] = level_text(city.pollution_at(at.x, at.y))
	out["Crime"] = level_text(city.crime_at(at.x, at.y))
	out["Traffic"] = level_text(city.traffic_at(at.x, at.y))
	out["Density"] = level_text(city.density_at(at.x, at.y))
	out["Police Coverage"] = level_text(city.police_at(at.x, at.y))
	out["Fire Coverage"] = level_text(city.fire_cover_at(at.x, at.y))
	if sim != null and Buildings.is_zone_building(id):
		var zones := sim.get_system(&"zones")
		if zones != null and zones.has_method("population_of"):
			var people := int(zones.call("population_of", id))
			var jobs := int(zones.call("jobs_of", id))
			out["Residents"] = people
			out["Jobs"] = jobs
			if zones.has_method("stage_of"):
				out["Development stage"] = int(zones.call("stage_of", id))
	var record := city.facility(anchor)
	var station := id in [Buildings.RAIL_STATION,Buildings.SUBWAY_STATION]
	var resort := ResortThemes.key_for_building(id)
	if station or not record.is_empty() or resort != &"": out["#Facility"] = ""
	if station:
		out["Name"] = StationNameResolver.display_name(city,anchor,id==Buildings.SUBWAY_STATION)
		out["Name mode"] = String(StationNameResolver.name_mode(city,anchor)).capitalize()
	if not record.is_empty():
		if not station and record.has("name"):
			out["Name"] = String(record["name"])
		var built := int(record.get("built_day", city.day))
		@warning_ignore("integer_division")
		out["Built"] = str(city.founded_year + built / GameClock.DAYS_PER_YEAR)
		@warning_ignore("integer_division")
		out["Age"] = "%d years" % maxi(0, (city.day - built) / GameClock.DAYS_PER_YEAR)
		var shown := _facility_figures(city, sim, anchor, id)
		for key in shown:
			out[key] = shown[key]
		for field in record:
			var f := String(field)
			if f in HIDDEN_FIELDS or shown.has(f.replace("_", " ").capitalize()):
				continue
			var value: Variant = record[field]
			if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_BOOL:
				out[f.replace("_", " ").capitalize()] = value
	elif resort != &"":
		_resort_figures(out, city, sim, resort)
	out["_demolishable"] = id != Buildings.NONE or under != Underground.NONE
	out["_renamable"] = not record.is_empty()
	return out


## The live figures the systems keep for a facility: plant output, water
## output and storage, arcology residents, station riders, prison counts.
static func _facility_figures(city: City, sim: Simulation, anchor: Vector2i, id: int) -> Dictionary:
	var out: Dictionary = {}
	if sim == null:
		return out
	match Buildings.category(id):
		Buildings.Category.PLANT:
			var power := sim.get_system(&"power")
			if power != null and power.has_method("plant_capacity"):
				out["Output"] = "%d units" % int(power.call("plant_capacity", anchor))
			var rec := city.facility(anchor)
			if rec.has("age_years"):
				out["Service years"] = int(rec["age_years"])
		Buildings.Category.UTILITY:
			var water := sim.get_system(&"water")
			if water != null and water.has_method("network_summary"):
				var summary: Dictionary = water.call("network_summary")
				for entry in summary.get("facilities", []):
					var facility: Dictionary = entry
					if facility.get("anchor", Vector2i(-1, -1)) == anchor:
						out["Output"] = "%d units" % int(facility.get("output", 0))
						if int(facility.get("stored", 0)) > 0 or id == Buildings.WATER_TOWER:
							out["Stored"] = int(facility.get("stored", 0))
						out["Powered"] = "Yes" if bool(facility.get("powered", false)) else "No"
		Buildings.Category.ARCOLOGY:
			var rewards := sim.get_system(&"rewards")
			if rewards != null and rewards.has_method("arcology_report"):
				for entry in rewards.call("arcology_report"):
					var arcology: Dictionary = entry
					if arcology.get("anchor", Vector2i(-1, -1)) == anchor:
						out["Residents"] = int(arcology.get("residents", 0))
						out["Capacity"] = int(arcology.get("capacity", 0))
						out["Condition"] = int(arcology.get("condition", 0))
			var resort := ResortThemes.key_for_building(id)
			if resort != &"": _resort_figures(out, city, sim, resort)
		Buildings.Category.TRANSIT:
			var transport := sim.get_system(&"transport")
			if transport != null and transport.has_method("ridership"):
				var riders: Dictionary = transport.call("ridership")
				var mode := &"bus"
				if id == Buildings.RAIL_STATION:
					mode = &"rail"
				elif id == Buildings.SUBWAY_STATION:
					mode = &"subway"
				out["Riders this year"] = "%d (%s, citywide)" % [int(riders.get(mode, 0)), String(mode)]
		Buildings.Category.CIVIC:
			if id == Buildings.PRISON:
				var services := sim.get_system(&"services")
				if services != null and services.has_method("prison_report"):
					var report: Dictionary = services.call("prison_report")
					for entry in report.get("records", []):
						var prison: Dictionary = entry
						if int(prison.get("x", -1)) == anchor.x and int(prison.get("y", -1)) == anchor.y:
							out["Inmates"] = int(prison.get("inmates", 0))
							out["Guards"] = int(prison.get("guards", 0))
							out["Capacity"] = int(prison.get("capacity", 0))
							out["Utilization"] = "%d%%" % int(prison.get("utilization", 0))
							out["Escapes"] = int(prison.get("escapes", 0))
	return out


## A gaming resort's casino floor and the mayor's net play there this year
## (signed: "+$1,200" ahead, "-$500" behind). The ledger is kept per resort
## design, so when more than one lot of the design stands the figure says
## it covers them all: "+$1,200 across 2 floors".
static func _resort_figures(out: Dictionary, city: City, sim: Simulation, resort: StringName) -> void:
	out["Casino floor"] = ResortThemes.floor_name(resort)
	var casino: CasinoSystem = sim.casino() if sim != null else null
	if casino == null: return
	var net := int(casino.ledger(resort).get("year_net", 0))
	var text := ("+" if net > 0 else "") + CasinoLines.money(net)
	var floors := resort_lot_count(city, ResortThemes.building(resort))
	if floors > 1: text += " across %d floors" % floors
	out["Mayor's play this year"] = text


## How many lots of building `code` stand in the city (one per anchor).
static func resort_lot_count(city: City, code: int) -> int:
	if city == null or code <= 0: return 0
	var count := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if city.building_at(x, y) == code and city.anchor_of(x, y) == Vector2i(x, y):
				count += 1
	return count


## Numbers get thousands separators and flags read Yes/No.
static func value_text(value: Variant) -> String:
	if typeof(value) == TYPE_BOOL:
		return "Yes" if bool(value) else "No"
	if typeof(value) == TYPE_INT:
		return UIFactory.commafy_signed(int(value))
	return str(value)


## A word for a 0–255 map reading, so players compare tiles without
## learning the internal scale.
static func level_text(value: int) -> String:
	if value <= 0:
		return "None"
	if value < 64:
		return "Low"
	if value < 128:
		return "Medium"
	if value < 192:
		return "High"
	return "Very high"


## A short name for an underground code.
static func underground_text(code: int) -> String:
	if code == Underground.STATION_LINK:
		return "Subway station link"
	if Underground.is_crossing(code):
		return "Pipe and subway crossing"
	if Underground.is_subway(code):
		return "Subway tunnel"
	if Underground.is_pipe(code):
		return "Water pipe"
	return "Other underground works"


## The visible rows as "label: value" strings.
func lines() -> Array[String]:
	var out: Array[String] = []
	for key in info:
		var k := String(key)
		if k.begins_with("_") or k.begins_with("#"):
			continue
		out.append("%s: %s" % [k, value_text(info[key])])
	return out


func close() -> void:
	if not visible:
		return
	visible = false
	tile = Vector2i(-1, -1)
	closed.emit()


func is_open() -> bool:
	return visible
