# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name WorldCoverCog
extends RefCounted

const INITIAL_BYTES := 16384
const MAX_RANGE := 65536
const MAX_INDEX_BYTES := 262144
const MAX_RANGES := 64
const MAX_TAGS := 128
const SOURCE_SIZE := 36000
const BLOCK_SIZE := 1024
const BLOCKS_ACROSS := 36
const BLOCK_COUNT := 1296
const MAX_BLOCK_BYTES := 2*1024*1024
const PIXEL_SCALE := 1.0/12000.0
const CLASS_VALUES := [10,20,30,40,50,60,70,80,90,95,100]
const TYPE_BYTES := {1:1,2:1,3:2,4:4,5:8,6:1,7:1,8:2,9:4,10:8,11:4,12:8}
const READ_TAGS := [254,256,257,258,259,262,266,274,277,284,317,320,322,323,324,325,338,339,33550,33922,34264,34735,34736,34737]

static func _fail(error: String) -> Dictionary:
	return {"ok":false,"error":error}

static func _uint(bytes: PackedByteArray, at: int, size: int, little: bool) -> int:
	var value := 0
	for i in size: value=(value<<8)|int(bytes[at+(size-1-i if little else i)])
	return value

static func _double(bytes: PackedByteArray, at: int, little: bool) -> float:
	if little: return bytes.decode_double(at)
	var reversed := PackedByteArray()
	reversed.resize(8)
	for i in 8: reversed[i]=bytes[at+7-i]
	return reversed.decode_double(0)

static func _inside(offset: int, length: int, object_size: int) -> bool:
	return offset>=0 and length>0 and offset<=object_size and length<=object_size-offset

# A reader sees only the size-limited index byte ranges it was given. Sorting
# them into disjoint intervals rules out overlapping bytes and makes the list of
# missing ranges independent of dictionary order.
static func _reader(ranges: Dictionary, object_size: int) -> Dictionary:
	if object_size<8: return _fail("TIFF object is smaller than its header")
	if ranges.size()>MAX_RANGES: return _fail("Too many TIFF index ranges")
	var spans: Array[Dictionary] = []
	var total := 0
	for offset in ranges:
		if not offset is int or not ranges[offset] is PackedByteArray: return _fail("TIFF index ranges require integer offsets and byte arrays")
		var body: PackedByteArray = ranges[offset]
		if body.size()>MAX_RANGE or not _inside(offset,body.size(),object_size): return _fail("TIFF index range exceeds object or 64 KiB ceiling")
		total+=body.size()
		if total>MAX_INDEX_BYTES: return _fail("TIFF index bodies exceed 256 KiB")
		spans.append({"offset":offset,"length":body.size(),"body":body})
	spans.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.offset<b.offset)
	var end := 0
	for span in spans:
		if span.offset<end: return _fail("Overlapping TIFF index ranges are ambiguous")
		end=span.offset+span.length
	return {"ok":true,"error":"","spans":spans,"total":total,"object_size":object_size,"missing":[]}

static func _read(reader: Dictionary, offset: int, length: int) -> Dictionary:
	if length>MAX_RANGE or not _inside(offset,length,reader.object_size): return _fail("TIFF tag or IFD range exceeds object or bounded index read")
	var cursor := offset
	var limit := offset+length
	var missing := false
	for span in reader.spans:
		if span.offset+span.length<=cursor: continue
		if span.offset>=limit: break
		if span.offset>cursor:
			reader.missing.append({"offset":cursor,"length":mini(span.offset,limit)-cursor})
			missing=true
		cursor=mini(limit,span.offset+span.length)
		if cursor==limit: break
	if cursor<limit:
		reader.missing.append({"offset":cursor,"length":limit-cursor})
		missing=true
	if missing: return {"ok":false,"error":""}
	var bytes := PackedByteArray()
	bytes.resize(length)
	cursor=offset
	for span in reader.spans:
		if span.offset+span.length<=cursor: continue
		if span.offset>=limit: break
		var count := mini(limit,span.offset+span.length)-cursor
		for i in count: bytes[cursor-offset+i]=span.body[cursor-span.offset+i]
		cursor+=count
		if cursor==limit: break
	return {"ok":true,"error":"","bytes":bytes}

