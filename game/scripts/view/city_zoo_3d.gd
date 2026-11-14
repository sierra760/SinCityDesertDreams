# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The animals of every Zoo (building 218), the Mirage Menagerie.
## Like the livestock, they live beside the compiled city, outside its static
## batches, and follow each zoo lot's authored placement. Presentation only:
## no city state, save data or game random stream. Explore visitors read a
## pen's plaque (nearest_exhibit/perform) and its animal does a trick.
class_name CityZoo3D
extends Node3D

## Detail follows how tall an animal appears on screen, in pixels: smaller
## than DRAW_PIXELS it is not drawn, smaller than ANIMATE_PIXELS (or off
## camera) it holds still, and only from SHADOW_PIXELS does it cast a shadow.
const DRAW_PIXELS := 2.0
const ANIMATE_PIXELS := 3.0
const SHADOW_PIXELS := 24.0
## A drawn animal's height in tiles (about 2.5 m at its 1.25 scale).
const ANIMAL_TILES := .2
## Half the lot's diagonal in tiles: the nearest a pen can be to the camera
## relative to the lot centre.
const LOT_REACH := 2.83
## How close (lot metres, on the ground) a visitor must stand to a plaque.
const READ_METRES := 3.0

var buildings: CityBuildings3D
var _revision := -1
## Lot instance id -> {"lot": Node3D, "anchor": Node3D, "animals": Array[ZooAnimal]}
var _zoos: Dictionary = {}

func clear() -> void:
	for id: int in _zoos.keys(): _remove(id)
	_zoos.clear()
	_revision = -1

func zoo_count() -> int:
	return _zoos.size()

func animals() -> Array[ZooAnimal]:
	var out: Array[ZooAnimal] = []
	for zoo: Dictionary in _zoos.values():
		for animal: ZooAnimal in zoo.animals: out.append(animal)
	return out

## Follow added, removed and replaced zoo lots; cheap when nothing changed.
func sync() -> void:
	if not is_instance_valid(buildings):
		if not _zoos.is_empty(): clear()
		return
	if buildings.zoo_revision == _revision: return
	_revision = buildings.zoo_revision
	for id: int in _zoos.keys():
		var zoo: Dictionary = _zoos[id]
		if not buildings.zoo_lots.has(id) or not is_instance_valid(zoo.lot): _remove(id)
	for id: int in buildings.zoo_lots:
		if _zoos.has(id): continue
		var lot: Node3D = buildings.zoo_lots[id]
		if is_instance_valid(lot) and lot.has_meta("authored_transform"): _add(id,lot)

func _add(id: int, lot: Node3D) -> void:
	var anchor := Node3D.new()
	anchor.name = "Zoo"
	add_child(anchor)
	var at: Transform3D = lot.get_meta("authored_transform")
	if is_inside_tree() and buildings.is_inside_tree(): anchor.global_transform = buildings.global_transform*at
	else: anchor.transform = at
	var cell: Vector2i = lot.get_meta("cell",Vector2i.ZERO)
	var animals: Array[ZooAnimal] = []
	for i: int in ZooAnimal.ORDER.size():
		var animal := ZooAnimal.new()
		anchor.add_child(animal)
		animal.setup(ZooAnimal.ORDER[i],_phase(cell,i))
		animals.append(animal)
	_zoos[id] = {"lot":lot,"anchor":anchor,"animals":animals,"cell":cell}

func _remove(id: int) -> void:
	var zoo: Dictionary = _zoos.get(id,{})
	if zoo.is_empty(): return
	if is_instance_valid(zoo.anchor): zoo.anchor.free()
	_zoos.erase(id)

## A stable fraction from the lot cell and animal, so a zoo looks the same
## each time it is shown.
static func _phase(cell: Vector2i, index: int) -> float:
	var h := (cell.x*73856093) ^ (cell.y*19349663) ^ ((index+1)*83492791)
	h = (h ^ (h >> 13))*1274126177
	return float(posmod(h ^ (h >> 16),1 << 20))/float(1 << 20)

func advance(delta: float, camera: Camera3D, paused: bool, player_world: Vector3 = Vector3.INF) -> void:
	sync()
	if _zoos.is_empty() or not is_instance_valid(camera) or not camera.is_inside_tree(): return
	var viewport := camera.get_viewport()
	var height := viewport.get_visible_rect().size.y if viewport != null else 0.0
	var frustum: Array[Plane] = []
	if height > 0.0 and camera.get_world_3d() != null: frustum = camera.get_frustum()
	var active := is_visible_in_tree()
	for zoo: Dictionary in _zoos.values():
		var anchor: Node3D = zoo.anchor
		var pixels := screen_pixels(camera,anchor.global_position,height)
		var drawn := pixels >= DRAW_PIXELS
		var shadow := pixels >= SHADOW_PIXELS
		for animal: ZooAnimal in zoo.animals: animal.set_detail(drawn,shadow)
		if paused or not active or pixels < ANIMATE_PIXELS or not _in_view(anchor,frustum): continue
		var local := anchor.global_transform.affine_inverse()*player_world if player_world.is_finite() else Vector3.INF
		for animal: ZooAnimal in zoo.animals: animal.advance(delta,local)

## How tall an animal of the lot centred at `centre` appears, in pixels. In
## perspective the pens' nearest reach counts; orthographic sizes are uniform.
static func screen_pixels(camera: Camera3D, centre: Vector3, height: float) -> float:
	if height <= 0.0: return INF
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return height*ANIMAL_TILES/maxf(camera.size,.0001)
	var distance := maxf(camera.global_position.distance_to(centre)-LOT_REACH,.05)
	return height*ANIMAL_TILES/(2.0*distance*tan(deg_to_rad(camera.fov)*.5))

## The lot's box against the camera frustum (no frustum: always in view).
static func _in_view(anchor: Node3D, frustum: Array[Plane]) -> bool:
	if frustum.is_empty(): return true
	var at := anchor.global_position
	var corners: Array[Vector3] = []
	for x: float in [-2.0,2.0]:
		for y: float in [0.0,.3]:
			for z: float in [-2.0,2.0]: corners.append(at+Vector3(x,y,z))
	for plane: Plane in frustum:
		var outside := true
		for corner: Vector3 in corners:
			if plane.distance_to(corner) <= 0.0:
				outside = false
				break
		if outside: return false
	return true

## The pen plaque a visitor at `world_point` can read, or {}.
## {"animal": ZooAnimal, "name": String, "distance": metres}
func nearest_exhibit(world_point: Vector3) -> Dictionary:
	sync()
	var best := {}
	for zoo: Dictionary in _zoos.values():
		var anchor: Node3D = zoo.anchor
		if not is_instance_valid(anchor): continue
		var local := anchor.global_transform.affine_inverse()*world_point
		if absf(local.y-.2) > 3.0: continue
		for animal: ZooAnimal in zoo.animals:
			var plaque := ZooAnimal.plaque_point(animal.quadrant)
			var gap := Vector2(local.x-plaque.x,local.z-plaque.z).length()
			if gap <= READ_METRES and (best.is_empty() or gap < float(best.distance)):
				best = {"animal":animal,"name":animal.display_name(),"distance":gap}
	return best

## Read a plaque: its animal shows off, and the plaque's text is returned.
func perform(exhibit: Dictionary) -> String:
	var animal: ZooAnimal = exhibit.get("animal")
	if not is_instance_valid(animal): return ""
	animal.start_trick()
	return animal.fact()

func _exit_tree() -> void:
	clear()
