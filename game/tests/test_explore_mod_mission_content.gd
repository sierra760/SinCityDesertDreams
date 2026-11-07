# SPDX-License-Identifier: GPL-3.0-or-later
## The call and job content shipped in Desert Air Patrol and Silver State
## Express, checked inside the real restricted Lua runtime: required fields,
## pedestrian variants, lengths that fit the HUD line and dialogue, no
## duplicates, drivable getaway vehicles and the expected amount of variety.
extends "res://tests/test_case.gd"

## Shared Lua checking helpers; each section runs on its own tick to stay well
## inside the per-callback instruction budget.
const HELPERS := '''
local errors, report = 0, ""
local function fail(message)
  errors = errors + 1
  if string.len(report) < 1500 then report = report .. message .. "\\n" end
end
local function text(entry, field, low, high, where)
  local value = entry[field]
  if type(value) ~= "string" then fail(where .. ": " .. field .. " missing") return end
  local size = string.len(value)
  if size < low or size > high then fail(where .. ": " .. field .. " is " .. size .. " bytes") end
end
local function variant(entry, field, where)
  local value = entry[field]
  if type(value) ~= "number" or value ~= math.floor(value) or value < 0 or value > 15 then fail(where .. ": bad " .. field) end
end
local function unique(list, field, name)
  local seen = {}
  for i, entry in ipairs(list) do
    local key = field and entry[field] or entry
    if type(key) == "string" then
      key = string.lower(key)
      if seen[key] then fail(name .. " " .. i .. ": duplicate " .. key) end
      seen[key] = true
    end
  end
end
local function count(list, name, minimum)
  if type(list) ~= "table" or #list < minimum then fail(name .. ": " .. (type(list) == "table" and #list or 0) .. " entries, want " .. minimum) end
end
local sections, index = {}, 0
local function finish(api)
  api.state.set("errors", errors)
  api.state.set("report", report)
  api.state.set("done", true)
end
local handlers = {
  on_tick = function(api)
    index = index + 1
    if sections[index] then sections[index]() end
    if index == #sections then finish(api) end
  end
}
'''

const AIR := '''
local calls = require("calls")
local function people(list, name)
  for i, e in ipairs(list) do
    local where = name .. " " .. i
    text(e, "who", 2, 32, where)
    variant(e, "variant", where)
    text(e, "story", 20, 220, where)
    text(e, "thanks", 20, 220, where)
  end
  unique(list, "who", name)
  unique(list, "story", name)
end
sections[1] = function() count(calls.medevac, "medevac", 55) people(calls.medevac, "medevac") end
sections[2] = function() count(calls.hikers, "hikers", 36) people(calls.hikers, "hiker") end
sections[3] = function()
  count(calls.suspects, "suspects", 55)
  local kinds = {sedan = true, compact = true, pickup = true, taxi = true, van = true, car = true}
  for i, e in ipairs(calls.suspects) do
    local where = "suspect " .. i
    if not kinds[e.kind] then fail(where .. ": vehicle kind " .. tostring(e.kind)) end
    text(e, "what", 3, 24, where)
    text(e, "crime", 20, 220, where)
    if type(e.what) == "string" and string.sub(e.what, 1, 2) ~= "a " and string.sub(e.what, 1, 3) ~= "an " then fail(where .. ": what starts with a or an") end
  end
  unique(calls.suspects, "crime", "suspect")
end
sections[4] = function()
  count(calls.officers, "officers", 36)
  for i, name in ipairs(calls.officers) do
    if type(name) ~= "string" or string.len(name) < 3 or string.len(name) > 32 then fail("officer " .. i) end
  end
  unique(calls.officers, nil, "officer")
end
sections[5] = function()
  count(calls.traffic_lines, "traffic lines", 55)
  for i, e in ipairs(calls.traffic_lines) do
    local where = "traffic " .. i
    if type(e.a) ~= "string" or type(e.b) ~= "string" then fail(where .. ": a and b")
    elseif string.len(e.a) + string.len(e.b) < 10 or string.len(e.a) + string.len(e.b) > 140 then fail(where .. ": length") end
    if e.none ~= nil then text(e, "none", 10, 140, where) end
  end
  unique(calls.traffic_lines, "b", "traffic")
end
sections[6] = function()
  count(calls.charters, "charters", 55)
  for i, e in ipairs(calls.charters) do
    local where = "charter " .. i
    text(e, "who", 2, 32, where)
    variant(e, "variant", where)
    if e.rule ~= nil and e.rule ~= "hurry" and e.rule ~= "nervous" then fail(where .. ": rule") end
    text(e, "ask", 10, 120, where)
    text(e, "dest", 3, 16, where)
    text(e, "thanks", 20, 220, where)
    if e.rule ~= nil then text(e, "late", 20, 220, where) end
  end
  unique(calls.charters, "who", "charter")
  unique(calls.charters, "dest", "charter")
end
return handlers
'''

