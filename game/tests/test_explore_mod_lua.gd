extends "res://tests/test_case.gd"
const Bridge = preload("res://scripts/exploration/mods/explore_lua_bridge.gd")
func context() -> Dictionary:
	return {"owner":"test.mod", "generation":3, "progress":{}, "queries":{}}
func test_native_instruction_and_memory_limits() -> void:
	check(Bridge.available(), "Native Lua is required for this suite")
	if not Bridge.available(): return
	var vm = Bridge.new()
	check_eq(vm.start("while true do end", {}, context(), 7).fault, "instruction_limit")
	check_eq(vm.start("local a='abcd'; for i=1,22 do a=a..a end; return {}", {}, context(), 7).fault, "memory_limit")
	check(not vm.start(String.chr(27) + "Lua", {}, context(), 7).ok)
	vm.close()
func run_callback(code: String, data: Dictionary = {}, budget: Dictionary = {}) -> Dictionary:
	var vm = Bridge.new()
	var init: Dictionary = vm.start("return {on_tick=function(api, context) " + code + " end}", {}, context(), 7)
	if not init.ok:
		vm.close()
		return init
	var c := context()
	c.merge(data, true)
	var result: Dictionary = vm.dispatch("on_tick", {}, c, budget)
	vm.close()
	return result
func test_libraries_and_protected_call_escape() -> void:
	var code := "assert(os==nil and io==nil and package==nil and debug==nil and coroutine==nil); assert(load==nil and loadfile==nil and dofile==nil and collectgarbage==nil); assert(pcall==nil and xpcall==nil and getmetatable==nil and setmetatable==nil); assert(string.dump==nil and string.rep==nil and string.find==nil and string.match==nil and string.gsub==nil and string.gmatch==nil and table.sort==nil); assert(math.random==nil and math.randomseed==nil); assert(('x').rep==nil and ('x').dump==nil); api.utility.log(string.upper('allowed'))"
	var result := run_callback(code)
	check(result.ok, str(result))
	check_eq(result.logs, ["ALLOWED"])
	check(not run_callback("pcall(function() while true do end end)").ok)
	check(not run_callback("xpcall(function() while true do end end, function() end)").ok)
func test_deadline_and_remaining_instructions() -> void:
	check_eq(run_callback("api.utility.log('never')", {}, {"remaining_usec":0}).fault, "deadline")
	check(run_callback("api.utility.log('never')", {}, {"deadline_usec":Time.get_ticks_usec() - 1}).get("deferred",false))
	check_eq(run_callback("api.utility.log('never')", {}, {"remaining_usec":0,"deadline_usec":Time.get_ticks_usec()-1}).fault, "deadline")
	check_eq(run_callback("while true do end", {}, {"instructions":400}).fault, "instruction_limit")
	check_eq(run_callback("while true do end", {}, {"instructions":0}).fault, "instruction_limit")
func test_transactional_fault_cleanup() -> void:
	for code in ["error('broken')", "while true do end", "return {}"]:
		var result := run_callback("api.actor.spawn('pedestrian', {key='courier'}); api.state.set('score', 1); api.utility.log('discard'); " + code)
		check(not result.ok)
		check_eq(result.commands, [])
		check_eq(result.progress_writes, {})
		check_eq(result.logs, [])
	var vm = Bridge.new()
	check(vm.start("return {on_tick=function() error('fault') end, on_stop=function(api) api.state.set('bad',true) end}", {}, context(), 7).ok)
	check(not vm.dispatch("on_tick", {}, context(), {}).ok)
	check_eq(vm.dispatch("on_stop", {}, context(), {}).fault, "closed")
	vm.close()
