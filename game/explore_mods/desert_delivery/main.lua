-- Desert Dispatch: run delivery shifts in a borrowed Delivery Van.
-- Tips and courier ranks are this pack's own score; city funds never change.
local guide = require("guide")
local PARCELS = require("parcels")

local SHIFT = 3
local RANKS = {{0, "Rookie Runner"}, {5, "Road Regular"}, {15, "Sun-Baked Pro"}, {30, "Mirage Master"}, {60, "Desert Legend"}}
local STAT_KEYS = {"deliveries", "tips", "shifts", "best_shift", "on_time"}

local requests, pending = {}, {}
local courier, van, recipient, van_at
local probe_ok, unroutable, offered
local retry_round, retry_scheduled = 0, false
local park_tries = 0
local stats = {}
local shift, job
local player, player_request
local now, next_refresh, next_poll = 0, 0, 0
local shown, shown_status
local flash, flash_until = nil, 0
local queued
local serial = 0
local leaving = {}
local finished, next_job

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
  -- Version 1 of this pack saved a single completed delivery.
  if stats.deliveries == 0 and api.state.get("completed", false) == true then stats.deliveries = 1 end
end

local function save_stats(api)
  for _, key in ipairs(STAT_KEYS) do api.state.set(key, stats[key]) end
end

local function objective(api, text, status)
  status = status or "active"
  if text ~= shown or status ~= shown_status then
    shown, shown_status = text, status
    api.objective.set("delivery", text, status)
  end
end

local function journal(api)
  if stats.deliveries == 0 then return end
  local _, title = rank_of(stats.deliveries)
  api.objective.set("rank", "Courier rank: " .. title .. " · " .. stats.deliveries ..
    (stats.deliveries == 1 and " parcel · " or " parcels · ") ..
    tips(stats.tips) .. " · best shift " .. tips(stats.best_shift), "completed")
end

local function show_flash(text, seconds)
  flash, flash_until, next_refresh = text, now + seconds, 0
end

local function track(api, action, result)
  if result.ok and result.request_id then
    requests[result.request_id] = action
    pending[action] = true
  else
    finished(api, action, result.code, result.data)
  end
end

local function say(api, key, speaker, text, choices)
  queued = {key = key, speaker = speaker, text = text, choices = choices}
  track(api, "dialogue", api.dialogue.show(key, speaker, text, choices))
end

local function offer(api)
  if offered or unroutable or shift or not (courier and van and probe_ok) then return end
  offered = true
  api.interaction.register("parcel", {target = {id = courier}, label = "talk to Marisol at Desert Dispatch"})
  objective(api, "Talk to Marisol at Desert Dispatch, beside the Delivery Van, to start a delivery shift.")
end

local function spawn_missing(api)
  if not shift and not courier and not pending.courier then
    track(api, "courier", api.actor.spawn("pedestrian", {key = "courier", variant = "pedestrian_03", near_player = true}))
  end
  if not van and not pending.van then
    track(api, "van", api.actor.spawn("van", {key = "delivery_car", near_player = true, enterable = true}))
  end
  if not probe_ok and not unroutable and not pending.probe then
    track(api, "probe", api.world.find_landmark("road_destination", {kind = "van"}))
  end
end

local function refused(api, code)
  if unroutable then return end
  if retry_round < 2 then
    if not retry_scheduled then
      retry_scheduled = true
      api.timer.after("startup_retry", 3 * (retry_round + 1))
    end
    objective(api, "Desert Dispatch is waiting for a safe spot on the road; it will try again shortly.")
  else
    objective(api, "Desert Dispatch could not find a safe spot on the road after two tries. Move to a clear connected street, then reenter Explore or Disable and Enable this pack and Resume. Your courier record is kept.", "failed")
  end
end

