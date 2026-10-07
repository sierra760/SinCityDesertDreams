# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name TerrariumTiles
extends RefCounted

const PIXELS := 65536
const MAX_BODY := 2*1024*1024
const MIN_METRES := -12000.0
const MAX_METRES := 10000.0
const SIGNATURE := [137,80,78,71,13,10,26,10]
# PNG Adam7 passes, or the single ordinary pass.
const ADAM7 := [[0,0,8,8],[4,0,8,8],[0,4,4,8],[2,0,4,4],[0,2,2,4],[1,0,2,2],[0,1,1,2]]

static func _fail(error: String) -> Dictionary:
	return {"ok":false,"error":error}

static func _be32(body: PackedByteArray, at: int) -> int:
	return (int(body[at])<<24)|(int(body[at+1])<<16)|(int(body[at+2])<<8)|int(body[at+3])

static func _crc32(body: PackedByteArray, at: int, count: int, table: PackedInt64Array) -> int:
	var crc := 0xffffffff
	for index in range(at,at+count): crc=(crc>>8)^table[(crc^body[index])&255]
	return crc^0xffffffff

static func _crc_table() -> PackedInt64Array:
	var table := PackedInt64Array()
	table.resize(256)
	for i in 256:
		var value := i
		for bit in 8: value=(value>>1)^(0xedb88320 if value&1 else 0)
		table[i]=value
	return table

# Validate all framing, sizes and CRCs before allocating any Image. Numeric
# channels deliberately ignore gAMA/sRGB/iCCP; those are presentation metadata.
static func _png(body: PackedByteArray) -> Dictionary:
	if body.size()<45 or body.size()>MAX_BODY: return _fail("PNG body is empty, truncated or exceeds 2 MiB")
	for i in 8:
		if body[i]!=SIGNATURE[i]: return _fail("Invalid PNG signature")
	if _be32(body,8)!=13 or body.slice(12,16).get_string_from_ascii()!="IHDR": return _fail("PNG must begin with a 13-byte IHDR")
	if _be32(body,16)!=256 or _be32(body,20)!=256: return _fail("Terrarium PNG dimensions must be 256 by 256")
	if body[24]!=8 or not body[25] in [2,6] or body[26]!=0 or body[27]!=0 or body[28]>1: return _fail("Terrarium PNG must be 8-bit RGB or RGBA")
	var channels := 3 if body[25]==2 else 4
	var offset := 8
	var chunks := 0
	var has_data := false
	var data_ended := false
	var has_palette := false
	var has_transparency := false
	var transparent := PackedByteArray()
	var compressed := PackedByteArray()
	var table := _crc_table()
	while offset<body.size():
		if body.size()-offset<12: return _fail("Truncated PNG chunk")
		var length := _be32(body,offset)
		if length>MAX_BODY or length>body.size()-offset-12: return _fail("PNG chunk length exceeds bounded body")
		for i in range(offset+4,offset+8):
			if not (body[i]>=65 and body[i]<=90 or body[i]>=97 and body[i]<=122): return _fail("Invalid PNG chunk type")
		if body[offset+6]&32: return _fail("Invalid PNG reserved chunk bit")
		var kind := body.slice(offset+4,offset+8).get_string_from_ascii()
		if _crc32(body,offset+4,length+4,table)!=_be32(body,offset+8+length): return _fail("PNG chunk CRC mismatch")
		if kind=="IHDR":
			if chunks!=0: return _fail("Duplicate PNG IHDR")
		elif kind=="PLTE":
			if has_palette or has_data or length==0 or length>768 or length%3!=0: return _fail("Invalid PNG palette")
			has_palette=true
		elif kind=="tRNS":
			if channels!=3 or has_data or has_transparency or length!=6: return _fail("Invalid PNG transparency chunk")
			has_transparency=true
			transparent=body.slice(offset+8,offset+8+length)
		elif kind=="IDAT":
			if data_ended: return _fail("PNG IDAT chunks must be consecutive")
			has_data=true
			compressed.append_array(body.slice(offset+8,offset+8+length))
		elif kind=="IEND":
			if length!=0 or not has_data or compressed.is_empty() or offset+12!=body.size(): return _fail("Invalid PNG end or missing pixel data")
			return {"ok":true,"error":"","channels":channels,"interlace":body[28],"compressed":compressed,"transparent":transparent}
		elif not body[offset+4]&32: return _fail("Unsupported critical PNG chunk")
		if has_data and kind!="IDAT": data_ended=true
		chunks+=1
		offset+=length+12
	return _fail("Missing PNG IEND")

static func _paeth(a: int, b: int, c: int) -> int:
	var p := a+b-c
	var pa := absi(p-a)
	var pb := absi(p-b)
	var pc := absi(p-c)
	return a if pa<=pb and pa<=pc else (b if pb<=pc else c)

