# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Downloads real-world elevation and land-cover data and converts it into a
## city map. Every request gets a new generation number, and results from older
## generations are discarded. Worker threads do the numeric work; whenever they
## need the network or the tile cache they hand a ticket to the main thread,
## which is the only thread that touches Nodes and the cache.
class_name RealWorldImporter
extends Node
signal availability_changed(status: String, detail: String)
signal progress_changed(stage: String, fraction: float, detail: String)
signal candidate_ready(generation: int, candidate: Dictionary)
signal failed(generation: int, detail: String)
signal relief_fitted(generation: int, result: Dictionary)
const MEMORY_LIMIT := 134217728
const DEADLINE_MS := 300000
const PROBES := [{"source":"terrarium","z":0,"x":0,"y":0},{"source":"worldcover","tile":"N36W117"}]

# One handoff. Results move through a mutex and are cleared on consumption.
class Ticket extends RefCounted:
	var mutex := Mutex.new()
	var wake := Semaphore.new()
	var request: Dictionary
	var result: Dictionary = {}
	var done := false
	func finish(value: Dictionary) -> void:
		mutex.lock()
		if not done:
			result=value
			done=true
			wake.post()
		mutex.unlock()
	func take() -> Dictionary:
		wake.wait()
		mutex.lock()
		var value := result
		result={}
		mutex.unlock()
		return value

