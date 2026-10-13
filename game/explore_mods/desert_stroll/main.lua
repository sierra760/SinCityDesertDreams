-- Three independent greetings with ordered far-to-near walking stops.
local walkers = {}
local requests = {}
local origin
local origin_failed = false
local variants = {"pedestrian_03", "pedestrian_05", "pedestrian_07"}
local start, finished
local function track(api, result, index, action)
  if result.ok and result.request_id then
    requests[result.request_id] = {index=index, action=action}
  else
    finished(api,index,action,result.code,result.data)
  end
end
local function settle(api, index)
  local person = walkers[index]
  if person.settled then return end
  person.settled = true
  if index < 3 then start(api,index+1) end
end
local function walk(api, index)
  local person = walkers[index]
  if person.id and person.destination and origin and not person.moving and not person.settled then
    -- Followers start only after the preceding walker settles. They cannot
    -- stop ahead of the leader on the shared far-to-near destination path.
    local point = person.destination
    local stop = {x=point.x, y=point.y, z=point.z,
      coordinate_space=point.coordinate_space, geometry_revision=point.geometry_revision}
    local dx, dz = point.x-origin.x, point.z-origin.z
    if math.abs(dx) >= math.abs(dz) then
      stop.x = stop.x - (index-1) * (dx >= 0 and 1 or -1)
    else
      stop.z = stop.z - (index-1) * (dz >= 0 and 1 or -1)
    end
    person.moving = true
    track(api,api.actor.navigate(person.id, stop),index,"walk")
  end
end
-- Followers set out from the leader's starting point, never from wherever the
-- player has since wandered, so their far-to-near stops stay in order.
local function anchor(index)
  if index > 1 and origin then return {x=origin.x, y=origin.y, z=origin.z} end
end
local function find_destination(api, index)
  local person = walkers[index]
  if not origin or not person.started or person.destination_requested then return end
  person.destination_requested = true
  -- Every follower uses the same origin as its spawn and far-to-near stop.
  track(api,api.world.find_landmark("road_destination",{from={x=origin.x,y=origin.y,z=origin.z}}),index,"destination")
end
start = function(api, index)
  local person = walkers[index]
  if person.started then return end
  person.started = true
  track(api,api.actor.spawn("pedestrian",{key="stroller"..index,variant=variants[index],near_player=true,position=anchor(index)}),index,"spawn")
  find_destination(api,index)
end
finished = function(api, index, action, code, data)
  local person = walkers[index]
  if code ~= "ok" then
    if action == "origin" then origin_failed = true end
    if action == "spawn" and not person.retried then
      person.retried = true
      api.timer.after("spawn"..index,9 * index)
    elseif action ~= "wave" then
      settle(api,index)
    end
    if action ~= "wave" then
      api.objective.set("stroll","A walker is waiting: no safe connected walking route is available. Clear the street through normal interactions, or try another street and reenter Explore; progress is kept.","active")
    end
    return
  end
  if action == "origin" then
    origin = data
    for next_index=1,3 do find_destination(api,next_index); walk(api,next_index) end
  elseif action == "spawn" then
    person.id = data.id
    api.interaction.register("greet"..index,{target={id=person.id},label="greet the walker"})
    -- A missing origin keeps all greetings, but starts no walking route.
    if origin_failed then settle(api,index) end
  elseif action == "destination" then
    person.destination = data
  elseif action == "walk" then
    track(api,api.actor.wait(person.id,2.0),index,"wait")
  elseif action == "wait" then
    track(api,api.actor.wave(person.id),index,"wave")
    api.state.set("strolls",api.state.get("strolls",0)+1)
    settle(api,index)
  end
  walk(api,index)
end
return {
  on_start = function(api)
    api.objective.set("stroll","Meet the neighborhood walkers along the road.","active")
    for index=1,3 do walkers[index] = {} end
    track(api,api.world.player(),1,"origin")
    start(api,1)
  end,
  on_event = function(api,event)
    local request = requests[event.request_id]
    if request then
      requests[event.request_id] = nil
      finished(api,request.index,request.action,event.code,event.data)
    end
    if event.kind == "timer" then
      for index=1,3 do
        if event.key == "spawn"..index and not walkers[index].id and not walkers[index].settled then
          track(api,api.actor.spawn("pedestrian",{key="stroller"..index,variant=variants[index],near_player=true,position=anchor(index)}),index,"spawn")
        end
      end
    end
    if event.kind == "interaction" then
      api.dialogue.show("greeting","Neighborhood walker","A good walk makes the desert city feel like home. See you along the road!",{{key="hello",label="Hello, neighbor"}})
    end
    if event.kind == "route_failed" then
      api.objective.set("stroll","The walking route changed. The walkers will wait safely here.","active")
    end
  end
}
