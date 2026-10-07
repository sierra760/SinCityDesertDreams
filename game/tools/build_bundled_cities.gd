# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Import each classic source city through the actual game host and write the
## native `.sc2d` a player gets from Import Classic City followed by Save.
##   godot --headless --path <isolated copy> -s res://tools/build_bundled_cities.gd -- <out dir> <name>...
## Run through `tools/build_bundled_cities.py`, which supplies a private
## user-data directory; this script never writes outside `<out dir>`.
extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const SOURCE := "res://assets/cities/%s.sc2"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL: ", message)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <out dir> <city name>...")
		quit(2)
		return
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var host: GameHost = MainScene.instantiate()
	host.preferences_path = "user://build-bundled-cities.cfg"
	root.add_child(host)
	await process_frame
	var built := 0
	for index in range(1, args.size()):
		if await _build(host, String(args[index]), output): built += 1
	host.queue_free()
	await process_frame
	print("Results: %d passed, %d failed" % [built, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _build(host: GameHost, city_name: String, output: String) -> bool:
	var source := SOURCE % city_name
	var expected := Sc2Import.load(source)
	if not bool(expected["ok"]):
		_fail("%s: source does not import: %s" % [city_name, expected.get("error", "")])
		return false
	if not host.import_city(source):
		_fail("%s: host import failed" % city_name)
		return false
	# The included city carries its catalog name, whatever the classic file stored.
	host.sim.city.name = city_name
	# Let deferred naming/binding work settle exactly as a player would see it.
	for frame in 3:
		await process_frame
	var target := output.path_join("%s.%s" % [city_name, SaveFormat.EXTENSION])
	var error := SaveFormat.save(target, host.sim.city, host.sim.snapshot())
	if error != OK:
		_fail("%s: save error %d" % [city_name, error])
		return false
	var reloaded := SaveFormat.load(target)
	if not bool(reloaded["ok"]):
		_fail("%s: written save does not load: %s" % [city_name, reloaded.get("error", "")])
		return false
	var city: City = reloaded["city"]
	var source_city: City = expected["city"]
	if SaveFormat.encode_city(city) != SaveFormat.encode_city(host.sim.city):
		_fail("%s: reloaded city differs from the imported city" % city_name)
		return false
	if city.name != city_name or city.funds != source_city.funds or city.day != source_city.day:
		_fail("%s: name/funds/day differ from the catalog name or classic source" % city_name)
		return false
	print("built %s -> %s (%d bytes)" % [city_name, target, FileAccess.get_file_as_bytes(target).size()])
	return true