class Work extends RefCounted:
	var thread := Thread.new()
	var mutex := Mutex.new()
	var stopped_flag := false
	var now := 0
	var deadline := 0
	var generation := 0
	var kind := "download"
	var selection: Dictionary
	var controls: Dictionary
	var metadata: Dictionary
	var packet: Dictionary = {}
	var pending: Array[Ticket] = []
	var tickets: Array[Ticket] = []
	var result: Dictionary = {}
	var stage := "Planning"
	var fraction := 0.0
	var retained := {}
	var stats := {"peak_working_bytes":0,"rejected_working_bytes":0,"peak_decoded_water_blocks":0,"peak_decoded_water_bytes":0,"elevation_tiles":0,"water_blocks":0,"water_samples":0,"vertex_samples":0,"center_samples":0,"compressed_block_bytes":0,"validated_source_bytes":0,"deadline_ms":0,"planning_retained_bytes":0,"grouping_reserved_bytes":0,"grouping_retained_bytes":0,"grouping_items":0,"grouping_max_block_items":0}
	func cancelled() -> bool:
		mutex.lock()
		var value := stopped_flag or now>=deadline
		mutex.unlock()
		return value
	func cancel() -> void:
		mutex.lock()
		stopped_flag=true
		var waiting := tickets.duplicate()
		mutex.unlock()
		for ticket in waiting: ticket.finish({"ok":false,"error":"canceled"})
	func enqueue(request: Dictionary) -> Ticket:
		var ticket := Ticket.new()
		ticket.request=request
		mutex.lock()
		if stopped_flag or now>=deadline: ticket.finish({"ok":false,"error":"canceled or deadline exceeded"})
		else:
			pending.append(ticket)
			tickets.append(ticket)
		mutex.unlock()
		return ticket
	func receive(ticket: Ticket) -> Dictionary:
		var value := ticket.take()
		mutex.lock()
		tickets.erase(ticket)
		mutex.unlock()
		if cancelled(): return {"ok":false,"error":"canceled or deadline exceeded"}
		return value
	func request(descriptor: Dictionary, span: Dictionary = {}, identity: Dictionary = {}, head: bool = false) -> Dictionary:
		return receive(enqueue({"action":"fetch","descriptor":descriptor,"span":span,"identity":identity,"head":head}))
	func publish(descriptor: Dictionary, span: Dictionary, identity: Dictionary, body: PackedByteArray) -> void:
		# Optional cache failure cannot turn validated source data into an acquisition failure.
		receive(enqueue({"action":"publish","descriptor":descriptor,"span":span,"identity":identity,"body":body}))
	func phase(value: String, progress: float = 0.0) -> void:
		mutex.lock()
		stage=value
		fraction=progress
		mutex.unlock()
	func reserve(category: String, bytes: int) -> bool:
		var total := bytes
		for key in retained:
			if key!=category: total+=int(retained[key])
		if total>=MEMORY_LIMIT:
			stats.rejected_working_bytes=maxi(stats.rejected_working_bytes,total)
			return false
		retained[category]=bytes
		stats.peak_working_bytes=maxi(stats.peak_working_bytes,total)
		return not cancelled()
	func run() -> Dictionary:
		var value: Dictionary
		if kind=="rebuild": value=convert_packet()
		elif kind=="fit": value=fit_packet()
		else: value=acquire()
		if cancelled(): value={"ok":false,"error":"canceled or deadline exceeded"}
		return value
	func fit_packet() -> Dictionary:
		phase("Fitting relief")
		if not reserve("fit_scratch",16777216): return fail("Working memory budget exceeded")
		if cancelled(): return fail("canceled or deadline exceeded")
		var fitted := RealWorldTerrain.fit_exaggeration(packet,controls,cancelled)
		if cancelled(): return fail("canceled or deadline exceeded")
		if not fitted.ok: return fitted
		return {"ok":true,"error":"","fit":fitted}
	func convert_packet() -> Dictionary:
		phase("Building preview")
		# All acquisition bodies have been consumed. Keep 8 MiB for terminal source
		# handoff references while the calling acquisition stack unwinds.
		reserve("broker",0)
		reserve("decoder_scratch",0)
		reserve("source_handoff",8388608 if kind=="download" else 0)
		# Enforced Array worklist limit + other bounded packed arrays, component/repair
		# queues, normalization tile dictionaries, City projection and validation copies.
		if not reserve("conversion_scratch",16777216+33554432): return fail("Working memory budget exceeded")
		var converted := RealWorldTerrain.convert(packet,controls,metadata,cancelled,16777216)
		if converted.has("working_memory"): stats.merge(converted.working_memory,true)
		if not converted.ok: return converted
		reserve("conversion_scratch",0)
		if not reserve("candidate",RealWorldImporter.owned_bytes(converted)): return fail("Working memory budget exceeded")
		return {"ok":true,"error":"","candidate":converted,"packet":packet}
	func acquire() -> Dictionary:
		# Water append relocation <=30 MiB, retained stencil/center backing <4 MiB,
		# plus bounded descriptors/containers and small temporaries: reserve 40 MiB.
		if not reserve("planning",40*1024*1024): return fail("Working memory budget exceeded")
		var plan := TerrainGeography.plan_samples(selection,cancelled)
		if cancelled(): return fail("canceled or deadline exceeded")
		if not plan.ok: return plan
		stats.planning_retained_bytes=RealWorldImporter.owned_bytes(plan)
		if not reserve("planning",stats.planning_retained_bytes): return fail("Working memory budget exceeded")
		stats.elevation_tiles=plan.elevation_tiles
		stats.vertex_samples=plan.vertex_samples
		stats.center_samples=plan.center_samples
		stats.water_samples=plan.water_samples
		# Group packed triples by block before fetching any object. Max 512 across objects.
		# Across all groups, retained payload plus the one moving old/new buffer is
		# <= 2.5*3145728*4 = 30 MiB. Two MiB covers <=512 block containers and rounding.
		# The plan itself stays counted separately until nothing references it.
		if not reserve("grouping",32*1024*1024): return fail("Working memory budget exceeded")
		stats.grouping_reserved_bytes=32*1024*1024
		var groups := {}
		var block_count := 0
		for tile in plan.water_groups:
			var grouped := {}
			var samples: PackedInt32Array = plan.water_groups[tile]
			for i in range(0,samples.size(),3):
				if i%3072==0 and cancelled(): return fail("canceled or deadline exceeded")
				var block_id: int = (samples[i+2]/1024)*36+samples[i+1]/1024
				if not grouped.has(block_id):
					grouped[block_id]=PackedInt32Array()
					block_count+=1
					if block_count>512: return fail("Water block budget exceeds 512")
				grouped[block_id].append(samples[i])
				grouped[block_id].append(samples[i+1])
				grouped[block_id].append(samples[i+2])
				stats.grouping_items+=3
			samples=PackedInt32Array()
			groups[tile]=grouped
			for block_id in grouped:
				stats.grouping_max_block_items=maxi(stats.grouping_max_block_items,grouped[block_id].size())
		plan.water_groups={}
		stats.water_blocks=block_count
		stats.grouping_retained_bytes=RealWorldImporter.owned_bytes(groups)
		if not reserve("planning",RealWorldImporter.owned_bytes(plan)) or not reserve("grouping",stats.grouping_retained_bytes): return fail("Working memory budget exceeded")
		var sources: Array = plan.sources
		var objects: Array[Dictionary] = []
		var dem := {}
		phase("Downloading elevation")
		# HEAD every source on every acquisition, including warm-cache reuse.
		var heads: Array[Ticket] = []
		for descriptor in sources:
			heads.append(enqueue({"action":"fetch","descriptor":descriptor,"span":{},"identity":{},"head":true}))
		var identities := {}
		# ESA publishes only cells containing land. A definitive HEAD 404 for a water
		# descriptor is an absent open-ocean cell: all of its samples are class 80.
		# Other failures, including 403, remain fatal; present objects stay pinned.
		var absent := {}
		for i in sources.size():
			var head := receive(heads[i])
			if not head.ok:
				if sources[i].source=="worldcover" and head.get("absent",false)==true:
					absent[i]=true
					continue
				return head
			identities[i]={"etag":head.etag,"size":head.size}
		heads.clear()
		var elevation: Array[Dictionary] = []
		for i in sources.size():
			if sources[i].source=="terrarium": elevation.append({"descriptor":sources[i],"identity":identities[i]})
		# Four-at-a-time batch bounds waiting response bodies, independent of source count.
		for first in range(0,elevation.size(),4):
			var batch: Array[Ticket] = []
			for i in range(first,mini(first+4,elevation.size())):
				batch.append(enqueue({"action":"fetch","descriptor":elevation[i].descriptor,"span":{},"identity":elevation[i].identity,"head":false}))
			for j in batch.size():
				var entry: Dictionary = elevation[first+j]
				var fetched := receive(batch[j])
				if not fetched.ok: return fetched
				var decoded := TerrariumTiles.decode_png(fetched.body)
				if cancelled(): return fail("canceled or deadline exceeded")
				if not decoded.ok: return decoded
				var d: Dictionary = entry.descriptor
				dem["%d/%d/%d"%[d.z,d.x,d.y]]=decoded
				if not reserve("dem",RealWorldImporter.owned_bytes(dem)): return fail("Working memory budget exceeded")
				objects.append(evidence(d,entry.identity,[range_evidence(0,fetched.body)]))
				if not reserve("evidence",RealWorldImporter.owned_bytes(objects)): return fail("Working memory budget exceeded")
				stats.validated_source_bytes+=fetched.body.size()
				publish(d,{},entry.identity,fetched.body)
				phase("Downloading elevation",float(first+j+1)/elevation.size())
		var vertices := PackedFloat64Array()
		vertices.resize(16641)
		for i in 16641:
			if i%128==0 and cancelled(): return fail("canceled or deadline exceeded")
			var total := 0.0
			for j in 9:
				var at := (i*9+j)*2
				var value := TerrariumTiles.sample_bilinear_xy(plan.vertex_stencils[at],plan.vertex_stencils[at+1],plan.zoom,dem)
				if not value.ok: return value
				total+=value.metres
			vertices[i]=total/9.0
		var centers := PackedFloat64Array()
		centers.resize(16384)
		for i in 16384:
			if i%128==0 and cancelled(): return fail("canceled or deadline exceeded")
			var value := TerrariumTiles.sample_bilinear_xy(plan.centers[i*2],plan.centers[i*2+1],plan.zoom,dem)
			if not value.ok: return value
			centers[i]=value.metres
		dem.clear()
		reserve("dem",0)
		plan.vertex_stencils=PackedFloat64Array()
		plan.centers=PackedFloat64Array()
		reserve("planning",RealWorldImporter.owned_bytes(plan))
		var water := PackedByteArray()
		water.resize(16384)
		reserve("samples",RealWorldImporter.owned_bytes(vertices)+RealWorldImporter.owned_bytes(centers)+RealWorldImporter.owned_bytes(water))
		phase("Downloading water")
		var consumed := 0
		var known := RealWorldImporter._known_classes()
		for i in sources.size():
			var descriptor: Dictionary = sources[i]
			if descriptor.source!="worldcover": continue
			if absent.has(i):
				var ocean: Dictionary = groups[descriptor.tile]
				for block_id in ocean:
					var ocean_samples: PackedInt32Array = ocean[block_id]
					for at in range(0,ocean_samples.size(),3):
						if at%3072==0 and cancelled(): return fail("canceled or deadline exceeded")
						water[ocean_samples[at]/64]+=1
						consumed+=1
				groups.erase(descriptor.tile)
				reserve("grouping",RealWorldImporter.owned_bytes(groups))
				phase("Downloading water",float(consumed)/1048576.0)
				continue
			var identity: Dictionary = identities[i]
			var ranges := {}
			var parsed := WorldCoverCog.parse_index(ranges,identity.size)
			var records: Array[Dictionary] = []
			while not parsed.ok:
				if not parsed.get("error","").is_empty(): return parsed
				if cancelled(): return fail("canceled or deadline exceeded")
				for span in parsed.needed_ranges:
					var fetched := request(descriptor,span,identity)
					if not fetched.ok: return fetched
					ranges[span.offset]=fetched.body
					records.append(range_evidence(span.offset,fetched.body))
					stats.validated_source_bytes+=fetched.body.size()
				if not reserve("index",RealWorldImporter.owned_bytes(ranges)*3+65536): return fail("Working memory budget exceeded")
				parsed=WorldCoverCog.parse_index(ranges,identity.size)
			var index: Dictionary = parsed.index
			var token: String = descriptor.tile
			var west := int(token.substr(4,3))*(-1 if token[3]=="W" else 1)
			var south := int(token.substr(1,2))*(-1 if token[0]=="S" else 1)
			if index.transform.longitude_origin!=float(west) or index.transform.latitude_origin!=float(south+3): return fail("WorldCover geographic transform differs from descriptor")
			for offset in ranges: publish(descriptor,{"offset":offset,"length":ranges[offset].size()},identity,ranges[offset])
			ranges.clear()
			var blocks: Dictionary = groups[token]
			var keys := blocks.keys()
			keys.sort()
			var block_spans: Array[Dictionary] = []
			for block_id in keys:
				var span_result := WorldCoverCog.block_range(index,block_id)
				if not span_result.ok: return span_result
				block_spans.append({"offset":span_result.offset,"length":span_result.length})
			# Keep up to four block requests in flight, matching the transport's four
			# connections and the broker's four-body reservation; consume in key order.
			var inflight: Array[Ticket] = []
			var queued := 0
			for k in keys.size():
				var block_id: int = keys[k]
				if cancelled(): return fail("canceled or deadline exceeded")
				while queued<keys.size() and queued<k+4:
					inflight.append(enqueue({"action":"fetch","descriptor":descriptor,"span":block_spans[queued],"identity":identity,"head":false}))
					queued+=1
				var span: Dictionary = block_spans[k]
				var fetched := receive(inflight.pop_front())
				if not fetched.ok: return fetched
				var decoded := WorldCoverCog.decode_block(index,block_id,fetched.body)
				if not decoded.ok: return decoded
				stats.peak_decoded_water_blocks=1
				stats.peak_decoded_water_bytes=maxi(stats.peak_decoded_water_bytes,decoded.classes.size())
				var samples: PackedInt32Array = blocks[block_id]
				# WorldCoverCog.class_at semantics: index and decoded plane are validated
				# once per block, then each sample indexes the class plane directly.
				if not WorldCoverCog._valid_index(index): return fail("WorldCover source pixel is outside full-resolution geography")
				if decoded.get("ok")!=true or not decoded.get("classes") is PackedByteArray or decoded.classes.size()!=WorldCoverCog.BLOCK_SIZE*WorldCoverCog.BLOCK_SIZE: return fail("Invalid decoded WorldCover source block")
				var classes: PackedByteArray = decoded.classes
				for at in range(0,samples.size(),3):
					if at%3072==0 and cancelled(): return fail("canceled or deadline exceeded")
					var px := samples[at+1]
					var py := samples[at+2]
					if px<0 or py<0 or px>=WorldCoverCog.SOURCE_SIZE or py>=WorldCoverCog.SOURCE_SIZE: return fail("WorldCover source pixel is outside full-resolution geography")
					if (py/WorldCoverCog.BLOCK_SIZE)*WorldCoverCog.BLOCKS_ACROSS+px/WorldCoverCog.BLOCK_SIZE!=block_id: return fail("Missing WorldCover source block")
					var value := classes[(py%WorldCoverCog.BLOCK_SIZE)*WorldCoverCog.BLOCK_SIZE+px%WorldCoverCog.BLOCK_SIZE]
					if known[value]==0: return fail("WorldCover class is unknown or nodata")
					if value==80: water[samples[at]/64]+=1
					consumed+=1
				classes=PackedByteArray()
				# Only a fully decoded block with valid required classes may enter cache.
				publish(descriptor,span,identity,fetched.body)
				var record := range_evidence(span.offset,fetched.body)
				if record not in records: records.append(record)
				stats.compressed_block_bytes+=fetched.body.size()
				stats.validated_source_bytes+=fetched.body.size()
				decoded.clear()
				samples=PackedInt32Array()
				blocks.erase(block_id)
				phase("Downloading water",float(consumed)/1048576.0)
			groups.erase(token)
			reserve("grouping",RealWorldImporter.owned_bytes(groups))
			records.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.offset<b.offset if a.offset!=b.offset else a.length<b.length)
			objects.append(evidence(descriptor,identity,records))
			if not reserve("evidence",RealWorldImporter.owned_bytes(objects)): return fail("Working memory budget exceeded")
		if consumed!=1048576: return fail("Incomplete required water samples")
		# Provenance lists only objects that exist and were read; absent ocean cells
		# contributed no bytes. Every listed source keeps its pinned identity.
		var acquired: Array[Dictionary] = []
		for i in sources.size():
			if not absent.has(i): acquired.append(sources[i])
		# Stable descriptor ordering, independent of completion order.
		objects.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return acquired.find(a.descriptor)<acquired.find(b.descriptor))
		packet={"selection":selection,"vertex_metres":vertices,"center_metres":centers,"water_counts":water,"sources":acquired,"source_objects":objects,"acquired_utc":Time.get_datetime_string_from_system(true)+"Z"}
		var valid := TerrainImportContract.validate_packet(packet)
		if not valid.ok: return valid
		reserve("index",0)
		reserve("planning",0)
		reserve("samples",0)
		if not reserve("packet",RealWorldImporter.owned_bytes(packet)*2): return fail("Working memory budget exceeded")
		return convert_packet()
	static func evidence(descriptor: Dictionary, identity: Dictionary, ranges: Array) -> Dictionary:
		return {"descriptor":descriptor,"etag":identity.etag,"size":identity.size,"ranges":ranges}
	static func range_evidence(offset: int, body: PackedByteArray) -> Dictionary:
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(body)
		return {"offset":offset,"length":body.size(),"sha256":hash.finish().hex_encode()}
	static func fail(detail: String) -> Dictionary: return {"ok":false,"error":detail}