func test_copied_context_commands_progress_and_queries() -> void:
	var c := context()
	c.progress = {"score":2}
	c.queries = {"world.find_landmark":[{"args":["park"], "result":{"ok":true,"code":"ok","data":{"x":3,"y":0,"z":7}}}]}
	var vm = Bridge.new()
	var code := "return {on_start=function(api, c) c.progress.score=99; local hit=api.world.find_landmark('park'); assert(hit.ok and hit.data.x==3); hit.data.x=99; assert(api.world.find_landmark('park').data.x==3); assert(api.state.get('score')==2); api.state.set('score',3); assert(api.state.get('score')==3); local r=api.actor.spawn('pedestrian',{key='courier',owner='forged'}); assert(r.ok and r.code=='pending'); api.timer.after('wake',0.1) end}"
	check(vm.start(code, {}, c, 7).ok)
	var r: Dictionary = vm.dispatch("on_start", {}, c, {})
	check(r.ok, str(r))
	check_eq(c.progress.score, 2)
	check_eq(r.progress_writes, {"score":3})
	check_eq(r.commands.size(), 2)
	if r.commands.size() == 2:
		check_eq(r.commands[0].kind, "actor.spawn")
		check_eq(r.commands[0].owner, "test.mod")
		check_eq(r.commands[0].generation, 3)
		check_eq(r.commands[0].args.kind, "pedestrian")
		check_eq(r.commands[1].kind, "timer.after")
	vm.close()
func test_require_snapshot_cache_cycles_and_compile_errors() -> void:
	var vm = Bridge.new()
	var modules := {"helper.lua":"module_runs=(module_runs or 0)+1; return {value=module_runs}"}
	var code := "local a=require('helper'); return {on_tick=function(api) assert(require('helper')==a); api.utility.log(tostring(a.value)) end}"
	check(vm.start(code, modules, context(), 7).ok)
	modules["helper.lua"] = "error('changed')"
	var result: Dictionary = vm.dispatch("on_tick", {}, context(), {})
	check(result.ok)
	check_eq(result.logs, ["1"])
	vm.close()
	check(not vm.start("require('a'); return {}", {"a.lua":"return require('b')", "b.lua":"return require('a')"}, context(), 7).ok)
	check(not vm.start("return {}", {"unused.lua":"this is not lua"}, context(), 7).ok)
	check(not vm.start("require('../outside'); return {}", {}, context(), 7).ok)
	check(not vm.start("require('missing'); return {}", {}, context(), 7).ok)
	check(not vm.start("return {}", {"helper.lua":String.chr(27) + "Lua"}, context(), 7).ok)
	var failed: Dictionary = vm.start("require('helper'); return {}", {"helper.lua":"local a=1\nerror('module broke')"}, context(), 7)
	check("helper.lua:2" in failed.diagnostic)
	check(not "/private/" in failed.diagnostic)
	vm.close()
func test_json_and_hostile_utf8_limits() -> void:
	for code in ["local a={}; a.self=a; api.state.set('x',a)", "api.state.set('x',{[1]='a',name='b'})", "api.state.set('x',{[2]='a'})", "api.state.set('x',function() end)", "api.state.set('x',0/0)", "api.state.set('x',1/0)", "api.state.set('x','\\255')", "api.state.set('x','\\192\\128')", "local a='a'; for i=1,13 do a=a..a end; api.state.set('x',a)", "local a={}; for i=1,1025 do a[i]=i end; api.state.set('x',a)", "local a={}; local b=a; for i=1,9 do b.child={}; b=b.child end; api.state.set('x',a)"]:
		check(not run_callback(code).ok, code)
	var vm = Bridge.new()
	var bad := context()
	var object := RefCounted.new()
	bad["object"] = object
	check(not vm.start("return {}", {}, bad, 7).ok)
	bad = context()
	bad["callable"] = Callable(self, "context")
	check(not vm.start("return {}", {}, bad, 7).ok)
	check(vm.start("return {}", {}, context(), 7).ok)
	check(not vm.dispatch("on_event", {"object":object}, context(), {}).ok)
	vm.close()