static func decode_png(body: PackedByteArray) -> Dictionary:
	var png := _png(body)
	if not png.ok: return png
	var channels := int(png.channels)
	var passes := ADAM7 if png.interlace else [[0,0,1,1]]
	var expected := 0
	for pass_info in passes:
		var width := (255-int(pass_info[0]))/int(pass_info[2])+1
		var height := (255-int(pass_info[1]))/int(pass_info[3])+1
		expected+=(width*channels+1)*height
	var inflated := TerrainZlib.inflate_exact(png.compressed,expected)
	if not inflated.ok: return inflated
	var scanlines: PackedByteArray = inflated.bytes
	var raw := PackedByteArray()
	raw.resize(PIXELS*channels)
	var cursor := 0
	for pass_info in passes:
		var width := (255-int(pass_info[0]))/int(pass_info[2])+1
		var height := (255-int(pass_info[1]))/int(pass_info[3])+1
		var stride := width*channels
		var previous := PackedByteArray()
		previous.resize(stride)
		for row in height:
			var filter := int(scanlines[cursor])
			cursor+=1
			if filter>4: return _fail("Invalid PNG scanline filter")
			var current := PackedByteArray()
			current.resize(stride)
			for i in stride:
				var a := int(current[i-channels]) if i>=channels else 0
				var b := int(previous[i])
				var c := int(previous[i-channels]) if i>=channels else 0
				var predictor := 0
				if filter==1: predictor=a
				elif filter==2: predictor=b
				elif filter==3: predictor=(a+b)/2
				elif filter==4: predictor=_paeth(a,b,c)
				current[i]=(int(scanlines[cursor+i])+predictor)&255
			cursor+=stride
			for col in width:
				var x := int(pass_info[0])+col*int(pass_info[2])
				var y := int(pass_info[1])+row*int(pass_info[3])
				var target := (y*256+x)*channels
				for channel in channels: raw[target+channel]=current[col*channels+channel]
			previous=current
	# An Image holds the raw numeric RGB byte plane. No PNG loader, texture,
	# color-space conversion or floating-point Color channel is involved.
	var image := Image.create_from_data(256,256,false,Image.FORMAT_RGB8 if channels==3 else Image.FORMAT_RGBA8,raw)
	if image.get_width()!=256 or image.get_height()!=256: return _fail("Decoded Terrarium size mismatch")
	raw=image.get_data()
	if raw.size()!=PIXELS*channels: return _fail("Decoded Terrarium byte size mismatch")
	var metres := PackedFloat64Array()
	metres.resize(PIXELS)
	for pixel in PIXELS:
		var at := pixel*channels
		if channels==4 and raw[at+3]!=255: return _fail("Terrarium contains transparent pixels")
		if not png.transparent.is_empty():
			var t: PackedByteArray = png.transparent
			if int(raw[at])==int(t[0])*256+t[1] and int(raw[at+1])==int(t[2])*256+t[3] and int(raw[at+2])==int(t[4])*256+t[5]: return _fail("Terrarium contains transparent pixels")
		var value := int(raw[at])*256.0+int(raw[at+1])+int(raw[at+2])/256.0-32768.0
		if not is_finite(value) or value<MIN_METRES or value>MAX_METRES: return _fail("Terrarium elevation is outside plausible DEM bounds")
		metres[pixel]=value
	return {"ok":true,"error":"","metres":metres}

# Pixel coordinates already refer to pixel centers, so no half-pixel offset is
# applied here. This Vector2 wrapper is single precision.
static func sample_bilinear(pixel: Vector2, zoom: int, tiles: Dictionary) -> Dictionary:
	return sample_bilinear_xy(pixel.x,pixel.y,zoom,tiles)

# The importer calls this directly with the planner's 64-bit coordinates.
# tiles maps z/x/y -> a successful decode_png result with fractional metres.
static func sample_bilinear_xy(x: float, y: float, zoom: int, tiles: Dictionary) -> Dictionary:
	if zoom<0 or zoom>30 or not is_finite(x) or not is_finite(y): return _fail("Invalid Terrarium sample coordinate or zoom")
	var size := 256*(1<<zoom)
	x=fposmod(x,float(size))
	if y<0.0 or y>=float(size-1): return _fail("Terrarium bilinear latitude neighbors exceed source bounds")
	var left := int(floor(x))
	var top := int(floor(y))
	var fx := x-left
	var fy := y-top
	# Neighbors usually share one tile, so look up and validate a tile only when
	# it changes from the previous neighbor.
	var v00 := 0.0
	var v10 := 0.0
	var v01 := 0.0
	var v11 := 0.0
	var last_x := -1
	var last_y := -1
	var key := ""
	var metres := PackedFloat64Array()
	for n in 4:
		var px := posmod(left+(n&1),size)
		var py := top+(n>>1)
		if px/256!=last_x or py/256!=last_y:
			last_x=px/256
			last_y=py/256
			key="%d/%d/%d"%[zoom,last_x,last_y]
			if not tiles.has(key) or not tiles[key] is Dictionary: return _fail("Missing Terrarium neighbor: "+key)
			var tile: Dictionary = tiles[key]
			if tile.get("ok")!=true or not tile.get("metres") is PackedFloat64Array or tile.metres.size()!=PIXELS: return _fail("Invalid decoded Terrarium neighbor: "+key)
			metres=tile.metres
		var value := float(metres[(py%256)*256+px%256])
		if not is_finite(value) or value<MIN_METRES or value>MAX_METRES: return _fail("Invalid Terrarium neighbor meters: "+key)
		if n==0: v00=value
		elif n==1: v10=value
		elif n==2: v01=value
		else: v11=value
	return {"ok":true,"error":"","metres":lerpf(lerpf(v00,v10,fx),lerpf(v01,v11,fx),fy)}
