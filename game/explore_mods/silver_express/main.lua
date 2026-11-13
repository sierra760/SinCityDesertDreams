-- Silver State Express: long-haul courier jobs across your whole city in a
-- borrowed pickup. Each stop is found hop by hop so routes reach well past the
-- neighborhood (often a kilometre or two). Tips and ranks are this pack's own
-- score; city funds never change.
local guide = require("guide")
local far = require("far")
local JOBS = require("jobs")

local RANKS = {{0, "Mailroom Rookie"}, {4, "Route Rider"}, {12, "Silver Spur"}, {25, "Long-Hauler"}, {50, "Loneliest Road Legend"}}
local STAT_KEYS = {"jobs", "deliveries", "tips", "tiles", "best_tip", "on_time"}
local HANK = "Hank Delgado, Silver State Express"
local ARRIVE = 1.0

local requests, pending = {}, {}
local hank, truck, truck_at, depot
local retry_round, retry_scheduled = 0, false
local park_tries = 0
local offered
local stats = {}
local job
local job_serial = 0
local player, player_request
local now, next_refresh, next_poll, last_poll = 0, 0, 0, nil
local shown, shown_status
local flash, flash_until = nil, 0
local queued
local serial = 0
local leaving = {}
local finished, plan_next

-- Helpers ------------------------------------------------------------------

