# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends RefCounted
# Stands in for the street-map and place-search HTTP backends. Production
# basemap/search code validates everything it receives.
class Backend extends Node:
 signal finished(result: int, code: int, headers: PackedStringArray, body: PackedByteArray)
 var controller: RefCounted
 var url := ""
 var active := false
 func start(value: String, headers: PackedStringArray) -> int:
  url=value
  active=true
  controller.starts.append({"url":value,"headers":headers})
  controller.pending.append(self)
  controller.active+=1
  controller.peak_active=maxi(controller.peak_active,controller.active)
  controller.peak_tile_active=maxi(controller.peak_tile_active,controller.pending.filter(func(b: Node) -> bool: return is_instance_valid(b) and b.active and b.url.ends_with(".png")).size())
  return OK
 func abort() -> void:
  if active:
   active=false
   controller.active-=1
   controller.aborts+=1
var starts: Array[Dictionary] = []
var pending: Array = []
var active := 0
var peak_active := 0
var peak_tile_active := 0
var aborts := 0
## Status code per URL substring; 200 otherwise.
var codes := {}
var search_json := "[]"
var config_json := ""
var tile_body := PackedByteArray()
var hidpi_tile_body := PackedByteArray()

func _init() -> void:
 var image := Image.create(256,256,false,Image.FORMAT_RGB8)
 image.fill(Color("e8e0d0"))
 image.fill_rect(Rect2i(0,120,256,16),Color("f2c66b"))
 tile_body=image.save_png_to_buffer()
 image.resize(512,512)
 hidpi_tile_body=image.save_png_to_buffer()

func factory() -> Node:
 var backend := Backend.new()
 backend.controller=self
 return backend

func tile_starts(host: String = "https://tile.openstreetmap.org/") -> Array:
 return starts.filter(func(item: Dictionary) -> bool: return item.url.begins_with(host))
func config_starts() -> Array:
 return starts.filter(func(item: Dictionary) -> bool: return item.url.ends_with(".json"))
func search_starts() -> Array:
 return starts.filter(func(item: Dictionary) -> bool: return item.url.begins_with("https://nominatim.openstreetmap.org/"))

## Answer every request still waiting, in start order.
func serve() -> int:
 var served := 0
 var waiting: Array = pending.duplicate()
 pending.clear()
 for backend in waiting:
  if not is_instance_valid(backend) or not backend.active: continue
  backend.active=false
  active-=1
  served+=1
  var code := 404 if backend.url.ends_with(".json") and config_json.is_empty() else 200
  for fragment in codes:
   if backend.url.contains(fragment): code=codes[fragment]
  var body := search_json.to_utf8_buffer()
  if backend.url.ends_with(".json"): body=config_json.to_utf8_buffer()
  elif backend.url.ends_with("@2x.png"): body=hidpi_tile_body
  elif backend.url.ends_with(".png"): body=tile_body
  backend.finished.emit(HTTPRequest.RESULT_SUCCESS,code,PackedStringArray(),body if code==200 else PackedByteArray())
 return served
