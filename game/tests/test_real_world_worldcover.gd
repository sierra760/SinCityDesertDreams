# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const Fixtures = preload("res://tests/real_world/terrain_source_fixtures.gd")

func parsed(fixture: Dictionary) -> Dictionary:
 return WorldCoverCog.parse_index({0:fixture.body},fixture.object_size)

func test_endian_class_bytes_and_georeference() -> void:
 for little in [true,false]:
  var fixture := Fixtures.worldcover_tiff(little)
  var result := parsed(fixture)
  check(result.ok,"full-resolution endian class index")
  if not result.ok: continue
  var index: Dictionary = result.index
  check_eq(index.width,36000)
  check_eq(index.height,36000)
  check_eq(index.offsets.size(),1296)
  check_eq(index.transform.longitude_origin,-117.0)
  check_eq(index.transform.latitude_origin,39.0)
  check_eq(index.transform.pixel_width,1.0/12000.0)
  check_eq(index.transform.pixel_height,-1.0/12000.0)
  check_eq(index.transform.epsg,4326)
  var block := WorldCoverCog.decode_block(index,0,fixture.block)
  check(block.ok,"exact raw bytes decode")
  if not block.ok: continue
  check_eq(block.classes.size(),1024*1024)
  var water_sample := WorldCoverCog.class_at(index,Vector2i(0,0),{0:block})
  var dry_sample := WorldCoverCog.class_at(index,Vector2i(2,0),{0:block})
  check(water_sample.ok)
  check(dry_sample.ok)
  if water_sample.ok: check_eq(water_sample.value,80,"palette color must never replace the raw class")
  if dry_sample.ok: check_eq(dry_sample.value,60)
  var edge := WorldCoverCog.decode_block(index,1295,fixture.block)
  check(edge.ok,"last partial edge still decodes complete padded 1024-square source block")
  var edge_sample := WorldCoverCog.class_at(index,Vector2i(35999,35999),{1295:edge})
  check(edge_sample.ok,"full-resolution bottom/right geography stays source pixels")
  if edge_sample.ok: check_eq(edge_sample.value,60)
 check(parsed(Fixtures.worldcover_tiff(true,{"explicit_defaults":true})).ok,"explicit TIFF defaults and absent defaults both supported")

func test_partial_index_requests_and_offset_bounds() -> void:
 var fixture := Fixtures.worldcover_tiff()
 var initial := WorldCoverCog.parse_index({},fixture.object_size)
 check(initial.has("needed_ranges"),"initial 16 KiB range requested")
 if initial.has("needed_ranges"): check_eq(initial.needed_ranges,[{"offset":0,"length":16384}])
 var ranges := {0:fixture.body.slice(0,16384)}
 var partial := WorldCoverCog.parse_index(ranges,fixture.object_size)
 check(not partial.ok)
 check_eq(partial.error,"")
 check(partial.has("needed_ranges"),"bounded metadata ranges requested")
 if not partial.has("needed_ranges"): return
 check_eq(partial.needed_ranges,[{"offset":20000,"length":5184},{"offset":26000,"length":5184}],"deterministic uncovered arrays only")
 for needed in partial.needed_ranges:
  check(needed.length<=65536)
  ranges[needed.offset]=fixture.body.slice(needed.offset,needed.offset+needed.length)
 var complete := WorldCoverCog.parse_index(ranges,fixture.object_size)
 check(complete.ok,"partial index completes without requesting covered bytes")
 if complete.ok:
  check(not complete.has("needed_ranges"))
  var span := WorldCoverCog.block_range(complete.index,1295)
  check(span.ok)
  if span.ok:
   check_eq(span.offset,100000)
   check_eq(span.length,fixture.block.size())
  check(not WorldCoverCog.block_range(complete.index,1296).ok)
 var high := Fixtures.worldcover_tiff(false,{"block_offset":4294967040})
 var high_result := parsed(high)
 check(high_result.ok,"unsigned offset near 2^32 survives integer arithmetic")
 if high_result.ok: check_eq(WorldCoverCog.block_range(high_result.index,0).offset,4294967040)
 var past_object_end := WorldCoverCog.parse_index({0:high.body},4294967295)
 check(not past_object_end.ok,"offset plus count exceeds object, even across 2^32")
 check(past_object_end.error!="")
 var split := {0:fixture.body.slice(0,20003),20003:fixture.body.slice(20003)}
 check(WorldCoverCog.parse_index(split,fixture.object_size).ok,"tag values span adjacent ranges")
 var huge := PackedByteArray()
 huge.resize(65537)
 check(not WorldCoverCog.parse_index({0:huge},fixture.object_size).ok,"single supplied range bounded")

