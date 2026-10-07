# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const Fake = preload("res://tests/real_world/fake_terrain_transport.gd")
const Fixtures = preload("res://tests/real_world/terrain_source_fixtures.gd")
var fake: RefCounted
var importer: RealWorldImporter
var transport: TerrainHttpTransport
var cache: TerrainTileCache
var candidates: Array = []
var failures: Array = []
func before_each() -> void:
 fake=Fake.new()
 fake.install_flat_objects()
 transport=fake.make_transport()
 root.add_child(transport)
 cache=TerrainTileCache.new()
 cache.configure("user://terrain_tiles_v1/importer-tests")
 cache.clear()
 importer=RealWorldImporter.new()
 importer.configure(transport,cache)
 importer.set_clock(func() -> int: return fake.now)
 root.add_child(importer)
 candidates.clear(); failures.clear()
 importer.candidate_ready.connect(func(g: int,c: Dictionary) -> void: candidates.append([g,c]))
 importer.failed.connect(func(g: int,e: String) -> void: failures.append([g,e]))
func after_each() -> void:
 importer.cancel()
 while not importer.is_drained(): await process_frame
 importer.queue_free()
 transport.queue_free()
 await process_frame
 await process_frame
 fake=null
func pump() -> void:
 fake.advance_clock(0)
 fake.serve_pending()
 await process_frame
func online() -> bool:
 importer.check_online(true)
 for i in 12: await pump()
 check(importer.is_online_fresh(),"both production HEAD validations make session online")
 return importer.is_online_fresh()
func acquire() -> void:
 importer.download(Fixtures.selection({"side_km":0.5,"longitude":-115.13671875}),Fixtures.controls(),Fixtures.metadata())
 var until := Time.get_ticks_msec()+45000
 while candidates.is_empty() and failures.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(not candidates.is_empty(),"complete validated acquisition publishes: "+str(failures))
# Missing either service gating or expiry admits unavailable acquisition.
func test_both_service_probes_and_sixty_second_expiry() -> void:
 check(not importer.is_online_fresh())
 fake.deny_water_probe=true
 importer.check_online(true)
 for i in 12: await pump()
 check(not importer.is_online_fresh())
 fake.deny_water_probe=false
 if not await online(): return
 fake.advance_clock(59999)
 check(importer.is_online_fresh())
 fake.advance_clock(1)
 check(not importer.is_online_fresh())
# Missing sampling/group completeness, numeric decode, stable ordering or accounting breaks this.
func test_complete_grouped_packet_independent_of_arrival_order() -> void:
 if not await online(): return
 await acquire()
 if candidates.is_empty(): return
 var baseline: PackedByteArray = importer.candidate.baseline.duplicate()
 check_eq(baseline.size(),82222)
 check(importer.is_ready())
 check_eq(importer.metrics.elevation_tiles,2,"complete two-tile DEM seam")
 check_eq(importer.metrics.water_blocks,1)
 check_eq(importer.metrics.downloaded_bytes,importer.metrics.validated_source_bytes)
 check_eq(importer.metrics.peak_decoded_water_bytes,1048576)
 check_eq(importer.metrics.water_samples,1048576)
 check_eq(importer.metrics.vertex_samples,149769)
 check_eq(importer.metrics.center_samples,16384)
 check(importer.metrics.downloaded_bytes<=67108864)
 check_lt(importer.metrics.peak_working_bytes,134217728)
 check_eq(importer.metrics.peak_decoded_water_blocks,1)
 check(importer.metrics.get("normalization_worklist_peak_bytes",0)>0,"production import uses the canonical worklist guard")
 check(importer.metrics.get("normalization_worklist_peak_bytes",16777217)<=16777216)
 check(importer.metrics.get("normalization_queue_items",0)>=16641)
 check(importer.metrics.get("normalization_recent_items",0)>=16641)
 check_eq(importer.candidate.origin.source_objects.size(),importer.candidate.origin.sources.size())
 print("IMPORT_METRICS ",importer.metrics)
 importer.clear_cache()
 candidates.clear()
 fake.reverse_responses=true
 await acquire()
 if not candidates.is_empty(): check_eq(importer.candidate.baseline,baseline)