func test_event_shape_normal_stop_and_quotas() -> void:
	var vm = Bridge.new()
	check(vm.start("return {on_event=function(api,event,c) assert(event.kind=='interaction' and c.owner=='test.mod'); api.state.set('event',event.kind) end,on_stop=function(api) assert(api.actor.spawn('pedestrian',{}).code=='unavailable'); assert(api.utility.random().code=='unavailable'); api.state.set('stopped',true); api.utility.log('stopped') end}", {}, context(), 7).ok)
	check_eq(vm.dispatch("on_event", {"kind":"interaction"}, context(), {}).progress_writes, {"event":"interaction"})
	var r: Dictionary = vm.dispatch("on_stop", {}, context(), {})
	check(r.ok)
	check_eq(r.progress_writes, {"stopped":true})
	check_eq(r.commands, [])
	check_eq(vm.dispatch("on_tick", {}, context(), {}).fault, "closed")
	vm.close()
	r = run_callback("for i=1,32 do assert(api.actor.wave(i).ok) end; assert(api.actor.wave(33).code=='quota_exceeded')")
	check(r.ok, str(r))
	check_eq(r.commands.size(), 32)
	r = run_callback("assert(api.timer.after('x',0).code=='invalid_argument'); assert(api.timer.after('x',86401).code=='invalid_argument'); assert(api.timer.after('x',86400).ok); assert(api.timer.after('x',0.1).ok)")
	check(r.ok)
	check_eq(r.commands.size(), 2)
func test_deterministic_local_random() -> void:
	var code := "api.state.set('value',api.utility.random())"
	var a := run_callback(code)
	var b := run_callback(code)
	check(a.ok and b.ok)
	check_eq(a.progress_writes, b.progress_writes)
	check(a.progress_writes.value >= 0 and a.progress_writes.value < 1)
func test_total_vm_cap_and_source_return_contract() -> void:
	var vms := []
	for i in range(8):
		var vm = Bridge.new()
		check(vm.start("return {}", {}, context(), i + 1).ok)
		vms.append(vm)
	var ninth = Bridge.new()
	check_eq(ninth.start("return {}", {}, context(), 9).fault, "vm_limit")
	for vm in vms: vm.close()
	check(ninth.start("return {}", {}, context(), 9).ok)
	ninth.close()
	for source in ["return 1", "return {on_tick=4}", "return {unknown=function() end}"]:
		check(not ninth.start(source, {}, context(), 7).ok)
	ninth.close()
func test_host_payload_bounds_and_query_pending() -> void:
	var vm = Bridge.new()
	check(vm.start("return {on_event=function() end}", {}, context(), 7).ok)
	check(not vm.dispatch("on_event", {"s":"a".repeat(4097)}, context(), {}).ok)
	check(vm.start("return {on_event=function() end}", {}, context(), 7).ok)
	var many := []
	many.resize(1025)
	check(not vm.dispatch("on_event", {"many":many}, context(), {}).ok)
	vm.close()
	var r := run_callback("local q=api.world.find_landmark('station',{near_player=true}); assert(q.ok and q.code=='pending' and q.request_id~=nil)")
	check(r.ok)
	check_eq(r.commands.size(), 1)
	check_eq(r.commands[0].kind, "world.find_landmark")
	check_eq(r.commands[0].args, {"kind":"station", "options":{"near_player":true}})
	check(not run_callback("local a='a'; for i=1,13 do a=a..a end; tonumber(a)").ok)
	check(not run_callback("local a='a'; for i=1,13 do a=a..a end; tostring(a)").ok)
func test_escaped_json_payload_size() -> void:
	check(not run_callback("local a=string.char(34); for i=1,12 do a=a..a end; api.state.set('x',a)").ok)
func test_native_relative_deadline() -> void:
	check(Bridge.available())
	if not Bridge.available(): return
	var native: RefCounted = ClassDB.instantiate(&"SCDDExploreLua")
	check(native.call("start", "return {on_tick=function() end}", {}, context(), 7).ok)
	check_eq(native.call("dispatch", "on_tick", {}, context(), {"remaining_usec":0}).fault, "deadline")
	check(native.call("start", "return {on_tick=function() end}", {}, context(), 7).ok)
	check_eq(native.call("dispatch", "on_tick", {}, context(), {"instructions":RefCounted.new()}).fault, "invalid_input")
	native.call("close")

