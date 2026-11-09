# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Offline curation support. Only supplied city files and output paths are used;
## no host, clock, preferences, cloud or player saves are opened.
##   -- inspect <output.json> <native city paths...>
##   -- stations <output directory> <native candidate paths...>
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3 or args[0] not in ["inspect", "stations", "validate"]:
		push_error("Expected inspect/stations, output path, and native city paths")
		quit(1)
		return
	var records := {}
	var count := 0
	for index: int in range(2, args.size()):
		var path: String = args[index]
		var loaded := SaveFormat.load(path)
		if not loaded.ok:
			push_error("Cannot load %s: %s" % [path, loaded.get("detail", loaded.get("error", ""))])
			quit(1)
			return
		var city: City = loaded.city
		var topology := StreetTopology.new()
		topology.rebuild(city)
		if args[0] == "inspect":
			var segments := []
			for segment: Dictionary in topology.segments({}):
				segments.append({"links":segment.links})
			var lots := []
			for anchor: Vector2i in city.facilities:
				var code := city.building.atv(anchor)
				if Buildings.is_arcology(code):
					var size := Buildings.size(code)
					lots.append({"anchor":[anchor.x,anchor.y],"code":code,"key":Buildings.key(code),"size":[size.x,size.y]})
			records[path] = {"segments":segments,"lots":lots}
		else:
			for segment: Dictionary in topology.segments({}):
				for link: String in segment.links:
					if not city.street_naming.links.has(link):
						push_error("Unnamed connection in %s: %s" % [city.name, link])
						quit(1)
						return
			if not city.signs.is_empty():
				push_error("Classic signs remain in " + city.name)
				quit(1)
				return
			var service := StreetNamingService.new()
			service.set_station_allocator(StationNameResolver.reconcile)
			var bound := service.bind_city(city, topology)
			if not bound.ok:
				push_error("Station naming failed: " + bound.error)
				quit(1)
				return
			if args[0] == "stations":
				# Emit metadata only. The Python curator merges this into the raw
				# document, preserving exact integers and all simulation history.
				var target := String(args[1]).path_join(path.get_file() + ".naming.json")
				var file := FileAccess.open(target, FileAccess.WRITE)
				if file == null:
					push_error("Cannot write station metadata " + target)
					quit(1)
					return
				file.store_string(JSON.stringify(SaveFormat._encode_street_naming(city.street_naming)) + "\n")
				file.close()
		count += 1
	if args[0] == "inspect":
		var file := FileAccess.open(args[1], FileAccess.WRITE)
		if file == null:
			push_error("Cannot write topology inventory")
			quit(1)
			return
		file.store_string(JSON.stringify(records))
		file.close()
	print("Results: %d passed, 0 failed" % count)
	quit()
