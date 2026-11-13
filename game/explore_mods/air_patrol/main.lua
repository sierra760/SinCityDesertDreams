-- Desert Air Patrol: helicopter calls over your own city. Medevacs land beside
-- a patient and fly them to a real hospital, pursuits keep a fleeing car in
-- the spotlight, traffic reports hover over jams and charters carry picky
-- passengers across town. Patrol points are this pack's own score; city funds,
-- incidents and simulation state never change.
local guide = require("guide")
local far = require("far")
local CALLS = require("calls")

local SHIFT_CALLS = 3
local KINDS = {"medevac", "pursuit", "traffic", "charter"}
local RANKS = {{0, "Student Pilot"}, {5, "Patrol Pilot"}, {15, "Senior Pilot"}, {30, "Flight Captain"}, {60, "Ace of the Mojave"}}
local STAT_KEYS = {"calls", "points", "rescues", "arrests", "reports", "charters", "shifts", "best_shift"}
local CAPTAIN = "Captain Dee Vance, Desert Air Patrol"
local READY = "Talk to Captain Dee Vance at the Desert Air Patrol post to fly rescue, police, traffic and charter calls."
local GROUNDED = "Desert Air Patrol has no helicopter to fly in this city. Helicopters are kept at the Mayor’s House: " ..
  "build one, then explore again. Captain Dee Vance keeps your logbook."

local requests, pending = {}, {}
local captain, base
local retry_round, retry_scheduled = 0, false
local offered
local stats = {}
local shift, call
local player, player_request, look_request, nearby_request
local now, next_refresh, next_poll, next_look, last_poll = 0, 0, 0, 0, nil
local shown, shown_status
local flash, flash_until = nil, 0
local queued
local serial = 0
local leaving = {}
local finished, next_call
-- "ready" or "grounded" while the captain's offer is the objective on screen.
local offer_mode
local heli_marked

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

local function points(count)
  return count .. (count == 1 and " point" or " points")
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
    api.objective.set("patrol", text, status)
  end
end

local function journal(api)
  if stats.calls == 0 then return end
  local _, title = rank_of(stats.calls)
  api.objective.set("rank", "Pilot rank: " .. title .. " · " .. stats.calls ..
    (stats.calls == 1 and " call · " or " calls · ") .. points(stats.points) ..
    " · best shift " .. points(stats.best_shift), "completed")
end

local function show_flash(text, seconds)
  flash, flash_until, next_refresh = text, now + seconds, 0
end

local call_serial = 0

-- Each request remembers the call that asked, so a late reply for an earlier
-- call can never feed into the next one.
local function track(api, action, result)
  if result.ok and result.request_id then
    requests[result.request_id] = {action = action, call = action ~= "dialogue" and call and call.id or nil}
    pending[action] = true
  else
    finished(api, action, result.code, result.data)
  end
end

local function say(api, key, speaker, text, choices)
  queued = {key = key, speaker = speaker, text = text, choices = choices}
  track(api, "dialogue", api.dialogue.show(key, speaker, text, choices))
end

local function flying()
  return player ~= nil and player.mode == 2
end

-- Down on the ground in a helicopter, stopped, within radius of target.
local function touchdown(target, radius)
  return flying() and (player.speed or 0) < 0.12 and math.abs(guide.height(player, target)) < 0.35
    and guide.distance(player, target) <= radius
end

-- Hovering just above target: close enough to lower the rescue ladder.
local function low_hover(target)
  local h = guide.height(player, target)
  return flying() and (player.speed or 0) < 0.35 and h > -0.35 and h < 1.2 and guide.distance(player, target) < 1.6
end

-- Landing or a three-second low hover both count as reaching a ground stop.
local function reached(target, radius, dt)
  if touchdown(target, radius) then return true end
  if low_hover(target) then
    call.hold = (call.hold or 0) + dt
    if call.hold >= 3 then return true end
  else
    call.hold = 0
  end
  return false
end

-- Where the helicopter the player can fly is parked, from world.player.
local function parked_helicopter()
  return player and type(player.helicopter) == "table" and player.helicopter or nil
end

-- False only when the host has reported that this visit has no helicopter.
local function can_fly()
  return player == nil or flying() or parked_helicopter() ~= nil
end

local function board_hint()
  if flying() then return nil end
  local parked = parked_helicopter()
  if parked then return "board the helicopter " .. guide.describe(player, parked) end
  return "no helicopter to fly: ask Captain Vance to end the shift"
end

-- On foot during a shift, the parked helicopter is marked.
local function mark_helicopter(api)
  local parked = shift and not flying() and parked_helicopter() or nil
  if parked then
    if not heli_marked or guide.distance(heli_marked, parked) > 0.5 then
      heli_marked = guide.point(parked)
      api.marker.set("heli", {target = heli_marked, label = "Sky Ranger 7 · board here", icon = "vehicle"})
    end
  elseif heli_marked then
    heli_marked = nil
    api.marker.remove("heli")
  end