# Unknown water, geographic caps, whole-generation deadline must never publish partials.
func test_unknown_water_and_each_budget_fail_without_publish() -> void:
 if not await online(): return
 fake.install_flat_objects(0)
 importer.download(Fixtures.selection({"side_km":0.5,"longitude":-115.13671875}),Fixtures.controls(),Fixtures.metadata())
 var until := Time.get_ticks_msec()+45000
 while failures.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(not failures.is_empty(),"required unknown water fails")
 check(not cache.lookup({"source":"worldcover","tile":"N36W117"},{"offset":100000,"length":fake.objects.tiff.size()-100000},{"etag":fake.objects.etag,"size":fake.objects.tiff.size()}).ok,"unknown required classes are not published to cache")
 check_eq(candidates.size(),0)
 failures.clear()
 importer.download(Fixtures.selection({"side_km":129.0}),Fixtures.controls(),Fixtures.metadata())
 for i in 30: await pump()
 check(not failures.is_empty(),"over-cap selection fails")
 failures.clear()
 importer.download(Fixtures.selection(),Fixtures.controls(),Fixtures.metadata())
 fake.advance_clock(300000)
 for i in 12: await pump()
 check(not failures.is_empty(),"planning consumes deadline")
 check_eq(candidates.size(),0)
# Invalidation must precede callbacks and retain workers until joined.
func test_cancel_close_suspend_during_decode_and_late_response() -> void:
 if not await online(): return
 for action in ["cancel","suspend","invalidate_settings"]:
  importer.set_visible(true)
  if not await online(): return
  importer.download(Fixtures.selection(),Fixtures.controls(),Fixtures.metadata())
  await process_frame
  importer.call(action)
  while not importer.is_drained(): await pump()
  fake.serve_pending()
  check_eq(candidates.size(),0)
  check(not importer.is_ready())
  check_eq(fake.active,0)
# Rebuild expiry/error must invalidate acceptance while keeping prior completed bytes.
func test_rebuild_requires_online_but_prior_candidate_survives() -> void:
 if not await online(): return
 await acquire()
 if candidates.is_empty(): return
 var baseline: PackedByteArray = importer.candidate.baseline.duplicate()
 importer.invalidate_settings()
 check(not importer.is_ready())
 check_eq(importer.candidate.baseline,baseline)
 fake.advance_clock(60000)
 importer.rebuild(Fixtures.controls({"trees":10}),Fixtures.metadata())
 await process_frame
 check(not failures.is_empty())
 check_eq(importer.candidate.baseline,baseline)
 var old_city: City = importer.candidate.city
 if not await online(): return
 candidates.clear()
 failures.clear()
 var cancel_on_ready := func(stage: String,_fraction: float,_detail: String) -> void:
  if stage=="Ready": importer.invalidate_settings()
 importer.progress_changed.connect(cancel_on_ready)
 importer.rebuild(Fixtures.controls({"trees":10}),Fixtures.metadata())
 while not importer.is_drained(): await pump()
 check_eq(candidates.size(),0,"Ready progress listeners can invalidate before candidate publication")
 check(not importer.is_ready())
 importer.progress_changed.disconnect(cancel_on_ready)
 var metadata := Fixtures.metadata()
 metadata.name="Rebuilt metadata"
 importer.rebuild(Fixtures.controls({"trees":10}),metadata)
 while not importer.is_drained(): await pump()
 check_eq(candidates.size(),1,"online rebuild publishes a new independent candidate")
 check_eq(importer.candidate.city.name,"Rebuilt metadata")
 check(old_city!=importer.candidate.city)
 check_eq(old_city.name,"Real terrain fixture")
 importer.release_candidate()
 check(importer.candidate.is_empty())
 check_eq(old_city.name,"Real terrain fixture","explicit release never mutates handed-off City")
# Every cache use needs a fresh object HEAD; a different pinned identity cannot reuse stale body.
func test_revalidation_before_cache_reuse() -> void:
 if not await online(): return
 await acquire()
 if candidates.is_empty(): return
 var heads: int = fake.starts.filter(func(r: Dictionary) -> bool: return r.head_only).size()
 candidates.clear()
 await acquire()
 check(fake.starts.filter(func(r: Dictionary) -> bool: return r.head_only).size()>heads)
 fake.objects.etag="\"fixture-v2\""
 candidates.clear()
 var bytes: int = fake.response_bytes
 await acquire()
 check(fake.response_bytes>bytes,"changed identity refetches bodies")