static func _needed(reader: Dictionary) -> Dictionary:
	var missing: Array = reader.missing
	missing.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.offset<b.offset)
	var merged: Array[Dictionary] = []
	for span in missing:
		if not merged.is_empty() and span.offset<=merged[-1].offset+merged[-1].length:
			merged[-1].length=maxi(merged[-1].offset+merged[-1].length,span.offset+span.length)-merged[-1].offset
		else: merged.append({"offset":span.offset,"length":span.length})
	var needed: Array[Dictionary] = []
	var total := int(reader.total)
	for span in merged:
		var cursor := int(span.offset)
		var remaining := int(span.length)
		total+=remaining
		if total>MAX_INDEX_BYTES: return _fail("Required TIFF index bodies exceed 256 KiB")
		while remaining>0:
			var count := mini(remaining,MAX_RANGE)
			needed.append({"offset":cursor,"length":count})
			cursor+=count
			remaining-=count
	if reader.spans.size()+needed.size()>MAX_RANGES: return _fail("Required TIFF index ranges exceed count ceiling")
	return {"ok":false,"error":"","needed_ranges":needed}

static func _numeric(tag: Dictionary, little: bool) -> PackedInt64Array:
	var values := PackedInt64Array()
	values.resize(tag.count)
	var stride: int = TYPE_BYTES[tag.type]
	for i in tag.count: values[i]=_uint(tag.bytes,i*stride,stride,little)
	return values

static func _scalar(tags: Dictionary, tag_id: int, little: bool, default_value: int = -1) -> int:
	if not tags.has(tag_id): return default_value
	var tag: Dictionary = tags[tag_id]
	if not tag.type in [3,4] or tag.count!=1: return -1
	return _uint(tag.bytes,0,TYPE_BYTES[tag.type],little)