var candidate: Dictionary = {}
var metrics: Dictionary = {}
var _packet: Dictionary = {}
var _transport: TerrainHttpTransport
var _cache: TerrainTileCache
var _clock: Callable = Time.get_ticks_msec
var _serial := 0
var _generation := 0
var _metrics_generation := 0
var _probe_generation := 0
var _probe_remaining := 0
var _probe_failed := false
var _probe_errors := {}
var _online_at := -60000
var _ready_generation := -1
var _visible := true
var _suspended := false
var _workers: Array[Work] = []
var _requests := {}
var _last_stage := ""
var _last_fraction := -1.0

func configure(transport: TerrainHttpTransport, cache: TerrainTileCache) -> void:
	if _transport!=null: return
	_transport=transport
	_cache=cache
	_transport.completed.connect(_completed)
func set_clock(clock: Callable) -> void:
	if _serial==0 and clock.is_valid():
		_clock=clock
		if _transport!=null: _transport.set_clock(clock)
func _next() -> int:
	_serial+=1
	return _serial
func check_online(force: bool = false) -> void:
	if _transport==null or _suspended or not _visible: return
	if not force and (is_online_fresh() or _probe_remaining>0): return
	var previous := _probe_generation
	_probe_generation=_next()
	_probe_remaining=2
	_probe_failed=false
	_probe_errors.clear()
	_online_at=-60000
	if previous>0: _transport.cancel_generation(previous)
	var probe := _probe_generation
	availability_changed.emit("Checking","Checking elevation and water services")
	if probe!=_probe_generation or _suspended or not _visible: return
	_transport.set_generation_deadline(_probe_generation,int(_clock.call())+20000)
	for descriptor in PROBES:
		var id := _transport.enqueue(descriptor,{},_probe_generation,{},true)
		_requests[id]={"probe":_probe_generation,"service":"Elevation" if descriptor.source=="terrarium" else "Water"}
