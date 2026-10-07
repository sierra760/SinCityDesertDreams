# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name TerrainHttpTransport
extends Node
## HTTP downloads for the terrain importer: at most four requests at once, each
## for an exact byte range of a pinned object, with a download budget per
## generation. Callers invalidate a generation before cancelling it; cancelled
## requests still report a failure.
signal completed(request_id: int, generation: int, result: Dictionary)
const MAX_BODY := 2097152
const MAX_DOWNLOAD := 67108864
const MAX_DEADLINE_MS := 300000
const MAX_PENDING := 1024
# Native HTTPRequest reads before checking its cap; reserve one final read.
const READ_CHUNK := 4096

class NativeBackend extends Node:
	signal finished(result: int, code: int, headers: PackedStringArray, body: PackedByteArray)
	var http: HTTPRequest
	var received := 0
	func start(url: String, headers: PackedStringArray, head_only: bool, settings: Dictionary) -> int:
		http=HTTPRequest.new()
		add_child(http)
		http.max_redirects=0
		http.accept_gzip=false
		http.timeout=settings.timeout
		http.body_size_limit=settings.body_size_limit
		http.download_chunk_size=settings.download_chunk_size
		http.set_tls_options(TLSOptions.client())
		http.request_completed.connect(_finished)
		return http.request(url,headers,HTTPClient.METHOD_HEAD if head_only else HTTPClient.METHOD_GET)
	func _finished(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
		received=maxi(http.get_downloaded_bytes(),body.size())
		finished.emit(result,code,headers,body)
	func get_downloaded_bytes() -> int:
		return maxi(received,http.get_downloaded_bytes()) if is_instance_valid(http) else received
	func abort() -> void:
		if is_instance_valid(http):
			received=maxi(received,http.get_downloaded_bytes())
			http.cancel_request()

var _factory: Callable
var _clock: Callable = Time.get_ticks_msec
var _next_id := 1
var _requests := {}
var _generations := {}
# Generation IDs only increase. Older generations stay usable while active;
# once retired, an ID can never start a new budget, even after its metrics expire.
var _recent_generations := {}
var _retired_through := -1
var _rejections := {}
var _closed := false

func set_request_factory(factory: Callable) -> void:
	_factory=factory
func set_clock(clock: Callable) -> void:
	if _requests.is_empty() and _generations.is_empty() and clock.is_valid(): _clock=clock
func _now() -> int: return int(_clock.call())
func _generation(generation: int) -> Dictionary:
	if not _generations.has(generation):
		if generation<=_retired_through: return {}
		_generations[generation]={"deadline_ms":_now()+MAX_DEADLINE_MS,"downloaded_bytes":0,"cancelled":false,"elevation":[],"consumers":0}
	return _generations[generation]
func set_generation_deadline(generation: int, deadline_ms: int) -> void:
	var state := _generation(generation)
	if state.is_empty(): return
	# An established deadline can only tighten, never restart the operation clock.
	state.deadline_ms=mini(int(state.deadline_ms),mini(deadline_ms,_now()+MAX_DEADLINE_MS))

func retain_generation(generation: int) -> bool:
	var state := _generation(generation)
	if state.is_empty(): return false
	state.consumers+=1
	return true
func release_generation(generation: int) -> void:
	if _generations.has(generation):
		var state: Dictionary=_generations[generation]
		state.consumers=maxi(0,int(state.consumers)-1)
func retire_generation(generation: int) -> bool:
	if not _generations.has(generation): return generation<=_retired_through
	if int(_generations[generation].consumers)>0: return false
	for record in _requests.values():
		if record.generation==generation: return false
	if generation in _rejections.values(): return false
	var snapshot := get_generation_metrics(generation)
	snapshot.retired=true
	snapshot.telemetry_available=true
	_recent_generations[generation]=snapshot
	while _recent_generations.size()>8: _recent_generations.erase(_recent_generations.keys()[0])
	_generations.erase(generation)
	_retired_through=maxi(_retired_through,generation)
	return true

func retire_drained_generations() -> void:
	for generation in _generations.keys(): retire_generation(generation)

static func validate_request(resource: Dictionary, byte_range: Dictionary, identity: Dictionary, head_only: bool = false) -> Dictionary:
	var valid := TerrainImportContract.validate_sources([resource])
	if not valid.ok: return valid
	if not identity.is_empty():
		if identity.size()!=2 or not identity.get("etag") is String or identity.etag.is_empty() or identity.etag.length()>256 or not identity.get("size") is int or identity.size<1 or identity.size>1099511627776:
			return {"ok":false,"error":"Invalid object identity"}
		for byte in identity.etag.to_utf8_buffer():
			if byte<32 or byte==127: return {"ok":false,"error":"Invalid ETag control character"}
	if not byte_range.is_empty():
		if head_only or resource.source!="worldcover" or identity.is_empty() or byte_range.size()!=2 or not byte_range.get("offset") is int or not byte_range.get("length") is int or byte_range.offset<0 or byte_range.length<1 or byte_range.length>MAX_BODY or byte_range.offset>identity.size-byte_range.length:
			return {"ok":false,"error":"Invalid pinned byte range"}
	elif not head_only and resource.source=="worldcover":
		return {"ok":false,"error":"WorldCover requires bounded pinned ranges"}
	var url: String
	if resource.source=="terrarium": url="https://elevation-tiles-prod.s3.amazonaws.com/terrarium/%d/%d/%d.png"%[resource.z,resource.x,resource.y]
	else: url="https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_%s_Map.tif"%resource.tile
	return {"ok":true,"error":"","url":url}

func enqueue(resource: Dictionary, byte_range: Dictionary = {}, generation: int = 0, identity: Dictionary = {}, head_only: bool = false) -> int:
	var id := _next_id
	_next_id+=1
	var valid := validate_request(resource,byte_range,identity,head_only)
	var state := _generation(generation)
	var failure := ""
	if _closed: failure="Transport shut down"
	elif state.is_empty(): failure="Generation retired"
	elif state.cancelled: failure="Generation canceled"
	elif _requests.size()>=MAX_PENDING: failure="Request queue limit exceeded"
	elif _now()>=int(state.deadline_ms): failure="Operation deadline exceeded"
	elif not valid.ok: failure=valid.error
	elif resource.source=="terrarium" and resource not in state.elevation:
		if state.elevation.size()>=64: failure="Elevation tile limit exceeded"
		else: state.elevation.append(resource.duplicate(true))
	var record := {"id":id,"generation":generation,"resource":resource.duplicate(true),"range":byte_range.duplicate(true),"identity":identity.duplicate(true),"head":head_only,"url":valid.get("url",""),"attempts":0,"ready_ms":_now(),"started_ms":0,"backend":null,"accounted":0,"downloaded_bytes":0,"allowance":0,"reservation":0}
	# Invalid completions are deferred so callers can register request IDs first.
	if not failure.is_empty():
		_rejections[id]=generation
		_reject_later.call_deferred(id,generation,failure)
	else: _requests[id]=record
	return id
func _reject_later(id: int, generation: int, error: String) -> void:
	completed.emit(id,generation,{"ok":false,"error":error,"downloaded_bytes":0})
	_rejections.erase(id)

func get_generation_metrics(generation: int) -> Dictionary:
	var state := _generation(generation)
	if state.is_empty():
		# Do not invent zero-byte telemetry for a retired, evicted generation.
		return _recent_generations.get(generation,{"retired":true,"telemetry_available":false}).duplicate(true)
	var active := 0
	var queued := 0
	for record in _requests.values():
		if record.generation!=generation: continue
		if is_instance_valid(record.backend):
			_account(record)
			active+=1
		else: queued+=1
	return {"downloaded_bytes":state.downloaded_bytes,"deadline_ms":state.deadline_ms,"remaining_bytes":maxi(0,MAX_DOWNLOAD-int(state.downloaded_bytes)),"active":active,"queued":queued,"cancelled":state.cancelled}

func _account(record: Dictionary, delivered_size: int = 0) -> void:
	var received := delivered_size
	if is_instance_valid(record.backend): received=maxi(received,int(record.backend.get_downloaded_bytes()))
	var delta := maxi(0,received-int(record.accounted))
	record.accounted+=delta
	record.downloaded_bytes+=delta
	_generation(record.generation).downloaded_bytes+=delta
func _release(record: Dictionary) -> void:
	if is_instance_valid(record.backend):
		_account(record)
		record.backend.abort()
		record.backend.queue_free()
	record.backend=null
	record.accounted=0
	record.allowance=0
	record.reservation=0
func _finish(id: int, result: Dictionary) -> void:
	if not _requests.has(id): return
	var record: Dictionary = _requests[id]
	_release(record)
	_requests.erase(id)
	result.downloaded_bytes=record.downloaded_bytes
	if not result.get("ok",false):
		var service := "Elevation" if record.resource.get("source")=="terrarium" else "Water"
		result.error=service+" service unavailable: "+str(result.get("error","HTTP acquisition failed")).left(512)
	completed.emit(id,record.generation,result)
func _fail_generation(generation: int, error: String) -> void:
	var state := _generation(generation)
	if state.is_empty(): return
	state.cancelled=true
	for id in _requests.keys():
		if _requests.has(id) and _requests[id].generation==generation: _finish(id,{"ok":false,"error":error})
func cancel_generation(generation: int) -> void:
	_fail_generation(generation,"Generation canceled")
func shutdown() -> void:
	_closed=true
	for generation in _generations.keys(): _fail_generation(generation,"Transport shut down")
func _exit_tree() -> void: shutdown()

func _process(_delta: float) -> void:
	var now := _now()
	# Sample every active attempt before enforcing the shared budget.
	for record in _requests.values():
		if is_instance_valid(record.backend): _account(record)
	for generation in _generations.keys():
		var state: Dictionary = _generations[generation]
		if now>=int(state.deadline_ms): _fail_generation(generation,"Operation deadline exceeded")
		elif int(state.downloaded_bytes)>MAX_DOWNLOAD: _fail_generation(generation,"Downloaded byte budget exceeded")
	for id in _requests.keys():
		if not _requests.has(id): continue
		var record: Dictionary = _requests[id]
		if is_instance_valid(record.backend):
			if int(record.accounted)>int(record.allowance):
				_finish(id,{"ok":false,"error":"Response body cap exceeded"})
			elif now-int(record.started_ms)>=20000:
				_release(record)
				_retry_or_finish(id,HTTPRequest.RESULT_TIMEOUT,0,{})
	var active := 0
	for record in _requests.values():
		if is_instance_valid(record.backend): active+=1
	for id in _requests.keys():
		if active>=4: break
		if not _requests.has(id): continue
		var record: Dictionary = _requests[id]
		if is_instance_valid(record.backend) or now<int(record.ready_ms): continue
		var available := MAX_DOWNLOAD-int(_generation(record.generation).downloaded_bytes)
		for other in _requests.values():
			if other.generation==record.generation and is_instance_valid(other.backend): available-=maxi(0,int(other.reservation)-int(other.accounted))
		var cap := 0 if record.head else (int(record.range.length) if not record.range.is_empty() else mini(MAX_BODY,int(record.identity.get("size",MAX_BODY))))
		var reservation := 0 if record.head else cap+READ_CHUNK
		if available<reservation:
			# Other active reservations may finish smaller; wait for them before failure.
			var reserved := false
			for other in _requests.values():
				if other.generation==record.generation and is_instance_valid(other.backend): reserved=true
			if not reserved: _finish(id,{"ok":false,"error":"Downloaded byte budget exhausted"})
			continue
		_start(record,cap)
		if _requests.has(id) and is_instance_valid(_requests[id].backend): active+=1

func _start(record: Dictionary, cap: int) -> void:
	var backend: Node = _factory.call() if _factory.is_valid() else NativeBackend.new()
	if backend==null or not backend.has_signal("finished") or not backend.has_method("start") or not backend.has_method("abort") or not backend.has_method("get_downloaded_bytes"):
		if backend!=null: backend.queue_free()
		_finish(record.id,{"ok":false,"error":"Invalid HTTP backend"})
		return
	add_child(backend)
	record.backend=backend
	record.accounted=0
	record.allowance=cap
	record.reservation=0 if record.head else cap+READ_CHUNK
	record.started_ms=_now()
	record.attempts+=1
	backend.finished.connect(_on_finished.bind(record.id,backend))
	var headers := PackedStringArray(["Accept-Encoding: identity"])
	if not record.identity.is_empty(): headers.append("If-Match: "+record.identity.etag)
	if not record.range.is_empty(): headers.append("Range: bytes=%d-%d"%[record.range.offset,record.range.offset+record.range.length-1])
	var settings := {"request_id":record.id,"timeout":minf(20.0,maxf(0.001,(int(_generation(record.generation).deadline_ms)-_now())/1000.0)),"body_size_limit":cap,"download_chunk_size":READ_CHUNK,"max_redirects":0,"accept_gzip":false}
	var error: int = backend.start(record.url,headers,record.head,settings)
	if error!=OK and _requests.has(record.id):
		_release(record)
		_retry_or_finish(record.id,HTTPRequest.RESULT_CANT_CONNECT,0,{})

static func _headers(headers: PackedStringArray) -> Dictionary:
	var result := {}
	for line in headers:
		var colon := line.find(":")
		if colon<=0: continue
		var name := line.left(colon).strip_edges().to_lower()
		if result.has(name): return {"ok":false,"error":"Duplicate HTTP header"}
		result[name]=line.substr(colon+1).strip_edges()
	return {"ok":true,"error":"","headers":result}

func _on_finished(result: int, code: int, headers: PackedStringArray, body: PackedByteArray, id: int, backend: Node) -> void:
	if not _requests.has(id) or _requests[id].backend!=backend: return
	var record: Dictionary = _requests[id]
	_account(record,body.size())
	var state := _generation(record.generation)
	if int(state.downloaded_bytes)>MAX_DOWNLOAD:
		_fail_generation(record.generation,"Downloaded byte budget exceeded")
		return
	if _now()>=int(state.deadline_ms):
		_fail_generation(record.generation,"Operation deadline exceeded")
		return
	if body.size()>int(record.allowance) or int(record.accounted)>int(record.allowance):
		_finish(id,{"ok":false,"error":"Response body cap exceeded"})
		return
	var parsed := _headers(headers)
	if not parsed.ok:
		_finish(id,parsed)
		return
	var h: Dictionary = parsed.headers
	if result!=HTTPRequest.RESULT_SUCCESS or code==429 or code>=500 and code<=599:
		_release(record)
		_retry_or_finish(id,result,code,h)
		return
	var validated := _validate_response(record,code,h,body)
	_finish(id,validated)

static func _validate_response(record: Dictionary, code: int, h: Dictionary, body: PackedByteArray) -> Dictionary:
	var failure := {"ok":false,"error":"HTTP %d response does not match pinned raw object"%code}
	# ESA publishes WorldCover only for cells containing land. Mark a definitive
	# HEAD 404 for a water object so acquisition can treat it as open ocean; it
	# still fails here, so probes and every other caller keep failing closed.
	if record.head and code==404 and record.resource.get("source")=="worldcover" and body.is_empty():
		return {"ok":false,"error":"Water tile is not published (HTTP 404)","absent":true}
	if h.get("content-encoding","identity").to_lower()!="identity": return failure
	var etag: String = h.get("etag","")
	if etag.is_empty() or etag.length()>256: return failure
	for byte in etag.to_utf8_buffer():
		if byte<32 or byte==127: return failure
	var size := 0
	if record.head:
		if code!=200 or not body.is_empty() or not str(h.get("content-length","")).is_valid_int(): return failure
		size=int(h["content-length"])
		if size<1 or size>1099511627776: return failure
	elif not record.range.is_empty():
		if code!=206 or etag!=record.identity.etag or body.size()!=record.range.length: return failure
		var expected := "bytes %d-%d/%d"%[record.range.offset,record.range.offset+record.range.length-1,record.identity.size]
		if h.get("content-range","")!=expected: return failure
		size=record.identity.size
	else:
		if code!=200 or body.is_empty() or body.size()>MAX_BODY: return failure
		# Cheap framing only; full numeric/inflate decode runs in the acquisition worker.
		if body.size()<33 or body.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]) or body.slice(12,16).get_string_from_ascii()!="IHDR" or body.slice(16,24)!=PackedByteArray([0,0,1,0,0,0,1,0]): return failure
		size=body.size()
	if h.has("content-length") and not record.head:
		if not str(h["content-length"]).is_valid_int() or int(h["content-length"])!=body.size(): return failure
	if not record.identity.is_empty() and (etag!=record.identity.etag or size!=record.identity.size): return failure
	return {"ok":true,"error":"","body":body,"etag":etag,"size":size,"range":record.range.duplicate(true)}

