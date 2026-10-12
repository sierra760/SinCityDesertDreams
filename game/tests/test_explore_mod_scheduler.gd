extends "res://tests/test_case.gd"

func pack(owner: String, source: String) -> Dictionary:
	return ExploreModPack._snapshot({"manifest.json":JSON.stringify({"id":owner,"name":owner,"version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"}).to_utf8_buffer(),"main.lua":source.to_utf8_buffer()})

func test_queue_full_retains_completion_or_faults() -> void:
	var runtime := ExploreModRuntime.new()
	runtime.bind([pack("queue","return {on_event=function(api,event) end}")],ExploreModProgress.new(),1)
	for i in 128: runtime.deliver("queue",{"kind":"timer","key":str(i)})
	runtime.deliver("queue",{"kind":"action_completed","request_id":500})
	var fault := ""
	runtime.owner_disabled.connect(func(_owner: String, reason: String): set_meta("fault",reason))
	for diagnostic in runtime.diagnostics: fault = diagnostic.reason
	# Overflow must explicitly identify the queue, and close the owner.
	check_eq(fault,"event_queue_full")
	check(runtime._sessions.is_empty())
	runtime.stop("test")

func test_coalesced_ticks_do_not_replay_a_stall() -> void:
	var progress := ExploreModProgress.new()
	var runtime := ExploreModRuntime.new()
	runtime.bind([pack("clock","return {on_tick=function(api) api.state.set('ticks',api.state.get('ticks',0)+1) end}")],progress,1)
	runtime.step(4.0,false,{})
	check_eq(progress.get_state("clock",1).data.get("ticks",0),1,"one current tick, no forty-callback replay")
	runtime.stop("test")

func test_metrics_are_available_and_copied() -> void:
	var runtime := ExploreModRuntime.new()
	check(runtime.has_method("metrics"),"bounded accounting must be observable")
	runtime.stop("test")

func test_native_rejected_calls_count_at_32_33_boundary() -> void:
	for count in [32,33]:
		var runtime := ExploreModRuntime.new()
		runtime.bind([pack("invalid","return {on_start=function(api) for i=1,"+str(count)+" do api.timer.after('bad',0) end end}")],ExploreModProgress.new(),1)
		check_eq(runtime._sessions.has("invalid"),count==32,"native early rejection counted: "+str(count))
		runtime.stop("test")

class AccountingBridge extends ExploreLuaBridge:
	var owner := ""
	var cost := 200
	var calls: Array[String] = []
	var closed := false
	func start(_source: String,_modules: Dictionary,context: Dictionary,_seed: int) -> Dictionary:
		owner = context.owner
		return {"ok":true,"handlers":["on_event","on_tick"],"commands":[],"progress_writes":{},"logs":[]}
	func dispatch(handler: String,_payload: Dictionary,_context: Dictionary,budget: Dictionary) -> Dictionary:
		calls.append(handler)
		return {"ok":true,"instructions":mini(cost,budget.instructions),"commands":[],"progress_writes":{},"logs":[],"bytes_used":100}
	func close() -> void: closed = true

class AccountingRuntime extends ExploreModRuntime:
	var bridges: Array[AccountingBridge] = []
	var cost := 200
	func _create_vm() -> ExploreLuaBridge:
		var bridge := AccountingBridge.new()
		bridge.cost = cost
		bridges.append(bridge)
		return bridge

func test_eight_mod_fairness_ninth_refusal_and_instruction_caps() -> void:
	var runtime := AccountingRuntime.new()
	runtime.cost = 20000
	var packs: Array[Dictionary] = []
	for i in 9: packs.append(pack("owner"+str(i),"return {}"))
	runtime.bind(packs,ExploreModProgress.new(),1)
	check_eq(runtime._sessions.size(),8)
	check_eq(runtime.bridges.size(),8,"ninth pack never opens VM")
	check_eq(runtime.diagnostics[0].reason,"session_limit")
	for i in 8:
		runtime.step(.1,false,{})
		check(runtime.metrics().tick.instructions <= 100000)
		check(runtime.metrics().tick.callbacks <= 5,"20k callbacks bounded by 100k tick")
	for bridge in runtime.bridges: check(not bridge.calls.is_empty(),"every owner advances")
	var copy := runtime.metrics()
	copy.owners.clear()
	check_eq(runtime.metrics().owners.size(),8,"metric snapshots copied")
	runtime.stop("test")
	for bridge in runtime.bridges: check(bridge.closed)

