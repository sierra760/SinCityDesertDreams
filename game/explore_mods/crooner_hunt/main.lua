-- Find the Crooner: on-foot hide-and-seek with hot-and-cold hints.
-- The Velvet Crooner keeps slipping away before his show; find him as many
-- times as you can before the curtain. Scores are this pack's own.
local guide = require("guide")

local ROUND = 180
local BONUS = 10
local STAT_KEYS = {"rounds", "best", "found_total"}
local QUIPS = {
  "You found me! I was signing autographs for a cactus.",
  "Shh, I'm in disguise. These sunglasses cost a fortune.",
  "You caught me rehearsing my big finish for the pigeons.",
  "Lou sent you? Tell him I'll be there. Probably.",
  "A crooner has to stretch his legs between ballads, baby.",
  "Did you hear that high note? No? I'm saving it for the show.",
  "My fans need me. Mostly they need me to hide better.",
  "Fine, fine. One encore, then I vanish again.",
  "How did you spot me? Was it the sequins? It's always the sequins.",
  "I was only out here looking for my lucky microphone."
}

local requests, pending = {}, {}
local lou, crooner, spot
local probe_ok, unroutable, offered
local retry_round, retry_scheduled = 0, false
local stats = {}
local phase = "setup"
local round
local player, player_request, look_request
local now, next_refresh, next_poll = 0, 0, 0
local shown, shown_status
local flash, flash_until = nil, 0
local queued
local serial = 0
local leaving = {}
local last_quip
local finished

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
    api.objective.set("crooner", text, status)
  end
end

local function journal(api)
  if stats.rounds == 0 then return end
  api.objective.set("record", "Crooner searches: " .. stats.rounds .. " · best show " .. stats.best ..
    " finds · " .. stats.found_total .. " finds in all", "completed")
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

local function set_idle(api, text)
  phase = "idle"
  if lou then api.interaction.register("lou", {target = {id = lou}, label = "talk to Lou Lamarr, the promoter"}) end
  objective(api, text or "Showtime trouble: talk to Lou Lamarr, the promoter. His headliner has gone missing.")
end

local function offer(api)
  if offered or unroutable or phase ~= "setup" or not (lou and probe_ok) then return end
  offered = true
  set_idle(api)
end

local function spawn_missing(api)
  if not lou and not pending.lou then
    track(api, "lou", api.actor.spawn("pedestrian", {key = "lou", variant = "pedestrian_09", near_player = true}))
  end
  if not probe_ok and not unroutable and not pending.probe then
    track(api, "probe", api.world.find_landmark("sidewalk"))
  end
end

local function refused(api)
  if unroutable then return end
  if retry_round < 2 then
    if not retry_scheduled then
      retry_scheduled = true
      api.timer.after("startup_retry", 3 * (retry_round + 1))
    end
    objective(api, "Lou Lamarr is on his way; he'll be here shortly.")
  else
    objective(api, "Lou Lamarr couldn't find a clear spot on the sidewalk. Move to a clear connected street, then reenter Explore or Disable and Enable this pack and Resume. Your scores are kept.", "failed")
  end
end

local function offer_dialogue(api)
  say(api, "offer", "Lou Lamarr, Showtime Promoter",
    "My headliner, the Velvet Crooner, wandered off before his big show. Again! Find him before the curtain " ..
    "goes up. Walk around and I'll tell you if you're getting warmer or colder. Every time you catch him he " ..
    "buys you ten more seconds, then slips off to a new hiding spot, a little farther away each time. " ..
    "Hold the sprint key; he won't wait for you.\n\n" ..
    "Careful when you get close. Sometimes he spots you and makes a run for it.",
    {{key = "start", label = "Start the search (3 minutes)"}, {key = "record", label = "What's my best?"},
     {key = "later", label = "Not now"}})
end

local function remove_crooner(api, delay)
  if not crooner then return end
  api.interaction.unregister("catch")
  if delay then
    api.marker.remove("crooner")
    leaving["vanish" .. serial] = crooner
    api.timer.after("vanish" .. serial, delay)
  else
    api.actor.remove(crooner)
  end
  crooner, spot = nil, nil
end

local function hide(api)
  if not player then
    phase = "locating"
    return
  end
  phase = "hiding"
  round.attempt = round.attempt + 1
  local options = {from = guide.point(player)}
  if round.attempt == 1 then
    options.min_distance = math.min(10, 4 + round.found)
    options.skip = math.floor(api.utility.random() * 6)
  elseif round.attempt == 2 then
    options.min_distance = 4
  end
  next_refresh = 0
  track(api, "spot", api.world.find_landmark("sidewalk", options))
