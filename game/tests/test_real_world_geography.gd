# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const Fixtures = preload("res://tests/real_world/terrain_source_fixtures.gd")

func distance(a: Vector2,b: Vector2) -> float:
 var lat1 := deg_to_rad(a.y)
 var lat2 := deg_to_rad(b.y)
 var h := pow(sin((lat2-lat1)/2.0),2)+cos(lat1)*cos(lat2)*pow(sin(deg_to_rad(b.x-a.x)/2.0),2)
 return 6371008.8*2.0*asin(sqrt(h))

func test_ground_scale_and_rotation() -> void:
 for lat in [0.0,70.0]:
  for bearing in [0.0,90.0,359.0]:
   var s := Fixtures.selection({"latitude":lat,"bearing":bearing})
   var c := Vector2(s.longitude,s.latitude)
   check(abs(distance(c,TerrainGeography.local_to_geo(s,Vector2(4000,0)))-4000)<2,"ground distance")
 var east := TerrainGeography.local_to_geo(Fixtures.selection({"latitude":0.0,"longitude":0.0,"bearing":90.0}),Vector2(1000,0))
 check(east.y<0 and abs(east.x)<0.00001,"clockwise bearing")

func test_whole_boundary_and_invalid_numbers() -> void:
 for side in [0.5,8.0,128.0]:
  check(TerrainGeography.validate_selection(Fixtures.selection({"side_km":side})).ok,"valid side")
 for key in ["latitude","longitude","side_km","bearing"]:
  for value in [NAN,INF,-INF]:
   check(not TerrainGeography.validate_selection(Fixtures.selection({key:value})).ok,"finite controls")
 check(not TerrainGeography.validate_selection(Fixtures.selection({"latitude":82.75})).ok,"whole north boundary")
 var edge_peak := Fixtures.selection({"latitude":82.175,"side_km":128.0})
 for corner in [Vector2(-64000,-64000),Vector2(64000,-64000),Vector2(-64000,64000),Vector2(64000,64000)]:
  check(TerrainGeography.local_to_geo(edge_peak,corner).y<82.75,"corners alone fit")
 check(not TerrainGeography.validate_selection(edge_peak).ok,"interior boundary extremum exceeds coverage")
 check(not TerrainGeography.validate_selection(Fixtures.selection({"latitude":-60.0})).ok,"whole south boundary")
 check(not TerrainGeography.validate_selection(Fixtures.selection({"bearing":360.0})).ok)
 for side in [0.49,128.01]: check(not TerrainGeography.validate_selection(Fixtures.selection({"side_km":side})).ok)
 check(TerrainGeography.validate_selection(Fixtures.selection({"latitude":81.5,"bearing":45.0,"side_km":128.0})).ok)

func test_dateline_and_southwest_names() -> void:
 check_eq(TerrainGeography.worldcover_address(Vector2(-115.1,36.1)).tile,"N36W117")
 check_eq(TerrainGeography.worldcover_address(Vector2(-0.1,-0.1)).tile,"S03W003")
 var p := TerrainGeography.local_to_geo(Fixtures.selection({"longitude":179.999}),Vector2(4000,0))
 check(p.x<0 and p.x>=-180,"dateline wraps")

func test_stencils_and_budget() -> void:
 var plan := TerrainGeography.plan_samples(Fixtures.selection())
 check(plan.ok,"sample plan succeeds")
 if not plan.ok: return
 check_eq(plan.vertex_stencils.size(),16641*9*2)
 check_eq(plan.centers.size(),16384*2)
 check(plan.elevation_tiles<=64 and plan.water_tiles<=512,"early budget")
 check_eq(plan.zoom,12,"8 km half-tile resolution at Las Vegas")
 var expected := 2.0*PI*6371008.8*cos(deg_to_rad(Fixtures.selection().latitude))/(256.0*4096.0)
 check(abs(plan.source_spacing_metres-expected)<0.0001)
 check(abs(plan.vertex_stencils[0]-round(plan.vertex_stencils[0]))>0.00001,"fractional elevation coordinates retained")
 var crossing := TerrainGeography.worldcover_address(Vector2(180.0,0.0))
 check_eq(crossing.tile,"N00W180")
 var count := 0
 for group in plan.water_groups.values(): count += group.size()/3
 check_eq(count,16384*64)

func test_packet_rejects_missing_or_nonfinite_samples() -> void:
 var p := Fixtures.packet()
 check_eq(p.vertex_metres.size(),16641)
 check_eq(p.water_counts.size(),16384)
 check(TerrainImportContract.validate_packet(p).ok,"valid numeric packet")
 p.vertex_metres[5]=NAN
 check(not TerrainImportContract.validate_packet(p).ok)
 p=Fixtures.packet()
 p.center_metres=PackedFloat64Array()
 check(not TerrainImportContract.validate_packet(p).ok)
 check(TerrainImportContract.validate_controls(Fixtures.controls()).ok)
 check(not TerrainImportContract.validate_controls(Fixtures.controls({"exaggeration":INF})).ok)
 for override in [{"smoothing_passes":2},{"trees":101},{"water_mode":"ocean"},{"preserve_narrow":1}]:
  check(not TerrainImportContract.validate_controls(Fixtures.controls(override)).ok)
 p=Fixtures.packet()
 p.water_counts[0]=65
 check(not TerrainImportContract.validate_packet(p).ok)
 p=Fixtures.packet()
 p.sources=[{"source":"worldcover","tile":"N99W999"}]
 check(not TerrainImportContract.validate_packet(p).ok)