# Correctly shaped TIFF from a different 3-degree cell must not classify this city.
func test_wrong_transform_and_more_than_512_blocks_rejected() -> void:
 if not await online(): return
 fake.install_flat_objects(60,true)
 importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
 var until := Time.get_ticks_msec()+45000
 while failures.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(not failures.is_empty())
 if not failures.is_empty(): check("transform" in failures.back()[1])
 check_eq(candidates.size(),0)
 failures.clear()
 importer.download(Fixtures.selection({"latitude":80.0,"side_km":128.0}),Fixtures.controls(),Fixtures.metadata())
 until=Time.get_ticks_msec()+45000
 while failures.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(not failures.is_empty())
 if not failures.is_empty(): check("512" in failures.back()[1],"group planner rejects water budget before fetching")
 check_eq(candidates.size(),0)
 print("BLOCK_CAP_METRICS ",importer.metrics)
# Incomplete seam descriptor sets silently lose bilinear neighbors or WorldCover quadrants.
func test_complete_antimeridian_descriptor_set_and_geographic_cap() -> void:
 var plan := TerrainGeography.plan_samples(Fixtures.selection({"longitude":180.0,"latitude":0.0,"side_km":0.5}))
 check(plan.ok)
 if plan.ok:
  var expected: Array = [
   {"source":"terrarium","z":15,"x":0,"y":16383},
   {"source":"terrarium","z":15,"x":0,"y":16384},
   {"source":"terrarium","z":15,"x":32767,"y":16383},
   {"source":"terrarium","z":15,"x":32767,"y":16384},
   {"source":"worldcover","tile":"N00E177"},
   {"source":"worldcover","tile":"N00W180"},
   {"source":"worldcover","tile":"S03E177"},
   {"source":"worldcover","tile":"S03W180"}]
  check_eq(plan.sources,expected,"independent complete set including both seam neighbors")
 check(not TerrainGeography.plan_samples(Fixtures.selection({"side_km":128.01})).ok)
 check(not TerrainGeography.plan_samples(Fixtures.selection({"latitude":82.75,"side_km":0.5})).ok)
# Partial failed attempts are charged even when the subsequent request succeeds.
func test_retry_partial_bytes_and_cancel_during_numeric_decode() -> void:
 if not await online(): return
 importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
 var until := Time.get_ticks_msec()+45000
 var injected := false
 while candidates.is_empty() and failures.is_empty() and Time.get_ticks_msec()<until:
  fake.advance_clock(0)
  for record in fake.starts:
   if not injected and not record.head_only and record.url.ends_with(".png") and is_instance_valid(fake.nodes.get(record.id)) and fake.nodes[record.id].active:
    fake.partial(record.id,17)
    fake.respond(record.id,{"result":HTTPRequest.RESULT_CONNECTION_ERROR,"code":0,"downloaded_bytes":17})
    fake.advance_clock(1000)
    injected=true
  fake.serve_pending()
  await process_frame
 check(injected)
 check_eq(candidates.size(),1)
 if not candidates.is_empty():
  check_eq(importer.metrics.downloaded_bytes,importer.metrics.validated_source_bytes+17)
  print("RETRY_METRICS ",importer.metrics)
 var previous: PackedByteArray = importer.candidate.get("baseline",PackedByteArray()).duplicate()
 candidates.clear()
 importer.clear_cache()
 importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
 until=Time.get_ticks_msec()+45000
 var delivered := false
 while not delivered and Time.get_ticks_msec()<until:
  fake.advance_clock(0)
  for record in fake.starts:
   if not record.head_only and record.url.ends_with(".png") and is_instance_valid(fake.nodes.get(record.id)) and fake.nodes[record.id].active: delivered=true
  fake.serve_pending()
  await process_frame
 check(delivered,"an actual PNG body reaches the numeric worker")
 importer.cancel()
 while not importer.is_drained(): await pump()
 check_eq(candidates.size(),0)
 check_eq(importer.candidate.get("baseline",PackedByteArray()),previous)
 check_eq(fake.active,0)
