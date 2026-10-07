# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Read-only road bores. Imported cities mark 1 at mouths and 2 under hills;
## native cities use axis bits. Reciprocal portals and an uninterrupted marked run,
## rather than either bit convention alone, establish a finite through tunnel.
extends RefCounted
const WIDTH := .82
const CLEAR_HEIGHT := .48

static func profiles(city: City) -> Dictionary:
	var result := {}
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var start := Vector2i(x,y)
			var code := city.building.atv(start)
			if not NetworkShapes.is_tunnel(code) or result.has(start): continue
			var direction: Vector2i = [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN][code-Buildings.TUNNEL_FIRST]
			var cells: Array[Vector2i] = [start]
			var end := start+direction
			while city.in_bounds(end.x,end.y):
				var other := city.building.atv(end)
				if NetworkShapes.is_tunnel(other): break
				if city.tunnel_bits(end.x,end.y)==0: break
				cells.append(end)
				end += direction
			if not city.in_bounds(end.x,end.y): continue
			if city.building.atv(end)!=Buildings.TUNNEL_FIRST+posmod(code-Buildings.TUNNEL_FIRST+2,4): continue
			if cells.size()==1 and (city.tunnel_bits(start.x,start.y)==0 or city.tunnel_bits(end.x,end.y)==0): continue
			cells.append(end)
			var outside := Vector2(.5,.5)-Vector2(direction)*.5
			var h0 := CityGeometry3D.point_on_ground(city,start,outside).y
			var h1 := CityGeometry3D.point_on_ground(city,end,Vector2.ONE-outside).y
			for i: int in cells.size():
				var cell := cells[i]
				result[cell] = {"inward":Vector2(direction),"outside":outside,"across":Vector2(-direction.y,direction.x),
					"depth":1.0,"width":WIDTH,"floor_start":lerpf(h0,h1,float(i)/cells.size())+.04,
					"floor_end":lerpf(h0,h1,float(i+1)/cells.size())+.04,"tunnel":true,
					"entrance":i==0,"exit":i==cells.size()-1,"mouth_height":CLEAR_HEIGHT}
	return result

static func passage(cell: Vector2i, profile: Dictionary) -> Dictionary:
	var center := Vector2(cell)+Vector2(.5,.5)
	var low := minf(profile.floor_start,profile.floor_end)-.05
	var high := maxf(profile.floor_start,profile.floor_end)+CLEAR_HEIGHT
	var size := Vector3(WIDTH,high-low,1.002) if profile.inward.y!=0 else Vector3(1.002,high-low,WIDTH)
	var bounds := AABB(Vector3(center.x-size.x*.5,low,center.y-size.z*.5),size)
	return {"at":Transform3D.IDENTITY,"inverse":Transform3D.IDENTITY,"bounds":bounds}

static func contains(point: Vector3, profiles_by_cell: Dictionary) -> bool:
	var cell := Vector2i(floori(point.x),floori(point.z))
	var profile: Dictionary = profiles_by_cell.get(cell,{})
	if profile.is_empty(): return false
	var local: Vector2 = Vector2(point.x-cell.x,point.z-cell.y)-profile.outside
	var depth: float = local.dot(profile.inward)
	var floor_y: float = lerpf(profile.floor_start,profile.floor_end,depth)
	return depth>=0 and depth<=1 and absf(local.dot(profile.across))<WIDTH*.5 and point.y>=floor_y-.04 and point.y<floor_y+CLEAR_HEIGHT-.02