local function pick(api, list)
  return list[math.floor(api.utility.random() * #list) + 1]
end

-- A new call or job never repeats the previous story of its kind: a repeat
-- draw takes the next entry instead.
local last_case = {}
local function pick_fresh(api, list, slot)
  local index = math.floor(api.utility.random() * #list) + 1
  if #list > 1 and list[index] == last_case[slot] then index = index % #list + 1 end
  last_case[slot] = list[index]
  return list[index]
end

local function tips(count)
  return count .. (count == 1 and " tip" or " tips")
end

local function rank_of(count)
  local index = 1
  for i = 1, #RANKS do
    if count >= RANKS[i][1] then index = i end
  end
  local following = RANKS[index + 1]
  return index, RANKS[index][2], following and following[1] - count, following and following[2]
end

local function load_stats(api)
  for _, key in ipairs(STAT_KEYS) do
    local value = api.state.get(key, 0)
    stats[key] = type(value) == "number" and math.floor(value) or 0
  end
end

local function save_stats(api)
  for _, key in ipairs(STAT_KEYS) do api.state.set(key, stats[key]) end
end

local function objective(api, text, status)
  status = status or "active"
  if text ~= shown or status ~= shown_status then
    shown, shown_status = text, status
    api.objective.set("express", text, status)
  end
end

local function journal(api)
  if stats.jobs == 0 then return end
  local _, title = rank_of(stats.jobs)
  api.objective.set("rank", "Courier rank: " .. title .. " · " .. stats.jobs .. (stats.jobs == 1 and " job · " or " jobs · ") ..
    guide.km(stats.tiles) .. " hauled · " .. tips(stats.tips), "completed")
end

local function show_flash(text, seconds)
  flash, flash_until, next_refresh = text, now + seconds, 0
end

-- Each request remembers its job, so a late reply cannot leak into the next.
local function track(api, action, result)
  if result.ok and result.request_id then
    requests[result.request_id] = {action = action, job = action ~= "dialogue" and job and job.id or nil}
    pending[action] = true
  else
    finished(api, action, result.code, result.data)
  end
end

local function say(api, key, speaker, text, choices)
  queued = {key = key, speaker = speaker, text = text, choices = choices}
  track(api, "dialogue", api.dialogue.show(key, speaker, text, choices))
end

local function in_truck()
  return player ~= nil and player.mode == 1 and truck ~= nil and player.vehicle == truck
end

local function remove_later(api, id, wave)
  if not id then return end
  if wave then api.actor.wave(id) end
  serial = serial + 1
  leaving["leave" .. serial] = id
  api.timer.after("leave" .. serial, 2.5)
end

-- Setup --------------------------------------------------------------------

local function offer(api)
  if offered or job or not (hank and truck) then return end
  offered = true
  api.interaction.register("counter", {target = {id = hank}, label = "talk to Hank at Silver State Express"})
  objective(api, "Talk to Hank at the Silver State Express counter, beside the pickup, for a long-haul courier job.")
end

local function spawn_missing(api)
  if not job and not hank and not pending.hank then
    track(api, "hank", api.actor.spawn("pedestrian", {key = "hank", variant = "pedestrian_15", near_player = true}))
  end
  if not truck and not pending.truck then
    track(api, "truck", api.actor.spawn("pickup", {key = "express_pickup", near_player = true, enterable = true}))
  end
end

local function refused(api)
  if retry_round < 2 then
    if not retry_scheduled then
      retry_scheduled = true
      api.timer.after("startup_retry", 3 * (retry_round + 1))
    end
    objective(api, "Silver State Express is waiting for a safe spot on the road; it will try again shortly.")
  else
    objective(api, "Silver State Express could not find a safe spot on the road after two tries. Move to a clear connected street, then reenter Explore or Disable and Enable this pack and Resume. Your ledger is kept.", "failed")
  end
end

local function offer_dialogue(api)
  local _, title = rank_of(stats.jobs)
  local record = stats.jobs == 0 and "New hire? Grab the keys; the pickup's gassed up."
    or ("Look who's back: a " .. title .. " with " .. guide.km(stats.tiles) .. " on the odometer.")
  say(api, "offer", HANK,
    "Silver State Express doesn't do around-the-corner. We do across-town. Every job here crosses a good chunk " ..
    "of the city, so plan your route and watch the clock.\n\n" .. record ..
    " Tips are bragging rights only; city funds never change.",
    {{key = "rush", label = "Cross-Town Rush: pick up, then race it across town"},
     {key = "milk", label = "Milk Run: three drops all over, any order you like"},
     {key = "ice", label = "Ice Run: haul ice before it melts"},
     {key = "cake", label = "Wedding Cake: fragile, and the ceremony won't wait"},
     {key = "ledger", label = "Show my ledger"},
     {key = "later", label = "Maybe later"}})
end

local function ledger_dialogue(api)
  local _, title, need, upcoming = rank_of(stats.jobs)
  local lines = {"Rank: " .. title, "Jobs finished: " .. stats.jobs .. " · parcels delivered: " .. stats.deliveries,
    "Road hauled: about " .. guide.km(stats.tiles), "Tips earned: " .. stats.tips .. " · best job " .. tips(stats.best_tip),
    "On-time jobs: " .. stats.on_time}
  if upcoming then
    lines[#lines + 1] = "\n" .. need .. (need == 1 and " more job" or " more jobs") .. " until " .. upcoming .. "."
  else
    lines[#lines + 1] = "\nLoneliest Road Legend. Truck stops keep a stool open for you."
  end
  say(api, "ledger", HANK, table.concat(lines, "\n"), {{key = "back", label = "Back"}})
end

-- Planning -----------------------------------------------------------------

-- A stop is a person at a far address: who, what the marker says and
-- whether it is a pickup or a drop.
local function new_job(api, kind)
  job_serial = job_serial + 1
  job = {id = job_serial, kind = kind, phase = "planning", stops = {}, index = 0, clock = 0, route = 0,
    bumps = 0, ice = 100, tries = 0}
  offered = false
  api.interaction.unregister("counter")
  next_refresh = 0
  flash = nil
  if kind == "milk" then
    -- Three different drops by index; the sandbox bounds table helpers, so the
    -- long list is never copied or passed to table.remove.
    local taken = {}
    for i = 1, 3 do
      local slot = math.floor(api.utility.random() * #JOBS.milk) + 1
      while taken[slot] do slot = slot % #JOBS.milk + 1 end
      taken[slot] = true
      local parcel = JOBS.milk[slot]
      job.stops[i] = {role = "drop", label = parcel.item .. " for " .. parcel.to, who = parcel.to,
        variant = parcel.variant, thanks = parcel.thanks, item = parcel.item}
    end
  else
    local case = pick_fresh(api, JOBS[kind], kind)
    job.case = case
    local item = kind == "ice" and "200 kilos of ice" or (kind == "cake" and ("the wedding cake for " .. case.couple) or case.item)
    job.item = item
    job.stops[1] = {role = "pickup", label = "Pick up " .. item .. " at " .. case.from, who = case.from, variant = case.sender}
    job.stops[2] = {role = "drop", label = "Deliver to " .. case.to, who = case.to, variant = case.recipient, thanks = case.thanks}
  end
  plan_next(api)
end

local function spec_for(api, index)
  local r = api.utility.random()
  if job.kind == "milk" then
    local previous = job.stops[index - 1]
    return {from = depot, hops = 1, reach = 28 + math.floor(r * 7), vary = 5, away = previous and previous.found or nil}
  end
  if index == 1 then return {from = depot, hops = 1, reach = 30 + math.floor(r * 9), vary = 4} end
  return {from = job.stops[1].found, hops = 2, reach = 30 + math.floor(r * 7), vary = 3, away = depot}
end

plan_next = function(api)
  job.index = job.index + 1
  local stop = job.stops[job.index]
  if not stop then
    job.index = 0
    return false
  end
  job.search = far.new(spec_for(api, job.index))
  track(api, "search", far.request(api, job.search))
  return true
end

local function stuck(api)
  job.phase = "stuck"
  objective(api, "Hank can't find reachable addresses for this job from here.")
  say(api, "stuck", HANK, "Hmm. My map says there's no road from here to anywhere worth hauling to. " ..
    "Drive the pickup onto a bigger street and I'll look again.",
    {{key = "retry", label = "Look again"}, {key = "stop", label = "Cancel the job"}})
end

local function best_tour(points)
  -- Shortest straight-line order visiting every stop from the depot (3! = 6).
  local best
  local orders = {{1, 2, 3}, {1, 3, 2}, {2, 1, 3}, {2, 3, 1}, {3, 1, 2}, {3, 2, 1}}
  for _, order in ipairs(orders) do
    local at, length = depot, 0
    for _, i in ipairs(order) do
      if points[i] then
        length = length + guide.distance(at, points[i])
        at = points[i]
      end
    end
    if not best or length < best then best = length end
  end
  return best or 0
end

local function brief(api)
  job.phase = job.kind == "milk" and "milk" or "to_pickup"
  next_refresh = 0
  local case = job.case
  if job.kind == "milk" then
    local points = {}
    for i, stop in ipairs(job.stops) do points[i] = stop.at end
    local tour = best_tour(points)
    job.limit = 40 + math.floor(tour * 1.6)
    job.clock = 0
    local names = {}
    for _, stop in ipairs(job.stops) do names[#names + 1] = stop.item .. " for " .. stop.who end
    say(api, "brief", HANK, "Three drops, spread all over town: " .. table.concat(names, "; ") ..
      ". Every address is on your map. Deliver them in any order you like; the clock runs for the whole route. " ..
      "You have " .. guide.clock(job.limit) .. ". Pick your order wisely!", {{key = "go", label = "On it"}})
    return
  end
  local first, second = job.stops[1], job.stops[2]
  local leg = guide.distance(first.at, second.at)
  local text = "Pick up " .. job.item .. " at " .. case.from .. " (" .. guide.km(guide.distance(depot, first.at)) ..
    " from here), then take it to " .. case.to .. ", another " .. guide.km(leg) .. " as the crow flies. " ..
    "Expect about " .. guide.km(job.route) .. " of road all told."
  if job.kind == "rush" then text = text .. " The clock starts when you load up."
  elseif job.kind == "ice" then text = text .. " It starts melting the moment it's aboard, and faster when you sit still in the sun."
  else text = text .. " It's a four-tier cake: brake gently, don't hit anything, and get there before the vows." end
  say(api, "brief", HANK, text, {{key = "go", label = "On it"}})
end

-- Arrivals -----------------------------------------------------------------

local function load_up(api, stop)
  stop.done = true
  remove_later(api, stop.actor, true)
  stop.actor = nil
  api.marker.remove("stop1")
  job.phase = "to_drop"
  job.clock = 0
  job.leg = job.stops[2].route or job.route
  if job.kind == "rush" then
    job.limit = 20 + math.floor(job.leg / 1.2 * 1.35)
    show_flash("Loaded! " .. guide.clock(job.limit) .. " on the clock", 3)
  elseif job.kind == "cake" then
    job.limit = 30 + math.floor(job.leg / 1.2 * 1.6)
    show_flash("Cake aboard! Gently now", 3)
  else
    job.melt = 50 / (job.leg / 1.2 * 1.25 + 10)
    show_flash("Ice aboard! It's dripping", 3)
  end
end

local function finish_job(api, tip, text, on_time)
  job.phase = "done"
  for i = 1, #job.stops do api.marker.remove("stop" .. i) end
  local before = rank_of(stats.jobs)
  stats.jobs = stats.jobs + 1
  stats.tips = stats.tips + tip
  stats.tiles = stats.tiles + math.floor(job.route)
  if tip > stats.best_tip then stats.best_tip = tip end
  if on_time then stats.on_time = stats.on_time + 1 end
  save_stats(api)
  journal(api)
  local after, title = rank_of(stats.jobs)
  text = text .. "\n\nTip: " .. tip .. " · about " .. guide.km(job.route) .. " of road."
  if after > before then text = text .. "\n\nPromotion! You're now a " .. title .. "." end
  say(api, "result", HANK, text, {{key = "again", label = "Another job"}, {key = "done", label = "Clock out"}})
end

local function deliver_two_leg(api, stop)
  stop.done = true
  stats.deliveries = stats.deliveries + 1
  remove_later(api, stop.actor, true)
  stop.actor = nil
  local base = 10 + math.floor(job.route * 0.15)
  local notes, on_time = {}, false
  local text = stop.thanks
  if job.kind == "ice" then
    local left = math.floor(job.ice + 0.5)
    if left <= 0 then
      base = 2
      notes[#notes + 1] = "it's a puddle now"
      text = "All that's left is a very cold puddle and a lot of steam. \"Well... it was ice when it left, right?\""
    else
      local bonus = math.floor(left * 0.3)
      base = base + bonus
      notes[#notes + 1] = left .. "% of the ice left +" .. bonus
      on_time = left >= 50
    end
  else
    if job.clock <= job.limit then
      local early = 6 + math.floor((job.limit - job.clock) * 0.4)
      base = base + early
      notes[#notes + 1] = "on time +" .. early
      on_time = true
    else
      base = math.floor(base / 2)
      notes[#notes + 1] = "late, so half the tip"
      if job.kind == "cake" then text = "The ceremony started without the cake, but the reception is saved. " .. text end
    end
    if job.kind == "cake" then
      if job.bumps == 0 then
        base = base + 6
        notes[#notes + 1] = "not a crumb out of place +6"
      else
        local penalty = 3 * math.min(job.bumps, 4)
        base = base - penalty
        notes[#notes + 1] = job.bumps .. (job.bumps == 1 and " bump -" or " bumps -") .. penalty
      end
    end
  end
  local tip = math.max(1, base)
  finish_job(api, tip, text .. " (" .. table.concat(notes, ", ") .. ")", on_time)
end

local function deliver_milk(api, stop)
  stop.done = true
  stats.deliveries = stats.deliveries + 1
  remove_later(api, stop.actor, true)
  stop.actor = nil
  for i, other in ipairs(job.stops) do
    if other == stop then api.marker.remove("stop" .. i) end
  end
  local earned = 5 + math.floor(guide.distance(depot, stop.at) * 0.15)
  job.earned = (job.earned or 0) + earned
  local left = 0
  for _, other in ipairs(job.stops) do
    if not other.done then left = left + 1 end
  end
  if left > 0 then
    show_flash("Delivered +" .. earned .. "! " .. stop.thanks, 5)
    return
  end
  local on_time = job.clock <= job.limit
  local notes = {"three drops +" .. job.earned}
  local tip = job.earned
  if on_time then
    local bonus = 12 + math.floor((job.limit - job.clock) * 0.3)
    tip = tip + bonus
    notes[#notes + 1] = "whole route on time +" .. bonus
  else
    notes[#notes + 1] = "a little late, no route bonus"
  end
  local text = stop.thanks .. "\n\nThat's the whole milk run! (" .. table.concat(notes, ", ") .. ")"
  finish_job(api, tip, text, on_time)
end

-- Objective ------------------------------------------------------------------

local function current_target()
  if job.phase == "to_pickup" then return job.stops[1] end
  if job.phase == "to_drop" then return job.stops[2] end
  return nil
end

local function refresh_objective(api)
  if not job or now < next_refresh then return end
  next_refresh = now + 0.5
  local text
  if job.phase == "planning" then
    text = "Hank is mapping out a long-haul route..."
  elseif job.phase == "to_pickup" or job.phase == "to_drop" then
    -- The HUD shows the first ~35 characters: action and distance lead.
    local stop = current_target()
    local parts = {(stop.role == "pickup" and "Pick up " or "Deliver ") .. (player and guide.describe(player, stop.at) or "")}
    if job.phase == "to_drop" then
      if job.kind == "ice" then parts[#parts + 1] = "ice " .. math.floor(job.ice + 0.5) .. "%"
      else parts[#parts + 1] = job.clock <= job.limit and (guide.clock(job.limit - job.clock) .. " left") or "running late!" end
    end
    parts[#parts + 1] = stop.role == "pickup" and (job.item .. " at " .. stop.who) or (job.item .. " to " .. stop.who)
    if player and not in_truck() then parts[#parts + 1] = "hop in the Silver State pickup" end
    text = table.concat(parts, " · ")
  elseif job.phase == "milk" then
    local nearest, best
    for _, stop in ipairs(job.stops) do
      if not stop.done and player then
        local d = guide.distance(player, stop.at)
        if not best or d < best then nearest, best = stop, d end
      end
    end
    local left = 0
    for _, stop in ipairs(job.stops) do
      if not stop.done then left = left + 1 end
    end
    local parts = {job.clock <= job.limit and (guide.clock(job.limit - job.clock) .. " left") or "Over time!"}
    parts[#parts + 1] = left .. (left == 1 and " drop to go" or " drops to go")
    if nearest then parts[#parts + 1] = "nearest " .. guide.describe(player, nearest.at) .. ": " .. nearest.who end
    if player and not in_truck() then parts[#parts + 1] = "hop in the Silver State pickup" end
    text = table.concat(parts, " · ")
  else
    return
  end
  if flash and now < flash_until then text = flash .. " · " .. text end
  objective(api, text)
end

-- Player updates -------------------------------------------------------------

local function on_player(api, data)
  player = data
  local dt = last_poll and math.min(0.5, now - last_poll) or 0
  last_poll = now
  if not job then return end
  if in_truck() then truck_at = guide.point(data) end
  local driving = job.phase == "to_pickup" or job.phase == "to_drop" or job.phase == "milk"
  if not driving then return end
  if job.phase == "to_drop" or job.phase == "milk" then job.clock = job.clock + dt end
  local speed = data.speed or 0
  if job.phase == "to_drop" and job.kind == "ice" then
    -- Ice melts while it rides, and twice as fast parked in the sun.
    local rate = job.melt * ((in_truck() and speed > 0.1) and 1 or 2)
    job.ice = math.max(0, job.ice - rate * dt)
  end
  if job.phase == "to_drop" and job.kind == "cake" and in_truck() then
    if job.last_speed and dt > 0.04 and dt < 0.5 and job.last_speed > 0.35 and (job.last_speed - speed) / dt > 1.7
        and now - (job.bump_at or -10) > 1.2 then
      job.bump_at = now
      job.bumps = job.bumps + 1
      show_flash(job.bumps <= 4 and "Whoa! The top tier is wobbling (-3 tip)" or "Whoa! The top tier is wobbling", 2.5)
    end
    job.last_speed = speed
  else
    job.last_speed = nil
  end
  if not in_truck() then return end
  for i, stop in ipairs(job.stops) do
    local active = (job.phase == "milk" and not stop.done) or stop == current_target()
    if active and stop.at then
      local d = guide.distance(data, stop.at)
      if not stop.waved and stop.actor and d < 5 then
        stop.waved = true
        api.actor.wave(stop.actor)
      end
      if d < ARRIVE then
        if stop.role == "pickup" then load_up(api, stop)
        elseif job.kind == "milk" then deliver_milk(api, stop)
        else deliver_two_leg(api, stop) end
        return
      end
    end
  end
end

-- Completions ---------------------------------------------------------------

local function mark(api, index)
  local stop = job.stops[index]
  local icon = stop.role == "pickup" and "objective" or "checkpoint"
  api.marker.set("stop" .. index, {target = {id = stop.actor}, label = stop.role == "pickup" and ("Pick up · " .. stop.who) or ("Deliver · " .. stop.who), icon = icon})
end

finished = function(api, action, code, data)
  pending[action] = nil
  if action == "dialogue" then
    if code == "busy" then api.timer.after("say_retry", 1) else queued = nil end
    return
  end
  if action == "truck" and code ~= "ok" and park_tries < 3 then
    park_tries = park_tries + 1
    track(api, "truck_spot", api.world.find_landmark("road_destination", {kind = "pickup", skip = park_tries, min_distance = 2 + park_tries}))
    return
  elseif action == "truck_spot" then
    if code ~= "ok" then refused(api) return end
    track(api, "truck", api.actor.spawn("pickup", {key = "express_pickup", position = guide.point(data), enterable = true}))
    return
  elseif action == "hank" or action == "truck" then
    if code ~= "ok" then refused(api) return end
    if action == "hank" then
      hank, depot = data.id, guide.point(data.position)
      api.marker.set("hank", {target = {id = hank}, label = "Hank · Silver State Express", icon = "person"})
    else
      truck, truck_at = data.id, data.position
      api.marker.set("truck", {target = {id = truck}, label = "Silver State pickup", icon = "vehicle"})
    end
    offer(api)
    return
  end
  if not job then return end
  local stop = job.stops[job.index]
  if action == "search" and stop then
    local outcome = far.feed(job.search, code, data)
    if outcome == "again" then
      track(api, "search", far.request(api, job.search))
    elseif outcome == "done" then
      stop.found = guide.point(job.search.at)
      -- A retried doorstep adds its few doors to the haul already driven to
      -- this street.
      stop.route = (stop.haul or 0) + job.search.total
      stop.haul = nil
      job.route = job.route + stop.route
      serial = serial + 1
      track(api, "person", api.actor.spawn("pedestrian", {key = "stop" .. serial, position = stop.found,
        near_player = true, variant = "pedestrian_" .. stop.variant}))
    else
      stuck(api)
    end
  elseif action == "person" and stop then
    if code ~= "ok" then
      -- That doorstep is crowded: try the next address along the street.
      job.tries = job.tries + 1
      if job.tries > 4 then stuck(api) return end
      stop.haul = stop.route or 0
      job.route = job.route - stop.haul
      job.search = far.new({from = stop.found, hops = 1, reach = 2 + job.tries, vary = 2})
      track(api, "search", far.request(api, job.search))
      return
    end
    stop.actor = data.id
    stop.at = guide.point(data.position)
    mark(api, job.index)
    if not plan_next(api) then brief(api) end
  end
end

local function clear_job(api)
  if not job then return end
  for i, stop in ipairs(job.stops) do
    api.marker.remove("stop" .. i)
    if stop.actor then remove_later(api, stop.actor, false) end
    stop.actor = nil
  end
  job = nil
end

local function clock_out(api, text)
  clear_job(api)
  local _, title = rank_of(stats.jobs)
  objective(api, text or ("Clocked out. Rank: " .. title .. ". Hank will have more long hauls next time you explore."), "completed")
  offer(api)
end

return {
  on_start = function(api)
    load_stats(api)
    journal(api)
    objective(api, "Silver State Express is opening its counter nearby...")
    spawn_missing(api)
  end,
  on_event = function(api, event)
    if event.kind == "timer" then
      if event.key == "startup_retry" then
        retry_scheduled = false
        retry_round = retry_round + 1
        park_tries = 0
        spawn_missing(api)
      elseif event.key == "say_retry" and queued then
        say(api, queued.key, queued.speaker, queued.text, queued.choices)
      elseif leaving[event.key] then
        api.actor.remove(leaving[event.key])
        leaving[event.key] = nil
      end
      return
    end
    if player_request and event.request_id == player_request then
      player_request = nil
      if event.code == "ok" then on_player(api, event.data) end
      return
    end
    local entry = requests[event.request_id]
    if entry then
      requests[event.request_id] = nil
      pending[entry.action] = nil
      if entry.job == nil or (job and job.id == entry.job) then finished(api, entry.action, event.code, event.data) end
      return
    end
    if event.kind == "interaction" and event.key == "counter" and not job then
      offer_dialogue(api)
    elseif event.kind == "dialogue_choice" then
      local choice = event.data.choice
      if event.key == "offer" then
        if choice == "rush" or choice == "milk" or choice == "ice" or choice == "cake" then new_job(api, choice)
        elseif choice == "ledger" then ledger_dialogue(api)
        else offer(api) end
      elseif event.key == "ledger" then
        offer_dialogue(api)
      elseif event.key == "brief" then
        next_refresh = 0
      elseif event.key == "result" then
        clear_job(api)
        if choice == "again" then
          offer_dialogue(api)
        else
          clock_out(api)
        end
      elseif event.key == "stuck" then
        if choice == "retry" and job then
          local kind = job.kind
          clear_job(api)
          new_job(api, kind)
        else
          clock_out(api, "Job cancelled. Talk to Hank when you're ready for another long haul.")
        end
      end
    elseif event.kind == "route_failed" and event.data.id == truck then
      truck, truck_at = nil, nil
      spawn_missing(api)
    end
  end,
  on_tick = function(api, context)
    now = now + context.delta
    if job and not player_request and now >= next_poll then
      next_poll = now + 0.2
      local result = api.world.player()
      if result.request_id then player_request = result.request_id
      elseif result.ok then on_player(api, result.data) end
    end
    refresh_objective(api)
  end
}
