# SPDX-License-Identifier: GPL-3.0-or-later
## Transient, owner-scoped guidance. Resolve live actor poses at render time;
## scripts never receive engine objects or need to poll to move a marker.
class_name ExploreModMarkers
extends RefCounted

const MAX_PER_OWNER := 16
const MAX_TOTAL := 128
const ICONS := ["objective","person","vehicle","checkpoint"]
var actors: ExploreActorRegistry
var _owned: Dictionary = {}

func set_marker(owner: String, key: String, options: Dictionary) -> Dictionary:
	if key.is_empty() or key.to_utf8_buffer().size() > 128 or not valid_options(options): return {"code":"invalid_argument"}
	var target: Dictionary = options.target
	if target.has("id"):
		if actors == null or not actors._actors.has(target.id): return {"code":"stale_id"}
		if actors._actors[target.id].owner != owner: return {"code":"wrong_owner"}
	prune()
	var entries: Dictionary = _owned.get(owner,{})
	if not entries.has(key) and (entries.size() >= MAX_PER_OWNER or count() >= MAX_TOTAL): return {"code":"quota_exceeded"}
	entries[key] = {"owner":owner,"key":key,"target":target.duplicate(true),
		"label":String(options.get("label","")),"icon":String(options.get("icon","objective")),
		"map":bool(options.get("map",true)),"world":bool(options.get("world",true)),
		"max_distance":float(options.get("max_distance",2048.0)),"height":float(options.get("height",0.0))}
	_owned[owner] = entries
	return {"code":"ok"}

static func valid_options(options: Dictionary) -> bool:
	if not options.get("target") is Dictionary: return false
	var target: Dictionary = options.target
	if target.has("id"):
		if not target.id is String or target.id.is_empty(): return false
	else:
		var at := ExploreWorldQueries.point(target)
		if not at.is_finite() or at.x < 0 or at.x > City.WIDTH or at.z < 0 or at.z > City.HEIGHT or absf(at.y) > 1024: return false
	if options.has("label") and (not options.label is String or options.label.to_utf8_buffer().size() > 192): return false
	if options.has("icon") and (not options.icon is String or options.icon not in ICONS): return false
	for field in ["map","world"]:
		if options.has(field) and not options[field] is bool: return false
	for field in ["height","max_distance"]:
		if options.has(field) and not ExploreModApi._number(options[field]): return false
	if float(options.get("height",0)) < 0 or float(options.get("height",0)) > 8: return false
	if float(options.get("max_distance",2048)) < 0 or float(options.get("max_distance",2048)) > 2048: return false
	return true

func remove(owner: String, key: String) -> Dictionary:
	if _owned.has(owner): _owned[owner].erase(key)
	return {"code":"ok"}

func clear_owner(owner: String) -> void:
	_owned.erase(owner)

func clear() -> void:
	_owned.clear()

func count() -> int:
	prune()
	var total := 0
	for entries: Dictionary in _owned.values(): total += entries.size()
	return total

## Range applies to both displays, so opening a map cannot reveal a hidden
## search target. Missing actor handles expire rather than leaving ghost pins.
func visible_markers(player: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not player.is_finite(): return result
	var owners := _owned.keys()
	owners.sort()
	for owner: String in owners:
		var entries: Dictionary = _owned[owner]
		var keys := entries.keys()
		keys.sort()
		for key: String in keys:
			var entry: Dictionary = entries[key]
			var at := ExploreWorldQueries.point(entry.target)
			var lift := .16
			if entry.target.has("id"):
				var id: String = entry.target.id
				if actors == null or not actors._actors.has(id) or actors._actors[id].owner != owner:
					entries.erase(key)
					continue
				var record: Dictionary = actors._actors[id].record
				if not is_instance_valid(actors.traffic) or not actors.traffic.actors.has(record):
					entries.erase(key)
					continue
				if actors.traffic._claims.has(record.id): continue
				at = actors.traffic.actor_pose(record).origin
				lift = maxf(.16,CityTrafficCatalog.dimensions(record.kind).y+.05)
			var distance := at.distance_to(player)
			if not at.is_finite() or distance > entry.max_distance: continue
			var copy := entry.duplicate(true)
			copy.erase("target")
			copy["position"] = at
			copy["anchor"] = at+Vector3.UP*(lift+float(entry.height))
			copy["distance"] = distance
			result.append(copy)
	return result

## Accounting and quotas also expire actor pins while the renderer is hidden.
func prune() -> void:
	for owner: String in _owned:
		var entries: Dictionary = _owned[owner]
		for key: String in entries.keys():
			var target: Dictionary = entries[key].target
			if not target.has("id"): continue
			if actors == null or not actors._actors.has(target.id) or actors._actors[target.id].owner != owner:
				entries.erase(key)
