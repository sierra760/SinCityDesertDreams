-- Neon Rally: a checkpoint time trial through the city's own streets.
-- Course marshals wave you through each checkpoint; Dusty Dan drives the same
-- course in his pickup. Medals and records are this pack's own; city funds,
-- simulation and traffic rules are unchanged.
local guide = require("guide")

local KINDS = {sprint = {name = "Sprint", checkpoints = 3, leg = 8},
               grand = {name = "Grand Tour", checkpoints = 5, leg = 7}}
local STAT_KEYS = {"races", "gold", "silver", "bronze", "best_rating", "beat_dan", "lost_to_dan"}
local MARSHAL = "pedestrian_00"

local requests, pending = {}, {}
local fran, car, car_at
local probe_ok, unroutable, offered
local retry_round, retry_scheduled = 0, false
local park_tries = 0
local stats = {}
local phase = "setup"
local course, race
local player, player_request, dan_request
local now, next_refresh, next_poll = 0, 0, 0
local shown, shown_status
local flash, flash_until = nil, 0
local queued
local serial = 0
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
    api.objective.set("rally", text, status)
  end
end

local function journal(api)
  if stats.races == 0 then return end
  api.objective.set("trophies", "Neon Rally trophies: " .. stats.gold .. " gold · " .. stats.silver .. " silver · " ..
    stats.bronze .. " bronze · best run " .. stats.best_rating .. "% of par", "completed")
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

-- Fran only takes questions between races.
local function set_idle(api, text)
  if fran then api.marker.set("fran", {target = {id = fran}, label = "Flagger Fran · Neon Rally", icon = "person"}) end
  phase = "idle"
  if fran then api.interaction.register("race", {target = {id = fran}, label = "talk to Flagger Fran"}) end
  objective(api, text or "Talk to Flagger Fran at the start line to race the Neon Rally.")
end

local function offer(api)
  if offered or unroutable or phase ~= "setup" or not (fran and car and probe_ok) then return end
  offered = true
  set_idle(api)
end

local function spawn_missing(api)
  if not fran and not pending.fran then
    track(api, "fran", api.actor.spawn("pedestrian", {key = "fran", variant = "pedestrian_04", near_player = true}))
  end
  if not car and not pending.car then
    track(api, "car", api.actor.spawn("car", {key = "rally_car", near_player = true, enterable = true}))
  end
  if not probe_ok and not unroutable and not pending.probe then
    track(api, "probe", api.world.find_landmark("road_destination", {kind = "car"}))
  end
end

local function refused(api)
  if unroutable then return end
  if retry_round < 2 then
    if not retry_scheduled then
      retry_scheduled = true
      api.timer.after("startup_retry", 3 * (retry_round + 1))
    end
    objective(api, "The Neon Rally crew is waiting for a clear spot on the road; they'll try again shortly.")
  else
    objective(api, "The Neon Rally crew couldn't find a clear spot on the road. Move to a clear connected street, then reenter Explore or Disable and Enable this pack and Resume. Your trophies are kept.", "failed")
  end
end

local function offer_dialogue(api)
  say(api, "offer", "Flagger Fran",
    "Welcome to the Neon Rally! Take the Desert Cruiser, wait for my countdown, then drive past each course " ..
    "marshal in order. They'll wave you through. Beat par for gold.\n\n" ..
    "Dusty Dan says nobody's ever beaten his pickup on these streets. He'll be racing the same course. " ..
    "Prove him wrong.",
    {{key = "sprint", label = "Sprint: three checkpoints"}, {key = "grand", label = "Grand Tour: five checkpoints"},
     {key = "trophies", label = "My trophy case"}, {key = "later", label = "Not now"}})
end

local function trophy_dialogue(api)
  local text
  if stats.races == 0 then
    text = "Your trophy case is a little dusty. Nothing a race or two won't fix."
  else
    text = "Races finished: " .. stats.races .. "\nGold " .. stats.gold .. " · Silver " .. stats.silver ..
      " · Bronze " .. stats.bronze .. "\nBest run: " .. stats.best_rating .. "% of par\nAgainst Dusty Dan: you " ..
      stats.beat_dan .. ", Dan " .. stats.lost_to_dan
  end
  say(api, "trophies", "Flagger Fran", text, {{key = "back", label = "Back"}})
end

local function clear_course(api)
  api.marker.remove("checkpoint")
  if course then
    for _, checkpoint in ipairs(course.checkpoints) do
      if checkpoint.marshal then api.actor.remove(checkpoint.marshal) end
    end
  end
  if race and race.dan then api.actor.remove(race.dan) end
  course, race = nil, nil
  dan_request = nil
