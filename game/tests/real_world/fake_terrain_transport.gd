# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends RefCounted
# Stands in for the HTTP backend and clock only; every validator is the
# production one.
class Backend extends Node:
 signal finished(result: int, code: int, headers: PackedStringArray, body: PackedByteArray)
 var owner_controller: RefCounted
 var request_id := 0
 var downloaded := 0
 var active := false
 func start(url: String, headers: PackedStringArray, head_only: bool, settings: Dictionary) -> int:
  request_id=settings.request_id
  active=true
  owner_controller.nodes[request_id]=self
  owner_controller.attempts[request_id]=owner_controller.attempts.get(request_id,0)+1
  owner_controller.starts.append({"id":request_id,"url":url,"headers":headers,"head_only":head_only,"settings":settings.duplicate(true)})
  owner_controller.active+=1
  owner_controller.peak_active=maxi(owner_controller.peak_active,owner_controller.active)
  return OK
 func abort() -> void:
  if active:
   active=false
   owner_controller.active-=1
   owner_controller.cancel_count+=1
 func get_downloaded_bytes() -> int: return downloaded
var transport: TerrainHttpTransport
var nodes := {}
var attempts := {}
var starts: Array[Dictionary] = []
var now := 0
var active := 0
var peak_active := 0
var cancel_count := 0
var active_after_cancel: int:
 get: return active
func _factory() -> Node:
 var backend := Backend.new()
 backend.owner_controller=self
 return backend
func make_transport() -> TerrainHttpTransport:
 transport=TerrainHttpTransport.new()
 transport.set_request_factory(_factory)
 transport.set_clock(func() -> int: return now)
 return transport
func respond(request_id: int, response: Dictionary) -> void:
 if not nodes.has(request_id) or not is_instance_valid(nodes[request_id]): return
 var backend: Backend = nodes[request_id]
 if not backend.active: return
 var body: PackedByteArray = response.get("body",PackedByteArray())
 backend.downloaded=int(response.get("downloaded_bytes",body.size()))
 backend.active=false
 active-=1
 backend.finished.emit(response.get("result",HTTPRequest.RESULT_SUCCESS),response.get("code",200),PackedStringArray(response.get("headers",[])),body)
func partial(request_id: int, bytes: int) -> void:
 if nodes.has(request_id) and is_instance_valid(nodes[request_id]): nodes[request_id].downloaded=bytes
func advance_clock(milliseconds: int) -> void:
 now+=milliseconds
 if is_instance_valid(transport): transport._process(0.0)
func attempts_for(request_id: int) -> int: return attempts.get(request_id,0)

# Scripted public-object fixtures still traverse production HTTP validators.
var objects := {}
var reverse_responses := false
var deny_water_probe := false
var deny_elevation_probe := false
var response_bytes := 0
# WorldCover tile tokens answered with a status code instead of an object.
var water_tile_status := {}
func install_flat_objects(water_class: int = 60, wrong_origin: bool = false) -> void:
 var fixtures = preload("res://tests/real_world/terrain_source_fixtures.gd")
 var raw := PackedByteArray()
 raw.resize(1024*1024)
 raw.fill(water_class)
 var block := raw.compress(FileAccess.COMPRESSION_DEFLATE)
 var tiff: Dictionary = fixtures.worldcover_tiff(true,{"block_count":block.size(),"tie":[0.0,0.0,0.0,-114.0 if wrong_origin else -117.0,39.0,0.0]})
 var body: PackedByteArray = tiff.body
 body.resize(100000)
 body.append_array(block)
 objects={"png":fixtures.terrarium_png(Vector3i(128,100,0)),"tiff":body,"etag":"\"fixture-v1\""}
func serve_pending() -> void:
 var pending: Array = nodes.keys()
 pending.sort()
 if reverse_responses: pending.reverse()
 for id in pending:
  if not is_instance_valid(nodes[id]) or not nodes[id].active: continue
  var start: Dictionary = {}
  for record in starts:
   if record.id==id: start=record
  if start.is_empty(): continue
  var water: bool = start.url.ends_with(".tif")
  var status := 0
  for tile in water_tile_status:
   if water and start.url.contains("_%s_"%tile): status=water_tile_status[tile]
  if status!=0:
   respond(id,{"code":status})
   continue
  if start.head_only and (deny_water_probe if water else deny_elevation_probe):
   respond(id,{"code":404})
   continue
  var body: PackedByteArray = objects.tiff if water else objects.png
  var headers: Array = ["ETag: "+objects.etag,"Content-Length: "+str(body.size())]
  var code := 200
  var payload := PackedByteArray() if start.head_only else body
  for header in start.headers:
   if header.begins_with("Range: bytes="):
    var limits: PackedStringArray = header.trim_prefix("Range: bytes=").split("-")
    var lo := int(limits[0])
    var hi := int(limits[1])
    payload=body.slice(lo,hi+1)
    headers=["ETag: "+objects.etag,"Content-Length: "+str(payload.size()),"Content-Range: bytes %d-%d/%d"%[lo,hi,body.size()]]
    code=206
  response_bytes+=payload.size()
  respond(id,{"code":code,"headers":headers,"body":payload})

func install_ramp_png() -> void:
 var bytes := PackedByteArray()
 bytes.resize(256*256*3)
 for y in 256:
  for x in 256:
   var encoded := 32768+100+x*10
   var at := (y*256+x)*3
   bytes[at]=encoded/256
   bytes[at+1]=encoded%256
   bytes[at+2]=0
 objects.png=Image.create_from_data(256,256,false,Image.FORMAT_RGB8,bytes).save_png_to_buffer()
