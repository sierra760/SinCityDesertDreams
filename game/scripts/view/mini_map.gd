# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Corner overview: a 128×128 colour-coded top-down image of the city in
## screen orientation, a rectangle showing what the camera sees, and click
## to navigate. The image is regenerated only when the map or rotation
## changed since the last render.
class_name MiniMap
extends CanvasLayer

const DISPLAY_SIZE := 150
const IMAGE_SIZE := 128

const COLOR_EMPTY := Color(0.80, 0.70, 0.52)
const COLOR_TREES := Color(0.35, 0.55, 0.30)
const COLOR_RUBBLE := Color(0.40, 0.38, 0.35)
const COLOR_POWER := Color(0.90, 0.85, 0.20)
const COLOR_ROAD := Color(0.65, 0.65, 0.65)
const COLOR_HIGHWAY := Color(0.45, 0.45, 0.45)
const COLOR_RAIL := Color(0.55, 0.35, 0.15)
const COLOR_RESIDENTIAL := Color(0.45, 0.80, 0.40)
const COLOR_COMMERCIAL := Color(0.35, 0.50, 0.90)
const COLOR_INDUSTRIAL := Color(0.90, 0.65, 0.20)
const COLOR_CIVIC := Color(0.95, 0.95, 0.95)
const COLOR_WATER := Color(0.37, 0.64, 0.62)
const COLOR_DEFAULT := Color(0.55, 0.55, 0.55)
const ZONE_ALPHA := 0.35

var city: City
var view_3d: CityView3D
var input_blocked: Callable
var _image: Image
var _inputs: Dictionary = {}
var _texture_rect: TextureRect
var _overlay: Control
var _margin: MarginContainer


func _ready() -> void:
	layer = 10
	setup()


## Build the controls. Safe to call more than once.
func setup() -> void:
	if _texture_rect != null:
		return
	_margin = MarginContainer.new()
	_margin.name = "MiniMapMargin"
	_margin.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_margin.offset_left = -(DISPLAY_SIZE + 16)
	_margin.offset_top = -(DISPLAY_SIZE + 16)
	_margin.offset_right = -8
	_margin.offset_bottom = -8
	add_child(_margin)
	var container := Control.new()
	container.name = "MiniMapContainer"
	container.custom_minimum_size = Vector2(DISPLAY_SIZE, DISPLAY_SIZE)
	_margin.add_child(container)
	_texture_rect = TextureRect.new()
	_texture_rect.name = "MiniMapTexture"
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_texture_rect.custom_minimum_size = Vector2(DISPLAY_SIZE, DISPLAY_SIZE)
	_texture_rect.size = Vector2(DISPLAY_SIZE, DISPLAY_SIZE)
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_texture_rect.gui_input.connect(_on_click)
	container.add_child(_texture_rect)
	_overlay = Control.new()
	_overlay.name = "ViewportOverlay"
	_overlay.custom_minimum_size = Vector2(DISPLAY_SIZE, DISPLAY_SIZE)
	_overlay.size = Vector2(DISPLAY_SIZE, DISPLAY_SIZE)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_viewport_rect)
	container.add_child(_overlay)


## Follow canonical city data and the only playable camera.
func bind(value: City, view: CityView3D) -> void:
	if view_3d != null and view_3d.view_changed.is_connected(generate_image):
		view_3d.view_changed.disconnect(generate_image)
	city = value
	view_3d = view
	if view_3d != null:
		view_3d.view_changed.connect(generate_image)
	_inputs.clear()
	generate_image()

## Fit the overview in the logical city area beneath measured chrome.
func apply_layout(logical_bounds: Rect2, menu_height: float, status_height: float, toolbar_width: float) -> void:
	setup()
	var area := Rect2(logical_bounds.position + Vector2(toolbar_width, menu_height),
		Vector2(maxf(0, logical_bounds.size.x - toolbar_width), maxf(0, logical_bounds.size.y - menu_height - status_height)))
	var side := maxf(1.0, minf(DISPLAY_SIZE, minf(area.size.x, area.size.y) - 16.0))
	_margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_margin.position = area.end - Vector2(side + 8, side + 8)
	_margin.size = Vector2(side, side)
	var content := _texture_rect.get_parent() as Control
	content.custom_minimum_size = Vector2(side, side)
	_texture_rect.custom_minimum_size = Vector2(side, side)
	_texture_rect.size = Vector2(side, side)
	_overlay.custom_minimum_size = Vector2(side, side)
	_overlay.size = Vector2(side, side)

func _process(_delta: float) -> void:
	if _overlay != null:
		_overlay.queue_redraw()