# A retained large prior object must be charged before planning allocates its arrays.
func test_real_retained_memory_budget_and_compressed_source_limit() -> void:
 if not await online(): return
 var retained := PackedByteArray()
 retained.resize(64*1024*1024)
 importer.candidate={"retained_adversarial_fixture":retained}
 importer.download(Fixtures.selection(),Fixtures.controls(),Fixtures.metadata())
 var until := Time.get_ticks_msec()+5000
 while failures.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(not failures.is_empty())
 if not failures.is_empty(): check("memory" in failures.back()[1].to_lower())
 check_eq(candidates.size(),0)
 check_eq(importer.candidate.retained_adversarial_fixture.size(),64*1024*1024)
 check(importer.metrics.get("peak_working_bytes",0)>=96*1024*1024,"64 MiB of prior data keeps its conservative 96 MiB backing charge on refusal")
 check_lt(importer.metrics.get("peak_working_bytes",134217728),134217728)
 check(importer.metrics.get("rejected_working_bytes",0)>=134217728)
 importer.release_candidate()
 retained=PackedByteArray()
 failures.clear()
 var oversized: PackedByteArray=fake.objects.png.duplicate()
 oversized.resize(2097153)
 fake.objects.png=oversized
 importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
 until=Time.get_ticks_msec()+30000
 while failures.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(not failures.is_empty(),"compressed PNG cap refuses source")
 check_eq(candidates.size(),0)
# Deadline remains live during conversion, and metrics include partial aborted source bytes.
func test_deadline_during_conversion_and_partial_cancel_metrics() -> void:
 if not await online(): return
 var stages: Array[String]=[]
 var stop_at_conversion := func(stage: String,_fraction: float,_detail: String) -> void:
  stages.append(stage)
  if stage=="Building preview": fake.advance_clock(300000)
 importer.progress_changed.connect(stop_at_conversion)
 importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
 var until := Time.get_ticks_msec()+45000
 while failures.is_empty() and Time.get_ticks_msec()<until: await pump()
 check("Building preview" in stages,"actual conversion worker was observed")
 check(not failures.is_empty())
 while not importer.is_drained(): await pump()
 check_eq(candidates.size(),0)
 importer.progress_changed.disconnect(stop_at_conversion)
 if not await online(): return
 importer.clear_cache()
 failures.clear()
 importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
 until=Time.get_ticks_msec()+30000
 var partial_id := -1
 while partial_id<0 and Time.get_ticks_msec()<until:
  fake.advance_clock(0)
  for record in fake.starts:
   if not record.head_only and record.url.ends_with(".png") and is_instance_valid(fake.nodes.get(record.id)) and fake.nodes[record.id].active: partial_id=record.id
  if partial_id<0: fake.serve_pending()
  await process_frame
 check(partial_id>=0)
 if partial_id>=0: fake.partial(partial_id,23)
 importer.cancel()
 while not importer.is_drained(): await pump()
 check_eq(importer.metrics.get("downloaded_bytes",-1),23,"cancelled active attempt bytes stay in telemetry")
 check_eq(importer.metrics.get("active",-1),0)
 check_eq(importer.metrics.get("queued",-1),0)
 check_eq(candidates.size(),0)
 print("CANCEL_METRICS ",importer.metrics)

# A replacement must not overlap a cancelled-but-unjoined planner/decoder allocation.
func test_immediate_generation_replacement_waits_for_thread_drain() -> void:
 if not await online(): return
 var first := importer.download(Fixtures.selection({"side_km":8.0}),Fixtures.controls(),Fixtures.metadata())
 await process_frame
 await process_frame
 check(not importer.is_drained(),"real planner remains owned before restart")
 var latest := importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
 for revision in 6: latest=importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
 check(importer._workers.size()<=2,"rapid revisions retain at most one draining worker and one queued replacement")
 check(first!=latest)
 var until := Time.get_ticks_msec()+45000
 var peak_workers := 0
 while candidates.is_empty() and failures.is_empty() and Time.get_ticks_msec()<until:
  var alive := 0
  for worker in importer._workers:
   if worker.thread.is_alive(): alive+=1
  peak_workers=maxi(peak_workers,alive)
  await pump()
 check_eq(candidates.size(),1)
 if not candidates.is_empty(): check_eq(candidates[0][0],latest)
 check_eq(peak_workers,1,"new CPU allocation waits for cancelled worker join")
 check_lt(importer.metrics.get("peak_working_bytes",134217728),134217728)
 print("REPLACEMENT_METRICS ",importer.metrics," peak_workers=",peak_workers)