func test_downstream_environment_and_objective_contracts() -> void:
	var result := run_callback("assert(api.objective.complete==nil); api.objective.set('delivery','Delivered','completed'); api.environment.set('fog','desert_haze',{amount=0.3})")
	check(result.ok, str(result))
	check_eq(result.commands.size(), 2)
	if result.commands.size() == 2:
		check_eq(result.commands[0].kind, "objective.set")
		check_eq(result.commands[0].args, {"key":"delivery", "text":"Delivered", "status":"completed"})
		check_eq(result.commands[1].kind, "environment.set")
		check_eq(result.commands[1].args, {"channel":"fog", "preset":"desert_haze", "parameters":{"amount":0.3}})

func nested_copy_value(levels: int) -> Variant:
	var value: Variant = "leaf"
	for i in levels: value = {"child":value}
	return value

func test_maximum_depth_copied_context_query_and_progress() -> void:
	# Each standalone envelope is accepted at depth 8. Progress/queries gain
	# another level inside the full context and are pushed twice by invoke.
	# Run this suite with build.py --api-check to detect C API stack overflow
	# even when Lua's incidental physical allocation has unused spare slots.
	var c := context()
	c.progress = nested_copy_value(8)
	c["deep"] = nested_copy_value(7)
	c.queries = {"world.player":[{"args":[], "result":{"ok":true,"code":"ok","data":nested_copy_value(4)}}]}
	var source := """
local function leaf(value, depth)
  for i=1,depth do value=value.child end
  assert(value=='leaf')
end
return {
  on_tick=function(api, context, extra)
    leaf(context.progress,8); leaf(extra.progress,8); leaf(context.deep,7)
    leaf(context.queries['world.player'][1].result.data,4)
    local saved=api.state.get('child'); leaf(saved,7)
    assert(api.state.set('roundtrip',saved).ok)
    saved.child='changed'; leaf(api.state.get('roundtrip'),7)
    local query=api.world.player(); assert(query.ok); leaf(query.data,4)
    query.data.child='changed'; leaf(api.world.player().data,4)
  end,
  on_event=function(api, event, context)
    leaf(event,8); leaf(context.progress,8)
    assert(api.state.set('event_roundtrip',event.child).ok)
  end
}
"""
	var vm = Bridge.new()
	var started: Dictionary = vm.start(source, {}, c, 7)
	check(started.ok, str(started))
	if not started.ok:
		vm.close()
		return
	var result: Dictionary = vm.dispatch("on_tick", {}, c, {})
	check(result.ok, str(result))
	check_eq(result.progress_writes, {"roundtrip":nested_copy_value(7)})
	check_eq(c.progress, nested_copy_value(8))
	check_eq(c.queries["world.player"][0].result.data, nested_copy_value(4))
	result = vm.dispatch("on_event", nested_copy_value(8), c, {})
	check(result.ok, str(result))
	check_eq(result.progress_writes, {"event_roundtrip":nested_copy_value(7)})
	vm.close()

func test_validated_handler_inventory_is_copied_and_bounded() -> void:
	var vm = Bridge.new()
	var opened: Dictionary = vm.start("return {on_start=function() end,on_event=function() end}",{},context(),7)
	check(opened.ok)
	var names: Array = opened.get("handlers",[])
	names.sort()
	check_eq(names,["on_event","on_start"])
	names.append("on_tick")
	check(vm.dispatch("on_start",{},context(),{}).ok)
	check_eq(vm.start("return {}",{},context(),7).get("handlers",["missing"]),[])
	check(not vm.start("return {['on_tick\\0hidden']=function() end}",{},context(),7).ok,"handler names compare their complete Lua byte length")
	vm.close()

func test_expired_absolute_deadline_defers_without_invoking_or_closing() -> void:
	var vm = Bridge.new()
	check(vm.start("local count=0; return {on_event=function(api) count=count+1; api.state.set('count',count) end}",{},context(),7).ok)
	var deferred: Dictionary = vm.dispatch("on_event",{},context(),{"deadline_usec":Time.get_ticks_usec()-1})
	check(deferred.ok and deferred.get("deferred",false),str(deferred))
	check_eq(deferred.instructions,0)
	check_eq(deferred.progress_writes,{})
	var invoked: Dictionary = vm.dispatch("on_event",{},context(),{"deadline_usec":Time.get_ticks_usec()+1500})
	check(invoked.ok,str(invoked))
	check_eq(invoked.progress_writes,{"count":1})
	vm.close()

