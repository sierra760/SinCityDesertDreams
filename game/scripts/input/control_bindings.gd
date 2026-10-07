# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Player keyboard bindings. Physical keys are shared by all input consumers;
## city saves and Godot's GUI navigation actions are independent of this table.
class_name ControlBindings
extends RefCounted

const DEFAULTS := {
	"pan_forward":[KEY_W,KEY_UP], "pan_back":[KEY_S,KEY_DOWN],
	"pan_left":[KEY_A,KEY_LEFT], "pan_right":[KEY_D,KEY_RIGHT],
	"rotate":[KEY_R], "zoom_1":[KEY_1], "zoom_2":[KEY_2], "zoom_3":[KEY_3],
	"zoom_4":[KEY_4], "zoom_5":[KEY_5], "query":[KEY_Q],
	"bulldoze":[KEY_B], "underground":[KEY_U],
	# Arrow keys are Explore alternates; Build's pan uses them in its own scope.
	"move_forward":[KEY_W,KEY_UP], "move_back":[KEY_S,KEY_DOWN], "move_left":[KEY_A,KEY_LEFT], "move_right":[KEY_D,KEY_RIGHT],
	"sprint":[KEY_SHIFT], "jump":[KEY_SPACE], "brake":[KEY_SPACE],
	"ascend":[KEY_Q], "descend":[KEY_E], "interact":[KEY_F],
	"pause":[KEY_P], "faster":[KEY_EQUAL,KEY_KP_ADD],
	"slower":[KEY_MINUS,KEY_KP_SUBTRACT], "fullscreen":[KEY_F11],
}
const GROUPS := {
	"Build": ["pan_forward","pan_back","pan_left","pan_right","rotate","zoom_1","zoom_2","zoom_3","zoom_4","zoom_5","query","bulldoze","underground"],
	"Explore": ["move_forward","move_back","move_left","move_right","sprint","jump","brake","ascend","descend","interact"],
	"General": ["pause","faster","slower","fullscreen"],
}
const LABELS := {
	"pan_forward":"Pan forward", "pan_back":"Pan back", "pan_left":"Pan left", "pan_right":"Pan right",
	"rotate":"Rotate view", "zoom_1":"Zoom: far", "zoom_2":"Zoom: medium", "zoom_3":"Zoom: near",
	"zoom_4":"Zoom: close", "zoom_5":"Zoom: closest", "query":"Inspect tile", "bulldoze":"Hold to bulldoze",
	"underground":"Underground view", "move_forward":"Forward / accelerate", "move_back":"Back / reverse",
	"move_left":"Left / steer left", "move_right":"Right / steer right", "sprint":"Sprint (walking)",
	"jump":"Jump (walking)", "brake":"Brake (vehicles)", "ascend":"Climb (flight)",
	"descend":"Descend (flight)", "interact":"Interact / enter / exit", "pause":"Pause / resume city",
	"faster":"Faster city speed", "slower":"Slower city speed", "fullscreen":"Fullscreen",
}
var _bindings: Dictionary = DEFAULTS.duplicate(true)

func values() -> Dictionary:
	return _bindings.duplicate(true)

func reset() -> void:
	_bindings = DEFAULTS.duplicate(true)

## Invalid/colliding profiles fall back as a whole rather than losing actions.
static func sanitize(value: Variant) -> Dictionary:
	var candidate := DEFAULTS.duplicate(true)
	if not value is Dictionary: return candidate
	for action: String in DEFAULTS:
		if not value.has(action): continue
		var codes: Variant = value[action]
		if not codes is Array or codes.is_empty() or codes.size() > 2: return DEFAULTS.duplicate(true)
		for code: Variant in codes:
			if typeof(code) != TYPE_INT or not valid_key(code): return DEFAULTS.duplicate(true)
		if codes.size() == 2 and int(codes[0]) == int(codes[1]): return DEFAULTS.duplicate(true)
		candidate[action] = codes.duplicate()
	var validator := ControlBindings.new()
	validator._bindings = candidate
	for action: String in candidate:
		for slot: int in candidate[action].size():
			if not validator.conflict(action,slot,int(candidate[action][slot])).is_empty(): return DEFAULTS.duplicate(true)
	return candidate

const MOVEMENT_ACTIONS: Array[String] = ["move_forward","move_back","move_left","move_right"]