# A queued replacement must not start with an availability check that expired while draining.
func test_queued_start_rechecks_online_freshness() -> void:
 if not await online(): return
 importer.download(Fixtures.selection(),Fixtures.controls(),Fixtures.metadata())
 await process_frame
 await process_frame
 importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
 fake.advance_clock(60000)
 var until := Time.get_ticks_msec()+45000
 while candidates.is_empty() and failures.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(not failures.is_empty(),"freshness required again at actual queued start")
 check_eq(candidates.size(),0)

# A malformed source cancels siblings, charging their received partial bytes too.
func test_failure_charges_partial_sibling_requests() -> void:
 if not await online(): return
 importer.download(Fixtures.selection({"side_km":0.5,"longitude":-115.13671875}),Fixtures.controls(),Fixtures.metadata())
 var until := Time.get_ticks_msec()+30000
 var pending: Array[int]=[]
 while pending.size()<2 and Time.get_ticks_msec()<until:
  fake.advance_clock(0)
  pending.clear()
  for record in fake.starts:
   if not record.head_only and record.url.ends_with(".png") and is_instance_valid(fake.nodes.get(record.id)) and fake.nodes[record.id].active: pending.append(record.id)
  if pending.size()<2: fake.serve_pending()
  await process_frame
 check_eq(pending.size(),2)
 if pending.size()==2:
  fake.partial(pending[1],31)
  fake.respond(pending[0],{"code":404,"body":PackedByteArray([1,2,3])})
 while not importer.is_drained(): await process_frame
 check_eq(candidates.size(),0)
 check(not failures.is_empty())
 check_eq(importer.metrics.get("downloaded_bytes",-1),34)
 check_eq(importer.metrics.get("active",-1),0)
 check_eq(importer.metrics.get("queued",-1),0)
 print("FAILURE_METRICS ",importer.metrics)

# Explicit Fit must execute on a worker, return real source-derived E, and obey revisions.
func test_async_fit_relief_uses_source_and_rejects_cancelled_publication() -> void:
 check(importer.has_method("fit_relief"),"asynchronous Fit entry exists")
 if not importer.has_method("fit_relief"): return
 if not await online(): return
 fake.install_ramp_png()
 importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls({"exaggeration":0.02}),Fixtures.metadata())
 var until := Time.get_ticks_msec()+45000
 while candidates.is_empty() and failures.is_empty() and Time.get_ticks_msec()<until: await pump()
 check_eq(candidates.size(),1)
 if candidates.is_empty(): return
 var previous: PackedByteArray=importer.candidate.baseline.duplicate()
 var diagnostics: Dictionary=importer.candidate.diagnostics
 # All-dry fixture: the expected multiplier follows the 28-level span formula;
 # water-aware fitting is tested separately.
 var expected := clampf(28.0*(500.0/128.0)*CityGeometry3D.HEIGHT/(diagnostics.source_max_metres-diagnostics.source_min_metres),0.001,20.0)
 check(expected<1.0,"fixture demands a nontrivial fitted multiplier")
 var fitted: Array=[]
 importer.connect("relief_fitted",func(g: int,result: Dictionary) -> void: fitted.append([g,result]))
 var generation: int=importer.call("fit_relief",Fixtures.controls({"exaggeration":20.0}))
 check(fitted.is_empty(),"Fit never runs synchronously in the UI caller")
 check(not importer.is_ready())
 var observed_worker := false
 while not importer.is_drained():
  for worker in importer._workers:
   if worker.kind=="fit" and worker.thread.is_alive(): observed_worker=true
  await pump()
 check(observed_worker,"actual Fit helper ran off-tree")
 check_eq(fitted.size(),1)
 if not fitted.is_empty():
  check_eq(fitted[0][0],generation)
  check(absf(fitted[0][1].exaggeration-expected)<0.000000001)
  check_eq(fitted[0][1].remaining_clipping,0)
 check_eq(importer.candidate.baseline,previous,"Fit alone leaves prior completed candidate intact")
 fitted.clear()
 importer.call("fit_relief",Fixtures.controls({"exaggeration":20.0}))
 importer.invalidate_settings()
 while not importer.is_drained(): await pump()
 check_eq(fitted.size(),0)
 check_eq(importer.candidate.baseline,previous)
 fake.advance_clock(60000)
 importer.call("fit_relief",Fixtures.controls())
 check(not failures.is_empty(),"Fit has the same online gate as rebuild")
 print("FIT_EXPECTED ",expected)

