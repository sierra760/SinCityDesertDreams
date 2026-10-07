# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const Fake = preload("res://tests/real_world/fake_terrain_transport.gd")
const Fixtures = preload("res://tests/real_world/terrain_source_fixtures.gd")
const WATER = {"source":"worldcover","tile":"N36W117"}
const ELEVATION = {"source":"terrarium","z":10,"x":184,"y":401}
const IDENTITY = {"etag":"\"v1\"","size":100}
const SPAN = {"offset":10,"length":4}
var fake: RefCounted
var transport: TerrainHttpTransport
var results := {}
func before_each() -> void:
 fake=Fake.new()
 transport=fake.make_transport()
 root.add_child(transport)
 transport.completed.connect(func(id: int, _generation: int, result: Dictionary) -> void: results[id]=result)
 results.clear()
func after_each() -> void:
 transport.shutdown()
 transport.queue_free()
 await process_frame
 await process_frame
 fake=null
func deliver(id: int, overrides: Dictionary = {}) -> void:
 var response := {"code":206,"headers":["ETag: \"v1\"","Content-Range: bytes 10-13/100","Content-Length: 4"],"body":PackedByteArray([1,2,3,4])}
 response.merge(overrides,true)
 fake.respond(id,response)
func expect_result(id: int) -> Dictionary:
 check(results.has(id),"request must finish through production scheduler")
 return results.get(id,{"ok":false,"error":"Missing completion","downloaded_bytes":-1})
# A missing concurrency cap, excess retries or timeouts breaks this test.
func test_max_four_timeout_retry_and_429() -> void:
 var ids: Array[int] = []
 for i in 6: ids.append(transport.enqueue(WATER,SPAN,1,IDENTITY))
 await process_frame
 await process_frame
 check_eq(fake.active,4)
 check(fake.peak_active<=4)
 deliver(ids[0],{"result":HTTPRequest.RESULT_CONNECTION_ERROR,"code":0,"body":PackedByteArray([9,9])})
 for id in ids.slice(1,4): deliver(id)
 fake.advance_clock(999)
 for id in ids.slice(4): deliver(id)
 check_eq(fake.attempts_for(ids[0]),1)
 fake.advance_clock(1)
 check_eq(fake.attempts_for(ids[0]),2)
 deliver(ids[0],{"code":503,"body":PackedByteArray([9])})
 fake.advance_clock(2000)
 check_eq(fake.attempts_for(ids[0]),3)
 deliver(ids[0],{"code":503,"body":PackedByteArray([9])})
 check(not expect_result(ids[0]).ok)
 check_eq(expect_result(ids[0]).downloaded_bytes,4)
 var rate := transport.enqueue(WATER,SPAN,2,IDENTITY)
 for id in ids.slice(1): deliver(id)
 await process_frame
 await process_frame
 deliver(rate,{"code":429,"headers":["Retry-After: 3"],"body":PackedByteArray()})
 fake.advance_clock(2999)
 check_eq(fake.attempts_for(rate),1)
 fake.advance_clock(1)
 check_eq(fake.attempts_for(rate),2)
 deliver(rate)
 check(expect_result(rate).ok)
 var timeout := transport.enqueue(WATER,{"offset":0,"length":100},3,IDENTITY)
 await process_frame
 await process_frame
 fake.partial(timeout,17)
 fake.advance_clock(20000)
 fake.advance_clock(1000)
 check_eq(fake.attempts_for(timeout),2)
 var timeout_body := PackedByteArray()
 timeout_body.resize(100)
 timeout_body.fill(1)
 deliver(timeout,{"headers":["ETag: \"v1\"","Content-Range: bytes 0-99/100","Content-Length: 100"],"body":timeout_body})
 check(expect_result(timeout).ok)
 check_eq(expect_result(timeout).downloaded_bytes,117)