end

local function show_offer(api)
  offer_mode = can_fly() and "ready" or "grounded"
  objective(api, offer_mode == "ready" and READY or GROUNDED)
end

-- Setup --------------------------------------------------------------------

-- quiet keeps the current objective (an off-duty summary) on screen.
local function offer(api, quiet)
  if offered or shift or not captain then return end
  offered = true
  api.interaction.register("patrol", {target = {id = captain}, label = "talk to Captain Dee Vance, Desert Air Patrol"})
  if quiet then offer_mode = nil else show_offer(api) end
end

local function spawn_captain(api)
  if not captain and not pending.captain then
    track(api, "captain", api.actor.spawn("pedestrian", {key = "captain", variant = "pedestrian_07", near_player = true}))
  end
end

local function refused(api)
  if retry_round < 2 then
    if not retry_scheduled then
      retry_scheduled = true
      api.timer.after("startup_retry", 3 * (retry_round + 1))
    end
    objective(api, "Desert Air Patrol is waiting for a clear spot on the street; it will try again shortly.")
  else
    objective(api, "Desert Air Patrol could not find a clear spot on the street after two tries. Walk to a connected street, then reenter Explore or Disable and Enable this pack and Resume. Your logbook is kept.", "failed")
  end
end

local function offer_dialogue(api)
  local _, title = rank_of(stats.calls)
  if not can_fly() then
    say(api, "grounded", CAPTAIN,
      "I'd put you on the roster in a heartbeat, but there is no helicopter to fly in this city. " ..
      "Air Patrol helicopters are kept on the pad at the Mayor’s House, so the city needs a Mayor’s House " ..
      "with a clear pad. Build one, come back to Explore and Sky Ranger 7 will be waiting there.",
      {{key = "logbook", label = "Show my logbook"}, {key = "later", label = "Understood"}})
    return
  end
  local record = stats.calls == 0 and "New on the roster? Good. We've got calls stacking up."
    or ("Welcome back, " .. title .. ". " .. stats.calls .. " calls flown so far.")
  local parked = not flying() and parked_helicopter() or nil
  say(api, "offer", CAPTAIN,
    "Sky Ranger 7 is fueled and ready" .. (parked and (", parked " .. guide.describe(player, parked)) or "") ..
    ". Take a whole patrol shift and I'll radio calls as they come in, " ..
    "or pick one job yourself. Medevacs need a gentle landing beside the patient, pursuits need your spotlight on " ..
    "the suspect, traffic reports need a steady hover and charter passengers need, well, patience.\n\n" .. record ..
    " Patrol points are bragging rights only; city funds never change.",
    {{key = "shift", label = "Patrol shift: three radio calls"},
     {key = "medevac", label = "Medevac or search and rescue"},
     {key = "pursuit", label = "Police pursuit"},
     {key = "traffic", label = "Traffic report for KDSD radio"},
     {key = "charter", label = "VIP charter flight"},
     {key = "logbook", label = "Show my logbook"},
     {key = "later", label = "Maybe later"}})
end