# Optional normalization worklists must refuse growth/copies before their owned byte cap.
func test_guarded_normalization_and_conversion_budget_exhaustion() -> void:
 var surface := TerrainSurface.new()
 var args := 0
 for method in surface.get_method_list():
  if method.name=="normalize": args=method.args.size()
 check(args>=3,"normalization accepts optional worklist budget")
 if args<3: return
 check(TerrainSurface.NormalizationWorkBudget.allocation_bytes(65536)>=65536*100+128,"capacity bound covers 40-byte Variant and 1.5x growth plus old buffer")
 for mode in ["seed","copy","growth"]:
  surface=TerrainSurface.new()
  surface.vertices.fill(8)
  if mode=="growth":
   for y in 129:
    for x in 129: surface.vertices[y*129+x]=30 if (x+y)%2 else 2
  var limit := 1024 if mode=="seed" else 6*1024*1024
  var result: Dictionary=surface.call("normalize",Rect2i(),{},limit)
  check(not result.converged,mode+" resource guard rejects")
  check_eq(result.get("resource_error",""),"terrain_worklist_budget_exceeded")
  check(result.get("worklist_peak_bytes",-1)<=limit)
  check(result.get("worklist_required_bytes",0)>limit)
  if mode=="growth": check(result.get("worklist_queue_items",0)>16641,"actual relaxation growth is charged before copy")
  print("WORKLIST_GUARD ",mode," ",result)
 var converter := RealWorldTerrain.new()
 args=0
 for method in converter.get_method_list():
  if method.name=="convert": args=method.args.size()
 check(args>=5,"conversion propagates optional resource budget")
 if args<5: return
 var failed_conversion: Dictionary=converter.call("convert",Fixtures.packet(),Fixtures.controls(),Fixtures.metadata(),Callable(),1024)
 check(not failed_conversion.ok)
 check_eq(failed_conversion.error,"terrain_worklist_budget_exceeded")
 check(not failed_conversion.has("city"),"resource failure never carries partial City")
 var plain := TerrainSurface.new()
 plain.vertices.fill(8)
 var bounded := plain.duplicate_surface()
 var ordinary := plain.normalize()
 var admitted: Dictionary=bounded.call("normalize",Rect2i(),{},16777216)
 check(ordinary.converged and admitted.converged)
 check_eq(plain.vertices,bounded.vertices)
 check_eq(plain.water,bounded.water)
 check(not ordinary.has("worklist_peak_bytes"),"default return shape stays exact")

# Error callbacks can reset the UI or start a replacement before failed is emitted.
func test_error_callback_invalidates_entry_and_worker_failures() -> void:
 for action in ["invalidate_settings","suspend"]:
  var reset := func(stage: String,_fraction: float,_detail: String) -> void:
   if stage=="Error": importer.call(action)
  importer.progress_changed.connect(reset)
  importer.download(Fixtures.selection(),Fixtures.controls(),Fixtures.metadata())
  importer.progress_changed.disconnect(reset)
  check_eq(failures.size(),0,"entry Error callback invalidation suppresses stale failed")
  failures.clear()
 importer.set_visible(true)
 if not await online(): return
 fake.install_flat_objects(0)
 var state := {"replaced":false,"generation":-1}
 var replace := func(stage: String,_fraction: float,_detail: String) -> void:
  if stage=="Error" and not state.replaced:
   state.replaced=true
   fake.install_flat_objects()
   state.generation=importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
 importer.progress_changed.connect(replace)
 importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
 var until := Time.get_ticks_msec()+45000
 while candidates.is_empty() and Time.get_ticks_msec()<until: await pump()
 importer.progress_changed.disconnect(replace)
 check(state.replaced,"real unknown-class worker error invokes replacement callback")
 check_eq(failures.size(),0,"superseded worker failure stays suppressed")
 check_eq(candidates.size(),1)
 if not candidates.is_empty(): check_eq(candidates[0][0],state.generation)

func test_untouched_deadline_has_exactly_one_terminal_failure() -> void:
 if not await online(): return
 var generation := importer.download(Fixtures.selection(),Fixtures.controls(),Fixtures.metadata())
 fake.advance_clock(300000)
 for frame in 12: await pump()
 while not importer.is_drained(): await pump()
 check_eq(failures.size(),1,"deadline intentionally advances generation but still emits once")
 if not failures.is_empty(): check_eq(failures[0][0],generation)
 check_eq(candidates.size(),0)