func test_unsupported_format_and_truncation() -> void:
 for overrides in [{"magic":43},{"width":12000},{"scale":1.0/4000.0},{"compression":1},{"compression":5},{"epsg":3857},{"block_width":2048},{"block_count":2097153},{"tags":{277:[3,1,2]}},{"tags":{317:[3,1,2]}},{"tags":{339:[3,1,2]}},{"tags":{273:[4,1,100000]}},{"tags":{254:[4,1,1]}},{"tags":{258:[3,1,16]}}]:
  var result := parsed(Fixtures.worldcover_tiff(true,overrides))
  check(not result.ok,"unsupported TIFF source rejected: "+str(overrides))
  check(result.error!="","malformed index has terminal reason")
  check(not result.has("index"),"failure carries no usable partial index")
 var invalid_geokey := parsed(Fixtures.worldcover_tiff(true,{"epsg":0}))
 check(not invalid_geokey.ok)
 var fixture := Fixtures.worldcover_tiff()
 var malformed: PackedByteArray = fixture.body.duplicate()
 Fixtures._wc_uint(malformed,fixture.tags[324]+4,0xffffffff,4,true)
 check(not WorldCoverCog.parse_index({0:malformed},fixture.object_size).ok,"huge advertised tag count rejected before allocation")
 malformed=fixture.body.duplicate()
 Fixtures._wc_uint(malformed,8,65535,2,true)
 check(not WorldCoverCog.parse_index({0:malformed},fixture.object_size).ok,"IFD count bounded")
 check(not WorldCoverCog.parse_index({0:fixture.body.slice(0,7)},7).ok,"truncated header is terminal at object end")
 var truncated := WorldCoverCog.parse_index({0:fixture.body.slice(0,7)},fixture.object_size)
 check(truncated.has("needed_ranges"),"missing available bytes request instead of indexing outside body")
 malformed=fixture.body.duplicate()
 Fixtures._wc_uint(malformed,fixture.tags[324]+8,fixture.object_size-2,4,true)
 check(not WorldCoverCog.parse_index({0:malformed},fixture.object_size).ok,"tag pointer outside object rejected")

func test_deflate_output_bound() -> void:
 var fixture := Fixtures.worldcover_tiff()
 var result := parsed(fixture)
 check(result.ok,"valid index for compression bounds")
 if not result.ok: return
 for kind in ["oversized","short"]:
  var altered := Fixtures.worldcover_tiff(true,{"block_count":Fixtures.worldcover_block(kind).size()})
  var index_result := parsed(altered)
  check(index_result.ok)
  if index_result.ok:
   var oversized_deflate := WorldCoverCog.decode_block(index_result.index,0,Fixtures.worldcover_block(kind))
   check(not oversized_deflate.ok,"exact block output rejects "+kind)
   check(not oversized_deflate.has("classes"))
 var corrupted: PackedByteArray = fixture.block.duplicate()
 corrupted[-1]^=1
 check(not WorldCoverCog.decode_block(result.index,0,corrupted).ok,"bad zlib checksum is a clean data error")
 check(not WorldCoverCog.decode_block(result.index,0,fixture.block.slice(0,fixture.block.size()-1)).ok,"compressed byte count exact")