func is_online_fresh() -> bool:
	var elapsed := int(_clock.call())-_online_at
	return not _suspended and elapsed>=0 and elapsed<60000 and _probe_remaining==0 and not _probe_failed
## True while a connection check is in flight.
func is_checking_online() -> bool:
	return not _suspended and _probe_remaining>0
## Repeat a successful check that has expired, while terrain entry is visible.
## A failed check waits for a deliberate Retry. Returns true while checking.
func recheck_if_expired() -> bool:
	if _transport==null or _suspended or not _visible: return false
	if _probe_remaining>0: return true
	if _probe_failed or _online_at<0 or is_online_fresh(): return false
	check_online()
	return _probe_remaining>0
func is_ready() -> bool:
	return _ready_generation==_generation and not candidate.is_empty() and not _suspended
func download(selection: Dictionary, controls: Dictionary, metadata: Dictionary) -> int:
	var generation := _begin()
	if not is_online_fresh():
		_reject(generation,"Check online availability before downloading")
		return generation
	var valid := TerrainImportContract.validate_controls(controls)
	if not valid.ok:
		_reject(generation,valid.error)
		return generation
	var work := _new_work(generation,"download")
	work.selection=selection.duplicate(true)
	work.controls=controls.duplicate(true)
	work.metadata=metadata.duplicate(true)
	_start(work)
	return generation