local function offer_dialogue(api)
  local _, title = rank_of(stats.deliveries)
  local record = stats.deliveries == 0 and "First day on the job? Welcome aboard."
    or ("You're a " .. title .. " with " .. stats.deliveries .. " deliveries under your belt.")
  say(api, "offer", "Marisol, Desert Dispatch",
    "Three parcels, one Delivery Van and a whole lot of desert. Easy shifts run at your own pace. " ..
    "Express shifts are on the clock, and beating it earns bigger tips. Some parcels are fragile, some are hot, " ..
    "and one or two need a steady hand.\n\n" .. record .. " Tips are bragging rights only; city funds never change.",
    {{key = "accept", label = "Easy shift: three parcels, no rush"},
     {key = "express", label = "Express shift: beat the clock"},
     {key = "stats", label = "How am I doing?"},
     {key = "later", label = "Maybe later"}})
end

local function stats_dialogue(api)
  local _, title, need, upcoming = rank_of(stats.deliveries)
  local lines = {"Rank: " .. title, "Parcels delivered: " .. stats.deliveries, "Tips earned: " .. stats.tips,
    "Shifts worked: " .. stats.shifts .. " · best shift " .. tips(stats.best_shift),
    "Express parcels on time: " .. stats.on_time}
  if upcoming then
    lines[#lines + 1] = "\n" .. need .. (need == 1 and " more delivery" or " more deliveries") .. " until " .. upcoming .. "."
  else
    lines[#lines + 1] = "\nThere's no rank above Desert Legend. They name roads after people like you."
  end
  say(api, "stats", "Marisol, Desert Dispatch", table.concat(lines, "\n"), {{key = "back", label = "Back"}})
end

local function farewell(api)
  api.marker.remove("destination")
  if not recipient then return end
  api.actor.wave(recipient)
  leaving["farewell" .. serial] = recipient
  api.timer.after("farewell" .. serial, 2.5)
  recipient = nil
end

local function find_address(api)
  -- Addresses are measured from the van, where every run starts.
  local origin = van_at or player
  if not origin then
    job.phase = "locating"
    return
  end
  job.phase = "finding"
  job.attempt = job.attempt + 1
  local reach = math.min(30, 6 + 4 * shift.index)
  local options = {kind = "van", from = guide.point(origin)}
  if job.attempt == 1 then
    options.min_distance = reach
    options.skip = math.floor(api.utility.random() * 4)
    if shift.last then options.away_from = shift.last end
  elseif job.attempt == 2 then
    options.min_distance = reach
  elseif job.attempt == 3 then
    options.min_distance = math.max(3, math.floor(reach * 0.6))
  else
    options.min_distance = 3
  end
  track(api, "address", api.world.find_landmark("road_destination", options))
end

local function stuck(api)
  job.phase = "stuck"
  objective(api, "Dispatch can't find a reachable address from here. Drive onto a connected street and radio in.")
  say(api, "stuck", "Dispatch radio",
    "Bad news: I can't find a reachable address from where you are. Drive the van onto a connected street and I'll try again.",
    {{key = "retry", label = "Try again"}, {key = "stop", label = "End the shift"}})
end

local function start_shift(api, express)
  shift = {express = express, index = 0, delivered = 0, tips = 0, used = {}}
  offered = false
  api.interaction.unregister("parcel")
  if courier then
    api.marker.remove("dispatcher")
    api.actor.remove(courier)
    courier = nil
  end
  next_job(api)
end

next_job = function(api)
  shift.index = shift.index + 1
  local open = {}
  for i = 1, #PARCELS do
    if not shift.used[i] then open[#open + 1] = i end
  end
  local pick = open[math.floor(api.utility.random() * #open) + 1]
  shift.used[pick] = true
  job = {parcel = PARCELS[pick], attempt = 0, clock = 0, bumps = 0, wobbles = 0, wobble = 0}
  job.timed = shift.express or job.parcel.rule == "hot"
  flash = nil
  next_refresh = 0
  find_address(api)
end

local function intro()
  local p = job.parcel
  local text = "Parcel " .. shift.index .. "/" .. SHIFT .. ": " .. p.item .. " for " .. p.to .. "."
  if p.rule == "fragile" then text = text .. " Fragile! Brake gently and don't hit anything."
  elseif p.rule == "steady" then text = text .. " Keep it under three-quarter speed."
  elseif p.rule == "hot" then text = text .. " It's hot, so the clock is running!" end
  if shift.express then text = text .. " Express: " .. guide.clock(job.limit) .. " on the clock." end
  return text
end

local function refresh_objective(api)
  if not job or now < next_refresh then return end
  next_refresh = now + 0.5
  local text
  if job.phase == "locating" or job.phase == "finding" then
    text = "Parcel " .. shift.index .. "/" .. SHIFT .. ": Dispatch is looking up the next address..."
  elseif job.phase == "driving" then
    if now < job.intro_until then
      text = intro()
    else
      local parts = {shift.index .. "/" .. SHIFT .. " " .. job.parcel.short .. " for " .. job.parcel.who}
      if player then parts[#parts + 1] = guide.describe(player, job.drop) end
      if job.timed then
        parts[#parts + 1] = job.clock <= job.limit and (guide.clock(job.limit - job.clock) .. " left") or "running late!"
      end
      if player and player.mode == 0 then
        local where = van_at and guide.describe(player, van_at)
        parts[#parts + 1] = (where and where ~= "right here") and ("hop in the Delivery Van, " .. where) or "hop in the Delivery Van"
      elseif player and player.vehicle ~= van then
        parts[#parts + 1] = "the parcel is in the Delivery Van"
      end
      text = table.concat(parts, " · ")
    end
    if flash and now < flash_until then text = flash .. " · " .. text end
  end
  if text then objective(api, text) end
end

local function deliver(api)
  job.phase = "delivered"
  local p = job.parcel
  local base = 8 + math.floor(job.route * 0.6)
  if shift.express then base = math.floor(base * 1.5) end
  local bonus, late, notes = 0, false, {}
  if job.timed then
    if job.clock <= job.limit then
      local early = math.floor((job.limit - job.clock) * 0.5) + (shift.express and 5 or 2)
      bonus = bonus + early
      notes[#notes + 1] = "on time +" .. early
      if shift.express then stats.on_time = stats.on_time + 1 end
    else
      late = true
      base = math.floor(base / 2)
      notes[#notes + 1] = "late, so half the tip"
    end
  end
  if p.rule == "fragile" then
    if job.bumps == 0 then
      bonus = bonus + 4
      notes[#notes + 1] = "gentle hands +4"
    else
      notes[#notes + 1] = job.bumps > 4 and "a lot of crunching -12"
        or (job.bumps .. (job.bumps == 1 and " crunch -3" or " crunches -" .. 3 * job.bumps))
    end
  elseif p.rule == "steady" then
    if job.wobbles == 0 then
      bonus = bonus + 4
      notes[#notes + 1] = "smooth ride +4"
    else
      notes[#notes + 1] = job.wobbles > 4 and "a very wobbly ride -8"
        or (job.wobbles .. (job.wobbles == 1 and " wobble -2" or " wobbles -" .. 2 * job.wobbles))
    end
  end
  -- Penalties cap out so one rough run can't wipe out the whole tip.
  local tip = math.max(1, base + bonus - 3 * math.min(job.bumps, 4) - 2 * math.min(job.wobbles, 4))
  local before = rank_of(stats.deliveries)
  shift.tips = shift.tips + tip
  shift.delivered = shift.delivered + 1
  stats.deliveries = stats.deliveries + 1
  stats.tips = stats.tips + tip
  local after, title = rank_of(stats.deliveries)
  save_stats(api)
  journal(api)
  shift.last = guide.point(job.drop)
  if recipient then api.actor.wave(recipient) end
  local text = (late and p.late or p.thanks) .. "\n\nTip: " .. tip
  if #notes > 0 then text = text .. " (" .. table.concat(notes, ", ") .. ")" end
  text = text .. ". Shift total: " .. tips(shift.tips) .. "."
  if after > before then text = text .. "\n\nPromotion! You're now a " .. title .. "." end
  objective(api, "Delivered " .. p.item .. " to " .. p.to .. ".")
  local choices = {{key = "finish", label = "Finish the shift"}}
  if shift.index < SHIFT then
    choices = {{key = "next", label = "Next parcel"}, {key = "stop", label = "End the shift here"}}
  end
  say(api, "drop", p.who, text, choices)
end

local function end_shift(api)
  farewell(api)
  stats.shifts = stats.shifts + 1
  local record = shift.delivered > 0 and shift.tips > stats.best_shift
  if record then stats.best_shift = shift.tips end
  save_stats(api)
  journal(api)
  local _, title = rank_of(stats.deliveries)
  local summary = "Shift complete: " .. shift.delivered .. (shift.delivered == 1 and " parcel, " or " parcels, ") ..
    tips(shift.tips) .. ". Rank: " .. title .. "."
  objective(api, summary, "completed")
  local text = shift.delivered == 0 and "No harm done. The desert will still be here tomorrow."
    or ("That's a wrap! " .. shift.delivered .. (shift.delivered == 1 and " parcel" or " parcels") ..
    " delivered and " .. tips(shift.tips) .. " in the jar.")
  if record then text = text .. " That's your best shift yet!" end
  shift, job = nil, nil
  say(api, "radio", "Dispatch radio", text .. "\n\nWant another run while you've got the van?",
    {{key = "easy", label = "Another easy shift"}, {key = "express", label = "Another express shift"},
     {key = "done", label = "Clock out"}})
end

local function on_player(api, data)
  player = data
  if not job then return end
  if job.phase == "locating" then find_address(api) end
  if job.phase ~= "driving" then return end
  local p = job.parcel
  local in_van = data.mode == 1 and van ~= nil and data.vehicle == van
  if in_van then
    van_at = guide.point(data)
    local speed = data.speed or 0
    local dt = job.last_time and now - job.last_time or 0
    if p.rule == "fragile" and job.last_speed and dt > 0.04 and dt < 0.5 and job.last_speed > 0.35
        and (job.last_speed - speed) / dt > 1.7 and now - (job.bump_at or -10) > 1.2 then
      job.bump_at = now
      job.bumps = job.bumps + 1
      show_flash(job.bumps <= 4 and ("Crunch! Careful with the " .. string.lower(p.short) .. " (-3 tip)")
        or ("Crunch! Careful with the " .. string.lower(p.short)), 2.5)
    end
    -- Every two seconds spent above three-quarter speed sloshes the load.
    if p.rule == "steady" and speed > 0.85 then
      job.wobble = job.wobble + math.min(0.5, dt)
      if job.wobble >= 2 then
        job.wobble = 0
        job.wobbles = job.wobbles + 1
        show_flash(job.wobbles <= 4 and "Whoa, steady! Everything's sliding around back there (-2 tip)"
          or "Whoa, steady! Everything's sliding around back there", 2.5)
      end
    elseif p.rule == "steady" then
      job.wobble = 0
    end
    job.last_speed, job.last_time = speed, now
    if guide.distance(data, job.drop) < 0.8 then
      deliver(api)
      return
    end
  else
    job.last_speed, job.last_time = nil, nil
  end
  if not job.waved and recipient and guide.distance(data, job.drop) < 5 then
    job.waved = true
    api.actor.wave(recipient)
  end
end

finished = function(api, action, code, data)
  pending[action] = nil
  if action == "dialogue" then
    if code == "busy" then api.timer.after("say_retry", 1) else queued = nil end
    return
  end
  if action == "probe" then
    if code == "ok" then probe_ok = true
    elseif code == "no_route" then
      unroutable = true
      objective(api, "This city has no usable delivery route here. Try a connected street and reenter Explore.", "failed")
      return
    else refused(api, code) end
  elseif action == "van" and code ~= "ok" and park_tries < 3 then
    -- No room right beside the player: park a little way down the road.
    park_tries = park_tries + 1
    track(api, "van_spot", api.world.find_landmark("road_destination", {kind = "van", skip = park_tries, min_distance = 2 + park_tries}))
    return
  elseif action == "van_spot" then
    if code ~= "ok" then refused(api, code) return end
    track(api, "van", api.actor.spawn("van", {key = "delivery_car", position = guide.point(data), enterable = true}))
    return
  elseif action == "courier" or action == "van" then
    if code ~= "ok" then refused(api, code) return end
    if action == "courier" then
      courier = data.id
      api.marker.set("dispatcher", {target = {id = courier}, label = "Marisol · Desert Dispatch", icon = "person"})
    else
      van, van_at = data.id, data.position
      api.marker.set("van", {target = {id = van}, label = "Delivery Van", icon = "vehicle"})
    end
  elseif action == "address" then
    if not job then return end
    if code ~= "ok" then
      if job.attempt < 4 then find_address(api) else stuck(api) end
      return
    end
    job.route = type(data.distance) == "number" and data.distance or 6
    serial = serial + 1
    track(api, "recipient", api.actor.spawn("pedestrian", {key = "recipient" .. serial, position = guide.point(data),
      near_player = true, variant = "pedestrian_" .. job.parcel.variant}))
    return
  elseif action == "recipient" then
    if not job then return end
    if code ~= "ok" then
      if job.attempt < 4 then find_address(api) else stuck(api) end
      return
    end
    recipient = data.id
    api.marker.set("destination", {target = {id = recipient}, label = "Deliver to " .. job.parcel.to, icon = "objective"})
    -- Admission may choose a vacant cell beside the address; arrival uses
    -- the recipient's actual copied pose, never the requested anchor.
    job.drop = data.position
    job.limit = shift.express and (8 + 1.5 * job.route) or (12 + 2 * job.route)
    job.clock = 0
    job.intro_until = now + 5
    job.phase = "driving"
    next_refresh = 0
    return
  end
  offer(api)
end

return {
  on_start = function(api)
    load_stats(api)
    journal(api)
    objective(api, "Desert Dispatch is setting up nearby...")
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
    local action = requests[event.request_id]
    if action then
      requests[event.request_id] = nil
      finished(api, action, event.code, event.data)
      return
    end
    if event.kind == "interaction" and event.key == "parcel" and not shift then
      offer_dialogue(api)
    elseif event.kind == "dialogue_choice" then
      local choice = event.data.choice
      if event.key == "offer" then
        if choice == "accept" then start_shift(api, false)
        elseif choice == "express" then start_shift(api, true)
        elseif choice == "stats" then stats_dialogue(api) end
      elseif event.key == "stats" then
        offer_dialogue(api)
      elseif event.key == "drop" then
        -- Closing the dialogue without a choice keeps the shift rolling.
        if choice == "next" or (choice == "" and shift.index < SHIFT) then
          farewell(api)
          next_job(api)
        else
          end_shift(api)
        end
      elseif event.key == "stuck" then
        if choice ~= "stop" then
          job.attempt = 0
          find_address(api)
        else
          end_shift(api)
        end
      elseif event.key == "radio" then
        if choice == "easy" then start_shift(api, false)
        elseif choice == "express" then start_shift(api, true)
        else
          local _, title = rank_of(stats.deliveries)
          objective(api, "Clocked out. Rank: " .. title .. ". Marisol will have more parcels next time you explore.", "completed")
        end
      end
    elseif event.kind == "route_failed" and event.data.id == van then
      van, van_at = nil, nil
      spawn_missing(api)
    end
  end,
  on_tick = function(api, context)
    now = now + context.delta
    if job and job.phase == "driving" then job.clock = job.clock + context.delta end
    if job and not player_request and now >= next_poll then
      next_poll = now + 0.2
      local result = api.world.player()
      if result.request_id then player_request = result.request_id end
    end
    refresh_objective(api)
  end
}