end

local function build_step(api)
  local k = #course.checkpoints + 1
  local from = k == 1 and course.start or course.checkpoints[k - 1].landmark
  local options = {kind = "car", from = guide.point(from), min_distance = course.leg}
  if course.retry == 0 then
    options.skip = math.floor(api.utility.random() * 3)
    local back = k == 2 and course.start or (k > 2 and course.checkpoints[k - 2].landmark)
    if back then options.away_from = guide.point(back) end
  elseif course.retry == 2 then
    options.min_distance = 4
  end
  track(api, "checkpoint", api.world.find_landmark("road_destination", options))
end

local function mark_checkpoint(api, index)
  local checkpoint = course and course.checkpoints[index]
  if not checkpoint then api.marker.remove("checkpoint") return end
  local target = checkpoint.marshal and {id = checkpoint.marshal} or guide.point(checkpoint.at)
  api.marker.set("checkpoint", {target = target, label = "Checkpoint " .. index .. "/" .. #course.checkpoints, icon = "checkpoint"})
end

local function course_ready(api)
  mark_checkpoint(api, 1)
  local total = 0
  for _, checkpoint in ipairs(course.checkpoints) do total = total + checkpoint.route end
  course.par = math.floor(total * 1.05 + 2 * #course.checkpoints + 0.5)
  phase = "ready"
  next_refresh = 0
  -- Dusty Dan lines up a few lengths away. He always creeps past the line.
  track(api, "dan_spot", api.world.find_landmark("road_destination", {kind = "pickup", from = guide.point(course.start), skip = 1}))
end

local function plan_course(api, kind)
  clear_course(api)
  local start = (player and player.mode == 1) and player or car_at or player
  if not start then
    set_idle(api)
    return
  end
  local settings = KINDS[kind]
  course = {kind = kind, name = settings.name, want = settings.checkpoints, leg = settings.leg,
            start = guide.point(start), checkpoints = {}, retry = 0}
  phase = "building"
  api.interaction.unregister("race")
  api.marker.remove("fran")
  next_refresh = 0
  objective(api, "Fran's marshals are taking their places for the " .. settings.name .. "...")
  build_step(api)
end

local function place(api)
  if not race.dan or race.dan_out then return "1st" end
  if race.dan_done then return "2nd" end
  if race.dan_cp > race.passed then return "2nd" end
  if race.dan_cp < race.passed or not race.dan_at or not player then return "1st" end
  local target = course.checkpoints[race.passed + 1]
  if not target then return "1st" end
  return guide.distance(race.dan_at, target.at) < guide.distance(player, target.at) and "2nd" or "1st"
end

local function send_dan(api)
  local target = course.checkpoints[race.dan_cp + 1]
  if not target then return end
  track(api, "dan_drive", api.actor.navigate(race.dan, guide.point(target.landmark)))
end

local function medal_for(rating)
  if rating >= 100 then return "gold", "GOLD" end
  if rating >= 80 then return "silver", "SILVER" end
  if rating >= 62 then return "bronze", "BRONZE" end
  return nil, "no medal this time"
end

local function finish_race(api)
  api.marker.remove("checkpoint")
  phase = "finished"
  local time = race.clock + race.penalty
  local rating = math.floor(course.par / math.max(time, 1) * 100 + 0.5)
  local medal, medal_name = medal_for(rating)
  stats.races = stats.races + 1
  if medal then stats[medal] = stats[medal] + 1 end
  local best = rating > stats.best_rating
  if best then stats.best_rating = rating end
  local lines = {"Finish time " .. guide.stopwatch(time) .. ": " .. medal_name .. "!"}
  if race.penalty > 0 then lines[#lines + 1] = "(Includes a " .. race.penalty .. " second false-start penalty.)" end
  lines[#lines + 1] = "Par for this course was " .. guide.stopwatch(course.par) .. " (you ran " .. rating .. "% of par)."
  if race.dan and not race.dan_out and race.dan_done and race.dan_time < time then
    stats.lost_to_dan = stats.lost_to_dan + 1
    lines[#lines + 1] = "Dusty Dan beat you by " .. guide.stopwatch(time - race.dan_time) .. ". He's already telling everyone."
  elseif race.dan and not race.dan_out then
    stats.beat_dan = stats.beat_dan + 1
    lines[#lines + 1] = "You beat Dusty Dan! He's muttering something about his tires."
  elseif race.dan then
    lines[#lines + 1] = "Dusty Dan got lost somewhere back there. It still counts."
  end
  if best then lines[#lines + 1] = "That's your best run yet!" end
  save_stats(api)
  journal(api)
  objective(api, "Neon Rally " .. course.name .. ": " .. guide.stopwatch(time) .. ", " .. medal_name .. ".", "completed")
  say(api, "result", "Flagger Fran (radio)", table.concat(lines, "\n"),
    {{key = "again", label = "Race a new course from here"}, {key = "done", label = "Park it for now"}})
end

local function pass_checkpoint(api)
  race.passed = race.passed + 1
  local checkpoint = course.checkpoints[race.passed]
  if checkpoint.marshal then api.actor.wave(checkpoint.marshal) end
  if race.passed >= #course.checkpoints then
    finish_race(api)
  else
    mark_checkpoint(api, race.passed + 1)
    show_flash("Checkpoint " .. race.passed .. "/" .. #course.checkpoints .. " in " .. guide.stopwatch(race.clock), 2.5)
  end
end

local function refresh_objective(api)
  if now < next_refresh then return end
  next_refresh = now + 0.3
  local text
  if phase == "ready" then
    text = "Hop in the Desert Cruiser (or any car). Fran starts the countdown when you're behind the wheel."
    if car_at and player and player.mode == 0 then
      local where = guide.describe(player, car_at)
      if where ~= "right here" then text = text .. " The Cruiser is " .. where .. "." end
    end
    if course.checkpoints[1] and player then
      text = text .. " First marshal: " .. guide.describe(player, course.checkpoints[1].at) .. "."
    end
  elseif phase == "countdown" then
    text = race.count > 0 and ("Ready... " .. race.count) or "GO!"
    if race.penalty > 0 then text = text .. " (false start: +" .. race.penalty .. " s)" end
  elseif phase == "racing" then
    local target = course.checkpoints[race.passed + 1]
    local parts = {(race.passed + 1 == #course.checkpoints and "FINISH" or ("CP " .. race.passed + 1 .. "/" .. #course.checkpoints))}
    if player then parts[#parts + 1] = guide.describe(player, target.at) end
    parts[#parts + 1] = guide.stopwatch(race.clock + race.penalty)
    if race.dan then parts[#parts + 1] = place(api) end
    if player and player.mode ~= 1 then parts[#parts + 1] = "get back in a car!" end
    text = table.concat(parts, " · ")
  else
    return
  end
  if flash and now < flash_until then text = flash .. " · " .. text end
  objective(api, text)
end

local function on_player(api, data)
  player = data
  if car and data.mode == 1 and data.vehicle == car then car_at = guide.point(data) end
  if phase == "ready" and data.mode == 1 then
    phase = "countdown"
    race = {count = 3, count_at = now + 1, clock = 0, penalty = 0, passed = 0, dan = course.dan_id, dan_cp = 0}
    course.dan_id = nil
    next_refresh = 0
  elseif phase == "countdown" then
    if data.mode ~= 1 then
      phase = "ready"
      if race.dan then course.dan_id = race.dan end
      race = nil
    elseif race.penalty == 0 and (data.speed or 0) > 0.2 then
      race.penalty = 2
      show_flash("False start! +2 seconds", 2)
    end
  elseif phase == "racing" and data.mode == 1 then
    local target = course.checkpoints[race.passed + 1]
    if target and guide.distance(data, target.at) < 1.3 then pass_checkpoint(api) end
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
      objective(api, "These streets are too short for a rally. Try a bigger connected road network and reenter Explore.", "failed")
      return
    else refused(api) end
  elseif action == "car" and code ~= "ok" and park_tries < 3 then
    -- No room right beside the player: park a little way down the road.
    park_tries = park_tries + 1
    track(api, "car_spot", api.world.find_landmark("road_destination", {kind = "car", skip = park_tries, min_distance = 2 + park_tries}))
    return
  elseif action == "car_spot" then
    if code ~= "ok" then refused(api) return end
    track(api, "car", api.actor.spawn("car", {key = "rally_car", position = guide.point(data), enterable = true}))
    return
  elseif action == "fran" or action == "car" then
    if code ~= "ok" then refused(api) return end
    if action == "fran" then
      fran = data.id
      api.marker.set("fran", {target = {id = fran}, label = "Flagger Fran · Neon Rally", icon = "person"})
    else
      car, car_at = data.id, data.position
      api.marker.set("car", {target = {id = car}, label = "Desert Cruiser", icon = "vehicle"})
    end
  elseif action == "checkpoint" then
    if not course then return end
    if code ~= "ok" then
      course.retry = course.retry + 1
      if course.retry <= 2 then build_step(api)
      elseif #course.checkpoints >= 2 then course_ready(api)
      else
        clear_course(api)
        set_idle(api, "There's not enough connected road here for a course. Drive somewhere with more streets and talk to Fran again.")
      end
      return
    end
    course.retry = 0
    course.pending = {landmark = guide.point(data), at = data, route = type(data.distance) == "number" and data.distance or course.leg}
    serial = serial + 1
    track(api, "marshal", api.actor.spawn("pedestrian", {key = "marshal" .. serial, variant = MARSHAL,
      position = guide.point(data), near_player = true}))
    return
  elseif action == "marshal" then
    if not course or not course.pending then return end
    local checkpoint = course.pending
    course.pending = nil
    if code == "ok" then
      checkpoint.marshal = data.id
      checkpoint.at = data.position
      api.actor.wave(data.id)
    end
    course.checkpoints[#course.checkpoints + 1] = checkpoint
    if #course.checkpoints >= course.want then course_ready(api) else build_step(api) end
    return
  elseif action == "dan_spot" then
    if not course or code ~= "ok" then return end
    serial = serial + 1
    track(api, "dan", api.actor.spawn("pickup", {key = "dan" .. serial, position = guide.point(data)}))
    return
  elseif action == "dan" then
    if code ~= "ok" then return end
    if race then
      race.dan = data.id
      if phase == "racing" then send_dan(api) end
    elseif course then course.dan_id = data.id
    else api.actor.remove(data.id) end
    return
  elseif action == "dan_drive" then
    if not race or not race.dan then return end
    if code == "ok" then
      race.dan_cp = race.dan_cp + 1
      if race.dan_cp >= #course.checkpoints then
        race.dan_done = true
        race.dan_time = race.clock
        if phase == "racing" then show_flash("Dusty Dan just crossed the finish line!", 3) end
      else
        send_dan(api)
      end
    elseif phase == "racing" and code ~= "cancelled" then
      race.dan_out = true
      show_flash("Dusty Dan took a wrong turn. He's out of the race!", 3)
    end
    return
  elseif action == "dan_look" then
    if race and code == "ok" and data.position then race.dan_at = data.position end
    return
  end
  offer(api)
end

return {
  on_start = function(api)
    load_stats(api)
    journal(api)
    objective(api, "The Neon Rally crew is setting up nearby...")
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
      end
      return
    end
    if player_request and event.request_id == player_request then
      player_request = nil
      if event.code == "ok" then on_player(api, event.data) end
      return
    end
    if dan_request and event.request_id == dan_request then
      dan_request = nil
      finished(api, "dan_look", event.code, event.data)
      return
    end
    local action = requests[event.request_id]
    if action then
      requests[event.request_id] = nil
      finished(api, action, event.code, event.data)
      return
    end
    if event.kind == "interaction" and event.key == "race" and phase == "idle" then
      offer_dialogue(api)
    elseif event.kind == "dialogue_choice" then
      local choice = event.data.choice
      if event.key == "offer" then
        if choice == "sprint" or choice == "grand" then plan_course(api, choice)
        elseif choice == "trophies" then trophy_dialogue(api)
        else set_idle(api) end
      elseif event.key == "trophies" then
        offer_dialogue(api)
      elseif event.key == "result" then
        clear_course(api)
        if choice == "again" then
          phase = "idle"
          offer_dialogue(api)
        else
          set_idle(api, "Neon Rally: drive back to Flagger Fran at the start line to race again.")
        end
      end
    elseif event.kind == "route_failed" and event.data.id == car then
      car, car_at = nil, nil
      spawn_missing(api)
    end
  end,
  on_tick = function(api, context)
    now = now + context.delta
    if phase == "countdown" and now >= race.count_at then
      race.count = race.count - 1
      race.count_at = now + 1
      next_refresh = 0
      if race.count <= 0 then
        phase = "racing"
        show_flash("GO!", 1.5)
        if race.dan then send_dan(api) end
      end
    elseif phase == "racing" then
      race.clock = race.clock + context.delta
      if race.dan and not race.dan_out and not race.dan_done and not dan_request and now >= (race.dan_look_at or 0) then
        race.dan_look_at = now + 0.5
        local look = api.actor.inspect(race.dan)
        if look.request_id then dan_request = look.request_id end
      end
    end
    if (phase == "ready" or phase == "countdown" or phase == "racing") and not player_request and now >= next_poll then
      next_poll = now + 0.2
      local result = api.world.player()
      if result.request_id then player_request = result.request_id end
    end
    refresh_objective(api)
  end
}