## Give saved one-key movement bindings the default arrow alternate, unless the
## arrow is already used by an action that is active at the same time.
static func add_movement_alternates(value: Variant) -> Variant:
	if not value is Dictionary: return value
	var out: Dictionary = (value as Dictionary).duplicate(true)
	for action: String in MOVEMENT_ACTIONS:
		var codes: Variant = out.get(action)
		if not codes is Array or (codes as Array).size() != 1: continue
		var arrow := int(DEFAULTS[action][1])
		var taken := false
		for other: String in DEFAULTS:
			if other in GROUPS.Build: continue
			var other_codes: Variant = out.get(other, DEFAULTS[other])
			if other_codes is Array and arrow in (other_codes as Array): taken = true
		if not taken: (codes as Array).append(arrow)
	return out

func configure(value: Variant) -> void:
	_bindings = sanitize(value)

static func valid_key(code: int) -> bool:
	if code in [KEY_ESCAPE,KEY_TAB,KEY_ENTER,KEY_KP_ENTER,KEY_CTRL,KEY_META,KEY_ALT]: return false
	return (code >= KEY_SPACE and code <= KEY_ASCIITILDE) or (code >= KEY_BACKSPACE and code <= KEY_F35) or (code >= KEY_KP_MULTIPLY and code <= KEY_KP_9)

static func _scopes(action: String) -> Array:
	if action in GROUPS.General: return ["build","walk","drive","fly"]
	if action in GROUPS.Build: return ["build"]
	if action in ["sprint","jump"]: return ["walk"]
	if action == "brake": return ["drive"]
	if action in ["ascend","descend"]: return ["fly"]
	return ["walk","drive","fly"]

func conflict(action: String, slot: int, code: int) -> String:
	for other: String in _bindings:
		for index: int in _bindings[other].size():
			# The action's own other slot is not a conflict; assign() moves it.
			if other == action: continue
			if int(_bindings[other][index]) != code: continue
			for scope: String in _scopes(action):
				if scope in _scopes(other): return "Already used by %s." % LABELS[other]
	return ""

func assign(action: StringName, slot: int, code: int) -> String:
	var id := String(action)
	if not DEFAULTS.has(id) or slot < 0 or slot > 1: return "Unknown binding."
	if not valid_key(code): return "That key is reserved for menus. Choose another key."
	var error := conflict(id,slot,code)
	if not error.is_empty(): return error
	var codes: Array = _bindings[id]
	if slot >= codes.size(): codes.append(code)
	else: codes[slot] = code
	# Assigning the key already held by the other slot moves it there.
	for index: int in range(codes.size()-1,-1,-1):
		if index != mini(slot,codes.size()-1) and int(codes[index]) == code: codes.remove_at(index)
	return ""

func clear_alternate(action: StringName) -> void:
	var codes: Array = _bindings.get(String(action),[])
	if codes.size() > 1: codes.resize(1)

static func event_code(event: InputEventKey) -> int:
	var code := int(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	return KEY_EQUAL if code == KEY_PLUS else code

func matches(event: InputEventKey, action: StringName) -> bool:
	return (not event.pressed or (not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed)) and event_code(event) in _bindings.get(String(action),[])

func held(keys: Dictionary, action: StringName) -> bool:
	for code: int in _bindings.get(String(action),[]):
		var value: Variant = keys.get(code,false)
		if typeof(value) == TYPE_BOOL and value: return true
	return false

func pressed(action: StringName) -> bool:
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT) or Input.is_key_pressed(KEY_META): return false
	for code: int in _bindings.get(String(action),[]):
		if Input.is_physical_key_pressed(code): return true
	return false

func keys_for(group: String) -> Array[int]:
	var out: Array[int] = []
	for action: String in GROUPS.get(group,[]):
		for code: int in _bindings[action]:
			if code not in out: out.append(code)
	return out

func caption(action: StringName, slot: int = -1) -> String:
	var codes: Array = _bindings.get(String(action),[])
	if slot >= 0:
		return key_caption(int(codes[slot])) if slot < codes.size() else "Add key"
	var labels := PackedStringArray()
	for code: int in codes: labels.append(key_caption(code))
	return " / ".join(labels)

static func key_caption(code: int) -> String:
	var mapped := DisplayServer.keyboard_get_keycode_from_physical(code) if DisplayServer.get_name() in ["macOS","Windows","X11","Wayland"] else code
	return OS.get_keycode_string(mapped if mapped != 0 else code)
