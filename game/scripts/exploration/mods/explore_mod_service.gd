# SPDX-License-Identifier: GPL-3.0-or-later
class_name ExploreModService
extends RefCounted
var controller: CityExplorationController
var runtime := ExploreModRuntime.new()
var actors := ExploreActorRegistry.new()
var queries := ExploreWorldQueries.new()
var api := ExploreModApi.new()
static var _next_generation := 0
var generation := 0
var _packs: Array[Dictionary] = []
var _progress: ExploreModProgress
var _active := false
var _revision := -1
var _running_hashes: Dictionary = {}
var _pending_start: Dictionary = {}

func bind(value: CityExplorationController, packs: Array[Dictionary], progress: ExploreModProgress) -> void:
	controller = value
	_packs = packs.duplicate(true)
	_progress = progress
	if not runtime.owner_disabled.is_connected(_owner_disabled): runtime.owner_disabled.connect(_owner_disabled)

func enter() -> void:
	if _active: leave("reenter")
	_next_generation += 1
	generation = _next_generation
	queries.bind(controller.view.traffic.graph,controller.traversal)
	queries.traffic = controller.view.traffic
	actors.bind(controller,controller.view.traffic,generation)
	actors.queries = queries
	api.actors = actors
	api.queries = queries
	api.generation = generation
	api.runtime = runtime
	api.environment.bind(controller.view,controller.camera_rig.camera)
	if not RenderingServer.frame_pre_draw.is_connected(_refresh_environment_mask): RenderingServer.frame_pre_draw.connect(_refresh_environment_mask)
	api.interactions.actors = actors
	api.interactions.busy = controller.mod_dialogue_busy
	api.interactions.present = controller.present_mod_dialogue
	api.interactions.dismiss = controller.dismiss_mod_dialogue
	_active = true
	_update_context()
	runtime.bind(_packs,_progress,generation)
	_running_hashes.clear()
	_pending_start.clear()
	for pack in _packs:
		_running_hashes[pack.manifest.id] = pack.content_hash
	runtime.resource_counts = api.resource_metrics()

func _update_context() -> void:
	if is_instance_valid(controller.occupied):
		queries.player = ExploreWorldQueries.copied_point(controller.occupied.feet_position(),queries.graph.revision)
		queries.player["mode"] = int(controller.mode)
		queries.player["vehicle"] = ""
		if not controller._traffic_claim.is_empty():
			for id: String in actors._actors:
				if actors._actors[id].record.id == controller._traffic_claim.id: queries.player["vehicle"] = id
	queries.reserved_rail = controller.view.traffic._reserved_rail
	if _revision != queries.graph.revision:
		runtime.invalidate_queries()
		_revision = queries.graph.revision

func _indoors() -> bool:
	return controller.camera_rig.interior_active or (is_instance_valid(controller.resort_service) and controller.resort_service.is_inside())

func _refresh_environment_mask() -> void:
	if _active and is_instance_valid(controller) and is_instance_valid(controller.camera_rig): api.environment.step(0,_indoors())

func step(delta: float, suspended: bool) -> void:
	if not _active: return
	var indoors := _indoors()
	api.environment.step(0 if suspended else maxf(0,delta),indoors)
	if suspended:
		runtime.step(0,true,{})
		return
	_update_context()
	for event in api.interactions.take_choices(): runtime.deliver(event.owner,event)
	for event in api.step(maxf(0,delta),runtime):
		api.complete(event)
		runtime.deliver(event.owner,event)
	for event in actors.step(maxf(0,delta)):
		api.complete(event)
		runtime.deliver(event.owner,event)
	for command in runtime.step(delta,false,{}):
		# An earlier host completion in this batch may have disabled the owner.
		if not runtime.has_owner(command.owner): continue
		var event := api.apply(command)
		runtime.accept_command(command,event)
		if not runtime.has_owner(command.owner): continue
		if not event.is_empty():
			if command.kind == "actor.inspect": runtime.cache_query(command.owner,command.kind,[command.args.id],{"ok":event.code == "ok","code":event.code,"data":event.data})
			runtime.deliver(event.owner,event)

	runtime.resource_counts = api.resource_metrics()

func activate_interaction() -> bool:
	var result := api.interactions.activate(queries.player)
	if result.code != "ok": return false
	runtime.deliver(result.event.owner,result.event)
	return true

func leave(reason: String) -> void:
	if not _active: return
	runtime.stop(reason)
	if RenderingServer.frame_pre_draw.is_connected(_refresh_environment_mask): RenderingServer.frame_pre_draw.disconnect(_refresh_environment_mask)
	# Also remove host-created fixture/extension actors without live VMs.
	for actor in actors._actors.values().duplicate(): api.clear_owner(actor.owner)
	api.environment.restore()
	api._pending.clear()
	api._timers.clear()
	api._outstanding.clear()
	queries.bind(controller.view.traffic.graph,controller.traversal)
	runtime.resource_counts = api.resource_metrics()
	_active = false

func disable(id: String) -> void:
	runtime.disable(id,"disabled")
	_running_hashes.erase(id)
	_pending_start.erase(id)

func _owner_disabled(owner: String, _reason: String) -> void:
	api.clear_owner(owner)
	runtime.resource_counts = api.resource_metrics()

func configure_packs(packs: Array[Dictionary]) -> void:
	if _active and not controller.is_suspended(): return
	var selected := {}
	for pack in packs: selected[pack.manifest.id] = pack.content_hash
	for owner: String in _running_hashes.keys():
		if not selected.has(owner) or selected[owner] != _running_hashes[owner]:
			disable(owner)
	for owner: String in selected:
		if not _running_hashes.has(owner): _pending_start[owner] = true
	for owner: String in _pending_start.keys():
		if not selected.has(owner): _pending_start.erase(owner)
	_packs = packs.duplicate(true)

## Explicit Resume admits only missing owners. An unchanged owner is never
## rebound and retains its VM, callback queue, actors and active-time phase.
func apply_configuration() -> void:
	if not _active: return
	_update_context()
	for pack in _packs:
		var owner: String = pack.manifest.id
		if not _pending_start.has(owner): continue
		_pending_start.erase(owner)
		if runtime.has_owner(owner): continue
		runtime.start_pack(pack)
		_running_hashes[owner] = pack.content_hash
	runtime.resource_counts = api.resource_metrics()
