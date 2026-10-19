# SPDX-License-Identifier: GPL-3.0-or-later
## Bounded presentation pool. Actor owners supply every clock and pose.
class_name ExploreActorDetailManager
extends RefCounted
const LIMIT := 24
const RIG_LIMIT := 16
const ENTER := 18.0/16.0
const EXIT := 26.0/16.0
const VEHICLE_ENTER := 192.0/16.0
const VEHICLE_EXIT := 256.0/16.0
var _parent: Node3D
var _selected: Dictionary = {}
var _pool: Array[Dictionary] = []
var _created := 0
var _reused := 0
var _updates := 0
func bind(parent: Node3D) -> void:
	clear()
	_parent=parent
func update(candidates: Array[Dictionary], camera: Camera3D) -> Dictionary:
	if not is_instance_valid(_parent):
		clear()
		return {}
	var eligible: Array[Dictionary] = []
	if is_instance_valid(_parent) and is_instance_valid(camera) and _parent.is_visible_in_tree():
		var frustum := camera.get_frustum()
		for state in candidates:
			var id: String=state.id
			if state.get("excluded",false) or not state.get("visible",true): continue
			var distance: float=camera.global_position.distance_squared_to(state.position)
			var pedestrian := String(state.kind)=="pedestrian"
			var radius: float=(EXIT if _selected.has(id) else ENTER) if pedestrian else (VEHICLE_EXIT if _selected.has(id) else VEHICLE_ENTER)
			if distance>radius*radius or not _body_in_frustum(state,frustum): continue
			eligible.append({"state":state,"distance":distance})
	eligible.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		return String(a.state.id)<String(b.state.id) if a.distance==b.distance else a.distance<b.distance)
	var wanted: Dictionary={}
	var rigs:=0
	for entry in eligible:
		var state: Dictionary=entry.state
		if wanted.has(state.id): continue
		if String(state.kind)=="pedestrian":
			if rigs>=RIG_LIMIT: continue
			rigs+=1
		wanted[state.id]=state
		# Vehicles have their own population bound in CityTraffic3D. A nearby
		# crowd or a changing nearest-first order must never demote a vehicle.
	var capacity := maxi(LIMIT,wanted.size()+RIG_LIMIT)
	var next: Dictionary={}
	var used: Dictionary={}
	for slot in _pool:
		if wanted.has(slot.id) and slot.key==_key(wanted[slot.id]):
			next[slot.id]=slot.visual
			used[slot.visual]=true
		else: slot.visual.visible=false
	for id: String in wanted:
		if next.has(id): continue
		var key:=_key(wanted[id])
		var available: Dictionary={}
		for slot in _pool:
			if not used.has(slot.visual) and slot.key==key:
				available=slot
				break
		if available.is_empty():
			# Inactive instances count against both limits too.
			var rig_count:=0
			for slot in _pool:
				if slot.pedestrian: rig_count+=1
			if _pool.size()>=capacity or (String(wanted[id].kind)=="pedestrian" and rig_count>=RIG_LIMIT):
				for slot in _pool:
					if used.has(slot.visual): continue
					if String(wanted[id].kind)=="pedestrian" and rig_count>=RIG_LIMIT and not slot.pedestrian: continue
					slot.visual.free()
					_pool.erase(slot)
					break
			var visual:=CityTrafficCatalog.make_nearby_visual(StringName(wanted[id].kind),int(wanted[id].variant))
			_parent.add_child(visual)
			available={"id":id,"key":key,"visual":visual,"pedestrian":String(wanted[id].kind)=="pedestrian"}
			_pool.append(available)
			_created+=1
		else:
			available.id=id
			_reused+=1
		next[id]=available.visual
		used[available.visual]=true
	# Retain only a small reusable cache after a busy street leaves view.
	for i in range(_pool.size()-1,-1,-1):
		if _pool.size()<=capacity: break
		if used.has(_pool[i].visual): continue
		_pool[i].visual.free()
		_pool.remove_at(i)
	_selected=next
	for id: String in _selected:
		var visual: ExploreActorVisual=_selected[id]
		visual.visible=true
		_sample(visual,wanted[id])
	return _selected.duplicate()

## Feet or the vehicle origin can leave the screen before the visible body.
## Test its oriented envelope against each camera plane, keeping the existing
## distance hysteresis and pool caps independent of this visibility decision.
func _body_in_frustum(state: Dictionary, frustum: Array[Plane]) -> bool:
	var bounds := CityTrafficCatalog.visual_bounds(StringName(state.kind))
	var basis := Basis(Vector3.UP,float(state.yaw))
	var center: Vector3=state.position+basis*bounds.get_center()
	var half := bounds.size*.5
	for plane in frustum:
		var reach := absf(plane.normal.dot(basis.x))*half.x+absf(plane.normal.dot(basis.y))*half.y+absf(plane.normal.dot(basis.z))*half.z
		if plane.distance_to(center)>reach: return false
	return true

func _key(state: Dictionary) -> String:
	return String(state.kind)+":"+str(posmod(int(state.variant),16) if String(state.kind)=="pedestrian" else 0)
func _sample(visual: ExploreActorVisual,state: Dictionary) -> void:
	visual.position=state.position
	visual.rotation.y=float(state.yaw)
	visual.sample_owned_state(state)
func advance(states: Array[Dictionary], delta: float) -> void:
	if not is_instance_valid(_parent):
		clear()
		return
	if not is_finite(delta) or delta<=0: return
	for state in states:
		if _selected.has(state.id):
			_sample(_selected[state.id],state)
			_updates+=1
## Owner ticks need membership, without enumerating the pool's debug state.
func contains(id: String) -> bool:
	return _selected.has(id)
func is_empty() -> bool:
	return _selected.is_empty()
func clear() -> void:
	for slot in _pool:
		if is_instance_valid(slot.visual): slot.visual.free()
	_pool.clear()
	_selected.clear()
func debug_state() -> Dictionary:
	var rigs:=0
	for visual: ExploreActorVisual in _selected.values():
		if visual.has_meta("nearby_pedestrian"): rigs+=1
	return {"detailed_count":_selected.size(),"pedestrian_rigs":rigs,"allocated":_pool.size(),"created":_created,"reused":_reused,"owner_updates":_updates,"ids":_selected.keys().duplicate()}
