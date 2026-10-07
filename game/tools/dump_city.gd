# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Dump layer histograms of an imported classic city as JSON, for comparing
## the importer against other decoders.
##   godot --headless --path game -s res://tools/dump_city.gd -- city.sc2 out.json
extends SceneTree
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var result: Dictionary = Sc2Import.load(args[0])
	if not bool(result["ok"]):
		print("import failed: ", result.get("error", "")); quit(1); return
	var city: City = result["city"]
	var out := {}
	out["name"] = city.name; out["founded"] = city.founded_year; out["days"] = city.day; out["money"] = city.funds; out["sea"] = city.sea_level
	var hist := {}; var alt := {}; var ter := {}; var zon := {}; var corner := {}; var bit := {}
	for y in 128:
		for x in 128:
			var b := city.building_at(x, y); hist[b] = int(hist.get(b, 0)) + 1
			var a := city.ground_height(x, y); alt[a] = int(alt.get(a, 0)) + 1
			var t := city.terrain.at(x, y); ter[t] = int(ter.get(t, 0)) + 1
			var z := city.zone.at(x, y); zon[z & 15] = int(zon.get(z & 15, 0)) + 1; corner[z >> 4] = int(corner.get(z >> 4, 0)) + 1
			var f := city.flags.at(x, y); bit[f] = int(bit.get(f, 0)) + 1
	out["building_hist"] = hist; out["altitude_hist"] = alt; out["terrain_hist"] = ter; out["zone_hist"] = zon; out["corner_hist"] = corner; out["flag_hist"] = bit
	var sample := []
	for p in [[74, 74], [60, 60], [80, 70], [50, 90], [100, 40]]:
		sample.append({"x": p[0], "y": p[1], "bld": city.building_at(p[0], p[1]), "zon": city.zone.at(p[0], p[1]), "ter": city.terrain.at(p[0], p[1]), "alt": city.ground_height(p[0], p[1]), "water": city.water_height(p[0], p[1]), "word": city.altitude.at(p[0], p[1]), "bit": city.flags.at(p[0], p[1]), "und": city.underground.at(p[0], p[1])})
	out["samples"] = sample
	var alts := []; var ters := []; var waters := []
	for y in 128:
		for x in 128:
			alts.append(city.ground_height(x, y)); ters.append(city.terrain.at(x, y)); waters.append(city.water_height(x, y))
	out["alt"] = alts; out["ter"] = ters; out["water"] = waters
	out["warnings"] = result.get("warnings", [])
	var f := FileAccess.open(args[1], FileAccess.WRITE); f.store_string(JSON.stringify(out, "  ")); f.close()
	print("dumped"); quit()