# Actual append-backed packed data must fit the advertised retained/growth envelope.
func test_single_block_packed_capacity_and_grouping_envelope() -> void:
 var appended := PackedInt32Array()
 for i in 3145728: appended.append(i)
 check(RealWorldImporter.owned_bytes(appended)>=14173220+64,"real single-block int32 retained native capacity exceeds logical payload")
 appended=PackedInt32Array()
 var bytes := PackedByteArray()
 var ints := PackedInt64Array()
 var floats := PackedFloat32Array()
 var doubles := PackedFloat64Array()
 for i in 1000:
  bytes.append(i%256); ints.append(i); floats.append(i); doubles.append(i)
 # Godot 4.6 grows a packed array to a capacity of 1065 after 1000 appends.
 check(RealWorldImporter.owned_bytes(bytes)>=1065+64,"byte backing capacity")
 check(RealWorldImporter.owned_bytes(ints)>=1065*8+64,"int64 backing capacity")
 check(RealWorldImporter.owned_bytes(floats)>=1065*4+64,"float32 backing capacity")
 check(RealWorldImporter.owned_bytes(doubles)>=1065*8+64,"float64 backing capacity")
 if not await online(): return
 importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
 var until := Time.get_ticks_msec()+45000
 while candidates.is_empty() and failures.is_empty() and Time.get_ticks_msec()<until: await pump()
 check_eq(candidates.size(),1)
 check_eq(importer.metrics.get("grouping_items",0),3145728)
 check_eq(importer.metrics.get("grouping_max_block_items",0),3145728)
 check(importer.metrics.get("grouping_reserved_bytes",0)>=23622032+512,"grouping envelope covers old/new native buffers before append")
 check(importer.metrics.get("grouping_retained_bytes",0)>=14173220+64,"retained group backing remains charged after planning release")
 check_lt(importer.metrics.get("peak_working_bytes",134217728),134217728)
 if not candidates.is_empty():
  var hash := HashingContext.new()
  hash.start(HashingContext.HASH_SHA256)
  hash.update(importer.candidate.baseline)
  print("SINGLE_BLOCK_BASELINE ",hash.finish().hex_encode())
 print("PACKED_METRICS ",importer.metrics)

# Planning fits, but its actual retained packet plus new group growth must refuse.
func test_grouping_refuses_before_append_when_session_owns_headroom() -> void:
 if not await online(): return
 var retained := PackedByteArray()
 retained.resize(30*1024*1024)
 importer.candidate={"retained_adversarial_fixture":retained}
 importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
 var until := Time.get_ticks_msec()+45000
 while failures.is_empty() and candidates.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(not failures.is_empty(),"real retained session leaves insufficient grouping relocation allowance")
 check_eq(candidates.size(),0)
 check_eq(importer.metrics.get("water_samples",0),1048576,"real planning completed before refusal")
 check_eq(importer.metrics.get("grouping_items",-1),0,"refuse reservation before first packed group append")
 check_eq(importer.metrics.get("downloaded_bytes",-1),0)
 check(importer.metrics.get("rejected_working_bytes",0)>=134217728)
 check_lt(importer.metrics.get("peak_working_bytes",134217728),134217728)
 check_eq(importer.candidate.get("retained_adversarial_fixture",PackedByteArray()).size(),30*1024*1024)
 print("GROUP_REFUSAL_METRICS ",importer.metrics)

func test_probe_errors_name_elevation_water_or_both_and_retain_detail() -> void:
 var messages: Array=[]
 importer.availability_changed.connect(func(status: String,detail: String) -> void: messages.append([status,detail]))
 for denied in [[true,false],[false,true],[true,true]]:
  fake.deny_elevation_probe=denied[0];fake.deny_water_probe=denied[1]
  importer.check_online(true)
  for i in 12: await pump()
  check(not importer.is_online_fresh())
  var detail: String=messages.back()[1]
  check(detail.contains("Elevation service unavailable") if denied[0] else not detail.contains("Elevation service unavailable"),detail)
  check(detail.contains("Water service unavailable") if denied[1] else not detail.contains("Water service unavailable"),detail)
  check(detail.contains("HTTP 404"),"service failure retains bounded transport detail: "+detail)
 fake.deny_elevation_probe=false;fake.deny_water_probe=false
 check(await online())
 check_eq(messages.back()[0],"Online")