func test_unknown_is_not_dry() -> void:
 var fixture := Fixtures.worldcover_tiff()
 var result := parsed(fixture)
 check(result.ok,"index for unknown classification")
 if not result.ok: return
 var block := WorldCoverCog.decode_block(result.index,0,fixture.block)
 check(block.ok)
 if not block.ok: return
 var nodata_sample := WorldCoverCog.class_at(result.index,Vector2i(1,0),{0:block})
 check(not nodata_sample.ok,"class zero never becomes dry")
 check(not nodata_sample.has("value"))
 for pixel in [Vector2i(-1,0),Vector2i(36000,0),Vector2i(0,36000)]:
  check(not WorldCoverCog.class_at(result.index,pixel,{0:block}).ok)
 check(not WorldCoverCog.class_at(result.index,Vector2i(1024,0),{0:block}).ok,"missing source block cannot be dry")
 var malformed := {0:{"ok":true,"classes":PackedByteArray([80])}}
 check(not WorldCoverCog.class_at(result.index,Vector2i(0,0),malformed).ok,"malformed decoded plane rejected")
 block.classes[2]=79
 check(not WorldCoverCog.class_at(result.index,Vector2i(2,0),{0:block}).ok,"unknown nonzero class code cannot be dry")

func test_bounded_ranges_and_tag_data_are_terminal_errors() -> void:
 var fixture := Fixtures.worldcover_tiff()
 for ranges in [{"0":fixture.body},{-1:fixture.body},{0:PackedByteArray()},{0:fixture.body,10:PackedByteArray([0])}]:
  var result := WorldCoverCog.parse_index(ranges,fixture.object_size)
  check(not result.ok,"malformed/overlapping range container")
  check(result.error!="")
  check(not result.has("index"))
  check(not result.has("needed_ranges"))
 var huge := PackedByteArray()
 huge.resize(65536)
 var over_budget := {}
 for i in 5: over_budget[i*65536]=huge
 var excessive := WorldCoverCog.parse_index(over_budget,1000000)
 check(not excessive.ok,"total supplied index bytes bounded before parsing")
 check(String(excessive.error).contains("256 KiB"))
 var many := {}
 for i in 65: many[i]=PackedByteArray([0])
 check(not WorldCoverCog.parse_index(many,1000000).ok,"range count bounded")
 for tag in [320,324,325,33550,33922,34735]:
  var malformed: PackedByteArray = fixture.body.duplicate()
  Fixtures._wc_uint(malformed,fixture.tags[tag]+4,0xffffffff,4,true)
  var result := WorldCoverCog.parse_index({0:malformed},fixture.object_size)
  check(not result.ok,"tag count preallocation bound: "+str(tag))
  check(result.error!="")
 var incomplete := {0:fixture.body.slice(0,16384),20000:fixture.body.slice(20000,20010)}
 var partial := WorldCoverCog.parse_index(incomplete,fixture.object_size)
 check(partial.has("needed_ranges"))
 if partial.has("needed_ranges"):
  check_eq(partial.needed_ranges,[{"offset":20010,"length":5174},{"offset":26000,"length":5184}],"request only uncovered suffix, no repeated index bytes")
 var reordered := {26000:fixture.body.slice(26000,31184),0:fixture.body.slice(0,16384),20000:fixture.body.slice(20000,25184)}
 check(WorldCoverCog.parse_index(reordered,fixture.object_size).ok,"insertion order does not affect index")

func test_geographic_and_layout_corruption_do_not_select_an_overview() -> void:
 for overrides in [{"tie":[0.0,0.0,0.0,-116.0,39.0,0.0]},{"tie":[0.0,0.0,0.0,-183.0,39.0,0.0]},{"tie":[0.0,0.0,0.0,-117.0,93.0,0.0]},{"tie":[0.0,0.0,0.0,NAN,39.0,0.0]},{"scale":INF},{"tags":{274:[3,1,2]}},{"tags":{284:[3,1,2]}},{"tags":{266:[3,1,2]}},{"tags":{320:[4,768,1024]}},{"tags":{324:[4,1295,20000]}},{"tags":{33550:[12,2,3000]}},{"tags":{33922:[12,12,3040]}},{"tags":{338:[3,1,1]}},{"tags":{34264:[12,16,4000]}}]:
  var result := parsed(Fixtures.worldcover_tiff(false,overrides))
  check(not result.ok,"unsupported geography or layout: "+str(overrides))
  check(result.error!="")
 var fixture := Fixtures.worldcover_tiff()
 for at_value in [[3100,2],[3106,4],[3114,1],[3122,2],[3126,34737],[3128,100]]:
  var malformed: PackedByteArray = fixture.body.duplicate()
  Fixtures._wc_uint(malformed,at_value[0],at_value[1],2,true)
  var result := WorldCoverCog.parse_index({0:malformed},fixture.object_size)
  check(not result.ok,"malformed geographic key header/value/reference")
  check(result.error!="")
 var shifted := Fixtures.worldcover_tiff(true,{"tie":[12000.0,12000.0,0.0,-116.0,38.0,0.0]})
 var shifted_result := parsed(shifted)
 check(shifted_result.ok,"nonzero raster tiepoint normalized to geographic pixel-corner origin")
 if shifted_result.ok:
  check_eq(shifted_result.index.transform.longitude_origin,-117.0)
  check_eq(shifted_result.index.transform.latitude_origin,39.0)