func test_callback_and_command_caps_retain_remaining_work() -> void:
	var runtime := AccountingRuntime.new()
	var packs: Array[Dictionary] = []
	for i in 8: packs.append(pack("owner"+str(i),"return {}"))
	runtime.bind(packs,ExploreModProgress.new(),1)
	for owner: String in runtime._sessions:
		for i in 20: runtime.deliver(owner,{"kind":"event","request_id":i})
		for i in 16: runtime._commands.append({"owner":owner,"request_id":i})
	var commands := runtime.step(.1,false,{})
	check_eq(commands.size(),64)
	check_eq(runtime._commands.size(),64)
	check(runtime.metrics().tick.callbacks <= 32)
	var remaining := 0
	for session: Dictionary in runtime._sessions.values(): remaining += session.events.size()
	var delivered := 0
	for bridge in runtime.bridges: delivered += bridge.calls.count("on_event")
	check_eq(160-remaining,delivered,"only entered event callbacks dequeue")
	check(remaining >= 128)
	runtime.stop("test")
	check(runtime._commands.is_empty())

func test_invalid_window_freezes_and_expires_at_one_active_second() -> void:
	var runtime := AccountingRuntime.new()
	runtime.bind([pack("window","return {}")],ExploreModProgress.new(),1)
	runtime.invalid_command("window",32)
	runtime.step(100,true,{})
	check(runtime._sessions.has("window"))
	runtime.invalid_command("window")
	check(runtime._sessions.is_empty(),"suspension does not expire invalid window")
	runtime.bind([pack("window","return {}")],ExploreModProgress.new(),2)
	runtime.invalid_command("window",32)
	runtime.step(1.0,false,{})
	runtime.invalid_command("window")
	check(runtime._sessions.has("window"),"old misuse expires at one active second")
	runtime.stop("test")

func test_timer_boundaries_and_no_resource_creation_from_stop() -> void:
	var api := ExploreModApi.new()
	api.generation = 1
	var command := {"owner":"timer","generation":1,"request_id":1,"kind":"timer.after","args":{"key":"t","delay":.1}}
	for value in [.099,86400.001]:
		command.args.delay = value
		check_eq(api.apply(command).code,"invalid_argument")
	for value in [.1,86400.0]:
		command.args.delay = value
		check_eq(api.apply(command).code,"ok")
	for i in 17:
		command.args.key = "key"+str(i)
		var result := api.apply(command)
		check_eq(result.code,"ok" if i < 15 else "quota_exceeded")
	var runtime := ExploreModRuntime.new()
	var progress := ExploreModProgress.new()
	runtime.bind([pack("stop","return {on_stop=function(api) api.actor.spawn('pedestrian',{key='forbidden'}); api.timer.after('forbidden',1); api.environment.set('haze','fog',{}); api.state.set('stopped',true) end}")],progress,1)
	runtime.stop("test")
	check(runtime._commands.is_empty())
	check_eq(progress.get_state("stop",1).data.get("stopped"),true)

func test_repeated_native_create_close_and_fault_never_calls_stop() -> void:
	var progress := ExploreModProgress.new()
	for i in 12:
		var runtime := ExploreModRuntime.new()
		runtime.bind([pack("cycle","return {on_tick=function(api) error('fault') end,on_stop=function(api) api.state.set('unsafe',true) end}")],progress,i)
		runtime.step(.1,false,{})
		check(runtime._sessions.is_empty())
		check(runtime._commands.is_empty())
		check(not progress.get_state("cycle",1).data.has("unsafe"))
		runtime.stop("test")

func test_diagnostic_and_log_rings_preserve_128_per_owner() -> void:
	var runtime := ExploreModRuntime.new()
	for i in 140:
		runtime._note("one",str(i))
		runtime._note("two",str(i))
	check_eq(runtime.diagnostics.size(),256)
	check_eq(runtime.diagnostics[0].reason,"12")

func test_event_backlog_cannot_starve_coalesced_tick() -> void:
	var runtime := AccountingRuntime.new()
	runtime.bind([pack("busy","return {}")],ExploreModProgress.new(),1)
	for i in 128: runtime.deliver("busy",{"kind":"event"})
	runtime.step(.1,false,{})
	check_eq(runtime.bridges[0].calls.count("on_tick"),1,"bounded event slice leaves room for current tick")
	check_eq(runtime.bridges[0].calls.count("on_event"),3)
	runtime.stop("test")

func test_eight_actual_native_mods_make_progress_and_stop_without_leaks() -> void:
	var runtime := ExploreModRuntime.new()
	var progress := ExploreModProgress.new()
	var packs: Array[Dictionary] = []
	for i in 8: packs.append(pack("native"+str(i),"return {on_tick=function(api) api.state.set('ticks',api.state.get('ticks',0)+1) end}"))
	runtime.bind(packs,progress,2)
	for i in 16:
		runtime.step(.1,false,{})
		check(runtime.metrics().tick.callbacks <= 32)
		check(runtime.metrics().tick.instructions <= 100000)
	check(runtime.diagnostics.is_empty(),str(runtime.diagnostics))
	for i in 8: check(progress.get_state("native"+str(i),1).data.get("ticks",0)>0,"native owner advances "+str(i))
	runtime.stop("test")
	check(runtime._sessions.is_empty())