func test_repeated_probe_download_and_cancel_generations_retire_after_worker_join() -> void:
 for cycle in 20:
  if not await online(): return
  var generation := importer.download(Fixtures.selection({"side_km":0.5}),Fixtures.controls(),Fixtures.metadata())
  var until := Time.get_ticks_msec()+30000
  await pump()
  for work in importer._workers:
   check(transport._generations.has(work.generation),"CPU owner retains its generation")
   check_eq(transport._generations[work.generation].consumers,1)
   check(not transport.retire_generation(work.generation),"no retirement before consumer joins")
  if cycle%2==0: importer.cancel()
  while not importer.is_drained() and Time.get_ticks_msec()<until: await pump()
  check(importer.is_drained())
  await pump()
  check(transport._generations.is_empty(),"completed/canceled probes and downloads release descriptor state")
  check(transport._recent_generations.size()<=8)
  var recent := transport.get_generation_metrics(generation)
  check(recent.get("retired",false))
  if cycle%2==1:
   check(not candidates.is_empty(),"completed real download is published")
   check_eq(candidates.back()[0],generation)
  var delivered := candidates.size()
  importer._completed(-1,generation,{"ok":true,"body":fake.objects.png})
  check_eq(candidates.size(),delivered,"late retired result has no owner")
 print("BROKER_HISTORY live=",transport._generations.size()," recent=",transport._recent_generations.size()," candidates=",candidates.size())
# ESA omits open-ocean cells. A HEAD 404 for one of them is all water; 403 stays fatal.
func test_unpublished_worldcover_cell_is_open_water() -> void:
 if not await online(): return
 var crossing := Fixtures.selection({"side_km":0.5,"longitude":-114.0})
 fake.water_tile_status={"N36W114":404}
 importer.download(crossing,Fixtures.controls(),Fixtures.metadata())
 var until := Time.get_ticks_msec()+45000
 while candidates.is_empty() and failures.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(not candidates.is_empty(),"absent ocean cell does not abort acquisition: "+str(failures))
 if candidates.is_empty(): return
 var sources: Array = importer.candidate.origin.sources
 check(sources.has({"source":"worldcover","tile":"N36W117"}),"present land cell keeps provenance")
 check(not sources.has({"source":"worldcover","tile":"N36W114"}),"absent cell contributes no source object")
 check_eq(importer.candidate.origin.source_objects.size(),sources.size())
 var water: PackedByteArray = importer._packet.water_counts
 var west_wet := 0
 var east_wet := 0
 for y in 128:
  for x in 128:
   if x<62: west_wet+=water[y*128+x]
   elif x>=66: east_wet+=water[y*128+x]
 check_eq(west_wet,0,"published class-60 cell stays dry")
 check_eq(east_wet,128*62*64,"every absent-cell sample is class 80")
 check(not fake.starts.any(func(r: Dictionary) -> bool: return not r.head_only and r.url.contains("_N36W114_")),"absent cell fetches no index or block ranges")
 failures.clear()
 candidates.clear()
 fake.water_tile_status={"N36W114":403}
 importer.download(crossing,Fixtures.controls(),Fixtures.metadata())
 until=Time.get_ticks_msec()+45000
 while candidates.is_empty() and failures.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(not failures.is_empty(),"forbidden water cell remains a service failure")
 check_eq(candidates.size(),0)
# Pipelined WorldCover block requests stay bounded and arrival-order independent.
func test_pipelined_water_blocks_are_order_independent() -> void:
 if not await online(): return
 var wide := Fixtures.selection({"side_km":8.0,"longitude":-115.13671875})
 var outcomes: Array[PackedByteArray] = []
 for reverse in [false,true]:
  fake.reverse_responses=reverse
  importer.clear_cache()
  candidates.clear()
  failures.clear()
  importer.download(wide,Fixtures.controls(),Fixtures.metadata())
  var until := Time.get_ticks_msec()+90000
  while candidates.is_empty() and failures.is_empty() and Time.get_ticks_msec()<until: await pump()
  check(not candidates.is_empty(),"multi-block acquisition completes: "+str(failures))
  if candidates.is_empty(): return
  check(importer.metrics.water_blocks>=2,"selection spans several source blocks")
  check_eq(importer.metrics.peak_decoded_water_blocks,1)
  outcomes.append(importer._packet.water_counts.duplicate())
 check(fake.peak_active<=4,"transport keeps its four-request ceiling")
 check_eq(outcomes[0],outcomes[1])