end

local function start_round(api)
  round = {left = ROUND, found = 0, attempt = 0}
  api.interaction.unregister("lou")
  hide(api)
end

local function end_round(api)
  phase = "over"
  remove_crooner(api)
  stats.rounds = stats.rounds + 1
  stats.found_total = stats.found_total + round.found
  local record = round.found > stats.best
  if record then stats.best = round.found end
  save_stats(api)
  journal(api)
  local text
  if round.found == 0 then
    text = "Curtain's up and no Crooner. I'm out there doing card tricks to buy time. We'll get him next show."
  else
    text = "Showtime! You tracked down the Velvet Crooner " .. round.found ..
      (round.found == 1 and " time" or " times") .. ". The crowd went wild."
  end
  if record then text = text .. " That's a new record!" end
  objective(api, "Showtime: you found the Velvet Crooner " .. round.found .. (round.found == 1 and " time." or " times."), "completed")
  round = nil
  say(api, "over", "Lou Lamarr (on the phone)", text,
    {{key = "again", label = "Search again"}, {key = "done", label = "That's showbiz"}})
end

local function temperature(distance)
  if distance >= 12 then return "Ice cold" end
  if distance >= 8 then return "Cold" end
  if distance >= 5.5 then return "Cool" end
  if distance >= 3.5 then return "Warm" end
  if distance >= 2 then return "Hot!" end
  return "Sizzling! He's right around here"
end