func rebuild(controls: Dictionary, metadata: Dictionary) -> int:
	var generation := _begin()
	if not is_online_fresh() or _packet.is_empty():
		_reject(generation,"Online availability and a complete acquired source packet are required to rebuild")
		return generation
	var valid := TerrainImportContract.validate_controls(controls)
	if not valid.ok:
		_reject(generation,valid.error)
		return generation
	var work := _new_work(generation,"rebuild")
	work.controls=controls.duplicate(true)
	work.metadata=metadata.duplicate(true)
	_start(work)
	return generation
## Fit changes no candidate. UI applies returned E explicitly, then requests rebuild.
func fit_relief(controls: Dictionary) -> int:
	var generation := _begin()
	if not is_online_fresh() or _packet.is_empty():
		_reject(generation,"Online availability and a complete acquired source packet are required to fit relief")
		return generation
	var valid := TerrainImportContract.validate_controls(controls)
	if not valid.ok:
		_reject(generation,valid.error)
		return generation
	var work := _new_work(generation,"fit")
	work.controls=controls.duplicate(true)
	_start(work)
	return generation
func _begin() -> int:
	cancel()
	_generation=_next()
	_metrics_generation=_generation
	metrics={}
	_last_stage=""
	_last_fraction=-1.0
	if _transport!=null:
		_transport.set_generation_deadline(_generation,int(_clock.call())+DEADLINE_MS)
		metrics=_transport.get_generation_metrics(_generation)
	return _generation