# Accepting an ignored range, wrong object or transformed bytes breaks this test.
func test_range_requires_206_identity_and_exact_bounds() -> void:
 for overrides in [{"code":200},{"headers":["ETag: \"v1\"","Content-Range: bytes 11-14/100"]},{"headers":["ETag: \"v2\"","Content-Range: bytes 10-13/100"]},{"headers":["ETag: \"v1\"","Content-Range: bytes 10-13/101"]},{"headers":["ETag: \"v1\"","Content-Range: bytes 10-13/100","Content-Encoding: gzip"]},{"body":PackedByteArray([1,2,3])},{"code":404}]:
  var id := transport.enqueue(WATER,SPAN,4,IDENTITY)
  await process_frame
  await process_frame
  deliver(id,overrides)
  check(not expect_result(id).ok)
  check_eq(fake.attempts_for(id),1,"invalid data/404 never retries")
 var good := transport.enqueue(WATER,SPAN,4,IDENTITY)
 await process_frame
 await process_frame
 deliver(good)
 check(expect_result(good).ok)
 if not fake.starts.is_empty():
  check("Range: bytes=10-13" in fake.starts.back().headers)
  check("If-Match: \"v1\"" in fake.starts.back().headers)
  check("Accept-Encoding: identity" in fake.starts.back().headers)
 var head := transport.enqueue(WATER,{},4,{},true)
 await process_frame
 await process_frame
 fake.respond(head,{"headers":["ETag: \"probe\"","Content-Length: 100"]})
 var probe := expect_result(head)
 check(probe.ok)
 if probe.ok: check_eq(probe.size,100)
# Descriptor injection, redirect following, oversized/corrupt bodies must fail.
func test_redirect_host_and_body_caps() -> void:
 var invalid := transport.enqueue({"source":"worldcover","tile":"N36W117","url":"https://evil.example"},SPAN,5,IDENTITY)
 await process_frame
 await process_frame
 check(not expect_result(invalid).ok)
 check_eq(fake.attempts_for(invalid),0)
 for override in [{"code":302,"headers":["Location: https://evil.example"]},{"downloaded_bytes":2097153},{"result":HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED}]:
  var id := transport.enqueue(WATER,SPAN,5,IDENTITY)
  await process_frame
  await process_frame
  deliver(id,override)
  check(not expect_result(id).ok)
  check_eq(fake.attempts_for(id),1)
 var corrupt := transport.enqueue(ELEVATION,{},6)
 await process_frame
 await process_frame
 fake.respond(corrupt,{"headers":["ETag: \"png\"","Content-Length: 4"],"body":PackedByteArray([1,2,3,4])})
 check(not expect_result(corrupt).ok)
 check_eq(fake.attempts_for(corrupt),1)
 var valid := transport.enqueue(ELEVATION,{},6)
 await process_frame
 await process_frame
 var png := Fixtures.terrarium_png(Vector3i(128,10,0))
 fake.respond(valid,{"headers":["ETag: \"png\"","Content-Length: %d"%png.size()],"body":png})
 check(expect_result(valid).ok)
 if not fake.starts.is_empty():
  var settings: Dictionary = fake.starts.back().settings
  check_eq(settings.max_redirects,0)
  check_eq(settings.accept_gzip,false)
  check_eq(settings.body_size_limit,2097152)
  check(settings.timeout<=20.0)
  check_eq(fake.starts.back().url,"https://elevation-tiles-prod.s3.amazonaws.com/terrarium/10/184/401.png")
func test_cancel_removes_queued_and_active() -> void:
 var ids: Array[int] = []
 for i in 6: ids.append(transport.enqueue(WATER,{"offset":0,"length":100},7,IDENTITY))
 await process_frame
 await process_frame
 fake.partial(ids[0],23)
 transport.cancel_generation(7)
 check_eq(fake.active_after_cancel,0)
 check_eq(fake.cancel_count,4)
 for id in ids: check(not expect_result(id).ok)
 check_eq(expect_result(ids[0]).downloaded_bytes,23)
 fake.advance_clock(100000)
 check_eq(fake.starts.size(),4,"cancelled queue never starts")
func test_operation_deadline_counts_planning_backoff_and_partial_bytes() -> void:
 transport.set_generation_deadline(8,500)
 var id := transport.enqueue(WATER,{"offset":0,"length":100},8,IDENTITY)
 await process_frame
 await process_frame
 fake.partial(id,31)
 fake.advance_clock(500)
 check(not expect_result(id).ok)
 check_eq(expect_result(id).downloaded_bytes,31)
 transport.set_generation_deadline(9,fake.now+2000)
 var rate := transport.enqueue(WATER,SPAN,9,IDENTITY)
 await process_frame
 await process_frame
 deliver(rate,{"code":429,"headers":["Retry-After: 3"]})
 check(not expect_result(rate).ok,"backoff cannot outlive operation")
 var maximum := transport.enqueue(WATER,SPAN,10,IDENTITY)
 await process_frame
 await process_frame
 fake.advance_clock(300000)
 check(not expect_result(maximum).ok)
 check_eq(fake.attempts_for(maximum),1)