local function refresh_objective(api)
  if not round or now < next_refresh then return end
  next_refresh = now + 0.5
  local parts
  if phase == "searching" and spot and player then
    local d = guide.distance(player, spot)
    parts = {"Find the Crooner: " .. temperature(d)}
    if round.trend ~= "" then parts[#parts + 1] = round.trend end
  else
    parts = {"The Crooner is slipping off to a new hiding spot..."}
  end
  parts[#parts + 1] = "found " .. round.found
  parts[#parts + 1] = guide.clock(round.left) .. " left"
  if player and player.mode ~= 0 then parts[#parts + 1] = "catch him on foot" end
  local text = table.concat(parts, " · ")
  if flash and now < flash_until then text = flash .. " · " .. text end
  objective(api, text)
end

local function flee(api)
  round.fled = true
  track(api, "escape", api.world.find_landmark("sidewalk", {from = guide.point(spot), away_from = guide.point(player), min_distance = 4}))
end

local function on_player(api, data)
  player = data
  if phase == "locating" then hide(api) end
  if phase ~= "searching" or not spot then return end
  local d = guide.distance(data, spot)
  if not round.trend_at or now >= round.trend_at then
    if round.reference then
      -- Even a walk covers about 0.18 tiles in two seconds.
      if round.reference - d > 0.15 then round.trend = "warmer"
      elseif d - round.reference > 0.15 then round.trend = "colder"
      else round.trend = "" end
    end
    round.reference = d
    round.trend_at = now + 2
  end
  if not round.fled and not round.fleeing and round.found >= 1 and d < 3.5 and api.utility.random() < 0.45 then
    flee(api)
  end
  if now >= round.hint_at then
    round.hint_at = now + 35
    local where = guide.direction(data, spot)
    if where ~= "" and where ~= "right here" then show_flash("A fan spotted him somewhere " .. where, 5) end
  end
end

local function caught(api)
  phase = "caught"
  round.found = round.found + 1
  round.left = round.left + BONUS
  if crooner then api.actor.wave(crooner) end
  remove_crooner(api, 1.8)
  local index = math.floor(api.utility.random() * (#QUIPS - 1)) + 1
  if last_quip and index >= last_quip then index = index + 1 end
  last_quip = index
  local quip = QUIPS[index]
  say(api, "caught", "The Velvet Crooner", quip .. "\n\n+" .. BONUS .. " seconds. Found " .. round.found ..
    (round.found == 1 and " time" or " times") .. " this show.", {{key = "go", label = "Back to the show, Crooner!"}})
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
      objective(api, "There are no connected sidewalks here for a game of hide-and-seek. Try a bigger street and reenter Explore.", "failed")
      return
    else refused(api) end
  elseif action == "lou" then
    if code ~= "ok" then refused(api) return end
    lou = data.id
    api.marker.set("lou", {target = {id = lou}, label = "Lou Lamarr · Find the Crooner", icon = "person"})
  elseif action == "spot" then
    if not round then return end
    if code ~= "ok" then
      if round.attempt < 3 then hide(api) else end_round(api) end
      return
    end
    serial = serial + 1
    track(api, "crooner", api.actor.spawn("pedestrian", {key = "crooner" .. serial, variant = "pedestrian_12",
      position = guide.point(data), near_player = true}))
    return
  elseif action == "crooner" then
    if not round then
      if code == "ok" then api.actor.remove(data.id) end
      return
    end
    if code ~= "ok" then
      if round.attempt < 3 then hide(api) else end_round(api) end
      return
    end
    crooner, spot = data.id, data.position
    -- Reveal only within 32 metres; opening the full map cannot spoil the hunt.
    api.marker.set("crooner", {target = {id = crooner}, label = "Velvet Crooner", icon = "person", max_distance = 2})
    api.interaction.register("catch", {target = {id = crooner}, label = "tap the Velvet Crooner on the shoulder"})
    round.attempt = 0
    round.fled, round.fleeing = false, false
    round.reference, round.trend, round.trend_at = nil, "", nil
    round.hint_at = now + 35
    phase = "searching"
    next_refresh = 0
    return
  elseif action == "escape" then
    if code ~= "ok" or not crooner or phase ~= "searching" then return end
    round.fleeing = true
    show_flash("He spotted you! The Crooner is making a run for it", 3)
    round.escape_to = guide.point(data)
    track(api, "run", api.actor.navigate(crooner, round.escape_to))
    return
  elseif action == "run" then
    if round and round.fleeing then
      round.fleeing = false
      if code == "ok" and round.escape_to and crooner then spot = round.escape_to end
    end
    return
  end
  offer(api)
end

return {
  on_start = function(api)
    load_stats(api)
    journal(api)
    objective(api, "Lou Lamarr, the showtime promoter, is on his way...")
    spawn_missing(api)
  end,
  on_event = function(api, event)
    if event.kind == "timer" then
      if event.key == "startup_retry" then
        retry_scheduled = false
        retry_round = retry_round + 1
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
    if look_request and event.request_id == look_request then
      look_request = nil
      if event.code == "ok" and round and round.fleeing and event.data.position then spot = event.data.position end
      return
    end
    local action = requests[event.request_id]
    if action then
      requests[event.request_id] = nil
      finished(api, action, event.code, event.data)
      return
    end
    if event.kind == "interaction" then
      if event.key == "lou" and phase == "idle" then offer_dialogue(api)
      elseif event.key == "catch" and phase == "searching" then caught(api) end
    elseif event.kind == "dialogue_choice" then
      local choice = event.data.choice
      if event.key == "offer" then
        if choice == "start" then start_round(api)
        elseif choice == "record" then
          local text = stats.rounds == 0 and "No shows yet, kid. Your first search is waiting."
            or ("Best show: " .. stats.best .. (stats.best == 1 and " find" or " finds") .. ". Searches: " ..
                stats.rounds .. ". Total finds: " .. stats.found_total .. ". The Crooner says hi. Probably.")
          say(api, "record", "Lou Lamarr, Showtime Promoter", text, {{key = "back", label = "Back"}})
        end
      elseif event.key == "record" then
        offer_dialogue(api)
      elseif event.key == "caught" then
        if round then hide(api) end
      elseif event.key == "over" then
        if choice == "again" then start_round(api)
        else set_idle(api, "Lou Lamarr is waiting by the stage door whenever you want another search.") end
      end
    elseif event.kind == "route_failed" and crooner and event.data.id == crooner and round then
      round.fleeing = false
    end
  end,
  on_tick = function(api, context)
    now = now + context.delta
    if not round or phase == "caught" or phase == "over" then return end
    round.left = round.left - context.delta
    if round.left <= 0 then
      end_round(api)
      return
    end
    if not player_request and now >= next_poll then
      next_poll = now + 0.2
      local result = api.world.player()
      if result.request_id then player_request = result.request_id end
    end
    if round.fleeing and crooner and not look_request and now >= (round.look_at or 0) then
      round.look_at = now + 0.4
      local look = api.actor.inspect(crooner)
      if look.request_id then look_request = look.request_id end
    end
    refresh_objective(api)
  end
}
