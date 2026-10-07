# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name TerrainImportContract
extends RefCounted

static func defaults() -> Dictionary:
	return {"selection": {"latitude":36.1699,"longitude":-115.1398,"side_km":8.0,"bearing":0.0}, "controls":{"exaggeration":1.0,"smoothing_passes":0,"preserve_narrow":true,"water_mode":"auto","trees":0,"tree_seed":0}}

static func validate_controls(controls: Dictionary) -> Dictionary:
	for key in ["exaggeration","smoothing_passes","preserve_narrow","water_mode","trees","tree_seed"]:
		if not controls.has(key): return {"ok":false,"error":"Missing control " + key}
	if not (controls.exaggeration is float or controls.exaggeration is int) or not is_finite(float(controls.exaggeration)) or controls.exaggeration < 0.001 or controls.exaggeration > 20.0:
		return {"ok":false,"error":"Exaggeration must be finite within 0.001..20"}
	if not controls.smoothing_passes is int or controls.smoothing_passes not in [0,1,3] or not controls.preserve_narrow is bool or not controls.water_mode is String or controls.water_mode not in ["auto","fresh","sea"] or not controls.trees is int or controls.trees<0 or controls.trees>100 or not controls.tree_seed is int:
		return {"ok":false,"error":"Invalid terrain controls"}
	return {"ok":true,"error":""}

static func validate_packet(packet: Dictionary) -> Dictionary:
	if not packet.get("selection") is Dictionary: return {"ok":false,"error":"Missing selection"}
	var selection_result := TerrainGeography.validate_selection(packet.selection)
	if not selection_result.ok: return selection_result
	for key in ["vertex_metres","center_metres"]:
		if not packet.get(key) is PackedFloat64Array or packet[key].size() != (16641 if key=="vertex_metres" else 16384):
			return {"ok":false,"error":"Missing or incomplete " + key}
		for value in packet[key]:
			if not is_finite(value): return {"ok":false,"error":"Nonfinite " + key}
	if not packet.get("water_counts") is PackedByteArray or packet.water_counts.size()!=16384: return {"ok":false,"error":"Missing water samples"}
	for count in packet.water_counts:
		if count>64: return {"ok":false,"error":"Invalid water count"}
	if not packet.get("sources") is Array or packet.sources.is_empty() or not packet.get("acquired_utc") is String or packet.acquired_utc.is_empty(): return {"ok":false,"error":"Missing source provenance"}
	if packet.acquired_utc.length()>64: return {"ok":false,"error":"Acquisition time too long"}
	var descriptors := validate_sources(packet.sources)
	if not descriptors.ok: return descriptors
	if packet.has("source_objects"):
		return validate_source_objects(packet.source_objects,packet.sources)
	return {"ok":true,"error":""}

static func validate_sources(sources: Array) -> Dictionary:
	if sources.is_empty() or sources.size()>576: return {"ok":false,"error":"Invalid source count"}
	for source in sources:
		if not source is Dictionary: return {"ok":false,"error":"Invalid source descriptor"}
		if source.get("source")=="terrarium":
			if source.size()!=4 or not source.get("z") is int or not source.get("x") is int or not source.get("y") is int or source.z<0 or source.z>15 or source.x<0 or source.y<0 or source.x>=(1<<source.z) or source.y>=(1<<source.z): return {"ok":false,"error":"Invalid elevation descriptor"}
		elif source.get("source")=="worldcover":
			var regex := RegEx.new()
			regex.compile("^[NS][0-9]{2}[EW][0-9]{3}$")
			if source.size()!=2 or not source.get("tile") is String or regex.search(source.tile)==null: return {"ok":false,"error":"Invalid water descriptor"}
			var south := int(source.tile.substr(1,2))*(-1 if source.tile[0]=="S" else 1)
			var west := int(source.tile.substr(4,3))*(-1 if source.tile[3]=="W" else 1)
			if (south==0 and source.tile[0]=="S") or (west==0 and source.tile[3]=="W") or south < -60 or south > 81 or west < -180 or west > 177 or posmod(south,3)!=0 or posmod(west,3)!=0: return {"ok":false,"error":"Water tile outside source grid"}
		else: return {"ok":false,"error":"Unknown source descriptor"}
	return {"ok":true,"error":""}

## Received object identities only. No URLs, headers other than ETag, or bodies.
static func validate_source_objects(objects: Variant, sources: Array) -> Dictionary:
	if not objects is Array or objects.is_empty() or objects.size()>576: return {"ok":false,"error":"Invalid source object count"}
	var digest := RegEx.new()
	digest.compile("^[0-9a-f]{64}$")
	var seen: Array = []
	var count := 0
	for object in objects:
		if not object is Dictionary or object.size()!=4 or not object.get("descriptor") is Dictionary or object.descriptor not in sources or object.descriptor in seen: return {"ok":false,"error":"Invalid source object descriptor"}
		seen.append(object.descriptor)
		if not object.get("etag") is String or object.etag.is_empty() or object.etag.length()>256 or object.etag.contains("\n") or object.etag.contains("\r"): return {"ok":false,"error":"Invalid source ETag"}
		if not object.get("size") is int or object.size<1 or object.size>1099511627776: return {"ok":false,"error":"Invalid source size"}
		if not object.get("ranges") is Array or object.ranges.is_empty() or object.ranges.size()>1024: return {"ok":false,"error":"Invalid source ranges"}
		for span in object.ranges:
			count+=1
			if count>2048 or not span is Dictionary or span.size()!=3 or not span.get("offset") is int or not span.get("length") is int or span.offset<0 or span.length<1 or span.length>67108864 or span.offset>object.size-span.length or not span.get("sha256") is String or digest.search(span.sha256)==null: return {"ok":false,"error":"Invalid source range"}
	return {"ok":true,"error":""}