func test_shared_inflater_bounds_and_malformed_api_values() -> void:
 var fixture := Fixtures.worldcover_tiff()
 var too_large := PackedByteArray()
 too_large.resize(2097153)
 for expected in [-1,0,2097153]:
  check(not TerrainZlib.inflate_exact(fixture.block,expected).ok,"requested inflate allocation ceiling")
 check(not TerrainZlib.inflate_exact(too_large,1048576).ok,"compressed input ceiling before output allocation")
 for bytes in [PackedByteArray(),PackedByteArray([120,156,0]),PackedByteArray([0,0,0,0,0,0])]:
  check(not TerrainZlib.inflate_exact(bytes,1).ok,"truncated or invalid zlib framing")
 var result := parsed(fixture)
 check(result.ok)
 if not result.ok: return
 for bad_index in [{},{"width":36000},{"width":36000,"height":36000,"block_width":1024,"block_height":1024,"blocks_across":36,"blocks_down":36,"object_size":fixture.object_size,"offsets":[100000],"counts":[fixture.block.size()]}]:
  check(not WorldCoverCog.block_range(bad_index,0).ok,"malformed API index")
  check(not WorldCoverCog.decode_block(bad_index,0,fixture.block).ok)
  check(not WorldCoverCog.class_at(bad_index,Vector2i(0,0),{}).ok)
 check(not WorldCoverCog.decode_block(result.index,-1,fixture.block).ok,"negative block id")
 var wrong: Dictionary = result.index.duplicate(true)
 wrong.counts[0]=2097153
 check(not WorldCoverCog.decode_block(wrong,0,too_large).ok,"mutated block bound before inflater")
 var block := WorldCoverCog.decode_block(result.index,0,fixture.block)
 check(block.ok)
 if block.ok:
  for value in [10,20,30,40,50,60,70,80,90,95,100]:
   block.classes[2]=value
   var sample := WorldCoverCog.class_at(result.index,Vector2i(2,0),{0:block})
   check(sample.ok,"recognized class byte "+str(value))
   if sample.ok: check_eq(sample.value,value)

func test_ifd_pointer_and_angular_units_consistency() -> void:
 var fixture := Fixtures.worldcover_tiff()
 var next_at: int = 10+fixture.tags.size()*12
 for pointer in [2,8,fixture.object_size,4294967295]:
  var malformed: PackedByteArray = fixture.body.duplicate()
  Fixtures._wc_uint(malformed,next_at,pointer,4,true)
  var result := WorldCoverCog.parse_index({0:malformed},fixture.object_size)
  check(not result.ok,"invalid next-IFD pointer: "+str(pointer))
  check(result.error!="")
 var overview: PackedByteArray = fixture.body.duplicate()
 Fixtures._wc_uint(overview,next_at,90000,4,true)
 check(WorldCoverCog.parse_index({0:overview},fixture.object_size).ok,"valid following overview IFD remains unused; first full-resolution source retained")
 for units in [9101,9102]:
  var altered: PackedByteArray = fixture.body.duplicate()
  Fixtures._wc_uint(altered,fixture.tags[34735]+4,20,4,true)
  Fixtures._wc_uint(altered,3106,4,2,true)
  for i in 4: Fixtures._wc_uint(altered,3132+i*2,[2054,0,1,units][i],2,true)
  var result := WorldCoverCog.parse_index({0:altered},fixture.object_size)
  check_eq(result.ok,units==9102,"explicit angular units must agree with EPSG:4326 degree transform")
