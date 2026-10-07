extends "res://tests/exploration/async_test_case.gd"
const F = preload("res://tests/real_world/terrain_source_fixtures.gd")
var converter: Script
var manifest: Script
func before_all() -> void:
 if FileAccess.file_exists("res://scripts/terrain/real_world/real_world_terrain.gd"):
  converter=load("res://scripts/terrain/real_world/real_world_terrain.gd")
  manifest=load("res://scripts/terrain/real_world/real_world_manifest.gd")
func _convert(packet: Dictionary, controls: Dictionary = F.controls()) -> Dictionary:
 check(converter!=null,"Real-world conversion exists")
 if converter==null: return {"ok":false}
 var result: Dictionary=converter.convert(packet,controls,F.metadata())
 check(result.ok,result.get("error","conversion"))
 return result
func _canonical(result: Dictionary, packet: Dictionary, narrow: bool = true) -> void:
 var city: City=result.city
 check_eq(city.terrain_surface.cliff_count(),0)
 var lost:=0
 var added:=0
 var saddles:=0
 for y in 128:
  for x in 128:
   var i:=y*128+x
   var wet: bool=packet.water_counts[i]>=(1 if narrow else 32)
   if wet and not city.is_water(x,y): lost+=1
   if not wet and city.is_water(x,y): added+=1
   var corners: PackedInt32Array=city.terrain_surface.corners(x,y)
   var base: int=city.terrain_surface.tile_base(x,y)
   var mask:=0
   for k in 4:
    if corners[k]>base: mask|=1<<k
   if Terrain.shape_from_corners(mask)<0: saddles+=1
 check_eq(lost,0,"all classified water retained")
 check_eq(added,0,"no water added to dry footprint")
 check_eq(saddles,0)
 check_eq(result.diagnostics.lost_wet_tiles,0)
func test_physical_scale_fit_clipping_and_repairs() -> void:
 var packet:=F.packet()
 for y in 129:
  for x in 129: packet.vertex_metres[y*129+x]=float(x)*50.0
 var result:=_convert(packet)
 if not result.ok: return
 check_eq(result.diagnostics.metres_per_tile,62.5)
 check(absf(result.diagnostics.metres_per_level-62.5*CityGeometry3D.HEIGHT)<0.000001)
 check_gt(result.diagnostics.initial_clipped_targets,0)
 check_gt(result.diagnostics.repaired_vertices,0)
 _canonical(result,packet)
 var fit: Dictionary=converter.fit_exaggeration(packet,F.controls())
 check(fit.ok)
 check_lt(fit.exaggeration,1.0)
 check_eq(fit.remaining_clipping,0)
 var fitted:=_convert(packet,F.controls({"exaggeration":fit.exaggeration}))
 check_eq(fitted.diagnostics.initial_clipped_targets,0)
 var flat: Dictionary=converter.fit_exaggeration(F.packet(),F.controls({"exaggeration":7.0}))
 check_eq(flat.exaggeration,7.0)
func test_dry_below_sea_and_coastal_islands() -> void:
 for mode in ["auto","fresh","sea"]:
  var dry:=_convert(F.packet("negative_dry"),F.controls({"water_mode":mode}))
  if not dry.ok: return
  check(not dry.city.is_water(64,64))
  check_eq(dry.city.sea_level,-1)
 var packet:=F.packet("negative_dry")
 for y in 128:
  for x in 70: packet.water_counts[y*128+x]=64
 packet.water_counts[64*128+30]=0
 var coast:=_convert(packet)
 if not coast.ok: return
 _canonical(coast,packet)
 check(coast.city.is_salt_water(0,0))
 check(not coast.city.is_water(30,64))
 check_gt(coast.city.sea_level,-1)
func test_elevated_lake_and_descending_thin_channel() -> void:
 var packet:=F.packet()
 for y in range(20,100):
  packet.water_counts[y*128+64]=1
  packet.center_metres[y*128+64]=100.0+float(100-y)*10.0
 var result:=_convert(packet)
 if not result.ok: return
 _canonical(result,packet)
 check_eq(result.city.sea_level,-1)
 check_gt(result.diagnostics.widened_tiles,0)
 check_gt(result.city.water_height(64,20),result.city.water_height(64,99))
 check_gt(result.diagnostics.stream_tiles,0)
 check_gt(result.diagnostics.waterfall_tiles,0,"descending straight channel has legal waterfalls")
 check(manifest.valid_surface(result.city.terrain_surface))
 var broad:=F.packet("flat_wet")
 var lake:=_convert(broad)
 check_eq(lake.city.sea_level,-1)
 _canonical(lake,broad)
 var omitted:=_convert(packet,F.controls({"preserve_narrow":false}))
 _canonical(omitted,packet,false)