# index: width/height; block_width/block_height (padded source dimensions);
# blocks_across/blocks_down; offsets/counts PackedInt64Array in row-major order;
# object_size; transform {longitude_origin, latitude_origin, pixel_width,
# pixel_height, epsg, raster_type}. Origins are the upper-left pixel CORNER,
# scalar float64 degrees, and pixel_height is negative. No HTTP occurs here.
static func parse_index(ranges: Dictionary, object_size: int) -> Dictionary:
	var reader := _reader(ranges,object_size)
	if not reader.ok: return reader
	if ranges.is_empty():
		return {"ok":false,"error":"","needed_ranges":[{"offset":0,"length":mini(INITIAL_BYTES,object_size)}]}
	var header := _read(reader,0,8)
	if not header.ok: return _needed(reader) if header.error=="" else header
	var bytes: PackedByteArray = header.bytes
	var little := bytes[0]==73 and bytes[1]==73
	if not little and not (bytes[0]==77 and bytes[1]==77): return _fail("Invalid TIFF byte order")
	if _uint(bytes,2,2,little)!=42: return _fail("Only classic TIFF magic 42 is supported; BigTIFF is unsupported")
	var ifd_offset := _uint(bytes,4,4,little)
	if ifd_offset<8: return _fail("Invalid TIFF first IFD offset")
	var count_body := _read(reader,ifd_offset,2)
	if not count_body.ok: return _needed(reader) if count_body.error=="" else count_body
	var tag_count := _uint(count_body.bytes,0,2,little)
	if tag_count<1 or tag_count>MAX_TAGS: return _fail("TIFF IFD tag count exceeds bounded limit")
	var ifd := _read(reader,ifd_offset+2,tag_count*12+4)
	if not ifd.ok: return _needed(reader) if ifd.error=="" else ifd
	bytes=ifd.bytes
	var next_ifd := _uint(bytes,tag_count*12,4,little)
	if next_ifd!=0 and (next_ifd<8 or next_ifd==ifd_offset or not _inside(next_ifd,2,object_size)): return _fail("Invalid TIFF next IFD offset")
	var tags := {}
	var previous := -1
	for i in tag_count:
		var at := i*12
		var tag_id := _uint(bytes,at,2,little)
		var type := _uint(bytes,at+2,2,little)
		var count := _uint(bytes,at+4,4,little)
		if tag_id<=previous: return _fail("TIFF tags must be ordered and unique")
		previous=tag_id
		if not TYPE_BYTES.has(type) or count<1 or count>MAX_RANGE/TYPE_BYTES[type]: return _fail("TIFF tag type or count exceeds bounded limit")
		var length: int = count*TYPE_BYTES[type]
		var pointer := _uint(bytes,at+8,4,little) if length>4 else ifd_offset+2+at+8
		if not _inside(pointer,length,object_size): return _fail("TIFF tag data exceeds object bounds")
		if tag_id in [273,278,279]: return _fail("WorldCover requires full-resolution tiled data, not strips")
		if tag_id in READ_TAGS:
			tags[tag_id]={"type":type,"count":count,"offset":pointer,"length":length}
	# Validate types/counts before requesting or allocating tag arrays.
	for tag_id in [256,257,258,259,262,322,323,324,325,320,33550,33922,34735]:
		if not tags.has(tag_id): return _fail("Missing required WorldCover TIFF tag: %d"%tag_id)
	for tag_id in [258,259,262,266,274,277,284,317,339]:
		if tags.has(tag_id) and (tags[tag_id].type!=3 or tags[tag_id].count!=1): return _fail("Unsupported WorldCover sample tag shape")
	for tag_id in [256,257,254,322,323]:
		if tags.has(tag_id) and (not tags[tag_id].type in [3,4] or tags[tag_id].count!=1): return _fail("Unsupported WorldCover dimension tag shape")
	for tag_id in [324,325]:
		if tags[tag_id].type!=4 or tags[tag_id].count!=BLOCK_COUNT: return _fail("WorldCover tile index must contain 1296 LONG entries")
	if tags[320].type!=3 or tags[320].count!=768: return _fail("WorldCover requires an 8-bit TIFF palette")
	if tags[33550].type!=12 or tags[33550].count!=3 or tags[33922].type!=12 or tags[33922].count!=6: return _fail("Unsupported WorldCover geographic transform shape")
	if tags[34735].type!=3 or tags[34735].count<4 or tags[34735].count>1024: return _fail("Invalid bounded WorldCover GeoKey directory")
	if tags.has(34264) or tags.has(338): return _fail("Unsupported WorldCover matrix transform or extra samples")
	for tag_id in tags:
		var data := _read(reader,tags[tag_id].offset,tags[tag_id].length)
		if not data.ok and data.error!="": return data
		if data.ok: tags[tag_id].bytes=data.bytes
	if not reader.missing.is_empty(): return _needed(reader)
	if _scalar(tags,256,little)!=SOURCE_SIZE or _scalar(tags,257,little)!=SOURCE_SIZE: return _fail("WorldCover requires full-resolution 36000 by 36000 geography")
	if _scalar(tags,322,little)!=BLOCK_SIZE or _scalar(tags,323,little)!=BLOCK_SIZE: return _fail("WorldCover source blocks must be 1024 by 1024")
	if _scalar(tags,258,little)!=8 or _scalar(tags,259,little)!=8 or _scalar(tags,262,little)!=3: return _fail("WorldCover requires 8-bit palette classes with zlib compression 8")
	for tag_id in [266,274,277,284,317,339]:
		if _scalar(tags,tag_id,little,1)!=1: return _fail("Unsupported WorldCover orientation, sample layout or predictor")
	if _scalar(tags,254,little,0)!=0: return _fail("WorldCover first IFD must be full resolution")
	var scale := PackedFloat64Array()
	var tie := PackedFloat64Array()
	for i in 3: scale.append(_double(tags[33550].bytes,i*8,little))
	for i in 6: tie.append(_double(tags[33922].bytes,i*8,little))
	for value in scale:
		if not is_finite(value): return _fail("Nonfinite WorldCover pixel scale")
	for value in tie:
		if not is_finite(value): return _fail("Nonfinite WorldCover tiepoint")
	if absf(scale[0]-PIXEL_SCALE)>1e-14 or absf(scale[1]-PIXEL_SCALE)>1e-14 or scale[2]!=0.0 or tie[2]!=0.0 or tie[5]!=0.0: return _fail("WorldCover requires 1/12000-degree geographic pixel scale")
	var longitude := tie[3]-tie[0]*scale[0]
	var latitude := tie[4]+tie[1]*scale[1]
	if longitude< -180.0 or longitude>177.0 or latitude< -87.0 or latitude>90.0 or absf(longitude/3.0-round(longitude/3.0))>1e-9 or absf(latitude/3.0-round(latitude/3.0))>1e-9: return _fail("WorldCover transform must cover an aligned three-degree geographic tile")
	var geo := _numeric(tags[34735],little)
	if geo[0]!=1 or geo[1]!=1 or not geo[2] in [0,1] or geo.size()!=4+geo[3]*4: return _fail("Invalid WorldCover GeoKey header or count")
	var keys := {}
	previous=-1
	for i in geo[3]:
		var at := 4+i*4
		var key := geo[at]
		var location := geo[at+1]
		var count := geo[at+2]
		var value := geo[at+3]
		if key<=previous or count<1: return _fail("Invalid WorldCover GeoKey order or count")
		previous=key
		if location==0:
			if count!=1: return _fail("Inline WorldCover GeoKey must have one value")
			keys[key]=value
		else:
			if key==2054: return _fail("WorldCover angular units must be an inline degree key")
			if not location in [34735,34736,34737] or not tags.has(location) or value>tags[location].count or count>tags[location].count-value: return _fail("WorldCover GeoKey reference exceeds bounded tag")
			if location==34736 and tags[location].type!=12 or location==34737 and tags[location].type!=2: return _fail("Invalid WorldCover GeoKey parameter type")
	if keys.get(1024)!=2 or keys.get(1025)!=1 or keys.get(2048)!=4326: return _fail("WorldCover requires geographic EPSG:4326 pixel-area GeoKeys")
	if keys.get(2054,9102)!=9102: return _fail("WorldCover angular units must be degrees")
	var offsets := _numeric(tags[324],little)
	var counts := _numeric(tags[325],little)
	for i in BLOCK_COUNT:
		if counts[i]>MAX_BLOCK_BYTES or not _inside(offsets[i],counts[i],object_size): return _fail("WorldCover compressed block exceeds object or 2 MiB bounds")
	return {"ok":true,"error":"","index":{"width":SOURCE_SIZE,"height":SOURCE_SIZE,"block_width":BLOCK_SIZE,"block_height":BLOCK_SIZE,"blocks_across":BLOCKS_ACROSS,"blocks_down":BLOCKS_ACROSS,"offsets":offsets,"counts":counts,"object_size":object_size,"transform":{"longitude_origin":longitude,"latitude_origin":latitude,"pixel_width":scale[0],"pixel_height":-scale[1],"epsg":4326,"raster_type":1}}}