## Rebuild the image when the map or rotation changed.
func generate_image() -> void:
	if city == null:
		return
	var rotation := display_rotation()
	var inputs := {"city": city, "rotation": rotation,
		"building": city.building.data, "terrain": city.terrain.data, "zone": city.zone.data, "flood": city.flood_overlay}
	if inputs == _inputs and _image != null:
		return
	# The same city in the same orientation repaints only the tiles whose bytes
	# changed; every pixel reads the same tile colour a full pass would.
	var incremental: bool = _image != null and _inputs.get("city") == city and int(_inputs.get("rotation", -1)) == rotation and _inputs.has("flood")
	if incremental:
		var changed: Dictionary = {}
		for layer: String in ["building", "terrain", "zone"]:
			_changed_indices(_inputs[layer], inputs[layer], changed)
		for collection: Dictionary in [_inputs.flood, city.flood_overlay]:
			for cell: Vector2i in collection:
				if _inputs.flood.get(cell) != city.flood_overlay.get(cell): changed[cell.y * City.WIDTH + cell.x] = true
		for index: int in changed:
			var d := Vector2i(index % City.WIDTH, index / City.WIDTH)
			var s := RotationMapper.data_to_screen_i(d, rotation)
			_image.set_pixel(s.x, s.y, tile_color(city, d.x, d.y))
	_inputs = {"city": city, "rotation": rotation,
		"building": city.building.data.duplicate(), "terrain": city.terrain.data.duplicate(), "zone": city.zone.data.duplicate(),
		"flood": city.flood_overlay.duplicate(true)}
	if not incremental:
		_image = Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGB8)
		for sy: int in IMAGE_SIZE:
			for sx: int in IMAGE_SIZE:
				var d := RotationMapper.screen_to_data(sx, sy, rotation)
				_image.set_pixel(sx, sy, tile_color(city, d.x, d.y))
	if _texture_rect != null:
		if _texture_rect.texture is ImageTexture:
			(_texture_rect.texture as ImageTexture).update(_image)
		else:
			_texture_rect.texture = ImageTexture.create_from_image(_image)


## Indices whose bytes differ, comparing whole rows before individual tiles.
static func _changed_indices(before: PackedByteArray, after: PackedByteArray, changed: Dictionary) -> void:
	if before == after: return
	if before.size() != after.size():
		for index: int in after.size(): changed[index] = true
		return
	for y: int in City.HEIGHT:
		var start := y * City.WIDTH
		if before.slice(start, start + City.WIDTH) == after.slice(start, start + City.WIDTH): continue
		for index: int in range(start, start + City.WIDTH):
			if before[index] != after[index]: changed[index] = true


## Colour for a data tile by what stands on it.
static func tile_color(city: City, x: int, y: int) -> Color:
	var id := city.building.at(x, y)
	if id == Buildings.NONE:
		if city.is_water(x, y):
			return COLOR_WATER
		var zone_kind := city.zone_kind_at(x, y)
		if zone_kind != Zones.NONE:
			var tint: Color = CityOverlaySampler.ZONE_TINTS.get(zone_kind, COLOR_DEFAULT)
			return COLOR_EMPTY.lerp(tint, ZONE_ALPHA)
		return COLOR_EMPTY
	match Buildings.category(id):
		Buildings.Category.TREE: return COLOR_TREES
		Buildings.Category.RUBBLE, Buildings.Category.CONSTRUCTION, Buildings.Category.ABANDONED: return COLOR_RUBBLE
		Buildings.Category.POWER_LINE: return COLOR_POWER
		Buildings.Category.ROAD, Buildings.Category.TUNNEL: return COLOR_ROAD
		Buildings.Category.BRIDGE: return COLOR_POWER if id == Buildings.id_of(&"power_elevated") else COLOR_ROAD
		Buildings.Category.RAIL: return COLOR_RAIL
		Buildings.Category.HIGHWAY: return COLOR_HIGHWAY
		Buildings.Category.RESIDENTIAL: return COLOR_RESIDENTIAL
		Buildings.Category.COMMERCIAL: return COLOR_COMMERCIAL
		Buildings.Category.INDUSTRIAL: return COLOR_INDUSTRIAL
	return COLOR_CIVIC


func get_image() -> Image:
	return _image


# ── Navigation ───────────────────────────────────────────────────────────

func _on_click(event: InputEvent) -> void:
	if input_blocked.is_valid() and bool(input_blocked.call()):
		return
	if not (event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		return
	if city == null or view_3d == null or not view_3d.active:
		return
	var local: Vector2 = (event as InputEventMouseButton).position
	var factor := Vector2(IMAGE_SIZE, IMAGE_SIZE) / _texture_rect.size
	var sx := clampi(int(local.x * factor.x), 0, IMAGE_SIZE - 1)
	var sy := clampi(int(local.y * factor.y), 0, IMAGE_SIZE - 1)
	view_3d.set_center_cell(RotationMapper.screen_to_data(sx, sy, display_rotation()))


# ── Viewport rectangle ───────────────────────────────────────────────────

## Display-space rectangle of the camera's visible region: the bounding box
## of all four view corners mapped to minimap pixels.
func viewport_minimap_rect() -> Rect2:
	if view_3d != null and view_3d.active:
		return view_3d.minimap_rect(display_rotation(), _texture_rect.size.x / IMAGE_SIZE)
	return Rect2()


## The minimap's on-screen frame in global canvas coordinates.
func frame_rect() -> Rect2:
	return _margin.get_global_rect() if is_instance_valid(_margin) else Rect2()


func _draw_viewport_rect() -> void:
	if _overlay == null:
		return
	var rect := viewport_minimap_rect()
	if rect == Rect2():
		return
	rect = rect.intersection(Rect2(Vector2.ZERO, _texture_rect.size))
	if rect.size.x < 2 or rect.size.y < 2:
		return
	_overlay.draw_rect(rect, Color(1.0, 1.0, 1.0, 0.8), false, 1.5)


## Rotation changes orientation without modifying canonical city data.
func display_rotation() -> int:
	return posmod(view_3d.quarter_turn, 4) if view_3d != null else 0