func test_generation_budget_counts_failed_attempts_and_bounds_queue() -> void:
 var ids: Array[int] = []
 for i in 4: ids.append(transport.enqueue(WATER,SPAN,11,IDENTITY))
 await process_frame
 await process_frame
 for id in ids: fake.partial(id,16777217)
 fake.advance_clock(1)
 for id in ids: check(not expect_result(id).ok)
 check_eq(fake.active,0)
 var bad_span := transport.enqueue(WATER,{"offset":9223372036854775800,"length":100},12,IDENTITY)
 await process_frame
 await process_frame
 check(not expect_result(bad_span).ok)
 check_eq(fake.attempts_for(bad_span),0)

func test_reserves_native_chunk_margin_before_starting_concurrent_requests() -> void:
 var body := PackedByteArray()
 body.resize(2097152)
 var identity := {"etag":"\"v1\"","size":2097152}
 for i in 31:
  var id := transport.enqueue(WATER,{"offset":0,"length":2097152},20,identity)
  fake.advance_clock(0)
  fake.respond(id,{"code":206,"headers":["ETag: \"v1\"","Content-Range: bytes 0-2097151/2097152"],"body":body})
  check(expect_result(id).ok)
 var first := transport.enqueue(WATER,{"offset":0,"length":1048576},20,identity)
 var second := transport.enqueue(WATER,{"offset":0,"length":1048576},20,identity)
 fake.advance_clock(0)
 check_eq(fake.active,1,"reserve possible final native read chunk before simultaneous requests")
 fake.partial(first,1052672)
 fake.advance_clock(0)
 check(not expect_result(first).ok)
 check(not expect_result(second).ok,"remaining received-byte allowance insufficient")
 check_eq(fake.attempts_for(second),0)
 var metrics := transport.get_generation_metrics(20)
 check_eq(metrics.downloaded_bytes,66064384)
 check(metrics.downloaded_bytes<=67108864)
 check_eq(metrics.active,0)
 check_eq(metrics.queued,0)
func test_http_date_retry_and_probe_failures() -> void:
 var date := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system())+5)
 var date_header := "%s, %02d %s %04d %02d:%02d:%02d GMT"%[["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][date.weekday],date.day,["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][date.month-1],date.year,date.hour,date.minute,date.second]
 var id := transport.enqueue(WATER,SPAN,21,IDENTITY)
 fake.advance_clock(0)
 deliver(id,{"code":429,"headers":["Retry-After: "+date_header],"body":PackedByteArray()})
 fake.advance_clock(1000)
 check_eq(fake.attempts_for(id),1,"future HTTP date must delay retry")
 fake.advance_clock(5000)
 check_eq(fake.attempts_for(id),2)
 deliver(id)
 check(expect_result(id).ok)
 for response in [{"code":404,"headers":["ETag: \"v1\"","Content-Length: 100"]},{"headers":["Content-Length: 100"]},{"headers":["ETag: \"v1\"","Content-Length: 0"]},{"headers":["ETag: \"v1\"","Content-Length: 100","Content-Length: 101"]}]:
  var head := transport.enqueue(WATER,{},22,{},true)
  fake.advance_clock(0)
  fake.respond(head,response)
  check(not expect_result(head).ok)
  check_eq(fake.attempts_for(head),1)
func test_pending_queue_and_elevation_caps_and_deadline_clamp() -> void:
 for i in 65:
  var id := transport.enqueue({"source":"terrarium","z":10,"x":i,"y":401},{},23)
  if i==64:
   await process_frame
   check(not expect_result(id).ok,"65th elevation descriptor is refused")
 transport.cancel_generation(23)
 for i in 1025:
  var id := transport.enqueue(WATER,SPAN,24,IDENTITY)
  if i==1024:
   await process_frame
   check(not expect_result(id).ok,"pending queue is bounded")
 transport.cancel_generation(24)
 transport.set_generation_deadline(25,fake.now+999999)
 check_eq(transport.get_generation_metrics(25).deadline_ms,fake.now+300000)
 transport.set_generation_deadline(25,fake.now+200)
 transport.set_generation_deadline(25,fake.now+500)
 check_eq(transport.get_generation_metrics(25).deadline_ms,fake.now+200,"deadline cannot be extended")