func test_invalid_call_accounting_is_saturated_copied_and_reset() -> void:
	for count in [32,33,40]:
		var result := run_callback("for i=1,"+str(count)+" do api.timer.after('bad',0) end")
		check(result.ok,str(result))
		check_eq(result.get("invalid_calls",-1),mini(count,33))
		check(result.commands.is_empty(),"early invalid calls never buffer a command")
		check(result.get("timing",{}).has("thread_cpu_usec"))
	var vm := Bridge.new()
	check(vm.start("return {on_tick=function(api) api.timer.after('bad',0) end}",{},context(),1).ok)
	for i in 2: check_eq(vm.dispatch("on_tick",{},context(),{}).get("invalid_calls",-1),1)
	vm.close()

# Native absolute checks must work even when bridge preflight is bypassed.
func test_native_absolute_deadline_transport_and_retention() -> void:
	check(Bridge.available())
	if not Bridge.available(): return
	for absolute in [0, -1, Time.get_ticks_usec()-1]:
		var native: RefCounted = ClassDB.instantiate(&"SCDDExploreLua")
		check(native.call("start", "return {on_event=function() error('handler_entered') end}", {}, context(), 7).ok)
		var result: Dictionary = native.call("dispatch", "on_event", {}, context(), {"deadline_usec":absolute,"remaining_usec":1500})
		check(result.ok and result.get("deferred",false), str(result))
		check_eq(result.instructions,0)
		check_eq(result.commands,[])
		check_eq(result.progress_writes,{})
		check_eq(result.logs,[])
		# Guaranteed zero-budget fault discriminates retention from a closed VM,
		# without requiring another narrowly timed successful callback.
		check_eq(native.call("dispatch","on_event",{},context(),{"remaining_usec":0}).fault,"deadline")
		native.call("close")
	var delayed: RefCounted = ClassDB.instantiate(&"SCDDExploreLua")
	check(delayed.call("start", "return {on_event=function() error('handler_entered') end}", {}, context(), 7).ok)
	var captured := Time.get_ticks_usec()+1500
	OS.delay_usec(3000)
	check(Time.get_ticks_usec() >= captured)
	var deferred: Dictionary = delayed.call("dispatch","on_event",{},context(),{"deadline_usec":captured,"remaining_usec":1500})
	check(deferred.ok and deferred.get("deferred",false),str(deferred))
	check_eq(deferred.instructions,0)
	check_eq(delayed.call("dispatch","on_event",{},context(),{"remaining_usec":0}).fault,"deadline")
	delayed.call("close")

func test_native_absolute_zero_relative_precedence_and_budget_types() -> void:
	check(Bridge.available())
	if not Bridge.available(): return
	for absolute in [-1, 0, Time.get_ticks_usec()+1000000]:
		var native: RefCounted = ClassDB.instantiate(&"SCDDExploreLua")
		check(native.call("start","return {on_tick=function() error('handler_entered') end}",{},context(),7).ok)
		var result: Dictionary = native.call("dispatch","on_tick",{},context(),{"remaining_usec":0,"deadline_usec":absolute})
		check_eq(result.fault,"deadline")
		check(not result.get("deferred",false))
		check_eq(native.call("dispatch","on_tick",{},context(),{}).fault,"closed")
		native.call("close")
	for budget in [{"deadline_usec":1.0},{"deadline_usec":"1"},{"deadline_usec":RefCounted.new()},{"unknown":1},{"deadline_usec":0,"instructions":"bad"}]:
		var native: RefCounted = ClassDB.instantiate(&"SCDDExploreLua")
		check(native.call("start","return {on_tick=function() end}",{},context(),7).ok)
		check_eq(native.call("dispatch","on_tick",{},context(),budget).fault,"invalid_input")
		check_eq(native.call("dispatch","on_tick",{},context(),{}).fault,"closed")
		native.call("close")
	# Malformed callback inputs remain terminal even with expired absolute time.
	var invalid: RefCounted = ClassDB.instantiate(&"SCDDExploreLua")
	check(invalid.call("start","return {on_tick=function() end}",{},context(),7).ok)
	check_eq(invalid.call("dispatch","on_tick",{"object":RefCounted.new()},context(),{"deadline_usec":0}).fault,"invalid_input")
	invalid.call("close")