func _new_work(generation: int, kind: String) -> Work:
	_transport.retain_generation(generation)
	var work := Work.new()
	work.generation=generation
	work.kind=kind
	work.now=int(_clock.call())
	# Deadline established at entry, before any CPU planning or thread start.
	work.deadline=int(_transport.get_generation_metrics(generation).deadline_ms)
	work.stats.deadline_ms=work.deadline
	work.retained["session"]=owned_bytes(candidate)+owned_bytes(_packet)
	# Raw backend storage + broker/COW response handoff + optional cache read/hash copies.
	work.retained["broker"]=4*(2097152+4096)*2+4194304
	# Parser/inflate/PNG planes/Image copy/float64 plane; at most one decoder per worker.
	work.retained["decoder_scratch"]=8388608
	work.stats.peak_working_bytes=work.retained["session"]
	if kind in ["rebuild","fit"]: work.retained["packet_copy"]=owned_bytes(_packet)*2
	return work
func _start(work: Work) -> void:
	# Cancelled workers may still own their plan/decoder scratch. Defer starting new
	# CPU work until they have joined, bounding the total across rapid UI changes.
	work.retained["inputs"]=owned_bytes(work.selection)+owned_bytes(work.controls)+owned_bytes(work.metadata)
	# Reserve pending-revision dictionaries/tickets too; only one CPU thread starts.
	work.retained["control_plane"]=8388608
	work.stats.peak_working_bytes+=work.retained["inputs"]+8388608
	_workers.append(work)