func test_high_zoom_double_precision_and_seam_ordering() -> void:
 var selection := Fixtures.selection({"latitude":0.0,"longitude":170.123456,"side_km":0.5})
 var plan := TerrainGeography.plan_samples(selection)
 check(plan.ok)
 if not plan.ok: return
 check_eq(plan.zoom,15)
 var middle := ((64*129+64)*9+4)*2
 var expected_x := ((170.123456+180.0)/360.0)*8388608.0-0.5
 check(abs(plan.vertex_stencils[middle]-expected_x)<0.000001,"high zoom retains scalar longitude and pixel fraction")
 check(abs(plan.vertex_stencils[middle+1]-4194303.5)<0.000001,"center latitude pixel")
 # Independently evaluate the first tile center's equatorial inverse projection.
 var east := -63.5*500.0/128.0
 var north := 63.5*500.0/128.0
 var radius := sqrt(east*east+north*north)
 var c := radius/6371008.8
 var latitude := asin(north*sin(c)/radius)
 var longitude := deg_to_rad(170.123456)+atan2(east*sin(c),radius*cos(c))
 expected_x=(rad_to_deg(longitude)+180.0)/360.0*8388608.0-0.5
 var expected_y := (1.0-log(tan(latitude)+1.0/cos(latitude))/PI)*4194304.0-0.5
 check(abs(plan.centers[0]-expected_x)<0.000001,"center x preserves projected fraction")
 check(abs(plan.centers[1]-expected_y)<0.000001,"center y preserves projected fraction")
 var ordered := plan.water_groups["N00E168"] as PackedInt32Array
 check_eq(ordered[0],0,"water row-major tile/subgrid begins at zero")
 check_eq(ordered[3],1,"next water sample belongs to same tile")
 check_eq(ordered[8*3],8,"next subgrid row follows eight columns")
 var seam := TerrainGeography.plan_samples(Fixtures.selection({"latitude":0.0,"longitude":179.999999,"side_km":0.5}))
 check(seam.ok)
 if not seam.ok: return
 var west_neighbor := false
 var east_neighbor := false
 for source in seam.sources:
  if source.source=="terrarium":
   west_neighbor=west_neighbor or source.x==0
   east_neighbor=east_neighbor or source.x==32767
 check(west_neighbor and east_neighbor,"bilinear dateline neighbors include both wrapped edges")
 check(seam.water_groups.has("N00E177") and seam.water_groups.has("N00W180"),"water addresses cross dateline")
 for token in ["S00E000","N00W000"]:
  var packet := Fixtures.packet()
  packet.sources=[{"source":"worldcover","tile":token}]
  check(not TerrainImportContract.validate_packet(packet).ok,"signed zero source token rejected")

static func _digest(value: Variant) -> String:
 var hash := HashingContext.new()
 hash.start(HashingContext.HASH_SHA256)
 hash.update(var_to_bytes(value))
 return hash.finish().hex_encode()
# Golden plans produced by a straightforward per-sample planner; the
# allocation-free planner must match every stencil, center, group and source.
func test_plan_samples_match_recorded_reference_bytes() -> void:
 var cases := [
  [{"latitude":36.1699,"longitude":-115.1398,"side_km":8.0,"bearing":0.0},"032e3dc43b598d060aad2b9ca5c601f70c66840eb31eb53ecc83df7417ecbb0f"],
  [{"latitude":-33.9,"longitude":18.4,"side_km":100.0,"bearing":300.0},"b7faaefecf4dad51a56beda916465476900e478ed897b60ac250ecf646ed317c"],
  [{"latitude":0.0,"longitude":179.999999,"side_km":0.5,"bearing":0.0},"cc007e221dad6084ad9181ba752ce361a6fbf7732943f4cc9cf7ad9ef7995ea8"]]
 for item in cases:
  check_eq(_digest(TerrainGeography.plan_samples(item[0])),item[1],"plan bytes for "+str(item[0]))
# Planning polls its owner's cancellation once per row in each sampling phase.
func test_plan_samples_stop_promptly_when_cancelled() -> void:
 var polls := [0]
 var stopped := TerrainGeography.plan_samples(Fixtures.selection(),func() -> bool:
  polls[0]+=1
  return polls[0]>=3)
 check_eq(stopped,{"ok":false,"error":"canceled"})
 check_eq(polls[0],3,"cancellation observed at the first poll that reports it")
 polls[0]=-1000
 var completed := TerrainGeography.plan_samples(Fixtures.selection(),func() -> bool:
  polls[0]+=1
  return false)
 check(completed.ok)
 check_eq(polls[0],-1000+129+128+128,"one poll per planned row")