const COURIER := '''
local jobs = require("jobs")
sections[1] = function()
  count(jobs.rush, "rush", 45)
  for i, e in ipairs(jobs.rush) do
    local where = "rush " .. i
    text(e, "item", 5, 60, where)
    text(e, "from", 3, 48, where)
    text(e, "to", 3, 48, where)
    variant(e, "sender", where)
    variant(e, "recipient", where)
    text(e, "thanks", 20, 220, where)
  end
  unique(jobs.rush, "item", "rush")
end
sections[2] = function()
  count(jobs.milk, "milk", 85)
  for i, e in ipairs(jobs.milk) do
    local where = "milk " .. i
    text(e, "item", 3, 48, where)
    text(e, "to", 3, 40, where)
    variant(e, "variant", where)
    text(e, "thanks", 20, 220, where)
  end
  unique(jobs.milk, "item", "milk")
  unique(jobs.milk, "to", "milk")
end
sections[3] = function()
  count(jobs.ice, "ice", 32)
  for i, e in ipairs(jobs.ice) do
    local where = "ice " .. i
    text(e, "from", 3, 48, where)
    text(e, "to", 3, 48, where)
    variant(e, "sender", where)
    variant(e, "recipient", where)
    text(e, "thanks", 20, 220, where)
  end
  unique(jobs.ice, "from", "ice")
  unique(jobs.ice, "to", "ice")
end
sections[4] = function()
  count(jobs.cake, "cake", 32)
  for i, e in ipairs(jobs.cake) do
    local where = "cake " .. i
    text(e, "from", 3, 48, where)
    text(e, "to", 3, 48, where)
    text(e, "couple", 5, 40, where)
    variant(e, "sender", where)
    variant(e, "recipient", where)
    text(e, "thanks", 20, 220, where)
  end
  unique(jobs.cake, "couple", "cake")
  unique(jobs.cake, "from", "cake")
end
return handlers
'''

## A validator pack built from the shipped pack's sources (minus its main).
func _check(pack_id: String, modules: Array[String], body: String) -> Dictionary:
	var files := {"manifest.json":('{"id":"content_check","name":"Content check","version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"}').to_utf8_buffer(),
		"main.lua":(HELPERS+body).to_utf8_buffer()}
	for module in modules:
		var source := FileAccess.get_file_as_bytes("res://explore_mods/%s/%s" % [pack_id,module])
		check(not source.is_empty(),pack_id+"/"+module+" exists")
		files[module] = source
	var pack := ExploreModPack._snapshot(files)
	check(pack.ok,"validator pack for "+pack_id+": "+str(pack.get("error","")))
	if not pack.ok: return {}
	var progress := ExploreModProgress.new()
	var runtime := ExploreModRuntime.new()
	runtime.bind([pack],progress,23)
	for i in 40: runtime.step(.1,false,{})
	check(runtime.diagnostics.is_empty(),pack_id+" content loads and checks within budget: "+str(runtime.diagnostics))
	runtime.stop("test")
	return progress.get_state("content_check",1).data

func test_air_patrol_calls_are_complete_and_varied() -> void:
	var modules: Array[String] = ["calls.lua","calls_medevac.lua","calls_hikers.lua","calls_suspects.lua","calls_officers.lua","calls_traffic.lua","calls_charters.lua"]
	var state := _check("air_patrol",modules,AIR)
	check(bool(state.get("done",false)),"every section ran")
	check_eq(int(state.get("errors",-1)),0,"Air Patrol content: "+String(state.get("report","")))
	for kind in ["sedan","compact","pickup","taxi","van","car"]:
		check(CityTrafficCatalog.is_drivable(StringName(kind)),kind+" getaway vehicles are drivable road vehicles")

func test_silver_express_jobs_are_complete_and_varied() -> void:
	var modules: Array[String] = ["jobs.lua","jobs_rush.lua","jobs_milk.lua","jobs_ice.lua","jobs_cake.lua"]
	var state := _check("silver_express",modules,COURIER)
	check(bool(state.get("done",false)),"every section ran")
	check_eq(int(state.get("errors",-1)),0,"Silver State Express content: "+String(state.get("report","")))

## The shipped packs still read and start with the split modules.
func test_packs_read_with_content_modules() -> void:
	for id in ["air_patrol","silver_express"]:
		var pack := ExploreModPack.read("res://explore_mods/"+id)
		check(pack.ok,id+" reads")
		var runtime := ExploreModRuntime.new()
		runtime.bind([pack],ExploreModProgress.new(),7)
		for i in 5: runtime.step(.1,false,{})
		check(runtime.has_owner(id) and runtime.diagnostics.is_empty(),id+" starts cleanly: "+str(runtime.diagnostics))
		runtime.stop("test")
