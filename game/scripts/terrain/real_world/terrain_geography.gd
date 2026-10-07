# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name TerrainGeography
extends RefCounted
const RADIUS := 6371008.8
const WORLD_COVER_PIXELS := 36000

static func local_to_geo(selection: Dictionary, metres: Vector2) -> Vector2:
	var coordinates := _local_to_geo_scalars(selection,metres.x,metres.y)
	return Vector2(coordinates[0],coordinates[1])

# Works in 64-bit floats; only the public Vector2 wrappers round to 32 bits.
static func _local_to_geo_scalars(selection: Dictionary, x: float, y: float) -> PackedFloat64Array:
	var angle := deg_to_rad(float(selection.bearing))
	var east := x*cos(angle)-y*sin(angle)
	var north := -x*sin(angle)-y*cos(angle)
	var rho := sqrt(east*east+north*north)
	var lat := deg_to_rad(float(selection.latitude))
	var lon := deg_to_rad(float(selection.longitude))
	if rho > 0.0:
		var c := rho/RADIUS
		var next_lat := asin(clampf(cos(c)*sin(lat)+north*sin(c)*cos(lat)/rho,-1.0,1.0))
		lon += atan2(east*sin(c),rho*cos(lat)*cos(c)-north*sin(lat)*sin(c))
		lat = next_lat
	return PackedFloat64Array([fposmod(rad_to_deg(lon)+180.0,360.0)-180.0,rad_to_deg(lat)])

static func city_to_geo(selection: Dictionary, grid: Vector2) -> Vector2:
	return local_to_geo(selection,(grid-Vector2(64,64))*(float(selection.side_km)*1000.0/128.0))

static func _edge(selection: Dictionary, edge: int, t: float, radius: float) -> float:
	var x := t
	var y := radius
	if edge == 1: y=-radius
	elif edge == 2: x=radius; y=t
	elif edge == 3: x=-radius; y=t
	return _local_to_geo_scalars(selection,x,y)[1]

static func validate_selection(selection: Dictionary) -> Dictionary:
	for key in ["latitude","longitude","side_km","bearing"]:
		if not selection.has(key) or not (selection[key] is float or selection[key] is int) or not is_finite(float(selection[key])):
			return {"ok":false,"error":"Selection requires finite numeric " + key}
	if selection.latitude < -60.0 or selection.latitude > 82.75 or selection.longitude < -180.0 or selection.longitude > 180.0 or selection.side_km < 0.5 or selection.side_km > 128.0 or selection.bearing < 0.0 or selection.bearing > 359.0:
		return {"ok":false,"error":"Selection is outside allowed bounds"}
	var radius := float(selection.side_km)*500.0
	var low := 90.0
	var high := -90.0
	# For these sub-91 km footprints latitude has at most one interior extremum
	# on each edge. Search both signs; endpoints always participate.
	for edge in 4:
		for sign_value in [-1.0,1.0]:
			var a := -radius
			var b := radius
			for iteration in 64:
				var left := (2.0*a+b)/3.0
				var right := (a+2.0*b)/3.0
				if sign_value*_edge(selection,edge,left,radius) < sign_value*_edge(selection,edge,right,radius): a=left
				else: b=right
			for t in [-radius,radius,(a+b)/2.0]:
				var latitude := _edge(selection,edge,t,radius)
				low=minf(low,latitude)
				high=maxf(high,latitude)
	if low < -60.0 or high > 82.75:
		return {"ok":false,"error":"Complete rotated boundary exceeds source latitude coverage"}
	return {"ok":true,"error":"","latitude_min":low,"latitude_max":high}

static func elevation_pixel(geo: Vector2, zoom: int) -> Vector2:
	var coordinates := _elevation_pixel_scalars(geo.x,geo.y,zoom)
	return Vector2(coordinates[0],coordinates[1])

static func _elevation_pixel_scalars(longitude: float, latitude: float, zoom: int) -> PackedFloat64Array:
	var size := float(256*(1<<zoom))
	var lat := deg_to_rad(latitude)
	return PackedFloat64Array([(fposmod(longitude+180.0,360.0)/360.0)*size-0.5,(1.0-log(tan(lat)+1.0/cos(lat))/PI)*size/2.0-0.5])

