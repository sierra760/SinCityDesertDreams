# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const Fixtures = preload("res://tests/real_world/terrain_source_fixtures.gd")

func decoded_seam(dateline: bool = false) -> Dictionary:
 var tiles := {}
 var bodies := Fixtures.terrarium_seam(dateline)
 for key in bodies:
  tiles[key]=TerrariumTiles.decode_png(bodies[key])
 return tiles

func test_numeric_negative_fractional_metres() -> void:
 var decoded_negative := TerrariumTiles.decode_png(Fixtures.terrarium_png(Vector3i(127,254,128)))
 var decoded_zero := TerrariumTiles.decode_png(Fixtures.terrarium_png(Vector3i(128,0,0)))
 check(decoded_negative.ok,"numeric negative tile decodes")
 check(decoded_zero.ok,"numeric zero tile decodes")
 if not decoded_negative.ok or not decoded_zero.ok: return
 check_eq(decoded_negative.metres.size(),65536)
 check_eq(decoded_negative.metres[0],-1.5)
 check_eq(decoded_zero.metres[0],0.0)
 check_eq(decoded_negative.metres[65535],-1.5)
 var raw := PackedByteArray()
 raw.resize(65536*3)
 for i in 65536:
  raw[i*3]=128
  raw[i*3+1]=1
  raw[i*3+2]=1
 var rgb := TerrariumTiles.decode_png(Image.create_from_data(256,256,false,Image.FORMAT_RGB8,raw).save_png_to_buffer())
 check(rgb.ok,"8-bit RGB accepted")
 if rgb.ok: check_eq(rgb.metres[0],1.00390625,"raw numeric RGB fraction")
 for value in [Vector3i(81,32,0),Vector3i(167,16,0)]:
  check(TerrariumTiles.decode_png(Fixtures.terrarium_png(value)).ok,"plausible DEM endpoints inclusive")

func test_interpolation_crosses_tile_and_dateline_seams() -> void:
 var tiles := decoded_seam()
 var seam_sample := TerrariumTiles.sample_bilinear(Vector2(511.5,511.5),2,tiles)
 check(seam_sample.ok,"four-tile seam interpolates")
 if seam_sample.ok: check_eq(seam_sample.metres,25.0)
 var dateline := decoded_seam(true)
 for x in [1023.5,-0.5,2047.5]:
  var wrapped := TerrariumTiles.sample_bilinear_xy(x,511.5,2,dateline)
  check(wrapped.ok,"dateline neighbor wraps")
  if wrapped.ok: check_eq(wrapped.metres,25.0)
 var offcenter := TerrariumTiles.sample_bilinear_xy(511.25,511.75,2,tiles)
 check(offcenter.ok,"non-midpoint bilinear seam")
 if offcenter.ok: check_eq(offcenter.metres,27.5)

func test_corrupt_transparent_wrong_size_and_missing_neighbor() -> void:
 var body := Fixtures.terrarium_png(Vector3i(128,0,0))
 var damaged := body.duplicate()
 damaged[damaged.size()/2]^=1
 for invalid in [PackedByteArray(),PackedByteArray([1,2,3]),damaged,body.slice(0,body.size()-1)]:
  check(not TerrariumTiles.decode_png(invalid).ok,"corrupt or truncated PNG rejected")
 var oversized := PackedByteArray()
 oversized.resize(2*1024*1024+1)
 check(not TerrariumTiles.decode_png(oversized).ok,"body ceiling before allocation")
 var tiny_huge := body.slice(0,33)
 tiny_huge[16]=127
 tiny_huge[17]=255
 tiny_huge[18]=255
 tiny_huge[19]=255
 check(not TerrariumTiles.decode_png(tiny_huge).ok,"enormous advertised width in tiny body rejected")
 var full_huge := Fixtures.terrarium_authored_png("huge_dimensions_crc_repaired")
 var full_huge_result := TerrariumTiles.decode_png(full_huge)
 check(full_huge.size()>45,"complete huge-IHDR fixture reaches dimension validation")
 check(not full_huge_result.ok,"complete CRC-repaired enormous width and height rejected")
 check_eq(full_huge_result.error,"Terrarium PNG dimensions must be 256 by 256","dimension guard specifically rejects the complete body")
 var small := Image.create(1,1,false,Image.FORMAT_RGB8).save_png_to_buffer()
 check(not TerrariumTiles.decode_png(small).ok,"wrong dimensions rejected")
 var transparent_tile := TerrariumTiles.decode_png(Fixtures.terrarium_png(Vector3i(128,0,0),254))
 check(not transparent_tile.ok)
 check(not TerrariumTiles.decode_png(Fixtures.terrarium_png(Vector3i(0,0,0))).ok,"implausible negative DEM rejected")
 check(not TerrariumTiles.decode_png(Fixtures.terrarium_png(Vector3i(255,255,255))).ok,"implausible positive DEM rejected")
 var tiles := decoded_seam()
 tiles.erase("2/2/2")
 var missing_neighbor := TerrariumTiles.sample_bilinear_xy(511.5,511.5,2,tiles)
 check(not missing_neighbor.ok)
 for point in [Vector2(511,-0.1),Vector2(511,1023.5),Vector2(NAN,511),Vector2(INF,511)]:
  check(not TerrariumTiles.sample_bilinear(point,2,tiles).ok,"invalid y or nonfinite sample rejected")
 for zoom in [-1,31]: check(not TerrariumTiles.sample_bilinear_xy(1,1,zoom,tiles).ok,"invalid zoom rejected")
 var malformed := decoded_seam()
 malformed["2/2/2"]={"ok":true,"metres":PackedFloat64Array([1.0])}
 check(not TerrariumTiles.sample_bilinear_xy(511.5,511.5,2,malformed).ok,"malformed neighbor rejected")
 malformed=decoded_seam()
 if malformed["2/2/2"].ok:
  malformed["2/2/2"].metres[0]=NAN
  check(not TerrariumTiles.sample_bilinear_xy(511.5,511.5,2,malformed).ok,"nonfinite neighbor rejected")