func _retry_or_finish(id: int, result: int, code: int, headers: Dictionary) -> void:
	if not _requests.has(id): return
	var record: Dictionary = _requests[id]
	var transient := result in [HTTPRequest.RESULT_CANT_CONNECT,HTTPRequest.RESULT_CANT_RESOLVE,HTTPRequest.RESULT_CONNECTION_ERROR,HTTPRequest.RESULT_NO_RESPONSE,HTTPRequest.RESULT_REQUEST_FAILED,HTTPRequest.RESULT_TIMEOUT] or result==HTTPRequest.RESULT_SUCCESS and (code==429 or code>=500 and code<=599)
	if not transient or int(record.attempts)>=3:
		_finish(id,{"ok":false,"error":"HTTP acquisition failed (%d/%d)"%[result,code]})
		return
	var delay := int(record.attempts)*1000
	if code==429 and headers.has("retry-after"):
		var parsed := _retry_after(headers["retry-after"])
		if parsed<0:
			_finish(id,{"ok":false,"error":"Invalid Retry-After"})
			return
		delay=maxi(delay,parsed)
	if delay>=int(_generation(record.generation).deadline_ms)-_now():
		_finish(id,{"ok":false,"error":"Retry exceeds operation deadline"})
		return
	record.ready_ms=_now()+delay

static func _retry_after(value: String) -> int:
	if value.is_valid_int():
		var seconds := int(value)
		return mini(seconds,301)*1000 if seconds>=0 else -1
	# IMF-fixdate is UTC; convert only this server wall time to a bounded delay.
	var pattern := RegEx.new()
	pattern.compile("^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), ([0-9]{2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) ([0-9]{4}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) GMT$")
	var match_date := pattern.search(value)
	if match_date==null: return -1
	var month := ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"].find(match_date.get_string(3))+1
	var date := {"year":int(match_date.get_string(4)),"month":month,"day":int(match_date.get_string(2)),"hour":int(match_date.get_string(5)),"minute":int(match_date.get_string(6)),"second":int(match_date.get_string(7))}
	if date.year<1970 or date.day<1 or date.day>31 or date.hour>23 or date.minute>59 or date.second>59: return -1
	var delay := float(Time.get_unix_time_from_datetime_dict(date))-Time.get_unix_time_from_system()
	return int(clampf(ceil(delay),0.0,301.0))*1000
