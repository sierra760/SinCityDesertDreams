# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Read-only lookup of gaming resort entrances for Explore. A resort's front
## is the lot side its model faces (CityBuildings3D.resort_yaw: authored +Z,
## turned toward an adjacent street); its threshold is the outdoor pose at the
## middle of that front. Nothing here writes the city.
extends RefCounted

const Layouts := preload("res://scripts/exploration/resorts/resort_interior_layouts.gd")
## How close, in tile units, the walker must be to the threshold.
const REACH := .65
## Vertical tolerance: the apron of a sloped lot, never a hall far below.
const HEIGHT_REACH := 1.2
## Distance of the threshold from the lot's back edge, toward the front. Desert
## Orbit's entrance pods reach further toward the street than the others.
const FRONT := 3.75
const FRONT_BY_CODE := {254: 3.87}

## True when `anchor` is the anchor of a standing resort of a known code.
static func exists(city: City, anchor: Vector2i, code: int) -> bool:
	if city == null or Layouts.key_for_building(code).is_empty(): return false
	if not city.in_bounds(anchor.x,anchor.y) or city.building.atv(anchor) != code: return false
	return city.anchor_of(anchor.x,anchor.y) == anchor

## The nearest resort whose threshold is within reach of `position`, as
## {key, code, anchor, rect, threshold}, or {}.
static func nearby(city: City, position: Vector3) -> Dictionary:
	if city == null or not position.is_finite(): return {}
	var cell := Vector2i(floori(position.x),floori(position.z))
	var seen: Dictionary = {}
	var best: Dictionary = {}
	var distance := REACH*REACH
	# A threshold lies inside its lot, within .25 of the front edge on any
	# side, so a walker in reach stands on or beside a lot cell.
	for y: int in range(cell.y-1,cell.y+2):
		for x: int in range(cell.x-1,cell.x+2):
			if not city.in_bounds(x,y): continue
			var code := city.building.atv(Vector2i(x,y))
			if Layouts.key_for_building(code).is_empty(): continue
			var anchor := city.anchor_of(x,y)
			if seen.has(anchor): continue
			seen[anchor] = true
			if not exists(city,anchor,code): continue
			var pose := threshold(city,anchor,code)
			if absf(pose.origin.y-position.y)>HEIGHT_REACH: continue
			var gap := Vector2(position.x-pose.origin.x,position.z-pose.origin.z).length_squared()
			if gap>distance or (code == 126 and gap>.14*.14): continue
			distance = gap
			best = {"key": Layouts.key_for_building(code), "code": code, "anchor": anchor,
				"rect": Rect2i(anchor,Buildings.size(code)), "threshold": pose}
	return best

## The outdoor pose at the lot's front centre: on the visible ground 3.75
## from the back edge (anchor.y+3.75 for the authored +Z front), facing into
## the building. Its basis is the model's yaw, so its forward (-Z) points in.
static func threshold(city: City, anchor: Vector2i, code: int = -1) -> Transform3D:
	if code<0 and city != null and city.in_bounds(anchor.x,anchor.y): code = city.building.atv(anchor)
	var size := Buildings.size(code) if code >= 0 else Vector2i(4,4)
	# The one-tile store retains its authored exterior facing; resorts turn to streets.
	var yaw := CityBuildings3D.resort_yaw(city,Rect2i(anchor,size)) if city != null and code != 126 else 0.0
	var front := Vector2(sin(yaw),cos(yaw))
	var center := Vector2(size)*.5
	var distance := .25 if code == 126 else float(FRONT_BY_CODE.get(code,FRONT))-2.0
	var point := Vector2(anchor)+center+front*distance
	var cell := Vector2i(floori(point.x),floori(point.y))
	var ground := 0.0
	if city != null and city.in_bounds(cell.x,cell.y):
		ground = CityGeometry3D.visible_ground_height(city,cell,point-Vector2(cell))
	return Transform3D(Basis(Vector3.UP,yaw),Vector3(point.x,ground,point.y))