local function logbook_dialogue(api)
  local _, title, need, upcoming = rank_of(stats.calls)
  local lines = {"Rank: " .. title, "Calls flown: " .. stats.calls .. " · " .. points(stats.points),
    "Rescues: " .. stats.rescues .. " · arrests: " .. stats.arrests,
    "Traffic reports: " .. stats.reports .. " · charters: " .. stats.charters,
    "Shifts: " .. stats.shifts .. " · best shift " .. points(stats.best_shift)}
  if upcoming then
    lines[#lines + 1] = "\n" .. need .. (need == 1 and " more call" or " more calls") .. " until " .. upcoming .. "."
  else
    lines[#lines + 1] = "\nAce of the Mojave. The coyotes salute when you fly over."
  end
  say(api, "logbook", CAPTAIN, table.concat(lines, "\n"), {{key = "back", label = "Back"}})
end

-- Calls --------------------------------------------------------------------

local function search(api, action, spec)
  -- Ground stops stay well outside the 3.5-tile landing radius of each other.
  spec.floor = spec.floor or 6
  call.search = far.new(spec)
  call.search_action = action
  track(api, action, far.request(api, call.search))
end

local function stuck(api)
  call.phase = "stuck"
  objective(api, "Air Patrol dispatch can't find a reachable spot for this call from here.")
  say(api, "stuck", "Air Patrol dispatch",
    "Sky Ranger 7, I can't find a reachable street for that call. The city's roads may not connect from here.",
    {{key = "retry", label = "Try another call"}, {key = "stop", label = "End the shift"}})
end

local function remove_actor(api, id)
  if not id then return end
  serial = serial + 1
  leaving["leave" .. serial] = id
  api.timer.after("leave" .. serial, 2.5)
end

local function clear_call_markers(api)
  for _, key in ipairs({"target", "zone", "dest", "spot"}) do api.marker.remove(key) end
end

local function begin(api, kind)
  call_serial = call_serial + 1
  call = {id = call_serial, kind = kind, phase = "finding", clock = 0, hold = 0, tries = 0}
  next_refresh = 0
  flash = nil
  local from = shift.anchor
  if kind == "medevac" then
    call.sar = api.utility.random() < 0.4
    call.case = call.sar and pick_fresh(api, CALLS.hikers, "hikers") or pick_fresh(api, CALLS.medevac, "medevac")
    call.condition = 100
    search(api, "site", {from = from, hops = call.sar and 2 or 1, reach = 24 + math.floor(api.utility.random() * 14), vary = 4})
  elseif kind == "pursuit" then
    call.case = pick_fresh(api, CALLS.suspects, "suspects")
    search(api, "site", {from = from, hops = 1, reach = 18 + math.floor(api.utility.random() * 10), vary = 4, kind = call.case.kind})
  elseif kind == "traffic" then
    search(api, "spots", {from = from, hops = 3, reach = 18 + math.floor(api.utility.random() * 8), vary = 3})
  else
    call.case = pick_fresh(api, CALLS.charters, "charters")
    local landmarks = {"park", "station", "road_destination"}
    call.landmark = pick(api, landmarks)
    search(api, "site", {from = from, hops = 1, reach = 20 + math.floor(api.utility.random() * 10), vary = 3, landmark = call.landmark})
  end
end

-- Every briefing can be turned down; the call goes to another crew.
local function brief_choices(label)
  return {{key = "go", label = label}, {key = "abandon", label = "Call it off"}}
end

local function radio_intro(api)
  local c = call.case
  if call.kind == "medevac" then
    local where = player and guide.describe(player, call.sar and call.zone or call.site) or ""
    if call.sar then
      say(api, "brief", "Air Patrol dispatch", "Search and rescue! " .. c.story ..
        " The search area is " .. where .. ". Fly low over it; you'll spot them when you're close. " ..
        "Land beside them or hover low to lower the ladder, then get them to the hospital.", brief_choices("On my way"))
    else
      say(api, "brief", "Air Patrol dispatch", "Medevac! " .. c.story .. " They're " .. where ..
        ". Land beside them or hover low to lower the ladder, then get them to the hospital. Every second counts.",
        brief_choices("On my way"))
    end
  elseif call.kind == "pursuit" then
    say(api, "brief", "Air Patrol dispatch", c.crime .. " The suspect is in " .. c.what .. ", " ..
      (player and guide.describe(player, call.site) or "nearby") .. ". Get your spotlight on him (fly within 80 m) " ..
      "and stay on him until ground units box him in. Lose him for 15 seconds and he's gone.",
      brief_choices("On my way"))
  elseif call.kind == "traffic" then
    say(api, "brief", "Rita Ruiz, KDSD Traffic Desk", "We're on the air in a minute! I need eyes on " .. #call.spots ..
      (#call.spots == 1 and " jam" or " jams") .. " around town. Hover over each one, not too high, until I've got the " ..
      "picture. You have " .. guide.clock(call.limit) .. " of air time.", brief_choices("Rolling"))
  else
    local rule = c.rule == "hurry" and " They're in a hurry, so the clock is running." or
      (c.rule == "nervous" and " They're a nervous flyer: take it easy on the throttle." or "")
    say(api, "brief", "Air Patrol dispatch", "Charter job: " .. c.who .. ", " .. c.ask .. ", is waiting " ..
      (player and guide.describe(player, call.site) or "nearby") .. ". Land beside them to pick them up." .. rule,
      brief_choices("On my way"))
  end
end

local function complete(api, earned, speaker, text)
  call.phase = "done"
  clear_call_markers(api)
  local before = rank_of(stats.calls)
  shift.done = shift.done + 1
  shift.points = shift.points + earned
  stats.calls = stats.calls + 1
  stats.points = stats.points + earned
  save_stats(api)
  journal(api)
  local after, title = rank_of(stats.calls)
  text = text .. "\n\n+" .. points(earned) .. ". Shift total: " .. points(shift.points) .. "."
  if after > before then text = text .. "\n\nPromotion! You're now a " .. title .. "." end
  local choices
  if shift.single then
    choices = {{key = "again", label = "Fly another call"}, {key = "stop", label = "That's all for now"}}
  elseif shift.done < SHIFT_CALLS then
    choices = {{key = "next", label = "Take the next call"}, {key = "stop", label = "End the shift here"}}
  else
    choices = {{key = "stop", label = "Head back to base"}}
  end
  say(api, "result", speaker, text, choices)
end

local function end_shift(api)
  clear_call_markers(api)
  if call then
    if call.actor then remove_actor(api, call.actor) end
    call = nil
  end
  if not shift then return end
  -- Nothing left to say about the call that just ended.
  queued = nil
  api.interaction.unregister("stand_down")
  if heli_marked then
    heli_marked = nil
    api.marker.remove("heli")
  end
  -- A shift called off before its first call is not logged.
  if not shift.single and shift.done > 0 then
    stats.shifts = stats.shifts + 1
    if shift.points > stats.best_shift then stats.best_shift = shift.points end
  end
  save_stats(api)
  journal(api)
  local _, title = rank_of(stats.calls)
  objective(api, "Off duty. " .. shift.done .. (shift.done == 1 and " call, " or " calls, ") .. points(shift.points) ..
    ". Rank: " .. title .. ". Talk to Captain Vance for more calls.", "completed")
  shift = nil
  offered = false
  offer(api, true)
end

next_call = function(api, kind)
  if not kind then
    -- A patrol shift avoids flying the same kind of call twice in a row.
    repeat kind = pick(api, KINDS) until kind ~= shift.last_kind or #KINDS == 1
  end
  shift.last_kind = kind
  begin(api, kind)
end

local function start_shift(api, kind)
  shift = {anchor = base, done = 0, points = 0, single = kind ~= nil}
  offered = false
  offer_mode = nil
  api.interaction.unregister("patrol")
  -- The captain can end the shift at any time, mid-call included.
  api.interaction.register("stand_down", {target = {id = captain}, label = "ask Captain Dee Vance to end your shift"})
  next_call(api, kind)
end

-- Medevac -------------------------------------------------------------------

local function medevac_pickup(api)
  call.phase = "aboard"
  call.hold = 0
  api.marker.remove("target")
  api.marker.remove("zone")
  if call.actor then
    api.actor.remove(call.actor)
    call.actor = nil
  end
  show_flash(call.sar and "Found them!" or "Patient aboard!", 3)
  track(api, "hospital", api.world.find_landmark("hospital", {from = guide.point(call.found)}))
end

local function medevac_deliver(api)
  local c = call.case
  stats.rescues = stats.rescues + 1
  local earned = 10 + math.floor(call.condition * 0.4) + (call.sar and 6 or 0)
  local text = c.thanks .. "\n\nCondition on arrival: " .. math.floor(call.condition + 0.5) .. "%."
  if call.fallback then text = text .. " (No hospital is reachable here, so the paramedics met you at the pad.)" end
  shift.anchor = guide.point(call.dest)
  complete(api, earned, call.fallback and "Paramedic crew" or "Desert Valley General, ER", text)
end

-- Pursuit -------------------------------------------------------------------

local function plan_escape(api)
  call.phase = "chase"
  search(api, "escape", {from = call.leg_from, hops = 1, reach = 18 + math.floor(api.utility.random() * 8), vary = 3,
    kind = call.case.kind, away = call.site})
end

local function cornered(api, reason)
  if call.phase == "done" then return end
  stats.arrests = stats.arrests + 1
  local share = call.chase > 0 and call.lit / call.chase or 1
  local earned = 12 + math.floor(40 * share)
  local percent = math.floor(share * 100 + 0.5)
  local opener = reason == "dead_end" and "He drove right into a dead end! "
    or (reason == "stuck" and "He's stuck in traffic and ground units are all over him! " or "Ground units have him boxed in! ")
  local text = opener ..
    "Suspect in custody.\n\nYou kept your spotlight on him " .. percent .. "% of the chase."
  if percent >= 90 then text = text .. " Textbook tracking, Sky Ranger." end
  shift.anchor = guide.point(call.leg_from or call.found)
  local suspect = call.actor
  call.actor = nil
  remove_actor(api, suspect)
  complete(api, earned, pick(api, CALLS.officers), text)
end

local function escaped(api)
  local suspect = call.actor
  call.actor = nil
  remove_actor(api, suspect)
  shift.anchor = guide.point(call.leg_from or call.found)
  complete(api, 3, "Air Patrol dispatch", "We lost him. He'll turn up; they always do, usually at the buffet.")
end

-- Traffic --------------------------------------------------------------------

local function mark_spot(api)
  local spot = call.spots[call.index]
  api.marker.set("spot", {target = spot, label = "Traffic jam " .. call.index .. "/" .. #call.spots,
    icon = "checkpoint", height = 1})
end

local function traffic_done(api)
  stats.reports = stats.reports + 1
  local on_air = call.clock <= call.limit
  local earned = 6 * #call.spots + (on_air and 8 + math.floor((call.limit - call.clock) * 0.2) or 0)
  local text = on_air and ("That's a wrap, and with " .. guide.clock(call.limit - call.clock) ..
    " of air time to spare! Listeners are calling in to say they took the back roads.")
    or "We ran long and the station cut to an ad for Lucky Spur buffets. Still, good pictures!"
  shift.anchor = guide.point(call.spots[#call.spots])
  complete(api, earned, "Rita Ruiz, KDSD Traffic Desk", text)
end

local function cars(count)
  if count == 0 then return "no cars" end
  if count == 1 then return "one car" end
  return count .. " cars"
end

-- A traffic line reads a .. cars(count) .. b, or its own none text for an empty road.
local function traffic_line(line, count)
  local text = (count == 0 and line.none) or (line.a .. cars(count) .. line.b)
  return "\"" .. string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2) .. "\""
end

local function spot_reported(api, count)
  local line = traffic_line(pick(api, CALLS.traffic_lines), count)
  call.index = call.index + 1
  call.hold = 0
  if call.index > #call.spots then
    api.marker.remove("spot")
    traffic_done(api)
    return
  end
  show_flash("On the air: " .. line, 5)
  mark_spot(api)
end

-- Charter --------------------------------------------------------------------

local function charter_pickup(api)
  call.phase = "routing"
  call.hold = 0
  api.marker.remove("target")
  if call.actor then
    api.actor.remove(call.actor)
    call.actor = nil
  end
  show_flash("Buckled in!", 2)
  search(api, "charter_dest", {from = call.found, hops = 2, reach = 26 + math.floor(api.utility.random() * 8), vary = 3,
    away = shift.anchor})
end

local function charter_deliver(api)
  local c = call.case
  stats.charters = stats.charters + 1
  local straight = guide.distance(call.site, call.dest)
  local tip = 8 + math.floor(straight * 0.25)
  local notes, late = {}, false
  if c.rule == "hurry" then
    if call.clock <= call.limit then
      local early = 6 + math.floor((call.limit - call.clock) * 0.3)
      tip = tip + early
      notes[#notes + 1] = "on time +" .. early
    else
      late = true
      tip = math.floor(tip / 2)
      notes[#notes + 1] = "late, half the tip"
    end
  elseif c.rule == "nervous" then
    if call.eeks == 0 then
      tip = tip + 6
      notes[#notes + 1] = "smooth flying +6"
    else
      local penalty = 2 * math.min(call.eeks, 4)
      tip = math.max(2, tip - penalty)
      notes[#notes + 1] = call.eeks .. (call.eeks == 1 and " scream -" or " screams -") .. penalty
      if call.eeks > 3 then late = true end
    end
  end
  local text = ((late and c.late) or c.thanks) .. "\n\nFlight: " .. guide.km(straight) .. " · tip " .. tip
  if #notes > 0 then text = text .. " (" .. table.concat(notes, ", ") .. ")" end
  shift.anchor = guide.point(call.dest)
  complete(api, tip, c.who, text .. ".")
end

-- Objective ------------------------------------------------------------------

-- The HUD shows the first ~35 characters, so each line leads with what to do
-- and where; details follow for the journal.
local function progress_text()
  local c = call.case
  local parts = {}
  local hint = board_hint()
  local function where(target) return player and target and guide.describe(player, target) or nil end
  if call.kind == "medevac" then
    if call.phase == "inbound" then
      if call.sar and player and guide.distance(player, call.site) > 4 then
        parts[1] = "Search area " .. (where(call.zone) or "")
        parts[#parts + 1] = "fly low to spot " .. c.who
      else
        parts[1] = (call.sar and "Hiker " or "Patient ") .. (where(call.site) or "")
        parts[#parts + 1] = "land beside " .. c.who .. " or hover low"
      end
      parts[#parts + 1] = "condition " .. math.floor(call.condition + 0.5) .. "%"
    elseif call.phase == "aboard" then
      if call.dest then
        parts[1] = (call.fallback and "Pad " or "Hospital ") .. (where(call.dest) or "")
        parts[#parts + 1] = "land there"
      else
        parts[1] = "Finding the nearest hospital..."
      end
      parts[#parts + 1] = c.who .. " aboard, condition " .. math.floor(call.condition + 0.5) .. "%"
    end
  elseif call.kind == "pursuit" then
    if call.phase == "approach" then
      parts[1] = "Suspect " .. (where(call.car_at) or "")
      parts[#parts + 1] = "fly over " .. c.what .. " to light him up"
    else
      local share = call.chase > 0 and math.floor(call.lit / call.chase * 100 + 0.5) or 100
      if call.lost > 0.5 then parts[1] = "Losing him! " .. guide.clock(15 - call.lost)
      else parts[1] = "Spotlight " .. share .. "%" end
      parts[#parts + 1] = "suspect " .. (where(call.car_at) or "")
      parts[#parts + 1] = "stay within 80 m until ground units box him in"
    end
  elseif call.kind == "traffic" then
    local spot = call.spots[call.index]
    if call.hold > 0 then parts[1] = "Hold steady " .. math.floor(call.hold / 4 * 100) .. "%"
    else parts[1] = "Jam " .. call.index .. "/" .. #call.spots .. " " .. (where(spot) or "") end
    parts[#parts + 1] = call.clock <= call.limit and (guide.clock(call.limit - call.clock) .. " of air time") or "over time!"
    parts[#parts + 1] = "hover over each jam below 110 m for KDSD traffic"
  else
    if call.phase == "pickup" then
      parts[1] = "Charter " .. (where(call.site) or "")
      parts[#parts + 1] = "land beside " .. c.who
    elseif call.phase == "routing" then
      parts[1] = c.who .. " aboard · plotting the flight..."
    else
      parts[1] = c.dest .. " " .. (where(call.dest) or "")
      if c.rule == "hurry" then
        parts[#parts + 1] = call.clock <= call.limit and (guide.clock(call.limit - call.clock) .. " left") or "running late!"
      elseif c.rule == "nervous" then
        parts[#parts + 1] = "easy on the throttle"
      end
      parts[#parts + 1] = "land there with " .. c.who
    end
  end
  if hint then parts[#parts + 1] = hint end
  return table.concat(parts, " · ")
end

local function refresh_objective(api)
  if not call or now < next_refresh then return end
  next_refresh = now + 0.5
  local text
  if call.phase == "finding" or call.phase == "spawning" then
    text = "Air Patrol dispatch is taking a call..."
  elseif call.phase == "stuck" or call.phase == "done" or call.phase == "brief" then
    return
  else
    text = progress_text()
  end
  if flash and now < flash_until then text = flash .. " · " .. text end
  objective(api, text)
end

-- Player and suspect updates ---------------------------------------------------

local function on_player(api, data)
  player = data
  local dt = last_poll and math.min(0.5, now - last_poll) or 0
  last_poll = now
  mark_helicopter(api)
  if offer_mode and not shift and offer_mode ~= (can_fly() and "ready" or "grounded") then show_offer(api) end
  if not call then return end
  if call.kind == "medevac" then
    if call.phase == "inbound" or call.phase == "aboard" then
      -- Patients hold steadier once aboard; nobody's condition drops below 5%.
      local rate = call.phase == "aboard" and 0.22 or (call.sar and 0.25 or 0.35)
      call.condition = math.max(5, call.condition - rate * dt)
    end
    if call.phase == "inbound" and reached(call.site, 3, dt) then medevac_pickup(api)
    elseif call.phase == "aboard" and call.dest and reached(call.dest, 3.5, dt) then medevac_deliver(api) end
  elseif call.kind == "pursuit" and call.car_at then
    local d = guide.distance(data, call.car_at)
    if call.phase == "approach" then
      if flying() and d < 7 then
        show_flash("He's running!", 3)
        call.chase, call.lit, call.lost, call.legs = 0, 0, 0, 0
        call.escape_legs = 2 + math.floor(api.utility.random() * 2)
        call.leg_from = call.found
        plan_escape(api)
      end
    elseif call.phase == "chase" then
      call.chase = call.chase + dt
      if flying() and d < 5 and guide.height(data, call.car_at) < 8 then
        call.lit = call.lit + dt
        call.lost = 0
      elseif not flying() or d > 9 then
        call.lost = call.lost + dt
        if call.lost >= 15 then escaped(api) end
      end
    end
  elseif call.kind == "traffic" and call.phase == "report" then
    call.clock = call.clock + dt
    local spot = call.spots[call.index]
    local h = guide.height(data, spot)
    if flying() and guide.distance(data, spot) < 3 and h > 0.75 and h < 7 and (data.speed or 0) < 0.5 then
      call.hold = call.hold + dt
      if call.hold >= 4 and not nearby_request then
        local result = api.world.nearby({radius = 10})
        if result.request_id then nearby_request = result.request_id
        elseif result.ok then finished(api, "nearby", result.code, result.data) end
      end
    else
      call.hold = math.max(0, call.hold - dt)
    end
  elseif call.kind == "charter" then
    if call.phase == "pickup" and reached(call.site, 3, dt) then charter_pickup(api)
    elseif call.phase == "flying" then
      call.clock = call.clock + dt
      if call.case.rule == "nervous" and flying() then
        if (data.speed or 0) > 1.3 then
          call.jitter = call.jitter + dt
          if call.jitter >= 2 then
            call.jitter = 0
            call.eeks = call.eeks + 1
            show_flash(call.case.who .. ": \"Eeek! Slow down, slow down!\"", 2.5)
          end
        else
          call.jitter = 0
        end
      end
      if reached(call.dest, 3.5, dt) then charter_deliver(api) end
    end
  end
end

local function on_look(api, data)
  if not call or call.kind ~= "pursuit" or type(data) ~= "table" or type(data.position) ~= "table" then return end
  call.car_at = guide.point(data.position)
  if call.phase ~= "chase" then return end
  -- A getaway car that stops moving for twenty seconds (stuck behind something
  -- with no way round) is boxed in.
  if not call.still_at or guide.distance(call.car_at, call.still_at) > 0.3 then
    call.still_at, call.still_since = call.car_at, now
  elseif now - call.still_since > 20 then
    cornered(api, "stuck")
  end
end

-- Completions ---------------------------------------------------------------

local function searched(api, action, code, data)
  if not call or call.search_action ~= action then return nil end
  local outcome = far.feed(call.search, code, data)
  if outcome == "again" then
    track(api, action, far.request(api, call.search))
    return nil
  end
  return outcome
end

local function spawn_site(api)
  call.phase = "spawning"
  call.site = guide.point(call.search.at)
  call.found = guide.point(call.search.at)
  serial = serial + 1
  if call.kind == "pursuit" then
    track(api, "actor", api.actor.spawn(call.case.kind, {key = "suspect" .. serial, position = call.site}))
  else
    track(api, "actor", api.actor.spawn("pedestrian", {key = "person" .. serial, position = call.site,
      near_player = true, variant = "pedestrian_" .. call.case.variant}))
  end
end

finished = function(api, action, code, data)
  pending[action] = nil
  if action == "dialogue" then
    if code == "busy" then api.timer.after("say_retry", 1) else queued = nil end
    return
  end
  if action == "captain" then
    if code ~= "ok" then refused(api) return end
    captain, base = data.id, guide.point(data.position)
    api.marker.set("captain", {target = {id = captain}, label = "Capt. Vance · Desert Air Patrol", icon = "person"})
    offer(api)
    return
  end
  if not call then return end
  if action == "site" then
    local outcome = searched(api, action, code, data)
    if outcome == "done" then spawn_site(api)
    elseif outcome == "fail" then
      if call.kind == "charter" and call.landmark ~= "road_destination" then
        call.landmark = "road_destination"
        search(api, "site", {from = shift.anchor, hops = 1, reach = 22, vary = 3})
      else
        stuck(api)
      end
    end
  elseif action == "actor" then
    if code ~= "ok" then
      -- That exact spot was taken: look a little farther along.
      call.tries = call.tries + 1
      if call.tries > 3 then stuck(api) return end
      call.phase = "finding"
      search(api, "site", {from = call.found or call.search.at, hops = 1, reach = 3 + call.tries, vary = 2,
        kind = call.case and call.case.kind, landmark = call.kind == "charter" and call.landmark or nil})
      return
    end
    call.actor = data.id
    call.site = guide.point(data.position)
    if call.kind == "medevac" then
      call.phase = "inbound"
      if call.sar then
        call.zone = guide.offset(call.site, (api.utility.random() - 0.5) * 10, (api.utility.random() - 0.5) * 10)
        api.marker.set("zone", {target = call.zone, label = "Search area · " .. call.case.who .. " last seen", icon = "objective", height = 2})
        api.marker.set("target", {target = {id = call.actor}, label = call.case.who, icon = "person", max_distance = 4})
      else
        api.marker.set("target", {target = {id = call.actor}, label = "Patient · " .. call.case.who, icon = "person"})
      end
    elseif call.kind == "pursuit" then
      call.phase = "approach"
      call.car_at = call.site
      api.marker.set("target", {target = {id = call.actor}, label = "Suspect · " .. call.case.what, icon = "vehicle"})
    else
      call.phase = "pickup"
      api.marker.set("target", {target = {id = call.actor}, label = "Charter · " .. call.case.who, icon = "person"})
    end
    radio_intro(api)
  elseif action == "spots" then
    local outcome = searched(api, action, code, data)
    if outcome == "done" then
      call.spots = call.search.stops
      call.index = 1
      local path, at = 0, shift.anchor
      for _, spot in ipairs(call.spots) do
        path = path + guide.distance(at, spot)
        at = spot
      end
      -- Flight time at full speed plus a little slack for each hover.
      call.limit = 30 + math.floor(path / 1.5 * 1.6)
      call.phase = "report"
      mark_spot(api)
      radio_intro(api)
    elseif outcome == "fail" then stuck(api) end
  elseif action == "nearby" then
    nearby_request = nil
    if call.kind ~= "traffic" or call.phase ~= "report" then return end
    local count = 0
    if code == "ok" and type(data) == "table" then
      for _, seen in ipairs(data) do
        if seen.kind ~= "pedestrian" and seen.kind ~= "helicopter" and seen.kind ~= "plane" then count = count + 1 end
      end
    end
    spot_reported(api, count)
  elseif action == "hospital" then
    if code == "ok" then
      call.dest = guide.point(data)
      api.marker.set("dest", {target = call.dest, label = "Hospital · drop off " .. call.case.who, icon = "checkpoint", height = 0.5})
    else
      call.fallback = true
      call.dest = guide.point(base)
      api.marker.set("dest", {target = call.dest, label = "Air Patrol pad · paramedics waiting", icon = "checkpoint", height = 0.5})
    end
    next_refresh = 0
  elseif action == "escape" then
    local outcome = searched(api, action, code, data)
    if call.phase ~= "chase" then return end
    if outcome == "done" then
      call.legs = (call.legs or 0) + 1
      track(api, "flee", api.actor.navigate(call.actor, guide.point(call.search.at)))
    elseif outcome == "fail" then cornered(api, "dead_end") end
  elseif action == "flee" then
    if call.phase ~= "chase" then return end
    if code ~= "ok" then cornered(api, "dead_end") return end
    call.leg_from = guide.point(call.search.at)
    if call.legs >= call.escape_legs then cornered(api, nil) else plan_escape(api) end
  elseif action == "charter_dest" then
    local outcome = searched(api, action, code, data)
    if outcome == "done" then
      call.dest = guide.point(call.search.at)
      call.phase = "flying"
      call.clock, call.eeks, call.jitter = 0, 0, 0
      call.limit = 25 + math.floor(guide.distance(call.site, call.dest) / 1.5 * 1.4)
      api.marker.set("dest", {target = call.dest, label = call.case.dest .. " · land here", icon = "checkpoint", height = 0.5})
      local rule = call.case.rule == "hurry" and (" You have " .. guide.clock(call.limit) .. ".") or ""
      show_flash(call.case.who .. ": \"" .. call.case.dest .. ", please.\"" .. rule, 4)
    elseif outcome == "fail" then
      -- Nowhere farther to go: the passenger is happy with the Air Patrol pad.
      call.dest = guide.point(base)
      call.phase = "flying"
      call.clock, call.eeks, call.jitter = 0, 0, 0
      call.limit = 25 + math.floor(guide.distance(call.site, call.dest) / 1.5 * 1.4)
      api.marker.set("dest", {target = call.dest, label = "Air Patrol pad · land here", icon = "checkpoint", height = 0.5})
    end
  end
end

return {
  on_start = function(api)
    load_stats(api)
    journal(api)
    objective(api, "Desert Air Patrol is setting up nearby...")
    spawn_captain(api)
  end,
  on_event = function(api, event)
    if event.kind == "timer" then
      if event.key == "startup_retry" then
        retry_scheduled = false
        retry_round = retry_round + 1
        spawn_captain(api)
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
    if look_request and event.request_id == look_request then
      look_request = nil
      if event.code == "ok" then on_look(api, event.data) end
      return
    end
    if nearby_request and event.request_id == nearby_request then
      finished(api, "nearby", event.code, event.data)
      return
    end
    local entry = requests[event.request_id]
    if entry then
      requests[event.request_id] = nil
      pending[entry.action] = nil
      if entry.call == nil or (call and call.id == entry.call) then
        finished(api, entry.action, event.code, event.data)
      elseif entry.action == "actor" and event.code == "ok" and type(event.data) == "table" and event.data.id then
        -- Someone placed for a call that has since been called off.
        api.actor.remove(event.data.id)
      end
      return
    end
    if event.kind == "interaction" and event.key == "patrol" and not shift then
      offer_dialogue(api)
    elseif event.kind == "interaction" and event.key == "stand_down" and shift then
      say(api, "stand_down", CAPTAIN,
        "Calling it a day, Sky Ranger? I can hand the rest to another crew. Everything you've logged so far stays in your book.",
        {{key = "end", label = "End the shift"}, {key = "keep", label = "Keep flying"}})
    elseif event.kind == "dialogue_choice" then
      local choice = event.data.choice
      if event.key == "offer" then
        if choice == "shift" then start_shift(api, nil)
        elseif choice == "medevac" or choice == "pursuit" or choice == "traffic" or choice == "charter" then
          start_shift(api, choice)
        elseif choice == "logbook" then logbook_dialogue(api) end
      elseif event.key == "grounded" then
        if choice == "logbook" then logbook_dialogue(api) end
      elseif event.key == "stand_down" then
        if choice == "end" and shift then end_shift(api) end
      elseif event.key == "logbook" then
        offer_dialogue(api)
      elseif event.key == "brief" then
        if choice == "abandon" then end_shift(api) else next_refresh = 0 end
      elseif event.key == "result" and shift then
        if choice == "next" or (choice == "" and not shift.single and shift.done < SHIFT_CALLS) then
          next_call(api, nil)
        elseif choice == "again" then
          next_call(api, shift.last_kind)
        else
          end_shift(api)
        end
      elseif event.key == "stuck" and shift then
        if choice == "retry" then
          shift.anchor = base
          next_call(api, shift.single and shift.last_kind or nil)
        else
          end_shift(api)
        end
      end
    elseif event.kind == "route_failed" and call and call.kind == "pursuit" and event.data.id == call.actor then
      if call.phase == "chase" then cornered(api, "dead_end") end
    end
  end,
  on_tick = function(api, context)
    now = now + context.delta
    -- Off duty the player is only watched for a helicopter to fly.
    if not player_request and now >= next_poll then
      next_poll = now + (shift and 0.2 or 1)
      local result = api.world.player()
      if result.request_id then player_request = result.request_id
      elseif result.ok then on_player(api, result.data) end
    end
    if call and call.kind == "pursuit" and call.actor and (call.phase == "approach" or call.phase == "chase")
        and not look_request and now >= next_look then
      next_look = now + 0.3
      local look = api.actor.inspect(call.actor)
      if look.request_id then look_request = look.request_id
      elseif look.ok then on_look(api, look.data) end
    end
    refresh_objective(api)
  end
}