static func _valid_index(index: Dictionary) -> bool:
	return index.get("width")==SOURCE_SIZE and index.get("height")==SOURCE_SIZE and index.get("block_width")==BLOCK_SIZE and index.get("block_height")==BLOCK_SIZE and index.get("blocks_across")==BLOCKS_ACROSS and index.get("blocks_down")==BLOCKS_ACROSS and index.get("object_size") is int and index.get("offsets") is PackedInt64Array and index.get("counts") is PackedInt64Array and index.offsets.size()==BLOCK_COUNT and index.counts.size()==BLOCK_COUNT

static func block_range(index: Dictionary, block_id: int) -> Dictionary:
	if not _valid_index(index) or block_id<0 or block_id>=BLOCK_COUNT: return _fail("Invalid WorldCover index or block id")
	var offset: int = index.offsets[block_id]
	var length: int = index.counts[block_id]
	if length>MAX_BLOCK_BYTES or not _inside(offset,length,index.object_size): return _fail("Invalid bounded WorldCover block range")
	return {"ok":true,"error":"","offset":offset,"length":length}

static func decode_block(index: Dictionary, block_id: int, body: PackedByteArray) -> Dictionary:
	var span := block_range(index,block_id)
	if not span.ok: return span
	if body.size()!=span.length: return _fail("WorldCover compressed block byte count mismatch")
	# Source tiles pad their edge blocks; never substitute their clipped footprint.
	var inflated := TerrainZlib.inflate_exact(body,BLOCK_SIZE*BLOCK_SIZE)
	if not inflated.ok: return inflated
	return {"ok":true,"error":"","classes":inflated.bytes}

static func class_at(index: Dictionary, pixel: Vector2i, blocks: Dictionary) -> Dictionary:
	if not _valid_index(index) or pixel.x<0 or pixel.y<0 or pixel.x>=SOURCE_SIZE or pixel.y>=SOURCE_SIZE: return _fail("WorldCover source pixel is outside full-resolution geography")
	var block_id := (pixel.y/BLOCK_SIZE)*BLOCKS_ACROSS+pixel.x/BLOCK_SIZE
	if not blocks.has(block_id) or not blocks[block_id] is Dictionary: return _fail("Missing WorldCover source block")
	var block: Dictionary = blocks[block_id]
	if block.get("ok")!=true or not block.get("classes") is PackedByteArray or block.classes.size()!=BLOCK_SIZE*BLOCK_SIZE: return _fail("Invalid decoded WorldCover source block")
	var value := int(block.classes[(pixel.y%BLOCK_SIZE)*BLOCK_SIZE+pixel.x%BLOCK_SIZE])
	if not value in CLASS_VALUES: return _fail("WorldCover class is unknown or nodata")
	return {"ok":true,"error":"","value":value}