func test_mask_survives_shared_bed_repairs() -> void:
 var packet:=F.packet()
 for y in 129:
  for x in 129: packet.vertex_metres[y*129+x]=5000.0 if (x+y)%2==0 else -500.0
 for y in range(10,118):
  for x in range(10,118):
   if (x+y)%3==0: packet.water_counts[y*128+x]=32
 var result:=_convert(packet)
 if not result.ok: return
 _canonical(result,packet)
 for passes in [1,3]:
  var smoothed:=_convert(packet,F.controls({"smoothing_passes":passes}))
  if smoothed.ok: _canonical(smoothed,packet)
func test_repeatability_and_tree_rng() -> void:
 var packet:=F.packet()
 var controls:=F.controls({"trees":60,"tree_seed":17})
 var a:=_convert(packet,controls)
 if not a.ok: return
 var b:=_convert(packet,controls)
 check_eq(a.baseline,b.baseline)
 check_gt(a.city.building_census()[Buildings.TREES_1],0)
 var rng:=SimRng.new(17)
 var state:=rng.state()
 load("res://scripts/terrain/terrain_generator.gd").call("decorate_trees",a.city,60,17)
 check_eq(rng.state(),state)
 check_eq(packet.vertex_metres,F.packet().vertex_metres,"input untouched")
func test_baseline_isolation() -> void:
 var result:=_convert(F.packet(),F.controls({"trees":40,"tree_seed":19}))
 if not result.ok: return
 var original: PackedByteArray=result.city.terrain_surface.vertices.duplicate()
 var restore: Dictionary=manifest.restore_baseline(result.baseline,F.metadata(),result.origin)
 check(restore.ok)
 check_eq(restore.city.terrain_surface.vertices,original)
 result.city.terrain_surface.vertices[0]=31
 check_eq(restore.city.terrain_surface.vertices,original)
 var bad: PackedByteArray=result.baseline.duplicate()
 bad[30]^=1
 check(not manifest.restore_baseline(bad,F.metadata(),result.origin).ok)

func test_smoothing_fit_limits_and_cancelled_input() -> void:
 var packet:=F.conversion_packet("corner_spike")
 var none:=_convert(packet)
 if not none.ok: return
 check_eq(none.diagnostics.source_max_metres,900.0)
 var one:=_convert(packet,F.controls({"smoothing_passes":1}))
 check_eq(one.diagnostics.source_max_metres,400.0,"clamped edge samples in 3x3 average")
 var three:=_convert(packet,F.controls({"smoothing_passes":3}))
 check_lt(three.diagnostics.source_max_metres,one.diagnostics.source_max_metres)
 packet.vertex_metres[0]=1.0e12
 var fit: Dictionary=converter.fit_exaggeration(packet,F.controls())
 check_eq(fit.exaggeration,0.001)
 check_gt(fit.remaining_clipping,0)
 var stopped: Dictionary=converter.convert(packet,F.controls(),F.metadata(),func() -> bool: return true)
 check(not stopped.ok)
 check_eq(stopped.error,"canceled")
 check(not stopped.has("city"))

func test_manifest_provenance_bounds_and_json_roundtrip() -> void:
 var packet:=F.conversion_packet("provenance")
 var result:=_convert(packet,F.controls({"tree_seed":-9223372036854775807}))
 if not result.ok: return
 check(TerrainImportContract.validate_packet(packet).ok)
 var origin: Dictionary=manifest.sanitize_origin(JSON.parse_string(JSON.stringify(result.origin)))
 check_eq(origin,result.origin)
 check_eq(origin.source_objects.size(),2)
 check_eq(origin.controls.tree_seed,"-9223372036854775807")
 origin["fetch_url"]="https://should-not-survive.invalid"
 origin.controls["secret"]="discard"
 var safe: Dictionary=manifest.sanitize_origin(origin)
 check(not safe.has("fetch_url"))
 check(not safe.controls.has("secret"))
 var bad:=packet.duplicate(true)
 bad.source_objects[0].ranges[0].offset=4090
 check(not TerrainImportContract.validate_packet(bad).ok)
 bad=packet.duplicate(true)
 bad.source_objects[0].descriptor={"source":"terrarium","z":2,"x":1,"y":1}
 check(not TerrainImportContract.validate_packet(bad).ok)
 bad=packet.duplicate(true)
 bad.source_objects[0].ranges[0].sha256="Z".repeat(64)
 check(not TerrainImportContract.validate_packet(bad).ok)
 bad=packet.duplicate(true)
 bad.source_objects[0].etag="x".repeat(257)
 check(not TerrainImportContract.validate_packet(bad).ok)
 var incomplete: Dictionary=result.origin.duplicate(true)
 incomplete.source_objects.pop_back()
 check(manifest.sanitize_origin(incomplete).is_empty(),"never omit a required object identity")
 var huge: Dictionary=result.origin.duplicate(true)
 huge.sources=[]
 huge.source_objects=[]
 for i in 576:
  var descriptor: Dictionary={"source":"terrarium","z":10,"x":i,"y":401}
  huge.sources.append(descriptor)
  huge.source_objects.append({"descriptor":descriptor,"etag":"x".repeat(256),"size":4096,"ranges":[{"offset":0,"length":1,"sha256":"a".repeat(64)}]})
 check_gt(JSON.stringify(huge).to_utf8_buffer().size(),262144)
 check(manifest.sanitize_origin(huge).is_empty(),"serialized origin cap")

