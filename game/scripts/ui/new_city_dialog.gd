# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## New City: name, difficulty, founding year, terrain controls, a seed and a
## small preview of the generated map. Generate redraws the preview; Start
## hands the previewed city and its parameters to the host.
class_name NewCityDialog
extends Control

signal started(params: Dictionary, city: City)
signal closed

const YEARS: Array[int] = [1900, 1950, 2000, 2050]
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Medium", "Hard"]
const COASTS: Array[String] = ["none", "north", "south", "east", "west"]
const PREVIEW_SIZE := 192

var name_edit: LineEdit
var reroll_button: Button
var difficulty_button: OptionButton
var year_button: OptionButton
var hills_slider: HSlider
var water_slider: HSlider
var trees_slider: HSlider
var coast_button: OptionButton
var _row_captions: Array[Label] = []
var river_check: CheckBox
var seed_edit: LineEdit
var seed_button: Button
var preview_rect: TextureRect
var preview_label: Label
var generate_button: Button
var start_button: Button
var cancel_button: Button
var panel: PanelContainer
var form_columns: GridContainer

var source := "procedural"
var source_choice: OptionButton
var source_status: Label
var source_retry: Button
var import_button: Button
var procedural_form: VBoxContainer
var terrain_dialog: RealWorldTerrainDialog
var terrain_importer: RealWorldImporter
var terrain_transport: TerrainHttpTransport
var terrain_cache: TerrainTileCache
## Optional factory for a custom HTTP transport; native HTTPS is used otherwise.
var terrain_transport_factory: Callable
var _real_world_candidate := {}
## Real-world entry was chosen while the connection check was still running;
## open the chooser once it succeeds.
var _open_when_online := false
## Closing New City also closes the chooser; don't recheck the connection then.
var _closing := false

var preview_city: City
## Main supplies the shared loading transition; standalone dialogs stay usable.
var run_loading: Callable
var _preview_params: Dictionary = {}
var _name_rng := SimRng.new()