func test_high_zoom_scalar_fraction_survives() -> void:
 var seam := decoded_seam()
 var tiles := {"15/31250/0":seam["2/1/1"],"15/31251/0":seam["2/2/1"],"15/31250/1":seam["2/1/2"],"15/31251/1":seam["2/2/2"]}
 # 8,000,255.125 rounds to an integer through float32 Vector2.
 var result := TerrariumTiles.sample_bilinear_xy(8000255.125,255.25,15,tiles)
 check(result.ok,"double-scalar high zoom sample succeeds")
 if result.ok: check_eq(result.metres,16.25,"independent high-zoom 1/8 fraction preserved")

func test_authored_filters_interlace_and_color_metadata() -> void:
 var expected := [-1.5,2.25,15.125,100.75]
 for case_name in ["filter0","filter1","filter2","filter3","filter4","adam7","gamma"]:
  var decoded := TerrariumTiles.decode_png(Fixtures.terrarium_authored_png(case_name))
  check(decoded.ok,"independent raw fixture "+case_name)
  if not decoded.ok: continue
  for point in [Vector2i(0,0),Vector2i(1,0),Vector2i(2,0),Vector2i(3,0),Vector2i(17,28),Vector2i(255,255)]:
   check_eq(decoded.metres[point.y*256+point.x],expected[(point.x+point.y)%4],"raw RGB exact after "+case_name)

func test_crc_valid_compressed_corruption_is_data_error() -> void:
 for case_name in ["bad_zlib_header","bad_zlib_checksum","truncated_zlib","trailing_zlib","short_scanlines","bad_filter"]:
  var result := TerrariumTiles.decode_png(Fixtures.terrarium_authored_png(case_name))
  check(not result.ok,"valid chunk CRC but damaged compressed data: "+case_name)
  check(not result.has("metres"),"failed decode carries no partial elevation")
  check(result.error!="","failure carries reason")

func test_single_transparent_pixel_is_not_silently_interpolated() -> void:
 var image := Image.new()
 check_eq(image.load_png_from_buffer(Fixtures.terrarium_png(Vector3i(128,0,0))),OK,"fixture image")
 var raw := image.get_data()
 raw[65535*4+3]=0
 var result := TerrariumTiles.decode_png(Image.create_from_data(256,256,false,Image.FORMAT_RGBA8,raw).save_png_to_buffer())
 check(not result.ok,"last pixel opacity checked")

func test_incomplete_multibit_distance_tree_is_rejected() -> void:
 var result := TerrariumTiles.decode_png(Fixtures.terrarium_authored_png("incomplete_distance_tree"))
 check(not result.ok,"invalid Huffman tree must fail even when its available branch decodes pixels")

func test_empty_deflate_blocks_obey_parser_work_budget() -> void:
 var under := TerrariumTiles.decode_png(Fixtures.terrarium_authored_png("empty_fixed_under_budget"))
 check(under.ok,"valid modest fixed-block stream accepted")
 if under.ok: check_eq(under.metres[0],-1.5)
 for case_name in ["empty_fixed_over_budget","empty_dynamic_over_budget"]:
  var body := Fixtures.terrarium_authored_png(case_name)
  check(body.size()<2*1024*1024,"work-budget fixture stays inside byte ceiling")
  var started := Time.get_ticks_msec()
  var result := TerrariumTiles.decode_png(body)
  var elapsed := Time.get_ticks_msec()-started
  check(not result.ok,"valid empty blocks must fail bounded parser work: "+case_name)
  check(not result.has("metres"),"over-budget failure has no partial metres")
  check(String(result.error).contains("work budget"),"over-budget parser gives precise clean data error")
  check(elapsed<2000,"over-budget rejection completes within focused two-second guard")
  print("  work-budget %s: %d ms"%[case_name,elapsed])