func _resign(body: PackedByteArray) -> PackedByteArray:
 var payload:=body.slice(0,-32)
 payload.append_array(manifest.sha256(payload))
 return payload

func test_baseline_independent_validation_and_exact_seed() -> void:
 var result:=_convert(F.packet(),F.controls({"trees":50,"tree_seed":-9223372036854775807}))
 if not result.ok: return
 var baseline: PackedByteArray=result.baseline
 var restored: Dictionary=manifest.restore_baseline(baseline,F.metadata(),{})
 check(restored.ok,"baseline validates without origin or sources")
 check_eq(restored.tree_seed,-9223372036854775807)
 check(restored.origin.is_empty())
 var settings: Dictionary=manifest.editing_settings(result)
 check_eq(settings.seed,-9223372036854775807)
 var saved: Dictionary=JSON.parse_string(JSON.stringify(settings))
 var saved_body:=Marshalls.base64_to_raw(saved.baseline_base64)
 var offline: Dictionary=manifest.restore_baseline(saved_body,F.metadata(),{})
 check_eq(offline.tree_seed,-9223372036854775807,"restore seed comes from binary even after JSON")
 var high_seed:=9223372036854775807
 var positive: PackedByteArray=manifest.encode_baseline(restored.city,high_seed)
 check_eq(manifest.restore_baseline(positive,F.metadata(),{}).tree_seed,high_seed)
 check(not manifest.restore_baseline(baseline.slice(0,-1),F.metadata(),{}).ok)
 var changed:=baseline.duplicate()
 changed[13]=32
 check(not manifest.restore_baseline(_resign(changed),F.metadata(),{}).ok,"height code bound independent of checksum")
 changed=baseline.duplicate()
 changed[13+16641]=0
 check(not manifest.restore_baseline(_resign(changed),F.metadata(),{}).ok,"water cannot lie below ground")
 changed=baseline.duplicate()
 changed[13+16641+16384]=2
 check(not manifest.restore_baseline(_resign(changed),F.metadata(),{}).ok,"salt code bound")
 changed=baseline.duplicate()
 changed[13+16641+2*16384]=3
 check(not manifest.restore_baseline(_resign(changed),F.metadata(),{}).ok,"feature code bound")
 changed=baseline.duplicate()
 changed[13+16641+3*16384]=255
 check(not manifest.restore_baseline(_resign(changed),F.metadata(),{}).ok,"non-tree structure rejected")
 changed=baseline.duplicate()
 changed[13]=20
 check(not manifest.restore_baseline(_resign(changed),F.metadata(),{}).ok,"canonical slope validation")
 restored.city.building.put(0,0,255)
 check(manifest.encode_baseline(restored.city,0).is_empty(),"encoding also rejects non-tree buildings")

func test_broad_patch_and_huge_finite_targets() -> void:
 var packet:=F.packet()
 for y in range(60,62):
  for x in range(60,62): packet.water_counts[y*128+x]=64
 var patch:=_convert(packet)
 if not patch.ok: return
 check_eq(patch.diagnostics.stream_tiles,0,"2x2 open water remains broad")
 _canonical(patch,packet)
 packet=F.packet()
 packet.vertex_metres[0]=1.0e100
 var huge:=_convert(packet)
 check_gt(huge.diagnostics.initial_clipped_targets,0)
 check_gt(huge.diagnostics.repaired_vertices,0,"huge target clamps high before integer cast")

func test_fit_rechecks_water_median_at_new_scale() -> void:
 var packet:=F.packet()
 for y in range(40,80):
  packet.water_counts[y*128+64]=64
  packet.center_metres[y*128+64]=float(y-40)*0.5
 var fit: Dictionary=converter.fit_exaggeration(packet,F.controls())
 check(fit.ok)
 check_eq(fit.remaining_clipping,0,"Fit re-evaluates a lake that becomes a descending channel")
 var result:=_convert(packet,F.controls({"exaggeration":fit.exaggeration}))
 if result.ok: check_eq(result.diagnostics.initial_clipped_targets,0)