static func worldcover_address(geo: Vector2) -> Dictionary:
	return _worldcover_address_scalars(geo.x,geo.y)

static func _worldcover_address_scalars(lon: float, latitude: float) -> Dictionary:
	var longitude := fposmod(lon+180.0,360.0)-180.0
	var west := int(floor(longitude/3.0))*3
	var south := int(floor(latitude/3.0))*3
	var token := ("N" if south>=0 else "S")+"%02d"%absi(south)+("E" if west>=0 else "W")+"%03d"%absi(west)
	return {"tile":token,"x":clampi(int(floor((longitude-west)/3.0*WORLD_COVER_PIXELS)),0,35999),"y":clampi(int(floor((south+3.0-latitude)/3.0*WORLD_COVER_PIXELS)),0,35999)}

# Allocation-free projector for the planning loops. Each expression repeats
# _local_to_geo_scalars/_elevation_pixel_scalars operation for operation, with
# per-selection trigonometry hoisted, so it returns exactly the same doubles.
class _Projector extends RefCounted:
	var mpt := 0.0
	var cos_angle := 0.0
	var sin_angle := 0.0
	var lat0 := 0.0
	var lon0 := 0.0
	var cos_lat0 := 0.0
	var sin_lat0 := 0.0
	var size := 0.0
	var longitude := 0.0
	var latitude := 0.0
	var px := 0.0
	var py := 0.0
	func _init(selection: Dictionary, zoom: int) -> void:
		mpt=float(selection.side_km)*1000.0/128.0
		var angle := deg_to_rad(float(selection.bearing))
		cos_angle=cos(angle)
		sin_angle=sin(angle)
		lat0=deg_to_rad(float(selection.latitude))
		lon0=deg_to_rad(float(selection.longitude))
		cos_lat0=cos(lat0)
		sin_lat0=sin(lat0)
		size=float(256*(1<<zoom))
	func city(gx: float, gy: float) -> void:
		var x := (gx-64.0)*mpt
		var y := (gy-64.0)*mpt
		var east := x*cos_angle-y*sin_angle
		var north := -x*sin_angle-y*cos_angle
		var rho := sqrt(east*east+north*north)
		var lat := lat0
		var lon := lon0
		if rho > 0.0:
			var c := rho/RADIUS
			var next_lat := asin(clampf(cos(c)*sin_lat0+north*sin(c)*cos_lat0/rho,-1.0,1.0))
			lon += atan2(east*sin(c),rho*cos_lat0*cos(c)-north*sin_lat0*sin(c))
			lat = next_lat
		longitude=fposmod(rad_to_deg(lon)+180.0,360.0)-180.0
		latitude=rad_to_deg(lat)
	func pixel() -> void:
		var lat := deg_to_rad(latitude)
		px=(fposmod(longitude+180.0,360.0)/360.0)*size-0.5
		py=(1.0-log(tan(lat)+1.0/cos(lat))/PI)*size/2.0-0.5

# Integer-keyed equivalent of _elevation_neighbors; keys become z/x/y strings once.
static func _neighbor_keys(px: float, py: float, zoom: int, keys: Dictionary) -> bool:
	var size := 256*(1<<zoom)
	for dy in 2:
		for dx in 2:
			var x := posmod(int(floor(px))+dx,size)/256
			var y := (int(floor(py))+dy)/256
			if y<0 or y >= (1<<zoom): return false
			keys[(x<<16)|y]=true
	return keys.size()<=64

static func _cancelled(cancelled: Callable) -> bool:
	return cancelled.is_valid() and bool(cancelled.call())

