# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Records where an imported map came from (size-limited, plain JSON values) and
## stores a checksummed copy of the converted terrain so the import can be reset.
class_name RealWorldManifest
extends RefCounted
const ORIGIN_LIMIT := 262144
const VERTICES := 16641
const TILES := 16384
const BASELINE_SIZE := 4+8+1+VERTICES+4*TILES+32
const DIAGNOSTICS := ["source_min_metres","source_max_metres","metres_per_tile","metres_per_level","initial_clipped_targets","repaired_vertices","max_repair_metres","wet_tiles","widened_tiles","fresh_tiles","sea_tiles","lost_wet_tiles","stream_tiles","waterfall_tiles","sample_spacing_metres","water_year"]

static func sha256(body: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(body)
	return context.finish()

static func new_city(metadata: Dictionary) -> City:
	var city := City.new()
	city.name=String(metadata.get("name","New City")).left(256)
	city.difficulty=clampi(int(metadata.get("difficulty",0)),0,2)
	city.founded_year=int(metadata.get("founded_year",1900))
	city.funds=City.STARTING_FUNDS[city.difficulty]
	return city

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value)>=minimum and float(value)<=maximum and float(value)==floor(float(value))

static func _descriptor(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	if value.get("source")=="terrarium":
		if not _integer(value.get("z"),0,15) or not _integer(value.get("x"),0,32767) or not _integer(value.get("y"),0,32767): return {}
		return {"source":"terrarium","z":int(value.z),"x":int(value.x),"y":int(value.y)}
	if value.get("source")=="worldcover" and value.get("tile") is String and value.tile.length()==7:
		return {"source":"worldcover","tile":value.tile}
	return {}

## Attribution notices are chosen from the validated source descriptors, never
## from caller-supplied URLs or IDs.
static func _notice_ids(sources: Array[Dictionary]) -> Array[String]:
	var ids: Array[String]=[]
	for kind in ["terrarium","worldcover"]:
		for descriptor in sources:
			if descriptor.source==kind:
				ids.append("aws-terrain-joerd" if kind=="terrarium" else "esa-worldcover-2021-v200")
				break
	return ids

static func build_origin(packet: Dictionary, controls: Dictionary, diagnostics: Dictionary) -> Dictionary:
	var stored_controls := controls.duplicate(true)
	# JSON numbers cannot round-trip every signed64 seed. Persist its decimal spelling.
	stored_controls.tree_seed=str(controls.tree_seed)
	var origin := {"version":1,"source":"real_world","selection":packet.selection,"controls":stored_controls,"sources":packet.sources,"acquired_utc":packet.acquired_utc,"diagnostics":diagnostics}
	if packet.has("source_objects"):
		origin.source_objects=packet.source_objects
		# A real download records one object per source; refuse a mismatched list.
		if packet.source_objects.size()!=packet.sources.size(): return {}
	return sanitize_origin(origin)

static func sanitize_origin(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("source")!="real_world" or not _integer(value.get("version"),1,1): return {}
	if not value.get("selection") is Dictionary or not value.get("controls") is Dictionary: return {}
	var selection := {}
	for key in ["latitude","longitude","side_km","bearing"]:
		if not _number(value.selection.get(key)): return {}
		selection[key]=float(value.selection[key])
	if not TerrainGeography.validate_selection(selection).ok: return {}
	var input: Dictionary=value.controls
	var controls := {}
	if not _number(input.get("exaggeration")) or not _integer(input.get("smoothing_passes"),0,3) or not _integer(input.get("trees"),0,100) or not input.get("preserve_narrow") is bool or not input.get("water_mode") is String: return {}
	var seed: Variant=input.get("tree_seed")
	if not seed is String or seed.length()>20 or not seed.is_valid_int() or str(seed.to_int())!=seed: return {}
	controls={"exaggeration":float(input.exaggeration),"smoothing_passes":int(input.smoothing_passes),"trees":int(input.trees),"preserve_narrow":input.preserve_narrow,"water_mode":input.water_mode,"tree_seed":seed.to_int()}
	if not TerrainImportContract.validate_controls(controls).ok: return {}
	controls.tree_seed=seed
	if not value.get("sources") is Array or value.sources.is_empty() or value.sources.size()>576: return {}
	var sources: Array[Dictionary]=[]
	for raw in value.sources:
		var descriptor := _descriptor(raw)
		if descriptor.is_empty() or descriptor in sources: return {}
		sources.append(descriptor)
	if not TerrainImportContract.validate_sources(sources).ok: return {}
	if not value.get("acquired_utc") is String or value.acquired_utc.is_empty() or value.acquired_utc.length()>64: return {}
	if not value.get("diagnostics") is Dictionary: return {}
	var diagnostics := {}
	for key in DIAGNOSTICS:
		if not _number(value.diagnostics.get(key)): return {}
		if key.ends_with("tiles") or key in ["initial_clipped_targets","repaired_vertices","water_year"]:
			var maximum:=VERTICES+TILES if key=="initial_clipped_targets" else (VERTICES if key=="repaired_vertices" else TILES)
			if not _integer(value.diagnostics[key],0,maximum): return {}
			diagnostics[key]=int(value.diagnostics[key])
		else:
			diagnostics[key]=float(value.diagnostics[key])
	if diagnostics.water_year!=2021 or diagnostics.source_min_metres>diagnostics.source_max_metres or diagnostics.metres_per_tile<=0.0 or diagnostics.metres_per_level<=0.0 or diagnostics.max_repair_metres<0.0 or diagnostics.sample_spacing_metres<=0.0: return {}
	var out := {"version":1,"source":"real_world","selection":selection,"controls":controls,"sources":sources,"acquired_utc":value.acquired_utc,"diagnostics":diagnostics}
	out.notice_ids=_notice_ids(sources)
	if value.has("source_objects"):
		if not value.source_objects is Array or value.source_objects.is_empty() or value.source_objects.size()>576: return {}
		var objects: Array[Dictionary]=[]
		var range_count := 0
		for raw in value.source_objects:
			if not raw is Dictionary or not raw.get("etag") is String or raw.etag.length()>256 or not _integer(raw.get("size"),1,1099511627776) or not raw.get("ranges") is Array or raw.ranges.size()>1024: return {}
			var descriptor := _descriptor(raw.get("descriptor"))
			var ranges: Array[Dictionary]=[]
			for span in raw.ranges:
				range_count+=1
				if range_count>2048 or not span is Dictionary or not _integer(span.get("offset"),0,1099511627776) or not _integer(span.get("length"),1,67108864) or not span.get("sha256") is String or span.sha256.length()!=64: return {}
				ranges.append({"offset":int(span.offset),"length":int(span.length),"sha256":span.sha256})
			objects.append({"descriptor":descriptor,"etag":raw.etag,"size":int(raw.size),"ranges":ranges})
		if objects.size()!=sources.size() or not TerrainImportContract.validate_source_objects(objects,sources).ok: return {}
		out.source_objects=objects
	if JSON.stringify(out).to_utf8_buffer().size()>ORIGIN_LIMIT: return {}
	return out

## A single straight one-level waterfall tile: the high edge is at local water,
## upstream water is one level higher and downstream water meets local water.
## Both perpendicular banks must be dry. Used before assignment and on restore.
static func legal_waterfall(surface: TerrainSurface, x: int, y: int) -> bool:
	if x<0 or y<0 or x>=128 or y>=128: return false
	var base:=surface.tile_base(x,y)
	var water:=surface.water_level(x,y)
	if water!=base+1 or surface.tile_top(x,y)!=water: return false
	var corners:=surface.corners(x,y)
	var mask:=0
	for k in 4:
		if corners[k]>base: mask|=1<<k
	if mask not in [3,6,9,12]: return false
	var direction:=Vector2i.LEFT if mask==12 else (Vector2i.RIGHT if mask==3 else (Vector2i.UP if mask==9 else Vector2i.DOWN))
	var center:=Vector2i(x,y)
	var high:=center+direction
	var low:=center-direction
	if not surface.has_water(high.x,high.y) or not surface.has_water(low.x,low.y): return false
	if surface.water_level(high.x,high.y)!=water+1 or surface.water_level(low.x,low.y)!=water: return false
	var perpendicular:=Vector2i(direction.y,direction.x)
	var bank_a:=center+perpendicular
	var bank_b:=center-perpendicular
	return not surface.has_water(bank_a.x,bank_a.y) and not surface.has_water(bank_b.x,bank_b.y)

static func valid_surface(surface: TerrainSurface) -> bool:
	if surface.vertices.size()!=VERTICES or surface.water.size()!=TILES or surface.salt.size()!=TILES or surface.feature.size()!=TILES: return false
	for height in surface.vertices:
		if height>31: return false
	if surface.cliff_count()!=0: return false
	for y in 128:
		for x in 128:
			var i:=y*128+x
			var base:=surface.tile_base(x,y)
			var corners:=surface.corners(x,y)
			var mask:=0
			for k in 4:
				if corners[k]>base: mask|=1<<k
			if Terrain.shape_from_corners(mask)<0 or surface.salt[i]>1 or surface.feature[i]>TerrainSurface.Feature.WATERFALL: return false
			var water:=surface.water[i]
			if water==-1:
				if surface.salt[i]!=0 or surface.feature[i]!=TerrainSurface.Feature.NONE: return false
			elif water<1 or water>31 or water<=base: return false
			if surface.feature[i]==TerrainSurface.Feature.STREAM and not surface.is_tile_flat(x,y): return false
			if surface.feature[i]==TerrainSurface.Feature.WATERFALL and not legal_waterfall(surface,x,y): return false
	return true

static func encode_baseline(city: City, tree_seed: int) -> PackedByteArray:
	if city==null or not city.terrain_surface is TerrainSurface or not valid_surface(city.terrain_surface) or city.sea_level<-1 or city.sea_level>31: return PackedByteArray()
	var surface: TerrainSurface=city.terrain_surface
	var has_sea:=false
	for i in TILES:
		if surface.salt[i]:
			has_sea=true
			if city.sea_level!=surface.water[i]: return PackedByteArray()
		if city.building.data[i]!=Buildings.NONE and surface.has_water(i%128,i/128): return PackedByteArray()
	if has_sea!=(city.sea_level!=-1): return PackedByteArray()
	var out := "RWT1".to_ascii_buffer()
	out.resize(13)
	out.encode_s64(4,tree_seed)
	out[12]=255 if city.sea_level==-1 else city.sea_level
	out.append_array(surface.vertices)
	for i in TILES: out.append(255 if surface.water[i]==-1 else surface.water[i])
	out.append_array(surface.salt)
	out.append_array(surface.feature)
	for id in city.building.data:
		if id!=Buildings.NONE and not Buildings.is_tree(id): return PackedByteArray()
	out.append_array(city.building.data)
	out.append_array(sha256(out))
	return out

static func restore_baseline(body: PackedByteArray, metadata: Dictionary, origin: Dictionary) -> Dictionary:
	var invalid := {"ok":false,"error":"invalid_real_world_baseline"}
	if body.size()!=BASELINE_SIZE or body.slice(0,4).get_string_from_ascii()!="RWT1": return invalid
	if sha256(body.slice(0,-32))!=body.slice(-32): return invalid
	var sea:=int(body[12])
	if sea!=255 and sea>31: return invalid
	var surface := TerrainSurface.new()
	surface.vertices=body.slice(13,13+VERTICES)
	var offset:=13+VERTICES
	for i in TILES:
		var water:=int(body[offset+i])
		surface.water[i]=-1 if water==255 else water
	offset+=TILES
	surface.salt=body.slice(offset,offset+TILES)
	offset+=TILES
	surface.feature=body.slice(offset,offset+TILES)
	offset+=TILES
	var trees:=body.slice(offset,offset+TILES)
	for id in trees:
		if id!=Buildings.NONE and not Buildings.is_tree(id): return invalid
	if not valid_surface(surface): return invalid
	var probe:=surface.duplicate_surface()
	var normalization:=probe.normalize()
	if not normalization.converged or probe.vertices!=surface.vertices: return invalid
	var has_sea:=false
	for i in TILES:
		if surface.salt[i]: has_sea=true
		if surface.salt[i] and (sea==255 or surface.water[i]!=sea): return invalid
		if trees[i]!=Buildings.NONE and surface.has_water(i%128,i/128): return invalid
	if has_sea!=(sea!=255): return invalid
	var city:=new_city(metadata)
	city.sea_level=-1 if sea==255 else sea
	surface.project(city)
	city.building.data=trees
	return {"ok":true,"error":"","city":city,"origin":sanitize_origin(origin),"tree_seed":body.decode_s64(4)}

static func editing_settings(candidate: Dictionary) -> Dictionary:
	if not candidate.get("baseline") is PackedByteArray: return {}
	var baseline: PackedByteArray=candidate.baseline
	if baseline.size()!=BASELINE_SIZE or sha256(baseline.slice(0,-32))!=baseline.slice(-32): return {}
	return {"source":"real_world","seed":baseline.decode_s64(4),"baseline_version":1,"baseline_base64":Marshalls.raw_to_base64(baseline),"baseline_sha256":sha256(baseline).hex_encode(),"terrain_origin":sanitize_origin(candidate.get("origin"))}
