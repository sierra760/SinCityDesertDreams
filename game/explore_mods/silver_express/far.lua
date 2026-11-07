-- Chained outward stop search. One find_landmark query reaches at most 40
-- tiles, so a far stop is found hop by hop: each hop starts where the last one
-- ended and must keep moving away from the origin. Small or broken road
-- networks fall back to shorter hops, then to however far the chain got.
local guide = require("guide")
local far = {}

-- spec: from (point), hops, reach (tiles per hop), away (optional point the
-- first hop must leave behind), kind (optional actor domain), landmark
-- (default road_destination), vary (how many early matches to skip at most),
-- floor (the nearest a fallback stop may be, default 3 tiles).
function far.new(spec)
  return {spec = spec, at = guide.point(spec.from), hop = 0, attempt = 0, total = 0, stops = {}}
end

function far.request(api, search)
  local spec = search.spec
  search.attempt = search.attempt + 1
  local options = {from = search.at}
  if spec.kind then options.kind = spec.kind end
  local away = search.hop == 0 and spec.away or (search.hop > 0 and spec.from or nil)
  local reach = math.max(3, math.min(40, spec.reach))
  if search.attempt == 1 then
    options.min_distance = reach
    options.skip = math.floor(api.utility.random() * ((spec.vary or 3) + 1))
    if away then options.away_from = guide.point(away) end
  elseif search.attempt == 2 then
    options.min_distance = reach
    if away then options.away_from = guide.point(away) end
  elseif search.attempt == 3 then
    options.min_distance = math.max(3, math.floor(reach * 0.6))
    if away then options.away_from = guide.point(away) end
  else
    -- Last resort for small towns: a nearer stop in any direction.
    options.min_distance = math.max(spec.floor or 3, math.floor(reach * 0.3))
  end
  return api.world.find_landmark(spec.landmark or "road_destination", options)
end

-- Returns "again" (request the next query), "done" (search.at is the stop)
-- or "fail" (nothing reachable at all).
local function settle(search)
  -- A fallback hop on a small network can double back toward the origin;
  -- end at whichever stop got farthest from it instead.
  local origin = search.spec.from
  for _, stop in ipairs(search.stops) do
    if guide.distance(origin, stop) > guide.distance(origin, search.at) then search.at = guide.point(stop) end
  end
  return "done"
end

function far.feed(search, code, data)
  if code == "ok" and type(data) == "table" then
    search.hop = search.hop + 1
    search.total = search.total + (type(data.distance) == "number" and data.distance or 0)
    search.at = guide.point(data)
    search.stops[#search.stops + 1] = guide.point(data)
    search.attempt = 0
    if search.hop >= search.spec.hops then return settle(search) end
    return "again"
  end
  if search.attempt < 4 then return "again" end
  if search.hop > 0 then return settle(search) end
  return "fail"
end

return far
