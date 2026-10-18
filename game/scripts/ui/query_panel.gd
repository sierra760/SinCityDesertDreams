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
signal sign_edit_requested(tile: Vector2i)
signal closed

const PANEL_WIDTH := 320
## Record fields never listed as counters.
const HIDDEN_FIELDS: Array[String] = ["key", "built_day", "warned", "age_years", "name", "built_year", "imported", "tourism_instance", "tourism_migrated", "residents"]

var title_label: Label
var rows: VBoxContainer
var body_scroll: ScrollContainer
var demolish_button: Button
var rename_button: Button
var sign_button: Button
var close_button: Button
## The tile shown, or (-1,-1).
var tile := Vector2i(-1, -1)
## Everything shown, keyed by row label.
var info: Dictionary = {}
## Whether the city is shown underground: Demolish then digs up only the
## pipes and subway under the tile, and on the surface never touches them.
var underground_view := false
var _content_revision := 0
var _column: VBoxContainer
var _title_row: HBoxContainer
var _actions: HBoxContainer
var _compact_header := false
var _scroll_restore_revision := -1


func _init() -> void:
	name = "QueryPanel"
	if MobilePlatform.is_ios(): theme = UITheme.control_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UITheme.window_stylebox())
	custom_minimum_size = Vector2.ZERO
	_build()
	visible = false


func _ready() -> void:
	set_process_input(_scroll_restore_revision >= 0)


