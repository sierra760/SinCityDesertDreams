# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Pure numeric conversion; no nodes, I/O, global random stream or scene resources.
class_name RealWorldTerrain
extends RefCounted
const N := 128
const V := 129
const TILES := N*N
const VERTICES := V*V

static func _error(message: String) -> Dictionary:
	return {"ok":false,"error":message}

static func _cancelled(cancelled: Callable) -> bool:
	return cancelled.is_valid() and bool(cancelled.call())

static func _neighbors(i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if i>=N: out.append(i-N)
	if i%N<N-1: out.append(i+1)
	if i<TILES-N: out.append(i+N)
	if i%N>0: out.append(i-1)
	return out

static func _prepare(packet: Dictionary, controls: Dictionary, cancelled: Callable) -> Dictionary:
	var valid := TerrainImportContract.validate_packet(packet)
	if not valid.ok: return valid
	valid=TerrainImportContract.validate_controls(controls)
	if not valid.ok: return valid
	var ground: PackedFloat64Array=packet.vertex_metres.duplicate()
	for pass_index in int(controls.smoothing_passes):
		var next := ground.duplicate()
		for y in V:
			if _cancelled(cancelled): return _error("canceled")
			for x in V:
				var total := 0.0
				for dy in range(-1,2):
					for dx in range(-1,2): total+=ground[clampi(y+dy,0,N)*V+clampi(x+dx,0,N)]
				next[y*V+x]=total/9.0
		ground=next
	var wet := PackedByteArray()
	wet.resize(TILES)
	var salt := wet.duplicate()
	var visited := wet.duplicate()
	var settled := wet.duplicate()
	var surfaces: PackedFloat64Array=packet.center_metres.duplicate()
	var components: Array[PackedInt32Array]=[]
	var widened := 0
	for i in TILES:
		wet[i]=1 if packet.water_counts[i]>=(1 if controls.preserve_narrow else 32) else 0
		if wet[i] and packet.water_counts[i]<32: widened+=1
	var mpl: float=float(packet.selection.side_km)*1000.0/N*CityGeometry3D.HEIGHT/float(controls.exaggeration)
	for start in TILES:
		if start%128==0 and _cancelled(cancelled): return _error("canceled")
		if not wet[start] or visited[start]: continue
		var component := PackedInt32Array([start])
		visited[start]=1
		var head := 0
		var boundary := false
		var low := false
		var heights: Array[float]=[]
		while head<component.size():
			if head%256==0 and _cancelled(cancelled): return _error("canceled")
			var i := component[head]
			head+=1
			boundary=boundary or i<N or i>=TILES-N or i%N==0 or i%N==N-1
			low=low or surfaces[i]<-1.0
			heights.append(surfaces[i])
			for j in _neighbors(i):
				if wet[j] and not visited[j]:
					visited[j]=1
					component.append(j)
		var sea: bool=controls.water_mode=="sea" or (controls.water_mode=="auto" and boundary and low)
		heights.sort()
		var median: float=(heights[(heights.size()-1)/2]+heights[heights.size()/2])*0.5
		var flat: bool=heights.back()-heights.front()<=mpl
		for i in component:
			salt[i]=1 if sea else 0
			if sea: surfaces[i]=0.0
			elif flat: surfaces[i]=median
			if sea or flat: settled[i]=1
		components.append(component)
	# Open fresh water (tiles inside a fully wet 2x2 block) forms lake bodies. Their
	# elevation samples are level apart from a few that land on banks, data voids
	# or lake-bed bathymetry, and those few must not pile the surface into mounds
	# or pits. A body whose typical samples agree within one level is one lake at
	# its median, and later relaxation leaves it level.
	var open := PackedByteArray()
	open.resize(TILES)
	for y in N-1:
		for x in N-1:
			var a:=y*N+x
			if wet[a] and wet[a+1] and wet[a+N] and wet[a+N+1]:
				for i in [a,a+1,a+N,a+N+1]: open[i]=1
	var lake := PackedByteArray()
	lake.resize(TILES)
	for start in TILES:
		if start%128==0 and _cancelled(cancelled): return _error("canceled")
		if not open[start] or settled[start] or salt[start]: continue
		var body := PackedInt32Array([start])
		settled[start]=1
		var head := 0
		while head<body.size():
			var i := body[head]
			head+=1
			for j in _neighbors(i):
				if open[j] and not settled[j] and not salt[j]:
					settled[j]=1
					body.append(j)
		var samples: Array[float]=[]
		for i in body:
			if packet.water_counts[i]==64: samples.append(surfaces[i])
		if samples.size()<4:
			samples.clear()
			for i in body: samples.append(surfaces[i])
		samples.sort()
		var last:=samples.size()-1
		if samples[ceili(last*0.9)]-samples[floori(last*0.1)]>mpl: continue
		var level: float=(samples[last/2]+samples[samples.size()/2])*0.5
		for i in body:
			surfaces[i]=level
			lake[i]=1
	# Shoreline cells and stream mouths that only partly hold water sample the
	# bank, while their water lies at the lowest corner. Those within one level
	# of a neighbouring lake belong to it instead of standing above it, as do
	# coves whose only water neighbours are the lake (no stream feeds them).
	var shore := PackedInt32Array()
	for i in TILES:
		if lake[i]: shore.append(i)
	var head := 0
	while head<shore.size():
		if head%256==0 and _cancelled(cancelled): return _error("canceled")
		var i := shore[head]
		head+=1
		for j in _neighbors(i):
			if not wet[j] or salt[j] or lake[j] or settled[j]: continue
			var lowest: float=surfaces[j]
			for vertex in TerrainSurface.tile_vertices(j%N,j/N): lowest=minf(lowest,ground[vertex.y*V+vertex.x])
			var cove := true
			for k in _neighbors(j):
				if wet[k] and not lake[k]: cove=false
			if not cove and absf(lowest-surfaces[i])>mpl: continue
			surfaces[j]=surfaces[i]
			lake[j]=1
			shore.append(j)
	var include := PackedByteArray()
	include.resize(VERTICES)
	var lo := INF
	var hi := -INF
	for y in V:
		if _cancelled(cancelled): return _error("canceled")
		for x in V:
			var only_sea := true
			for tile in TerrainSurface.vertex_tiles(x,y):
				if not salt[tile.y*N+tile.x]: only_sea=false
			var i:=y*V+x
			if not only_sea:
				include[i]=1
				lo=minf(lo,ground[i])
				hi=maxf(hi,ground[i])
	for i in TILES:
		if wet[i]:
			lo=minf(lo,surfaces[i])
			hi=maxf(hi,surfaces[i])
	if not is_finite(lo) or not is_finite(hi) or not is_finite(hi-lo): return _error("nonfinite_relief_range")
	return {"ok":true,"ground":ground,"wet":wet,"salt":salt,"surfaces":surfaces,"lake":lake,"components":components,"include":include,"minimum":lo,"maximum":hi,"mpl":mpl,"widened":widened}

static func _clipping(data: Dictionary) -> int:
	var clipped := 0
	for i in VERTICES:
		if data.include[i] and (data.ground[i]-data.minimum)/data.mpl>28.0+0.000000001: clipped+=1
	for i in TILES:
		if data.wet[i] and (data.surfaces[i]-data.minimum)/data.mpl>28.0+0.000000001: clipped+=1
	return clipped

static func fit_exaggeration(packet: Dictionary, controls: Dictionary, cancelled: Callable = Callable()) -> Dictionary:
	var data := _prepare(packet,controls,cancelled)
	if not data.ok: return data
	var adjusted := controls.duplicate(true)
	var relief: float=data.maximum-data.minimum
	if relief>0.0:
		adjusted.exaggeration=clampf(28.0*float(packet.selection.side_km)*1000.0/N*CityGeometry3D.HEIGHT/relief,0.001,20.0)
	# Tightening the displayed scale can unflatten a near-level water component.
	# Recompute at that scale and only reduce E afterwards, so this cannot oscillate.
	for attempt in 64:
		if _cancelled(cancelled): return _error("canceled")
		data=_prepare(packet,adjusted,cancelled)
		if not data.ok: return data
		if _clipping(data)==0 or adjusted.exaggeration<=0.001: break
		relief=data.maximum-data.minimum
		var next:=clampf(28.0*float(packet.selection.side_km)*1000.0/N*CityGeometry3D.HEIGHT/relief,0.001,20.0)
		if next>=adjusted.exaggeration: break
		adjusted.exaggeration=next
	return {"ok":true,"error":"","exaggeration":adjusted.exaggeration,"remaining_clipping":_clipping(data)}

static func convert(packet: Dictionary, controls: Dictionary, metadata: Dictionary, cancelled: Callable = Callable(), worklist_budget_bytes: int = 0) -> Dictionary:
	var data := _prepare(packet,controls,cancelled)
	if not data.ok: return data
	if _cancelled(cancelled): return _error("canceled")
	var surface := TerrainSurface.new()
	var initial := PackedByteArray()
	initial.resize(VERTICES)
	for i in VERTICES:
		var target: float=2.0+(data.ground[i]-data.minimum)/data.mpl if data.include[i] else 2.0+(0.0-data.minimum)/data.mpl
		initial[i]=clampi(int(floor(clampf(target,2.0,30.0)+0.5)),2,30)
	surface.vertices=initial.duplicate()
	var levels := PackedInt32Array()
	levels.resize(TILES)
	levels.fill(-1)
	var sea_level := -1
	for i in TILES:
		if data.wet[i]:
			levels[i]=clampi(int(floor(clampf(2.0+(data.surfaces[i]-data.minimum)/data.mpl,2.0,30.0)+0.5)),2,30)
			if data.salt[i]: sea_level=levels[i]
	# Multi-source integer relaxation lowers only high surfaces; each tile changes <=28 times.
	# Lake bodies stay level: a lower outlet meets them as a fall, not a funnel.
	# Cells meeting only at a corner share that corner's height, so diagonal
	# water is bounded too; otherwise the higher cell stands as a column of water.
	var queue := PackedInt32Array()
	for i in TILES:
		if data.wet[i]: queue.append(i)
	var head := 0
	while head<queue.size():
		if head%256==0 and _cancelled(cancelled): return _error("canceled")
		var i:=queue[head]
		head+=1
		for dy in range(-1,2):
			for dx in range(-1,2):
				var x:=i%N+dx
				var y:=i/N+dy
				if x<0 or y<0 or x>=N or y>=N: continue
				var j:=y*N+x
				if data.wet[j] and not data.lake[j] and levels[j]>levels[i]+1:
					levels[j]=levels[i]+1
					queue.append(j)
	# A cell standing above all the water it touches sampled its bank; it settles
	# to its highest neighbour. One pass suffices: a settled cell equals a neighbour.
	for i in TILES:
		if not data.wet[i] or data.salt[i] or data.lake[i]: continue
		var top:=-1
		var above:=true
		for j in _neighbors(i):
			if not data.wet[j]: continue
			top=maxi(top,levels[j])
			if levels[j]>=levels[i]: above=false
		if top>=0 and above: levels[i]=top
	# Thin channels use the usual one-level stream bed. Shared high edges
	# form a waterfall only when the final straight profile passes its legality check.
	var thin := PackedByteArray()
	thin.resize(TILES)
	for i in TILES:
		if not data.wet[i] or data.salt[i]: continue
		var degree:=0
		for j in _neighbors(i):
			if data.wet[j]: degree+=1
		var broad:=false
		for dy in [-1,0]:
			for dx in [-1,0]:
				var x: int=i%N+dx
				var y: int=i/N+dy
				if x<0 or y<0 or x>=N-1 or y>=N-1: continue
				if data.wet[y*N+x] and data.wet[y*N+x+1] and data.wet[(y+1)*N+x] and data.wet[(y+1)*N+x+1]: broad=true
		if degree>=1 and degree<=2 and not broad: thin[i]=1
	var ceilings := PackedInt32Array()
	ceilings.resize(VERTICES)
	ceilings.fill(31)
	var vertices_queue := PackedInt32Array()
	for y in V:
		if _cancelled(cancelled): return _error("canceled")
		for x in V:
			var vi:=y*V+x
			var any_wet:=false
			var only_thin:=true
			var shallow:=31
			var stream_bed:=0
			# Open water meets a dry bank at its own level, as generated lakes do;
			# its bed lies one level down. Streams keep their one-level bed.
			var shore:=false
			for tile in TerrainSurface.vertex_tiles(x,y):
				if not data.wet[tile.y*N+tile.x]: shore=true
			for tile in TerrainSurface.vertex_tiles(x,y):
				var i:=tile.y*N+tile.x
				if not data.wet[i]: continue
				any_wet=true
				only_thin=only_thin and thin[i]!=0
				shallow=mini(shallow,levels[i]-(0 if shore and not thin[i] else 1))
				stream_bed=maxi(stream_bed,levels[i]-1)
			if any_wet:
				ceilings[vi]=stream_bed if only_thin else shallow
				surface.vertices[vi]=ceilings[vi] if only_thin else mini(surface.vertices[vi],ceilings[vi])
				vertices_queue.append(vi)
	for i in TILES:
		if not data.wet[i]: continue
		surface.set_water(i%N,i/N,levels[i],data.salt[i]!=0)
		# A low bend between two high branches cannot become a dry channel floor.
		if not surface.has_water(i%N,i/N):
			for vertex in TerrainSurface.tile_vertices(i%N,i/N):
				var vi:=vertex.y*V+vertex.x
				ceilings[vi]=mini(ceilings[vi],levels[i]-1)
				surface.vertices[vi]=mini(surface.vertices[vi],ceilings[vi])
	# Propagate the bed ceilings outward (including diagonals) before surface
	# normalization. This prevents high surrounding ground from filling a channel.
	var vertex_head:=0
	while vertex_head<vertices_queue.size():
		if vertex_head%256==0 and _cancelled(cancelled): return _error("canceled")
		var vi:=vertices_queue[vertex_head]
		vertex_head+=1
		var vx:=vi%V
		var vy:=vi/V
		for dy in range(-1,2):
			for dx in range(-1,2):
				if vx+dx<0 or vx+dx>=V or vy+dy<0 or vy+dy>=V: continue
				var ni: int=(vy+dy)*V+vx+dx
				if ceilings[ni]>ceilings[vi]+1:
					ceilings[ni]=ceilings[vi]+1
					vertices_queue.append(ni)
	for i in VERTICES: surface.vertices[i]=mini(surface.vertices[i],ceilings[i])
	var converged := false
	var normalization_peak := 0
	var normalization_counts := {"normalization_queue_items":0,"normalization_recent_items":0,"normalization_bound_items":0}
	for attempt in 64:
		if _cancelled(cancelled): return _error("canceled")
		var stats := surface.normalize(Rect2i(),{},worklist_budget_bytes)
		normalization_peak=maxi(normalization_peak,int(stats.get("worklist_peak_bytes",0)))
		for list_name in ["queue","recent","bound"]:
			var key: String="normalization_"+list_name+"_items"
			normalization_counts[key]=maxi(normalization_counts[key],int(stats.get("worklist_"+list_name+"_items",0)))
		if stats.has("resource_error"):
			return {"ok":false,"error":stats.resource_error,"working_memory":{"normalization_worklist_peak_bytes":normalization_peak,"normalization_worklist_limit_bytes":worklist_budget_bytes,"normalization_worklist_required_bytes":stats.worklist_required_bytes}}
		if not stats.converged: return _error("water_mask_normalization_failed")
		var lost := 0
		for i in TILES:
			if data.wet[i] and not surface.has_water(i%N,i/N):
				lost+=1
				for vertex in TerrainSurface.tile_vertices(i%N,i/N):
					surface.set_vertex(vertex.x,vertex.y,mini(surface.vertex(vertex.x,vertex.y),levels[i]-1))
		if lost==0:
			converged=true
			break
	if not converged or not RealWorldManifest.valid_surface(surface): return _error("water_mask_preservation_failed")
	# Water outside a lake rests at most one level over its own cell's lowest corner,
	# like a stream on its bed, instead of standing above the ground around it.
	for i in TILES:
		if data.wet[i] and not data.salt[i] and not data.lake[i]:
			var cap:=surface.tile_base(i%N,i/N)+1
			if surface.water_level(i%N,i/N)>cap: surface.set_water(i%N,i/N,cap,false)
	var streams := 0
	var waterfalls := 0
	for i in TILES:
		if not data.wet[i] or data.salt[i]: continue
		if thin[i] and surface.is_tile_flat(i%N,i/N):
			surface.feature[i]=TerrainSurface.Feature.STREAM
			streams+=1
		if RealWorldManifest.legal_waterfall(surface,i%N,i/N):
			surface.feature[i]=TerrainSurface.Feature.WATERFALL
			waterfalls+=1
	var repaired := 0
	var maximum_repair := 0.0
	for i in VERTICES:
		if surface.vertices[i]!=initial[i]:
			repaired+=1
			maximum_repair=maxf(maximum_repair,absf(float(surface.vertices[i])-initial[i])*data.mpl)
	var wet_count := 0
	var sea_count := 0
	for i in TILES:
		wet_count+=int(data.wet[i])
		sea_count+=int(data.salt[i])
	var city := RealWorldManifest.new_city(metadata)
	city.sea_level=sea_level
	surface.project(city)
	if _cancelled(cancelled): return _error("canceled")
	TerrainGenerator.decorate_trees(city,controls.trees,controls.tree_seed)
	var mpt: float=float(packet.selection.side_km)*1000.0/N
	var diagnostics := {"source_min_metres":data.minimum,"source_max_metres":data.maximum,"metres_per_tile":mpt,"metres_per_level":data.mpl,"initial_clipped_targets":_clipping(data),"repaired_vertices":repaired,"max_repair_metres":maximum_repair,"wet_tiles":wet_count,"widened_tiles":data.widened,"fresh_tiles":wet_count-sea_count,"sea_tiles":sea_count,"lost_wet_tiles":0,"stream_tiles":streams,"waterfall_tiles":waterfalls,"sample_spacing_metres":mpt/8.0,"water_year":2021}
	var origin := RealWorldManifest.build_origin(packet,controls,diagnostics)
	if origin.is_empty(): return _error("origin_metadata_invalid_or_too_large")
	var baseline := RealWorldManifest.encode_baseline(city,controls.tree_seed)
	if baseline.is_empty(): return _error("baseline_validation_failed")
	if _cancelled(cancelled): return _error("canceled")
	var result := {"ok":true,"error":"","city":city,"diagnostics":diagnostics,"baseline":baseline,"controls":controls.duplicate(true),"origin":origin}
	if worklist_budget_bytes>0:
		result.working_memory={"normalization_worklist_peak_bytes":normalization_peak,"normalization_worklist_limit_bytes":worklist_budget_bytes}
		result.working_memory.merge(normalization_counts)
	return result
