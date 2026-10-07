# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Validation and name normalization for a city's street-naming metadata.
## Anything that does not match the schema exactly is rejected. SaveFormat
## converts the metadata to and from the save file's JSON.
class_name StreetNamingCodec
extends RefCounted

const FIELDS := ["schema","next_street_id","streets","links","station_auto"]
const AUTO_FIELDS := ["source_street_ids","base_name","suffix","display_name"]

static func empty_metadata() -> Dictionary:
	return {"schema":1,"next_street_id":1,"streets":{},"links":{},"station_auto":{}}

static func _failure(message: String) -> Dictionary:
	return {"ok":false,"error":message,"metadata":{}}

static func _space(code: int) -> bool:
	return code in [32,160,5760,8239,8287,12288] or (code>=8192 and code<=8202)

static func _normalized(text: String, limit: int) -> Dictionary:
	var display := ""
	var pending_space := false
	for index: int in text.length():
		var code := text.unicode_at(index)
		if code<=31 or (code>=127 and code<=159) or code in [8232,8233]:
			return {"ok":false,"error":"Names cannot contain control characters or line breaks.","display":"","comparison":""}
		if _space(code):
			pending_space = not display.is_empty()
		else:
			if pending_space: display += " "
			display += String.chr(code)
			pending_space = false
	if display.is_empty():
		return {"ok":false,"error":"Enter a street name.","display":"","comparison":""}
	if display.length()>limit:
		return {"ok":false,"error":"Names may contain at most %d Unicode characters." % limit,"display":"","comparison":""}
	return {"ok":true,"error":"","display":display,"comparison":display.to_lower()}

static func normalize_name(text: String) -> Dictionary:
	return _normalized(text,48)

static func _exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size()!=fields.size(): return false
	for field: String in fields:
		if not value.has(field): return false
	return true

static func _positive_integer(value: Variant) -> bool:
	return typeof(value)==TYPE_INT and value>0

static func valid_anchor(value: Variant) -> bool:
	return typeof(value)==TYPE_VECTOR2I and value.x>=0 and value.y>=0 and value.x<City.WIDTH and value.y<City.HEIGHT

static func _endpoint(text: String) -> Dictionary:
	var parts := text.split(",",true)
	if parts.size()!=3 or parts[2] not in ["open","bore"]: return {}
	if not parts[0].is_valid_int() or not parts[1].is_valid_int(): return {}
	var cell := Vector2i(int(parts[0]),int(parts[1]))
	if not valid_anchor(cell) or str(cell.x)!=parts[0] or str(cell.y)!=parts[1]: return {}
	return {"cell":cell,"channel":parts[2]}

static func valid_link_key(text: String) -> bool:
	var parts := text.split(">",true)
	if parts.size()!=2: return false
	var a := _endpoint(parts[0])
	var b := _endpoint(parts[1])
	if a.is_empty() or b.is_empty(): return false
	var delta: Vector2i = b.cell-a.cell
	if absi(delta.x)+absi(delta.y)!=1: return false
	# Numeric row/column order, not lexical ordering (e.g. 9 versus 10).
	return a.cell.y<b.cell.y or (a.cell.y==b.cell.y and a.cell.x<b.cell.x)

static func validate(block: Variant) -> Dictionary:
	if typeof(block)!=TYPE_DICTIONARY or not _exact_fields(block,FIELDS):
		return _failure("Street naming metadata must contain exactly the schema fields.")
	if typeof(block.schema)!=TYPE_INT or block.schema!=1: return _failure("Unsupported street naming schema.")
	if not _positive_integer(block.next_street_id): return _failure("Invalid next street ID.")
	for field: String in ["streets","links","station_auto"]:
		if typeof(block[field])!=TYPE_DICTIONARY: return _failure("Invalid street naming %s registry." % field)
	var comparisons: Dictionary = {}
	for id: Variant in block.streets:
		if not _positive_integer(id) or id>=block.next_street_id: return _failure("Street IDs must be positive integers below the next ID.")
		if typeof(block.streets[id])!=TYPE_STRING: return _failure("Street display names must be strings.")
		var name := normalize_name(block.streets[id])
		if not name.ok or name.display!=block.streets[id]: return _failure("Street display names must be valid normalized names.")
		if comparisons.has(name.comparison): return _failure("Duplicate normalized street name.")
		comparisons[name.comparison] = id
	for key: Variant in block.links:
		if typeof(key)!=TYPE_STRING or not valid_link_key(key): return _failure("Invalid canonical street connection key.")
		if not _positive_integer(block.links[key]) or not block.streets.has(block.links[key]): return _failure("Street connection references an unknown ID.")
	for anchor: Variant in block.station_auto:
		if not valid_anchor(anchor): return _failure("Invalid station anchor.")
		var record: Variant = block.station_auto[anchor]
		if typeof(record)!=TYPE_DICTIONARY or not _exact_fields(record,AUTO_FIELDS): return _failure("Invalid automatic station record.")
		if typeof(record.source_street_ids)!=TYPE_ARRAY or record.source_street_ids.is_empty() or record.source_street_ids.size()>2:
			return _failure("Automatic stations require one or two source street IDs.")
		var seen: Dictionary = {}
		for id: Variant in record.source_street_ids:
			if not _positive_integer(id) or not block.streets.has(id) or seen.has(id): return _failure("Invalid automatic station street reference.")
			seen[id] = true
		if typeof(record.base_name)!=TYPE_STRING: return _failure("Invalid automatic station base name.")
		var base := _normalized(record.base_name,99) # Two complete 48-character names and " & ".
		if not base.ok or base.display!=record.base_name: return _failure("Invalid automatic station base name.")
		if typeof(record.suffix)!=TYPE_INT or record.suffix<0 or record.suffix==1: return _failure("Automatic station suffix must be zero or at least two.")
		var display: String = record.base_name if record.suffix==0 else record.base_name+" "+str(record.suffix)
		if typeof(record.display_name)!=TYPE_STRING or record.display_name!=display: return _failure("Automatic station display and suffix disagree.")
	return {"ok":true,"error":"","metadata":block.duplicate(true)}