func invalidate_settings() -> void: cancel()
func cancel() -> void:
	_ready_generation=-1
	_generation=_next()
	for work in _workers.duplicate():
		work.cancel()
		if _transport!=null: _transport.cancel_generation(work.generation)
		if not work.thread.is_started(): _release_work(work)
func suspend() -> void:
	_suspended=true
	_online_at=-60000
	cancel()
	var previous := _probe_generation
	_probe_generation=_next()
	_probe_remaining=0
	if _transport!=null and previous>0: _transport.cancel_generation(previous)
	availability_changed.emit("Offline","Online terrain is suspended")
func set_visible(value: bool) -> void:
	_visible=value
	if not value: suspend()
	else:
		_suspended=false
		check_online()
func release_candidate() -> void:
	cancel()
	candidate={}
	_packet={}
func clear_cache() -> Dictionary:
	cancel()
	return _cache.clear() if _cache!=null else {"ok":false,"error":"Cache is not configured"}
func is_drained() -> bool: return _workers.is_empty()
func _process(_delta: float) -> void:
	if _transport==null: return
	var now := int(_clock.call())
	for work in _workers.duplicate():
		work.mutex.lock()
		work.now=now
		var stage: String=work.stage
		var fraction: float=work.fraction
		work.mutex.unlock()
		if work.generation==_generation and now>=work.deadline:
			_generation=_next()
			work.cancel()
			_transport.cancel_generation(work.generation)
			_reject(work.generation,"Extraction exceeded the 300-second deadline")
		if not work.thread.is_started():
			if work.cancelled():
				_release_work(work)
				continue
			if _workers[0]!=work: continue
			if not is_online_fresh():
				_release_work(work)
				_reject(work.generation,"Online availability expired before queued extraction started")
				continue
			if work.kind in ["rebuild","fit"]:
				if not work.reserve("packet_copy",owned_bytes(_packet)*2):
					_release_work(work)
					_reject(work.generation,"Working memory budget exceeded before queued packet copy")
					continue
				work.packet=_packet.duplicate(true)
			var error: int = work.thread.start(work.run)
			if error!=OK:
				_release_work(work)
				_reject(work.generation,"Could not start terrain worker")
				continue
		if not work.thread.is_alive():
			var result: Dictionary=work.thread.wait_to_finish()
			_workers.erase(work)
			_finish(work,result)
			_transport.release_generation(work.generation)
			continue
		if work.generation==_generation and (stage!=_last_stage or fraction!=_last_fraction):
			_last_stage=stage
			_last_fraction=fraction
			progress_changed.emit(stage,fraction,"")
		work.mutex.lock()
		var pending: Array[Ticket]=work.pending.duplicate()
		work.pending.clear()
		work.mutex.unlock()
		for ticket in pending: _broker(work,ticket)
	# Drop transport bookkeeping for generations that no pending request or
	# running worker still uses, so each frame only scans live generations.
	_transport.retire_drained_generations()
func _release_work(work: Work) -> void:
	if work not in _workers: return
	_workers.erase(work)
	_transport.release_generation(work.generation)
func _broker(work: Work, ticket: Ticket) -> void:
	if work.cancelled():
		ticket.finish({"ok":false,"error":"canceled"})
		return
	var request := ticket.request
	if request.action=="publish":
		ticket.finish(_cache.publish(request.descriptor,request.span,request.identity,request.body) if _cache!=null else {"ok":false,"error":"No cache"})
		ticket.request={}
		return
	if not request.head and _cache!=null:
		var cached := _cache.lookup(request.descriptor,request.span,request.identity)
		if cached.ok:
			ticket.finish(cached)
			ticket.request={}
			return
	var id := _transport.enqueue(request.descriptor,request.span,work.generation,request.identity,request.head)
	_requests[id]={"ticket":ticket,"generation":work.generation}
	ticket.request={}