# Real OS descheduling: a helper process stops and resumes this whole process,
# so callbacks lose wall time while their thread CPU time stays small.
# The resume gap is generous: Rosetta can take several ms to resume a process.
func _preempt_self(pause: String, cycles: int) -> int:
	var pid := OS.get_process_id()
	var script := "for i in $(seq 1 %d); do kill -STOP %d; sleep %s; kill -CONT %d; sleep 0.02; done; kill -CONT %d" % [cycles, pid, pause, pid, pid]
	return OS.create_process("/bin/sh", ["-c", script])

func _wait_for(helper: int) -> void:
	while OS.is_process_running(helper): OS.delay_msec(1)

func test_preempted_callbacks_are_not_charged_for_lost_wall_time() -> void:
	# Windows has no /bin/sh helper and enforces only the wall backstop there.
	if OS.get_name() == "Windows": return
	var vm = Bridge.new()
	check(vm.start("return {on_tick=function(api) local n=0; for i=1,3000 do n=n+i end; api.state.set('n',n) end}", {}, context(), 7).ok)
	var helper := _preempt_self("0.006", 25)
	check(helper > 0)
	var stalled := 0
	var calls := 0
	var failure := {}
	while OS.is_process_running(helper):
		var result: Dictionary = vm.dispatch("on_tick", {}, context(), {})
		calls += 1
		if not result.ok:
			failure = result
			break
		var cpu := int(result.get("timing", {}).get("thread_cpu_usec", -1))
		if int(result.elapsed_usec) > 1500 and cpu >= 0 and cpu < 1500: stalled += 1
	_wait_for(helper)
	check(failure.is_empty(), "a 6 ms stall with low CPU must not fault: " + str(failure))
	check(stalled > 0, "a stop landed inside a callback (" + str(calls) + " calls)")
	check_eq(vm.dispatch("on_tick", {}, context(), {}).progress_writes, {"n":4501500})
	vm.close()

func test_wall_backstop_still_ends_a_stalled_callback() -> void:
	if OS.get_name() == "Windows": return
	var faulted := {}
	for attempt in 10:
		var vm = Bridge.new()
		check(vm.start("return {on_tick=function(api) local n=0; for i=1,3000 do n=n+i end end}", {}, context(), 7).ok)
		var helper := _preempt_self("0.08", 1)
		while OS.is_process_running(helper):
			var result: Dictionary = vm.dispatch("on_tick", {}, context(), {})
			if not result.ok:
				faulted = result
				break
		_wait_for(helper)
		vm.close()
		if not faulted.is_empty(): break
	check_eq(faulted.get("fault", ""), "deadline")
	check(String(faulted.get("diagnostic", "")).contains("wall-time backstop"), str(faulted))
	check(int(faulted.get("timing", {}).get("thread_cpu_usec", 99999)) < 1500, "stalled, not busy: " + str(faulted.get("timing", {})))

func test_thread_cpu_budget_still_ends_busy_callbacks() -> void:
	if OS.get_name() == "Windows": return
	# Each bounded 4 KiB string call costs far more CPU than its few counted
	# instructions, so the CPU budget ends this before the instruction limit.
	var result := run_callback("local s=string.char(97); for i=1,12 do s=s..s end; for i=1,3000 do s=string.lower(string.upper(s)) end")
	check_eq(result.fault, "deadline")
	check(String(result.get("diagnostic", "")).contains("thread CPU budget"), str(result))
	check(int(result.instructions) < 20000, str(result))
	check(int(result.get("timing", {}).get("thread_cpu_usec", 0)) >= 1500, str(result.get("timing", {})))