static func plan_samples(selection: Dictionary, cancelled: Callable = Callable()) -> Dictionary:
	var valid := validate_selection(selection)
	if not valid.ok: return valid
	var mpt := float(selection.side_km)*1000.0/128.0
	# Source detail is chosen at the selected center; boundary governs coverage.
	var latitude := float(selection.latitude)
	var zoom := 0
	while zoom<15 and 2.0*PI*RADIUS*cos(deg_to_rad(latitude))/(256.0*(1<<zoom)) > mpt/2.0: zoom+=1
	var projector := _Projector.new(selection,zoom)
	var vertices := PackedFloat64Array()
	var centers := PackedFloat64Array()
	var tile_keys := {}
	var offsets := PackedFloat64Array([-0.5,0.0,0.5])
	for y in 129:
		if _cancelled(cancelled): return {"ok":false,"error":"canceled"}
		for x in 129:
			for oy in offsets:
				for ox in offsets:
					projector.city(x+ox,y+oy)
					if projector.latitude < -60.0 or projector.latitude > 82.75: return {"ok":false,"error":"Required stencil exceeds source latitude coverage"}
					projector.pixel()
					vertices.append(projector.px)
					vertices.append(projector.py)
					if not _neighbor_keys(projector.px,projector.py,zoom,tile_keys): return {"ok":false,"error":"Elevation request budget exceeds 64 tiles"}
	for y in 128:
		if _cancelled(cancelled): return {"ok":false,"error":"canceled"}
		for x in 128:
			projector.city(x+0.5,y+0.5)
			projector.pixel()
			centers.append(projector.px)
			centers.append(projector.py)
			if not _neighbor_keys(projector.px,projector.py,zoom,tile_keys): return {"ok":false,"error":"Elevation request budget exceeds 64 tiles"}
	var descriptors := {}
	for key: int in tile_keys:
		var tx: int = key>>16
		var ty: int = key&0xFFFF
		descriptors["%d/%d/%d"%[zoom,tx,ty]]={"source":"terrarium","z":zoom,"x":tx,"y":ty}
	var groups := {}
	# Tile tokens change only at three-degree cells. Short runs are buffered and
	# appended in order, so each group keeps row-major tile, then subgrid order.
	var token := ""
	var cell_west := 0
	var cell_south := 0
	var run := PackedInt32Array()
	for y in 128:
		if _cancelled(cancelled): return {"ok":false,"error":"canceled"}
		for x in 128:
			for sy in 8:
				for sx in 8:
					projector.city(x+(sx+0.5)/8.0,y+(sy+0.5)/8.0)
					# Repeats _worldcover_address_scalars without its Dictionary/String.
					var longitude := fposmod(projector.longitude+180.0,360.0)-180.0
					var west := int(floor(longitude/3.0))*3
					var south := int(floor(projector.latitude/3.0))*3
					if token.is_empty() or west!=cell_west or south!=cell_south:
						if not run.is_empty(): groups[token].append_array(run)
						run.clear()
						cell_west=west
						cell_south=south
						token=("N" if south>=0 else "S")+"%02d"%absi(south)+("E" if west>=0 else "W")+"%03d"%absi(west)
						if not groups.has(token): groups[token]=PackedInt32Array()
						if groups.size()>512: return {"ok":false,"error":"Water source budget exceeds 512 tiles"}
					# Row-major tile, then row-major subgrid; no per-sample dictionaries retained.
					run.append((y*128+x)*64+sy*8+sx)
					run.append(clampi(int(floor((longitude-west)/3.0*WORLD_COVER_PIXELS)),0,35999))
					run.append(clampi(int(floor((south+3.0-projector.latitude)/3.0*WORLD_COVER_PIXELS)),0,35999))
					if run.size()>=3072:
						groups[token].append_array(run)
						run.clear()
	if not run.is_empty(): groups[token].append_array(run)
	run=PackedInt32Array()
	var sources: Array[Dictionary] = []
	var keys := descriptors.keys()
	keys.sort()
	for key in keys: sources.append(descriptors[key])
	keys=groups.keys()
	keys.sort()
	for key in keys: sources.append({"source":"worldcover","tile":key})
	return {"ok":true,"error":"","zoom":zoom,"source_spacing_metres":2.0*PI*RADIUS*cos(deg_to_rad(latitude))/(256.0*(1<<zoom)),"metres_per_tile":mpt,"vertex_stencils":vertices,"centers":centers,"water_groups":groups,"sources":sources,"elevation_tiles":descriptors.size(),"water_tiles":groups.size(),"water_samples":1048576,"vertex_samples":149769,"center_samples":16384}