func _build() -> void:
	var column := VBoxContainer.new()
	_column = column
	column.add_theme_constant_override("separation", UITheme.VSEP)
	add_child(column)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UITheme.title_bar_stylebox())
	column.add_child(bar)
	var bar_row := HBoxContainer.new()
	_title_row = bar_row
	bar.add_child(bar_row)
	title_label = UIFactory.make_label("Inspect", UITheme.FONT_TITLE, UITheme.TITLE_TEXT)
	title_label.add_theme_font_override("font", UITheme.DISPLAY_FONT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	body_scroll.get_v_scroll_bar().scrolling.connect(_cancel_scroll_restore)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(rows)
	column.add_child(body_scroll)
	sign_button = UIFactory.make_button("Edit Sign", "Edit this tile's sign; blank text removes it")
	sign_button.pressed.connect(func() -> void:
		if tile.x >= 0 and info.has("Sign"):
			sign_edit_requested.emit(tile))
	column.add_child(sign_button)
	var actions := HBoxContainer.new()
	_actions = actions
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


## Short landscape viewports put the same 44-point actions beside the title,
## recovering a readable scroll body without covering the status face.
func set_compact_header(compact: bool) -> void:
	if compact == _compact_header: return
	_compact_header = compact
	_actions.reparent(_title_row if compact else _column)
	if compact:
		_title_row.move_child(_actions, _title_row.get_child_count() - 2)


## Fill the panel for `at` and show it.
func show_tile(city: City, sim: Simulation, at: Vector2i) -> void:
	var next := describe(city, sim, at, underground_view)
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
	title_label.tooltip_text = title_label.text
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
	var buried := String(info.get("_removes_underground", ""))
	demolish_button.text = "Remove " + buried.to_lower() if not buried.is_empty() else "Demolish"
	demolish_button.tooltip_text = "Dig up the %s under this tile" % buried.to_lower() if not buried.is_empty() else "Bulldoze this tile"
	rename_button.disabled = not bool(info.get("_renamable", false))
	sign_button.visible = info.has("Sign")
	visible = true
	body_scroll.scroll_vertical = reading_position
	if _scroll_is_gliding():
		_cancel_scroll_restore()
		return
	_scroll_restore_revision = _content_revision
	set_process_input(true)
	_restore_scroll.call_deferred(reading_position, _content_revision)


## Called after completed simulation updates; a hidden inspector stays hidden.
func refresh(city: City, sim: Simulation) -> void:
	if visible and tile.x >= 0:
		show_tile(city, sim, tile)


func _restore_scroll(value: int, revision: int) -> void:
	if revision != _content_revision or _scroll_restore_revision != revision:
		if _scroll_restore_revision == revision: _cancel_scroll_restore()
		return
	# Row wrapping and the panel's content fit can change the range again after
	# this deferred call. Restore once that layout has completed.
	await get_tree().process_frame
	if _scroll_restore_revision == revision and _scroll_is_gliding(): _cancel_scroll_restore()
	if revision == _content_revision and _scroll_restore_revision == revision and visible:
		body_scroll.scroll_vertical = value
	if _scroll_restore_revision == revision:
		_scroll_restore_revision = -1
		set_process_input(false)


## Only pending layout restoration observes input. A newer scroll gesture or
## focus navigation owns the reading position; layout-driven clamps do not.
func _input(event: InputEvent) -> void:
	if _scroll_restore_revision < 0 or not visible: return
	var scroll_input := false
	if event is InputEventKey and event.pressed:
		var focused := get_viewport().gui_get_focus_owner()
		var in_body := focused != null and (focused == body_scroll or body_scroll.is_ancestor_of(focused))
		scroll_input = in_body and event.keycode in [KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END, KEY_SPACE]
		if event.keycode == KEY_TAB and focused != null and is_ancestor_of(focused): scroll_input = true
	elif event is InputEventMouseButton:
		scroll_input = event.pressed and _inside_scroll(event.position)
	elif event is InputEventScreenTouch:
		scroll_input = event.pressed and _inside_scroll(event.position)
	elif event is InputEventScreenDrag:
		scroll_input = _inside_scroll(event.position) or _inside_scroll(event.position-event.relative)
	elif event is InputEventPanGesture:
		scroll_input = _inside_scroll(event.position)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		scroll_input = _inside_scroll(event.position)
	if scroll_input: _cancel_scroll_restore()


func _cancel_scroll_restore() -> void:
	if _scroll_restore_revision < 0: return
	_scroll_restore_revision = -1
	set_process_input(false)


func _inside_scroll(point: Vector2) -> bool:
	var local := body_scroll.get_global_transform_with_canvas().affine_inverse()*point
	return Rect2(Vector2.ZERO,body_scroll.size).has_point(local)


func _scroll_is_gliding() -> bool:
	# The iOS gesture helper processes only while its existing momentum owns
	# the scroll. That motion needs no new raw input event to take precedence.
	var gesture := body_scroll.get_node_or_null(^"IOSGestureScroll") as IOSGestureScroll
	return gesture != null and gesture.is_processing()


## Everything the panel shows for a tile, in display order. Keys starting
## with "#" are section headers; keys starting with "_" are hidden.
static func describe(city: City, sim: Simulation, at: Vector2i, underground_layer: bool = false) -> Dictionary:
	var out: Dictionary = {}
	if city == null or not city.in_bounds(at.x, at.y):
		out["Location"] = "outside the city"
		return out
	var id := city.building_at(at.x, at.y)
	var anchor := city.anchor_of(at.x, at.y)
	var zone_kind := city.zone_kind_at(at.x, at.y)
	out["#Site"] = ""
	out["Location"] = "%d, %d" % [at.x, at.y]
	if Buildings.is_tree(id):
		out["Building"] = VegetationZones.tree_name(city, at, id)
	elif id != Buildings.NONE:
		out["Building"] = Buildings.display_name(id)
	elif city.is_water(at.x, at.y):
		out["Building"] = "Open water"
	elif zone_kind != Zones.NONE and Zones.NAMES.has(zone_kind):
		out["Building"] = "%s (vacant lot)" % String(Zones.NAMES[zone_kind])
	else:
		out["Building"] = "Open ground"
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
			if id != Buildings.id_of(&"com_corner_store"):
				out["Residents"] = people
			out["Jobs"] = jobs
			if zones.has_method("stage_of"):
				out["Development stage"] = int(zones.call("stage_of", id))
	# Inspect only on selection or completed source updates; no render-time census.
	if sim != null and Zones.is_agricultural(zone_kind):
		var agriculture := sim.get_system(&"agriculture") as AgricultureSystem
		if agriculture != null:
			var farm := agriculture.inspect_tile(at)
			if not farm.is_empty():
				out["#Agriculture"] = ""
				out["Agricultural state"] = String(farm.state).capitalize()
				out["Agricultural density"] = "High" if zone_kind == Zones.AGR_HIGH else "Low"
				if farm.archetype != &"":
					out["Farm type"] = String(farm.archetype).replace("_", " ").capitalize()
					if zone_kind == Zones.AGR_LOW:
						out["Parcel kind"] = "Pasture" if farm.archetype in [&"cattle_range", &"sheep_pasture"] else "Field"
				if int(farm.get("members_count",0)) > 0:
					out["Parcel area"] = "%d tiles" % int(farm.members_count)
					if farm.get("mode", &"") == &"legacy":
						out["Original footprint"] = "%d×%d" % [farm.rect.size.x, farm.rect.size.y]
				out["Agricultural jobs"] = int(farm.assigned_jobs)
				if farm.archetype in [&"cattle_range", &"sheep_pasture", &"dairy", &"feedlot"]:
					out["Livestock"] = int(farm.stock_count)
				out["Water requested"] = int(farm.water_required)
				out["Water supply"] = "Fully supplied" if bool(farm.water_supplied) else "Not fully supplied"
				out["Power requested"] = int(farm.power_required)
				out["Power supply"] = "Fully supplied" if bool(farm.power_supplied) else "Not fully supplied"
				out["Development reason"] = String(farm.blocked_reason) if not String(farm.blocked_reason).is_empty() else "All development requirements met."
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
	if underground_layer:
		# Underground, Demolish only digs up what is buried; the button says so.
		# A station's or portal's own track goes with it, from the surface.
		var portal := id >= Buildings.SUBWAY_PORTAL_FIRST and id <= Buildings.SUBWAY_PORTAL_LAST
		out["_demolishable"] = under != Underground.NONE and under != Underground.STATION_LINK and not portal
		if bool(out["_demolishable"]):
			out["_removes_underground"] = underground_text(under)
	else:
		out["_demolishable"] = id != Buildings.NONE
	out["_renamable"] = not record.is_empty()
	return out


## The live figures the systems keep for a facility: plant output, water
## output and storage, tourism attendance, station riders, prison counts.
static func _facility_figures(city: City, sim: Simulation, anchor: Vector2i, id: int) -> Dictionary:
	var out: Dictionary = {}
	if sim == null:
		return out
	match Buildings.category(id):
		Buildings.Category.PLANT:
			var power := sim.get_system(&"power")
			if power != null and power.has_method("plant_capacity"):
				out["Output"] = "%d units" % int(power.call("plant_capacity", anchor))
			var summary: Dictionary = power.call("network_summary") if power != null else {}
			out["City visitor power"] = "%d units" % int(summary.get("visitor_demand",0))
			out["City power spare"] = "%d units; local connections still required" % int(summary.get("spare_capacity",0))
			var rec := city.facility(anchor)
			if rec.has("age_years"):
				out["Service years"] = int(rec["age_years"])
		Buildings.Category.UTILITY:
			var water := sim.get_system(&"water")
			if water != null and water.has_method("network_summary"):
				var summary: Dictionary = water.call("network_summary")
				out["City visitor water"] = "%d units" % int(summary.get("visitor_demand",0))
				out["City water spare"] = "%d units; local connections still required" % int(summary.get("spare_capacity",0))
				for entry in summary.get("facilities", []):
					var facility: Dictionary = entry
					if facility.get("anchor", Vector2i(-1, -1)) == anchor:
						out["Output"] = "%d units" % int(facility.get("output", 0))
						if int(facility.get("stored", 0)) > 0 or id == Buildings.WATER_TOWER:
							out["Stored"] = int(facility.get("stored", 0))
						out["Powered"] = "Yes" if bool(facility.get("powered", false)) else "No"
		Buildings.Category.ARCOLOGY:
			out["Condition"] = int(city.facility(anchor).get("condition", 0))
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
	var resort := ResortThemes.key_for_building(id)
	if resort != &"":
		_tourism_figures(out, sim, anchor)
		_resort_figures(out, city, sim, resort)
	return out


static func _tourism_figures(out: Dictionary, sim: Simulation, anchor: Vector2i) -> void:
	var tourism := sim.tourism()
	if tourism == null: return
	var rec := tourism.venue_report(anchor)
	if rec.is_empty(): return
	out["#Tourism"] = ""
	out["Destination reputation"] = tourism.reputation_text()
	out["Resident effects"] = "Resident jobs, nearby shops, actual traffic and fares, local crime and nightlife use their ordinary systems. Visitors add no residents or votes."
	out["Tourists"] = int(rec.tourists)
	out["Guests"] = int(rec.guests)
	out["Day visitors"] = int(rec.day_visitors)
	out["Visitor segments"] = TourismMarkets.mix_text(rec.guest_segments,rec.day_segments)
	out["Tier yields"] = "Lodging %d%% / gaming %d%% of base; segment spending 85 / 100 / 150 / 110%%" % rec.yield_factors
	out["Tourism jobs"] = "%d offered / %d resident-filled / %d incoming" % [rec.positions,rec.local_staff,rec.incoming_staff]
	out["Staffing"] = "%d%%; supports %d of %d planned guests, %d of %d planned day visitors" % [rec.staffing_percent,rec.supported_capacity,rec.planned_guests,rec.supported_day_capacity,rec.planned_day_visitors]
	out["Utility support"] = "%d guests / %d day visitors; %s" % [rec.utility_supported_guests,rec.utility_supported_days,"accepted attendance" if String(rec.utility_limiting_reason).is_empty() else "limited by "+String(rec.utility_limiting_reason)]
	out["Visitor power"] = "%d %s above building demand" % [int(rec.visitor_power_demand),"unit" if int(rec.visitor_power_demand)==1 else "units"]
	out["Visitor water"] = "%d %s above building demand" % [int(rec.visitor_water_demand),"unit" if int(rec.visitor_water_demand)==1 else "units"]
	out["Lodging capacity"] = int(rec.capacity)
	out["Day visitor capacity"] = int(rec.day_capacity)
	out["Occupancy"] = "%d%%" % int(rec.occupancy)
	out["Operating"] = "Yes" if rec.operating else "No"
	out["Operating reason"] = "All services and access available" if rec.operating else String(rec.reason)
	out["Arrivals this month"] = int(rec.arrivals)
	out["Departures this month"] = int(rec.departures)
	var business_month := int(rec.business_month)
	@warning_ignore("integer_division")
	out["Business period"] = "Completed %s %d" % [GameClock.MONTH_NAMES[business_month % GameClock.MONTHS_PER_YEAR],
		sim.city.founded_year + business_month / GameClock.MONTHS_PER_YEAR] if business_month >= 0 else "No completed month"
	out["Completed lodging base"] = "$%.2f" % (int(rec.lodging_cents) / 100.0)
	out["Completed gaming base"] = "$%.2f" % (int(rec.gaming_cents) / 100.0)
	out["Casino source"] = "%.3f crime units / month" % (float(rec.crime_source_milli) / 1000.0)
	out["Casino safety"] = "%s tier; %s; ordinary police also applies" % [String(rec.security_tier).capitalize(), "program reduces source 40%" if rec.safety_active else "program inactive this period"]
	out["Nightlife exposure"] = "Up to %d local land-value points; six-tile reach, reduced by distance and greenery" % int(rec.nightlife_strength)
	out["District appeal"] = "+%d points; %d attraction categories" % [int(rec.district_appeal_bonus), rec.district_categories.size()]
	out["Resort variety"] = "+%d points from other resort identities" % int(rec.resort_variety_bonus)
	out["District access"] = String(rec.district_access)
	out["External access"] = String(rec.access_reason)
	out["Arrival capacity"] = "%d shared seats / month" % int(rec.arrival_capacity)
	out["Local day access"] = "Connected resident city" if rec.local_reachable else "No connected resident neighborhood"
	out["Retail support"] = "$%.2f business opportunity; $%.2f allocated nearby" % [int(rec.commercial_spending_cents) / 100.0, int(rec.commercial_allocated_cents) / 100.0]
	out["Business basis"] = "Completed average guest-month lodging; visitor gaming after payouts. Mayor play excluded."


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
	_cancel_scroll_restore()
	tile = Vector2i(-1, -1)
	closed.emit()


func is_open() -> bool:
	return visible