func test_baseline_waterfall_profile_and_straight_channel() -> void:
 # Authored canonical lattice, independent of conversion and independently re-signed.
 for high_direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
  var surface:=TerrainSurface.new(5)
  for vertex in TerrainSurface.tile_vertices(64,64):
   if (high_direction==Vector2i.LEFT and vertex.x==64) or (high_direction==Vector2i.RIGHT and vertex.x==65) or (high_direction==Vector2i.UP and vertex.y==64) or (high_direction==Vector2i.DOWN and vertex.y==65):
    surface.set_vertex(vertex.x,vertex.y,6)
  var high: Vector2i=Vector2i(64,64)+high_direction
  var low: Vector2i=Vector2i(64,64)-high_direction
  surface.set_water(64,64,6,false,TerrainSurface.Feature.WATERFALL)
  surface.set_water(high.x,high.y,7)
  surface.set_water(low.x,low.y,6)
  check(manifest.valid_surface(surface),"local6/upstream7/downstream6 is legal in every direction")
  var city:=City.new()
  surface.project(city)
  var baseline: PackedByteArray=manifest.encode_baseline(city,23)
  check_eq(baseline.size(),82222)
  var restored: Dictionary=manifest.restore_baseline(baseline,F.metadata(),{})
  check(restored.ok,"independent legal waterfall baseline restores")
  var water_offset:=13+16641
  var disconnected:=baseline.duplicate()
  disconnected[water_offset+high.y*128+high.x]=20
  disconnected[water_offset+low.y*128+low.x]=19
  check(not manifest.restore_baseline(_resign(disconnected),F.metadata(),{}).ok,"re-signed local6/upstream20/downstream19 must fail")
  surface.set_water(high.x,high.y,20)
  surface.set_water(low.x,low.y,19)
  check(not manifest.valid_surface(surface),"surface gate rejects disconnected waterfall heights")
  check(manifest.encode_baseline(city,23).is_empty(),"encoder independently rejects disconnected waterfall")
  var sideways:=baseline.duplicate()
  var bank: Vector2i=Vector2i(64,64)+Vector2i(high_direction.y,high_direction.x)
  sideways[water_offset+bank.y*128+bank.x]=6
  check(not manifest.restore_baseline(_resign(sideways),F.metadata(),{}).ok,"waterfall requires dry perpendicular banks")
# Relief fitting runs up to 64 preparation passes; it must observe cancellation.
func test_fit_exaggeration_observes_cancellation() -> void:
 var packet: Dictionary=F.packet()
 check_eq(RealWorldTerrain.fit_exaggeration(packet,F.controls(),func() -> bool: return true),{"ok":false,"error":"canceled"})
 var calls := [0]
 var fit := RealWorldTerrain.fit_exaggeration(packet,F.controls(),func() -> bool:
  calls[0]+=1
  return false)
 check(fit.ok)
 check(calls[0]>0,"fit polls its owner")
func test_lake_with_stray_samples_stays_level_in_its_banks() -> void:
 # A hydro-flattened lake whose elevation samples include a data void, a bank
 # sample and a lower outlet stream. It must stay one level and never stand
 # above the ground around it (one level of rounding at a sloping bank).
 var packet:=F.packet()
 var disk := {}
 for y in 128:
  for x in 128:
   if Vector2(x-40,y-60).length()<10.0:
    packet.water_counts[y*128+x]=64
    disk[y*128+x]=true
 packet.center_metres[60*128+40]=-500.0
 packet.center_metres[60*128+31]=900.0
 for x in range(50,90):
  packet.water_counts[60*128+x]=64
  packet.center_metres[60*128+x]=100.0-float(x-49)*4.0
 for y in 129:
  for x in range(50,91): packet.vertex_metres[y*129+x]=100.0-float(x-49)*4.0
 var result:=_convert(packet)
 if not result.ok: return
 _canonical(result,packet)
 var surface: TerrainSurface=result.city.terrain_surface
 var levels := {}
 var under := 0
 for i in disk:
  var level:=surface.water_level(i%128,i/128)
  levels[level]=true
  for vertex in TerrainSurface.tile_vertices(i%128,i/128):
   var dry:=false
   var outlet:=false
   for tile in TerrainSurface.vertex_tiles(vertex.x,vertex.y):
    if not surface.has_water(tile.x,tile.y): dry=true
    elif surface.water_level(tile.x,tile.y)<level: outlet=true
   if dry and not outlet and surface.vertex(vertex.x,vertex.y)<level-1: under+=1
 check_eq(levels.size(),1,"lake with stray samples keeps one level")
 check_eq(under,0,"lake never stands above its dry banks")
 var standing := 0
 for y in 128:
  for x in 128:
   if surface.has_water(x,y) and not disk.has(y*128+x) and surface.water_level(x,y)>surface.tile_base(x,y)+1: standing+=1
 check_eq(standing,0,"stream water rests on its bed")
 check(manifest.valid_surface(surface))