func _completed(id: int, generation: int, result: Dictionary) -> void:
	if not _requests.has(id): return
	var owner: Dictionary=_requests[id]
	_requests.erase(id)
	if owner.has("probe"):
		if generation!=_probe_generation: return
		_probe_remaining-=1
		_probe_failed=_probe_failed or not result.ok
		if not result.ok: _probe_errors[owner.service]=str(result.error).left(600)
		if _probe_remaining==0:
			if not _probe_failed: _online_at=int(_clock.call())
			var details: PackedStringArray=[]
			for service in ["Elevation","Water"]:
				if _probe_errors.has(service): details.append(_probe_errors[service])
			availability_changed.emit("Online" if not _probe_failed else "Offline","Both terrain services are available" if not _probe_failed else "; ".join(details))
	else: owner.ticket.finish(result)
func _finish(work: Work, result: Dictionary) -> void:
	# Record the final transfer metrics, including bytes spent on cancelled or
	# retried requests, before the cancellation check. A cancelled result is
	# still never accepted or emitted as a candidate.
	if not result.ok: _transport.cancel_generation(work.generation)
	if work.generation==_metrics_generation:
		metrics=work.stats.duplicate(true)
		metrics.merge(_transport.get_generation_metrics(work.generation),true)
	if work.cancelled(): return
	if work.generation!=_generation: return
	if not result.ok:
		_reject(work.generation,result.error)
		_transport.cancel_generation(work.generation)
		return
	if work.kind=="fit":
		relief_fitted.emit(work.generation,result.fit)
		return
	candidate=result.candidate
	_packet=result.packet
	_ready_generation=work.generation
	progress_changed.emit("Ready",1.0,"")
	if work.generation==_generation and is_ready(): candidate_ready.emit(work.generation,candidate)
func _reject(generation: int, detail: String) -> void:
	_ready_generation=-1
	# Deadline handling bumps the generation before calling this. Report the
	# failure only if no progress_changed handler starts a newer request.
	var revision := _generation
	progress_changed.emit("Error",0.0,detail)
	if revision==_generation: failed.emit(generation,detail)
func _exit_tree() -> void:
	suspend()
	# Only teardown waits for worker threads; closing the UI just suspends them.
	for work in _workers:
		if work.thread.is_started(): work.thread.wait_to_finish()
		_transport.release_generation(work.generation)
	_workers.clear()
	if _transport!=null:
		_transport.retire_drained_generations()
	if _transport!=null and is_instance_valid(_transport) and _transport.completed.is_connected(_completed): _transport.completed.disconnect(_completed)

## 256-entry membership table for WorldCoverCog.CLASS_VALUES.
static func _known_classes() -> PackedByteArray:
	var known := PackedByteArray()
	known.resize(256)
	for value in WorldCoverCog.CLASS_VALUES: known[value]=1
	return known

# Generous estimate of the memory a value keeps alive: packed payload bytes,
# container slots, scalars and strings. Script properties of objects are
# included, which covers a City's layer arrays.
static func owned_bytes(value: Variant, depth: int = 0) -> int:
	if depth>8: return 4096
	if value is PackedByteArray: return packed_retained_bytes(value.size(),1)
	if value is PackedFloat64Array or value is PackedInt64Array: return packed_retained_bytes(value.size(),8)
	if value is PackedInt32Array or value is PackedFloat32Array: return packed_retained_bytes(value.size(),4)
	if value is String or value is StringName: return String(value).length()*4+64
	if value is Dictionary:
		var bytes: int = 128+value.size()*128
		for key in value: bytes+=owned_bytes(key,depth+1)+owned_bytes(value[key],depth+1)
		return bytes
	if value is Array:
		var bytes: int = 64+value.size()*32
		for item in value: bytes+=owned_bytes(item,depth+1)
		return bytes
	if value is Object and value!=null:
		var bytes := 4096
		for property in value.get_property_list():
			if property.usage&PROPERTY_USAGE_SCRIPT_VARIABLE: bytes+=owned_bytes(value.get(property.name),depth+1)
		return bytes
	return 32

# Every packed array counted here is fixed-size or append-built and released as a whole.
# CowData append growth c'=c+ceil(c/2), c<n, gives c'<=ceil(1.5*n).
# Fixed resize from empty is no larger; 128 bytes covers headers and small rounding.
# This charges retained backing only; phase reservations separately cover relocation.
@warning_ignore("integer_division")
static func packed_retained_bytes(items: int, element_bytes: int) -> int:
	return 128+(items+(items+1)/2)*element_bytes