func test_pinned_full_png_reserves_known_size_and_rejects_changed_length() -> void:
 var png := Fixtures.terrarium_png(Vector3i(128,10,0))
 var pinned := {"etag":"\"png\"","size":png.size()}
 var id := transport.enqueue(ELEVATION,{},26,pinned)
 fake.advance_clock(0)
 check_eq(fake.starts.back().settings.body_size_limit,png.size(),"known HEAD size bounds native PNG allocation")
 fake.respond(id,{"headers":["ETag: \"png\"","Content-Length: %d"%png.size()],"body":png})
 check(expect_result(id).ok)
 var changed := transport.enqueue(ELEVATION,{},26,{"etag":"\"png\"","size":png.size()+1})
 fake.advance_clock(0)
 fake.respond(changed,{"headers":["ETag: \"png\"","Content-Length: %d"%png.size()],"body":png})
 check(not expect_result(changed).ok)
 check_eq(fake.attempts_for(changed),1)

func test_explicit_retirement_bounds_history_after_requests_and_consumers_drain() -> void:
 check(transport.has_method("retain_generation") and transport.has_method("retire_generation"),"transport needs explicit consumer-safe retirement")
 if not transport.has_method("retire_generation"): return
 for generation in range(100,132):
  check(transport.call("retain_generation",generation))
  var id := transport.enqueue(WATER,{"offset":0,"length":100},generation,IDENTITY)
  fake.advance_clock(0)
  fake.partial(id,23)
  check(not transport.call("retire_generation",generation),"pending actual bytes cannot be retired")
  var expected := 23
  if generation%2==0:
   transport.cancel_generation(generation)
  else:
   var body := PackedByteArray()
   body.resize(100)
   fake.respond(id,{"code":206,"headers":["ETag: \"v1\"","Content-Range: bytes 0-99/100","Content-Length: 100"],"body":body})
   expected=100
  check_eq(expect_result(id).downloaded_bytes,expected)
  check(not transport.call("retire_generation",generation),"drained requests still have an active CPU consumer")
  transport.call("release_generation",generation)
  check(transport.call("retire_generation",generation))
  check_eq(transport.get_generation_metrics(generation).downloaded_bytes,expected,"retirement preserves actual partial telemetry")
  check(transport._generations.size()<=1,"historical descriptors are released")
  check(transport.get("_recent_generations").size()<=8,"recent telemetry has a fixed bound")
 var starts: int=fake.starts.size()
 var stale := transport.enqueue(WATER,SPAN,100,IDENTITY)
 await process_frame
 check(not expect_result(stale).ok)
 check_eq(fake.starts.size(),starts,"old callbacks/enqueues never resurrect retired work")
 check(transport._generations.is_empty())
 # A retained older worker remains live when a newer generation retires first.
 check(transport.call("retain_generation",200))
 transport.set_generation_deadline(201,fake.now+10000)
 check(transport.call("retire_generation",201))
 var retry := transport.enqueue(WATER,SPAN,200,IDENTITY)
 fake.advance_clock(0)
 deliver(retry,{"result":HTTPRequest.RESULT_CONNECTION_ERROR,"code":0,"body":PackedByteArray([9,9])})
 fake.advance_clock(1000)
 deliver(retry)
 check(expect_result(retry).ok)
 check_eq(expect_result(retry).downloaded_bytes,6)
 transport.call("release_generation",200)
 check(transport.call("retire_generation",200))
 check_eq(transport.get_generation_metrics(200).downloaded_bytes,6,"retry bytes survive retirement")
 print("RETIRED_METRICS ",transport.get_generation_metrics(200)," recent ",transport.get("_recent_generations").size())
# Only a WorldCover HEAD 404 marks an unpublished ocean cell; it still fails closed.
func test_worldcover_head_404_is_marked_absent_only_for_water_heads() -> void:
 var water_head := transport.enqueue({"source":"worldcover","tile":"S36E015"},{},1,{},true)
 var forbidden := transport.enqueue({"source":"worldcover","tile":"S36E018"},{},1,{},true)
 var elevation_head := transport.enqueue(ELEVATION,{},1,{},true)
 var range_missing := transport.enqueue(WATER,SPAN,1,IDENTITY)
 await process_frame
 await process_frame
 for id in [water_head,elevation_head,range_missing]: fake.respond(id,{"code":404})
 fake.respond(forbidden,{"code":403})
 var absent := expect_result(water_head)
 check(not absent.ok,"absent water object is never a successful pinned identity")
 check_eq(absent.get("absent",false),true,"WorldCover HEAD 404 is marked absent")
 for id in [forbidden,elevation_head,range_missing]:
  var failed := expect_result(id)
  check(not failed.ok)
  check(not failed.has("absent"),"403, elevation and pinned-range 404s stay ordinary failures")
