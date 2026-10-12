# SPDX-License-Identifier: GPL-3.0-or-later
## A north-up slice of the canonical city. The live view follows; browsing
## changes only this camera, never the player or the Build camera.
class_name ExploreNavigationMap
extends Control

signal expand_requested
var texture: Texture2D
var center := Vector2(64,64)
var span := 24.0
var browsing := false
var player: Dictionary = {}
var markers: Array[Dictionary] = []
var _dragging := false
var _touches: Dictionary = {}
const INK := Color("173b3e")
const PAPER := Color("fff3d8")
const COLORS := {"objective":Color("ffca64"),"person":Color("87ead6"),"vehicle":Color("90bfff"),"checkpoint":Color("f6a7cb")}

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_map_input)

func map_point(at: Vector2) -> Vector2:
	return (at-center)*(size.x/span)+size*.5

func tile_point(at: Vector2) -> Vector2:
	return center+(at-size*.5)*(span/maxf(1,size.x))

func set_span(value: float) -> void:
	span = clampf(value,8,128)
	clamp_center()
	queue_redraw()

func clamp_center() -> void:
	center = center.clamp(Vector2.ZERO,Vector2(City.WIDTH,City.HEIGHT))

func pan_pixels(relative: Vector2) -> void:
	center -= relative*(span/maxf(1,size.x))
	clamp_center()
	queue_redraw()

func reset_gestures() -> void:
	_dragging = false
	_touches.clear()

func _map_input(event: InputEvent) -> void:
	# The real screen events own map gestures. Godot also emits a mouse stream
	# for the first finger; applying both would double pan and pinch motion.
	if event.device == InputEvent.DEVICE_ID_EMULATION and (event is InputEventMouseButton or event is InputEventMouseMotion):
		accept_event()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not browsing and event.pressed: expand_requested.emit()
			_dragging = browsing and event.pressed
		elif browsing and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			set_span(span*(.8 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.25))
	elif event is InputEventMouseMotion and _dragging and browsing:
		pan_pixels(event.relative)
	elif event is InputEventScreenTouch:
		if event.canceled:
			_touches.erase(event.index)
		elif event.pressed:
			if not browsing: expand_requested.emit()
			else: _touches[event.index] = event.position
		else: _touches.erase(event.index)
	elif event is InputEventScreenDrag and browsing and _touches.has(event.index):
		if _touches.size() == 1: pan_pixels(event.position-Vector2(_touches[event.index]))
		elif _touches.size() == 2:
			var indices := _touches.keys()
			var other: int = indices[1] if indices[0] == event.index else indices[0]
			var before := Vector2(_touches[event.index]).distance_to(_touches[other])
			var after: float = event.position.distance_to(_touches[other])
			if before > 4 and after > 4: set_span(span*before/after)
		_touches[event.index] = event.position
	elif event is InputEventMagnifyGesture and browsing:
		set_span(span/maxf(.1,event.factor))
	elif event is InputEventPanGesture and browsing:
		pan_pixels(event.delta*12)
	accept_event()

static func distance_text(tiles: float) -> String:
	var metres := tiles*ExploreActorProfile.METRES_PER_TILE
	return "%.1f km" % (metres/1000.0) if metres >= 1000 else "%d m" % roundi(metres)

static func draw_pin(canvas: Control, at: Vector2, icon: String, radius: float = 6.0) -> void:
	var color: Color = COLORS.get(icon,COLORS.objective)
	canvas.draw_circle(at,radius+2,INK)
	match icon:
		"person":
			canvas.draw_circle(at,radius,color)
			canvas.draw_circle(at-Vector2(0,2),1.6,INK)
			canvas.draw_line(at+Vector2(-2,2),at+Vector2(2,2),INK,2)
		"vehicle":
			canvas.draw_rect(Rect2(at-Vector2(radius,radius*.6),Vector2(radius*2,radius*1.2)),color)
		"checkpoint":
			canvas.draw_circle(at,radius,color,false,2)
			canvas.draw_line(at+Vector2(-radius*.5,0),at+Vector2(radius*.5,0),color,2)
		_:
			canvas.draw_colored_polygon(PackedVector2Array([at+Vector2(0,-radius),at+Vector2(radius,0),at+Vector2(0,radius),at+Vector2(-radius,0)]),color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),INK)
	var scale := size.x/span
	var crop := Rect2(center-size/(2*scale),size/scale)
	var source := crop.intersection(Rect2(0,0,City.WIDTH,City.HEIGHT))
	if texture != null and source.has_area():
		draw_texture_rect_region(texture,Rect2((source.position-crop.position)*scale,source.size*scale),source)
	# Labels get a short opaque backing; pins retain their own shapes in dense
	# streets. Deterministic nearest-first placement limits label overlap.
	var font := ThemeDB.fallback_font
	var occupied_labels: Array[Rect2] = [Rect2(5,5,23,25),Rect2(5,size.y-34,100,29)]
	var labels := 0
	for entry: Dictionary in markers:
		if not entry.map: continue
		var at: Vector3 = entry.position
		var raw := map_point(Vector2(at.x,at.z))
		var point := raw.clamp(Vector2(10,10),size-Vector2(10,10))
		if point != raw:
			var direction := (raw-point).normalized()
			draw_line(point,point+direction*7,Color(COLORS[entry.icon]),2)
		draw_pin(self,point,entry.icon)
		if browsing and labels < 12 and not String(entry.label).is_empty():
			var text := String(entry.label).replace("\n"," ").replace("\r"," ").left(30)
			var width := minf(size.x-20,font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+12)
			var label_rect := Rect2((point+Vector2(10,-10)).clamp(Vector2(4,4),size-Vector2(width+4,26)),Vector2(width,22))
			if not occupied_labels.any(func(rect: Rect2) -> bool: return rect.intersects(label_rect)):
				draw_rect(label_rect,INK)
				draw_string(font,label_rect.position+Vector2(6,16),text,HORIZONTAL_ALIGNMENT_LEFT,width-12,14,PAPER)
				occupied_labels.append(label_rect)
				labels += 1
	if not player.is_empty():
		var at: Vector2 = player.position
		var point := map_point(at).clamp(Vector2(9,9),size-Vector2(9,9))
		var direction: Vector2 = player.heading
		if direction.length_squared() < .001: direction = Vector2.UP
		draw_circle(point,8,INK)
		draw_colored_polygon(PackedVector2Array([point+direction*10,point-direction*5+direction.orthogonal()*5,point-direction*5-direction.orthogonal()*5]),PAPER)
		draw_circle(point,2,INK)
	# Compass and scale stay readable at every zoom and at the city edges.
	draw_rect(Rect2(5,5,23,25),INK)
	draw_string(font,Vector2(10,23),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,16,PAPER)
	var bar := minf(56,size.x*.3)
	var y := size.y-10
	draw_line(Vector2(10,y),Vector2(10+bar,y),INK,5)
	draw_line(Vector2(10,y),Vector2(10+bar,y),PAPER,2)
	var caption := distance_text(bar/scale)
	draw_string_outline(font,Vector2(10,y-7),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,4,INK)
	draw_string(font,Vector2(10,y-7),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,PAPER)
	draw_rect(Rect2(Vector2.ZERO,size),PAPER,false,2)
