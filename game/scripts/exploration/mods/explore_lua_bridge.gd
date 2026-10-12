# SPDX-License-Identifier: GPL-3.0-or-later
class_name ExploreLuaBridge
extends RefCounted
const CONFIG := "res://addons/scdd_explore_lua/scdd_explore_lua.cfg"
const NATIVE_CLASS := &"SCDDExploreLua"
var _native: RefCounted
static func supported_platform() -> bool:
	return OS.get_name() == "macOS" or (OS.get_name() == "Windows" and OS.has_feature("x86_64"))
static func available() -> bool:
	if not supported_platform(): return false
	if ClassDB.class_exists(NATIVE_CLASS): return true
	var library := "res://addons/scdd_explore_lua/bin/libSCDDExploreLua.dylib" if OS.get_name() == "macOS" else "res://addons/scdd_explore_lua/bin/SCDDExploreLua.windows.x86_64.dll"
	# Do not ask the engine to load an absent native library (and emit errors).
	var library_name := library.get_file()
	var executable_dir := OS.get_executable_path().get_base_dir()
	var exists := FileAccess.file_exists(library)
	# Godot exports shared objects beside the executable (Windows) or into
	# Contents/Frameworks (macOS). Match those documented bundle locations.
	exists = exists or FileAccess.file_exists(executable_dir.path_join(library_name))
	exists = exists or FileAccess.file_exists(executable_dir.path_join("../Frameworks").path_join(library_name))
	if not FileAccess.file_exists(CONFIG) or not exists: return false
	var status := GDExtensionManager.load_extension(CONFIG)
	return status in [GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED] and ClassDB.class_exists(NATIVE_CLASS)
static func _unavailable() -> Dictionary:
	return {"ok":false, "fault":"unavailable", "commands":[], "progress_writes":{}, "logs":[], "instructions":0, "elapsed_usec":0, "bytes_used":0}
func start(source: String, modules: Dictionary, context: Dictionary, seed: int) -> Dictionary:
	close()
	if not available(): return _unavailable()
	_native = ClassDB.instantiate(NATIVE_CLASS)
	return _native.call("start", source, modules, context, seed)
func dispatch(handler: String, payload: Dictionary, context: Dictionary, budget: Dictionary) -> Dictionary:
	if _native == null: return _unavailable()
	if budget.size() > 3:
		close()
		var rejected := _unavailable()
		rejected.fault = "invalid_input"
		return rejected
	for key in budget:
		if key not in ["instructions", "remaining_usec", "deadline_usec"] or not budget[key] is int:
			close()
			var rejected := _unavailable()
			rejected.fault = "invalid_input"
			return rejected
	# The absolute engine-Time deadline is the scheduler's admission window.
	# Native rechecks it before entering Lua; once admitted, a callback keeps its
	# own CPU budget and wall backstop, so the shared window never shrinks them.
	var native_budget := budget.duplicate()
	var remaining := clampi(int(budget.get("remaining_usec", 1500)), 0, 1500)
	if budget.has("deadline_usec") and remaining > 0 and int(budget.deadline_usec) <= Time.get_ticks_usec():
		# No native entry occurred: retain the VM and the caller's queued work.
		return {"ok":true,"deferred":true,"fault":"","commands":[],"progress_writes":{},"logs":[],"instructions":0,"elapsed_usec":0,"bytes_used":0}
	native_budget["remaining_usec"] = remaining
	return _native.call("dispatch", handler, payload, context, native_budget)
func close() -> void:
	if _native != null:
		_native.call("close")
		_native = null

## Lua error text is untrusted plain text. Native chunks are package-relative;
## redact absolute host paths even when an author embeds one in an error.
static func diagnostic_text(value: Variant) -> String:
	if not value is String: return ""
	var text: String = value.left(4096)
	var paths := RegEx.new()
	paths.compile("(?<![A-Za-z0-9_.])(?:[A-Za-z]:[\\\\/]|(?:res|user|file)://|/)[^\\s\"'<>]*")
	text = paths.sub(text,"[path]",true)
	# Inspect existing characters; constructing chr(0) itself emits a Godot error.
	for index in range(text.length()-1,-1,-1):
		var code := text.unicode_at(index)
		if code < 32 and code != 10 and code != 9: text = text.erase(index,1)
	return bounded_text(text,4096)

static func diagnostic_summary(entry: Dictionary) -> String:
	var detail := diagnostic_text(entry.get("diagnostic",""))
	return String(entry.get("reason",""))+(": "+detail if not detail.is_empty() else "")

static func bounded_text(text: String, max_bytes: int) -> String:
	var bytes := text.to_utf8_buffer()
	var cut := mini(max_bytes,bytes.size())
	# Cut before a partial UTF-8 character without repeatedly encoding the report.
	while cut > 0 and cut < bytes.size() and (bytes[cut] & 0xc0) == 0x80: cut -= 1
	return bytes.slice(0,cut).get_string_from_utf8()