func test_native_log_ring_retains_last_128_for_each_owner() -> void:
	var runtime := ExploreModRuntime.new()
	runtime.bind([pack("logs","return {on_tick=function(api) for i=1,32 do api.utility.log('message') end end}")],ExploreModProgress.new(),1)
	for i in 5: runtime.step(.1,false,{})
	check_eq(runtime.logs.size(),128)
	check(runtime.diagnostics.is_empty(),str(runtime.diagnostics))
	runtime.stop("test")

func test_ordered_callback_transactions_preserve_virtual_reads_and_prior_state() -> void:
	for should_fault in [false,true]:
		var runtime := ExploreModRuntime.new()
		var progress := ExploreModProgress.new()
		var ending := "error('fault')" if should_fault else "api.state.set('seen',api.state.get('virtual',0)+1)"
		var source := "return {on_event=function(api,e) if e.index==1 then api.state.set('prior','accepted') elseif e.index==2 then api.state.set('virtual',41); api.timer.after('pending',1) else "+ending+" end end}"
		runtime.bind([pack("ordered",source)],progress,1)
		for index in [1,2,3]: runtime.deliver("ordered",{"index":index})
		var commands := runtime.step(.1,false,{})
		check_eq(progress.get_state("ordered",1).data.get("prior"),"accepted","same-tick prior no-command callback is durable")
		check(not progress.get_state("ordered",1).data.has("virtual"),"unaccepted writes stay out of saved progress")
		if should_fault:
			check(commands.is_empty())
			check(runtime._transactions.is_empty())
		else:
			check_eq(commands.size(),1)
			check_eq(runtime.metrics().pending_transactions,2)
			runtime.accept_command(commands[0],{"code":"ok"})
			check_eq(progress.get_state("ordered",1).data.get("virtual"),41)
			check_eq(progress.get_state("ordered",1).data.get("seen"),42,"later callback reads copied staged progress")
			check_eq(runtime.metrics().pending_transactions,0)
		runtime.stop("test")

func test_disable_discards_unaccepted_state_before_restricted_stop() -> void:
	var runtime := ExploreModRuntime.new()
	var progress := ExploreModProgress.new()
	runtime.bind([pack("staged","return {on_start=function(api) api.state.set('unsafe',true); api.timer.after('pending',1) end,on_stop=function(api) api.state.set('stop_saw',api.state.get('unsafe',false)) end}")],progress,1)
	check_eq(runtime.metrics().pending_transactions,1)
	check(not progress.get_state("staged",1).data.has("unsafe"))
	runtime.stop("test")
	check_eq(runtime.metrics().pending_transactions,0)
	check(not progress.get_state("staged",1).data.has("unsafe"))
	check_eq(progress.get_state("staged",1).data.get("stop_saw"),false)

func test_ordinary_host_refusals_do_not_count_as_misuse_or_undo_progress() -> void:
	for code: String in ["no_route","player_controlled","quota_exceeded","unavailable","stale_id"]:
		var runtime := ExploreModRuntime.new()
		var progress := ExploreModProgress.new()
		runtime.bind([pack("ordinary","return {on_start=function(api) api.state.set('accepted',true); for i=1,32 do api.timer.cancel('none') end end,on_tick=function(api) api.timer.cancel('none') end}")],progress,1)
		var commands := runtime.step(.1,false,{})
		check_eq(commands.size(),32)
		for command in commands: runtime.accept_command(command,{"code":code})
		commands = runtime.step(.1,false,{})
		check_eq(commands.size(),1)
		for command in commands: runtime.accept_command(command,{"code":code})
		check(runtime.has_owner("ordinary"),code+" is not forged misuse")
		check(runtime.diagnostics.is_empty(),code+" has no misuse log")
		check_eq(progress.get_state("ordinary",1).data.get("accepted"),true)
		runtime.stop("test")

func test_pending_transaction_cannot_accumulate_unbounded_callbacks() -> void:
	var runtime := ExploreModRuntime.new()
	var progress := ExploreModProgress.new()
	runtime.bind([pack("bounded","return {on_tick=function(api) api.state.set('count',api.state.get('count',0)+1); api.timer.after('pending',1) end}")],progress,1)
	var commands := runtime.step(.1,false,{})
	for i in 40: runtime.step(.1,false,{})
	check_eq(runtime.metrics().pending_transactions,1,"unaccepted earlier tick prevents more staged callbacks")
	check(not progress.get_state("bounded",1).data.has("count"))
	runtime.accept_command(commands[0],{})
	check_eq(progress.get_state("bounded",1).data.get("count"),1)
	runtime.stop("test")
