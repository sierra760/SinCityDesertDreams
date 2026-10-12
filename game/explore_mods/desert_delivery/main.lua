local courier, car, recipient, landmark, destination, accepted, complete
local requests, pending = {}, {}
local player_request, retry_scheduled
local retry_round = 0
local start_missing, finished
local function offer(api)
  if (accepted or courier) and car and recipient and destination then
    if accepted then
      api.objective.set("delivery","Drive to the recipient in purple farther along the road.","active")
    else
      api.interaction.register("parcel",{target={id=courier},label="talk to the courier"})
      api.objective.set("delivery","Talk to the courier about a delivery.","active")
    end
  end
end
local function refused(api, action, code)
  if action == "landmark" and code == "no_route" then
    api.objective.set("delivery","This city has no usable delivery route. Try a connected street and reenter Explore.","failed")
    return
  end
  if retry_round < 2 then
    if not retry_scheduled then
      retry_scheduled = true
      api.timer.after("startup_retry",3 * (retry_round+1))
    end
    api.objective.set("delivery","Delivery is waiting for a safe road location; it will try again shortly.","active")
  else
    api.objective.set("delivery","Delivery could not find safe road locations after two retries. Move to a clear connected street, then reenter Explore or Disable and Enable this pack and Resume. Your progress is kept.","failed")
  end
end
local function track(api, action, result)
  if result.ok and result.request_id then
    requests[result.request_id] = action
    pending[action] = true
  else
    finished(api,action,result.code,result.data)
  end
end
finished = function(api, action, code, data)
  pending[action] = nil
  if code ~= "ok" then refused(api,action,code); return end
  if action == "courier" then courier = data.id
  elseif action == "car" then car = data.id
  elseif action == "landmark" then
    landmark = data
    track(api,"recipient",api.actor.spawn("pedestrian",{key="recipient",position=landmark,near_player=true,variant="pedestrian_07"}))
  elseif action == "recipient" then
    recipient = data.id
    -- Admission may choose a vacant connected cell beside the landmark.
    -- Arrival uses the actual copied actor pose, never the requested anchor.
    destination = data.position
  end
  offer(api)
end
start_missing = function(api)
  if not accepted and not courier and not pending.courier then
    track(api,"courier",api.actor.spawn("pedestrian",{key="courier",variant="pedestrian_03",near_player=true}))
  end
  if not car and not pending.car then
    track(api,"car",api.actor.spawn("car",{key="delivery_car",near_player=true,enterable=true}))
  end
  if not landmark and not pending.landmark then
    track(api,"landmark",api.world.find_landmark("road_destination",{kind="car"}))
  elseif landmark and not recipient and not pending.recipient then
    track(api,"recipient",api.actor.spawn("pedestrian",{key="recipient",position=landmark,near_player=true,variant="pedestrian_07"}))
  end
end
return {
  on_start=function(api)
    accepted=api.state.get("accepted",false)
    if api.state.get("completed",false) then
      complete=true
      api.objective.set("delivery","Parcel delivered.","completed")
      return
    end
    start_missing(api)
  end,
  on_event=function(api,event)
    local action = requests[event.request_id]
    if action then
      requests[event.request_id] = nil
      finished(api,action,event.code,event.data)
    end
    if event.kind == "timer" and event.key == "startup_retry" and not complete then
      retry_scheduled = nil
      retry_round = retry_round+1
      start_missing(api)
    end
    if player_request and event.request_id==player_request then
      player_request=nil
      if event.code=="ok" and destination and event.data.mode==1 and event.data.vehicle==car then
        local dx=event.data.x-destination.x
        local dz=event.data.z-destination.z
        if dx*dx+dz*dz<0.64 then
          complete=true
          api.state.set("completed",true)
          api.objective.set("delivery","Parcel delivered. Thank you!","completed")
          api.actor.remove(recipient)
          recipient=nil
        end
      end
    end
    if event.kind=="interaction" and event.key=="parcel" and not accepted then
      api.dialogue.show("offer","Desert Courier","A parcel needs a lift. Borrow the nearby car and follow the connected road to the recipient in purple farther along the road. This favor costs and pays no city funds.",{{key="accept",label="Accept the delivery"},{key="later",label="Maybe later"}})
    end
    if event.kind=="dialogue_choice" and event.key=="offer" and event.data.choice=="accept" then
      accepted=true
      api.interaction.unregister("parcel")
      api.state.set("accepted",true)
      api.objective.set("delivery","Drive to the recipient in purple farther along the road.","active")
      if courier then api.actor.remove(courier); courier=nil end
    end
  end,
  on_tick=function(api)
    if accepted and car and recipient and destination and not complete and not player_request then
      local result = api.world.player()
      if result.request_id then player_request=result.request_id end
    end
  end
}