func _init() -> void:
	name = "NewCityDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var chrome := UIFactory.make_window_chrome("New City")
	panel = chrome["root"]
	panel.name = "Panel"
	(chrome["close_button"] as Button).pressed.connect(close)
	var body: VBoxContainer = chrome["body"]
	var guide := UIFactory.make_label("Choose your landscape. Shape it for free, then select Found City to start the clock.", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(guide)
	var columns := GridContainer.new()
	columns.columns = 2
	form_columns = columns
	columns.add_theme_constant_override("h_separation",16)
	columns.add_theme_constant_override("v_separation",16)
	body.add_child(columns)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 4)
	columns.add_child(form)

	form.add_child(UIFactory.make_section_header("City name"))
	var name_row := UIFactory.WrappingActions.new()
	form.add_child(name_row)
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.custom_minimum_size.y = 44
	name_edit.max_length = 24
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_text: String) -> void: _submit_primary())
	name_row.add_child(name_edit)
	reroll_button = UIFactory.make_button("Another Name", "Try another city name")
	reroll_button.pressed.connect(reroll_name)
	name_row.add_child(reroll_button)

	form.add_child(UIFactory.make_section_header("Difficulty"))
	difficulty_button = OptionButton.new()
	difficulty_button.fit_to_longest_item = false
	difficulty_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty_button.custom_minimum_size.y = 44
	difficulty_button.name = "Difficulty"
	for i in DIFFICULTY_NAMES.size():
		difficulty_button.add_item("%s — $%s to start" % [DIFFICULTY_NAMES[i],
			UIFactory.commafy(int(City.STARTING_FUNDS[i]))], i)
	difficulty_button.select(0)
	form.add_child(difficulty_button)

	form.add_child(UIFactory.make_section_header("Founding year"))
	year_button = OptionButton.new()
	year_button.custom_minimum_size.y = 44
	year_button.name = "Year"
	for i in YEARS.size():
		year_button.add_item(str(YEARS[i]), i)
	year_button.select(0)
	form.add_child(year_button)

	form.add_child(UIFactory.make_section_header("Terrain source"))
	source_choice = OptionButton.new()
	source_choice.custom_minimum_size.y = 44
	source_choice.add_item("Procedural")
	source_choice.add_item("Real-world terrain · Online")
	form.add_child(source_choice)
	source_choice.item_selected.connect(func(index: int) -> void:
		set_source("procedural" if index == 0 else "real_world")
		if source == "real_world": open_real_world())
	source_status = UIFactory.make_label("Checking connection…", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	source_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(source_status)
	source_retry = UIFactory.make_button("Retry connection")
	source_retry.pressed.connect(func() -> void:
		_ensure_importer()
		terrain_importer.set_visible(true)
		terrain_importer.check_online(true))
	form.add_child(source_retry)
	import_button = UIFactory.make_button("Choose real-world terrain")
	import_button.pressed.connect(open_real_world)
	form.add_child(import_button)
	import_button.visible = false
	procedural_form = VBoxContainer.new()
	form.add_child(procedural_form)
	form = procedural_form
	form.add_child(UIFactory.make_section_header("Terrain"))
	hills_slider = _slider(form, "Hills", TerrainGenerator.DEFAULT_HILLS)
	water_slider = _slider(form, "Water", TerrainGenerator.DEFAULT_WATER)
	trees_slider = _slider(form, "Trees", TerrainGenerator.DEFAULT_TREES)
	var coast_row := HBoxContainer.new()
	form.add_child(coast_row)
	coast_row.add_child(_row_caption("Coast"))
	coast_button = OptionButton.new()
	coast_button.custom_minimum_size.y = 44
	coast_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coast_button.name = "Coast"
	for i in COASTS.size():
		coast_button.add_item(COASTS[i].capitalize(), i)
	coast_button.select(0)
	coast_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coast_row.add_child(coast_button)
	river_check = CheckBox.new()
	river_check.custom_minimum_size.y = 44
	river_check.name = "River"
	river_check.text = "River"
	river_check.button_pressed = true
	form.add_child(river_check)

	form.add_child(UIFactory.make_section_header("Seed"))
	var seed_row := HBoxContainer.new()
	form.add_child(seed_row)
	seed_edit = LineEdit.new()
	seed_edit.name = "SeedEdit"
	seed_edit.custom_minimum_size.y = 44
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.placeholder_text = "any number or word"
	seed_edit.text_submitted.connect(func(_text: String) -> void: _submit_primary())
	seed_row.add_child(seed_edit)
	seed_button = UIFactory.make_button("Shuffle", "Pick a random seed")
	seed_button.pressed.connect(new_seed)
	seed_row.add_child(seed_button)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	columns.add_child(side)
	side.add_child(UIFactory.make_section_header("Preview"))
	preview_rect = TextureRect.new()
	preview_rect.name = "Preview"
	preview_rect.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_rect.stretch_mode = TextureRect.STRETCH_SCALE
	preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	side.add_child(preview_rect)
	preview_label = UIFactory.make_label("Select Generate for a first look.", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_label.custom_minimum_size = Vector2(PREVIEW_SIZE, 0)
	side.add_child(preview_label)
	generate_button = UIFactory.make_button("Generate", "Preview a landscape with these settings")
	generate_button.pressed.connect(func() -> void:
		if run_loading.is_valid(): run_loading.call("Generating terrain…","Preparing your landscape preview.",generate_preview)
		else: generate_preview())
	side.add_child(generate_button)

	var row: HBoxContainer = chrome["actions"]
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	cancel_button = UIFactory.make_button("Cancel")
	cancel_button.pressed.connect(close)
	row.add_child(cancel_button)
	start_button = UIFactory.make_primary_button("Shape City", "Shape the land for free. Found City starts the clock.")
	start_button.pressed.connect(func() -> void:
		if run_loading.is_valid(): run_loading.call("Preparing new city…","Preparing the land for your city.",start)
		else: start())
	row.add_child(start_button)

	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -290
	panel.offset_right = 290
	panel.offset_top = -250
	panel.offset_bottom = 250
	add_child(panel)
	WindowDrag.enable(chrome["title_bar"], panel)
	terrain_dialog = RealWorldTerrainDialog.new()
	add_child(terrain_dialog)
	terrain_dialog.accepted.connect(accept_real_world)
	terrain_dialog.closed.connect(func() -> void:
		# Closing the chooser suspends online work; a still-open real-world
		# choice checks the connection again so entry becomes available.
		if visible and not _closing and source == "real_world" and terrain_importer != null:
			terrain_importer.set_visible(true)
		_update_online_entry()
		if visible: UIFactory.contain_modal_focus(self, source_retry if import_button.disabled else import_button))
	resized.connect(func() -> void: apply_layout(size.x < 1000))
	for slider: HSlider in [hills_slider, water_slider, trees_slider]:
		slider.value_changed.connect(func(_value: float): _mark_preview_changed())
	for choice: OptionButton in [difficulty_button, year_button, coast_button]:
		choice.item_selected.connect(func(_index: int): _mark_preview_changed())
	river_check.toggled.connect(func(_value: bool): _mark_preview_changed())
	name_edit.text_changed.connect(func(_text: String): _mark_preview_changed())
	seed_edit.text_changed.connect(func(_text: String): _mark_preview_changed())


## Inline captions share the widest caption's width. Narrow dialogs wrap body
## labels, and a narrower caption would break its word across lines and
## stretch the row (and its dropdown) to that height. The theme font resolves
## only inside the tree, so widths are measured there.
func _row_caption(text: String) -> Label:
	var caption := UIFactory.make_label(text)
	_row_captions.append(caption)
	caption.ready.connect(_fit_row_captions)
	caption.theme_changed.connect(_fit_row_captions)
	return caption


func _fit_row_captions() -> void:
	var width := 0.0
	for caption: Label in _row_captions:
		if not caption.is_inside_tree():
			continue
		var font := caption.get_theme_font("font")
		var font_size := caption.get_theme_font_size("font_size")
		width = maxf(width, font.get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			+ caption.get_theme_stylebox("normal").get_minimum_size().x)
	for caption: Label in _row_captions:
		caption.custom_minimum_size.x = ceilf(width) + 1.0


func _slider(parent: Control, label: String, value: int) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(_row_caption(label))
	var s := HSlider.new()
	s.custom_minimum_size.y = 40
	s.name = label + "Slider"
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.custom_minimum_size.y = 44
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	var v := UIFactory.make_label(str(value), UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	v.custom_minimum_size = Vector2(28, 0)
	row.add_child(v)
	s.value_changed.connect(func(nv: float) -> void: v.text = str(int(nv)))
	return s


# ── Values ───────────────────────────────────────────────────────────────

## The generator parameters as set in the form.
func params() -> Dictionary:
	return {
		"name": name_edit.text.strip_edges(),
		"difficulty": difficulty_button.get_selected_id(),
		"founded_year": YEARS[clampi(year_button.get_selected_id(), 0, YEARS.size() - 1)],
		"hills": int(hills_slider.value),
		"water": int(water_slider.value),
		"trees": int(trees_slider.value),
		"coast": COASTS[clampi(coast_button.get_selected_id(), 0, COASTS.size() - 1)],
		"river": river_check.button_pressed,
		"seed": seed_value(),
	}


func set_params(values: Dictionary) -> void:
	if values.has("name"):
		name_edit.text = String(values["name"])
	if values.has("difficulty"):
		difficulty_button.select(clampi(int(values["difficulty"]), 0, 2))
	if values.has("founded_year"):
		var i := YEARS.find(int(values["founded_year"]))
		year_button.select(maxi(i, 0))
	if values.has("hills"):
		hills_slider.value = int(values["hills"])
	if values.has("water"):
		water_slider.value = int(values["water"])
	if values.has("trees"):
		trees_slider.value = int(values["trees"])
	if values.has("coast"):
		var c := COASTS.find(String(values["coast"]))
		coast_button.select(maxi(c, 0))
	if values.has("river"):
		river_check.button_pressed = bool(values["river"])
	if values.has("seed"):
		seed_edit.text = str(values["seed"])
	_mark_preview_changed()


## The seed as a number: digits are read as-is, any other text is hashed.
func seed_value() -> int:
	var text := seed_edit.text.strip_edges()
	if text.is_empty():
		new_seed()
		text = seed_edit.text
	if text.is_valid_int():
		return int(text)
	return text.hash()


func new_seed() -> void:
	seed_edit.text = str(randi() % 1000000000)
	_mark_preview_changed()


func reroll_name() -> void:
	name_edit.text = CityNames.random_name(_name_rng)
	_mark_preview_changed()


# ── Preview and start ────────────────────────────────────────────────────

## Generate the map for the current settings and draw it. Returns the city.
func generate_preview() -> City:
	if source == "real_world": return preview_city
	var p := params()
	if p["name"].is_empty():
		reroll_name()
		p = params()
	preview_city = TerrainGenerator.new().generate(p, SimRng.new(int(p["seed"])))
	_preview_params = p.duplicate()
	preview_rect.texture = ImageTexture.create_from_image(preview_image(preview_city))
	preview_label.text = "%s\nFounding year %d\nSeed %s" % [preview_city.name, preview_city.founded_year, _seed_caption(int(p["seed"]))]
	return preview_city


## The seed as the player typed it: a word stays a word, not its hash.
func _seed_caption(value: int) -> String:
	var typed := seed_edit.text.strip_edges()
	return typed if not typed.is_empty() and not typed.is_valid_int() else str(value)


## Enter in the name or seed field acts as the primary Shape City button.
func _submit_primary() -> void:
	if not visible or start_button.disabled: return
	start_button.pressed.emit()


## A finished start clears the name and seed so the next New City rolls fresh
## ones. Cancel keeps whatever the player typed.
func _clear_started_entries() -> void:
	name_edit.text = ""
	seed_edit.text = ""


## A colour-coded top-down picture of a city, one pixel per tile.
static func preview_image(city: City) -> Image:
	var image := Image.create(City.WIDTH, City.HEIGHT, false, Image.FORMAT_RGB8)
	for y in City.HEIGHT:
		for x in City.WIDTH:
			image.set_pixel(x, y, MiniMap.tile_color(city, x, y))
	return image


## Start with the previewed city, regenerating first if settings changed.
func start() -> void:
	if source == "real_world":
		if preview_city == null or _real_world_candidate.is_empty(): return
		_update_imported_metadata()
		var settings := RealWorldManifest.editing_settings(_real_world_candidate)
		if settings.is_empty(): return
		settings.merge(metadata(), true)
		var accepted_city := preview_city
		cancel_online_work()
		_open_when_online = false
		visible = false
		started.emit(settings, accepted_city)
		_clear_started_entries()
		closed.emit()
		return
	var p := params()
	if p["name"].is_empty():
		reroll_name()
		p = params()
	if preview_city == null or p != _preview_params:
		generate_preview()
		p = _preview_params
	cancel_online_work()
	_open_when_online = false
	visible = false
	started.emit(p, preview_city)
	_clear_started_entries()
	closed.emit()


func open() -> void:
	# The last handed-off city may now be the one in play. Drop every
	# reference to it before changing any metadata.
	preview_city = null
	_preview_params = {}
	_real_world_candidate = {}
	_ensure_importer()
	terrain_importer.release_candidate()
	terrain_dialog.reset_session()
	preview_rect.texture = null
	set_source("procedural")
	if name_edit.text.strip_edges().is_empty():
		reroll_name()
	if seed_edit.text.strip_edges().is_empty():
		new_seed()
	visible = true
	# Procedural maps need no network: the online check starts only when
	# Real-world terrain is chosen.
	UIFactory.contain_modal_focus(self, name_edit)


func close() -> void:
	if not visible:
		return
	_open_when_online = false
	_closing = true
	if terrain_dialog.visible: terrain_dialog.close()
	_closing = false
	cancel_online_work()
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		if terrain_dialog.visible: terrain_dialog.close()
		else: close()
		accept_event()

func apply_layout(compact: bool) -> void:
	form_columns.columns = 1 if compact else 2
	terrain_dialog.apply_layout(compact)


func _mark_preview_changed() -> void:
	if source == "real_world":
		_update_imported_metadata()
		return
	if preview_city != null:
		preview_label.text = "Your settings changed. Select Generate for a fresh preview, or Shape City to use them."


func metadata() -> Dictionary:
	return {"name": name_edit.text.strip_edges(), "difficulty": difficulty_button.get_selected_id(),
		"founded_year": YEARS[clampi(year_button.get_selected_id(), 0, YEARS.size()-1)]}

func _ensure_importer() -> void:
	if terrain_importer != null: return
	terrain_transport = terrain_transport_factory.call() if terrain_transport_factory.is_valid() else TerrainHttpTransport.new()
	add_child(terrain_transport)
	terrain_cache = TerrainTileCache.new()
	terrain_cache.configure()
	terrain_importer = RealWorldImporter.new()
	terrain_importer.configure(terrain_transport, terrain_cache)
	add_child(terrain_importer)
	terrain_dialog.bind(terrain_importer)
	terrain_importer.availability_changed.connect(func(status: String, detail: String) -> void:
		source_status.text = ("Ready" if status == "Online" else "Checking" if status == "Checking" else "Unavailable") + " · " + detail
		if status == "Online": _open_pending_real_world.call_deferred()
		elif status != "Checking": _open_when_online = false
		_update_online_entry())

func _update_online_entry() -> void:
	# An expired check repeats on its own while Real-world terrain is chosen.
	if visible and source == "real_world" and terrain_importer != null and terrain_importer.recheck_if_expired():
		source_status.text = "Checking…"
	import_button.disabled = terrain_importer == null or not terrain_importer.is_online_fresh()
	if import_button.disabled and source_status.text.begins_with("Ready"):
		source_status.text = "Checking…" if terrain_importer != null and terrain_importer.is_checking_online() else "Unavailable · Select Retry connection."

## Finish a real-world entry that waited for the connection check.
func _open_pending_real_world() -> void:
	if not _open_when_online: return
	_open_when_online = false
	if visible and source == "real_world" and not terrain_dialog.visible and terrain_importer != null and terrain_importer.is_online_fresh():
		terrain_dialog.open(metadata())

func _process(_delta: float) -> void:
	if visible: _update_online_entry()

func open_real_world() -> void:
	if not visible: return
	_ensure_importer()
	set_source("real_world")
	_update_online_entry()
	if not terrain_importer.is_online_fresh():
		# Still checking: open the chooser when the check succeeds. A failed
		# check waits for a deliberate Retry.
		_open_when_online = terrain_importer.is_checking_online()
		return
	_open_when_online = false
	terrain_dialog.open(metadata())

func set_source(value: String) -> void:
	if value not in ["procedural", "real_world"]: return
	var changed := source != value
	source = value
	source_choice.select(0 if source == "procedural" else 1)
	procedural_form.visible = source == "procedural"
	generate_button.visible = source == "procedural"
	import_button.visible = source == "real_world"
	if changed:
		if terrain_importer != null: terrain_importer.invalidate_settings()
		preview_city = _real_world_candidate.get("city") if source == "real_world" else null
		preview_rect.texture = ImageTexture.create_from_image(preview_image(preview_city)) if preview_city != null else null
		_preview_params = {}
	start_button.disabled = source == "real_world" and preview_city == null
	# The online status and Retry belong to Real-world terrain only.
	source_status.visible = source == "real_world"
	source_retry.visible = source == "real_world"
	if visible and terrain_importer != null:
		if source == "real_world" and changed: terrain_importer.set_visible(true)
		elif source == "procedural" and changed:
			_open_when_online = false
			terrain_importer.set_visible(false)
	if source == "real_world": _update_imported_metadata()
	else: preview_label.text = "Select Generate for a first look."

func accept_real_world(candidate: Dictionary) -> void:
	if not candidate.get("city") is City or RealWorldManifest.editing_settings(candidate).is_empty(): return
	_real_world_candidate = candidate.duplicate()
	source = "real_world"
	set_source(source)
	preview_city = candidate.city
	start_button.disabled = false
	_update_imported_metadata()
	preview_rect.texture = ImageTexture.create_from_image(preview_image(preview_city))

func _update_imported_metadata() -> void:
	if preview_city == null or _real_world_candidate.is_empty():
		preview_label.text = "Choose and preview real-world terrain before shaping your city."
		return
	var values := metadata()
	preview_city.name = values.name if not values.name.is_empty() else "New City"
	preview_city.difficulty = values.difficulty
	preview_city.founded_year = values.founded_year
	preview_city.funds = City.STARTING_FUNDS[values.difficulty]
	preview_label.text = "%s\nFounding year %d\nReal-world terrain · ready to shape" % [preview_city.name, preview_city.founded_year]

func cancel_online_work() -> void:
	terrain_dialog.suspend()

func resume_online_work() -> void:
	if visible and source == "real_world": terrain_dialog.resume()
