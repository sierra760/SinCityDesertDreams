-- Distance, direction and clock wording shared by this pack's objectives.
-- Directions are relative to the camera heading from api.world.player(), so
-- "ahead-left" means ahead-left on screen. One tile is sixteen metres.
local guide = {}

local SECTORS = {"ahead", "ahead-right", "right", "behind-right", "behind", "behind-left", "left", "ahead-left"}

function guide.distance(a, b)
  local dx, dz = b.x - a.x, b.z - a.z
  return math.sqrt(dx * dx + dz * dz)
end

function guide.metres(tiles)
  local m = math.floor(tiles * 1.6 + 0.5) * 10
  if m >= 1000 then
    local tenths = math.floor(m / 100 + 0.5)
    return tostring(tenths // 10) .. "." .. tostring(tenths % 10) .. " km"
  end
  return tostring(m) .. " m"
end

function guide.direction(player, target)
  local dx, dz = target.x - player.x, target.z - player.z
  local length = math.sqrt(dx * dx + dz * dz)
  local heading = player.heading
  if length < 0.75 then return "right here" end
  if type(heading) ~= "table" then return "" end
  local ahead = (dx * heading.x + dz * heading.z) / length
  local right = (dz * heading.x - dx * heading.z) / length
  local sector = math.floor((math.atan(right, ahead) + math.pi / 8) / (math.pi / 4)) % 8
  return SECTORS[sector + 1]
end

-- "240 m ahead-left", or "right here" when close.
function guide.describe(player, target)
  local where = guide.direction(player, target)
  if where == "right here" then return where end
  local text = guide.metres(guide.distance(player, target))
  if where ~= "" then text = text .. " " .. where end
  return text
end

-- Whole seconds as m:ss.
function guide.clock(seconds)
  local s = math.max(0, math.floor(seconds + 0.999))
  local r = s % 60
  return tostring(s // 60) .. ":" .. (r < 10 and "0" or "") .. tostring(r)
end

-- Tenths of a second as m:ss.t for race timing.
function guide.stopwatch(seconds)
  local tenths = math.max(0, math.floor(seconds * 10 + 0.5))
  local s = tenths // 10
  local r = s % 60
  return tostring(s // 60) .. ":" .. (r < 10 and "0" or "") .. tostring(r) .. "." .. tostring(tenths % 10)
end

function guide.point(value)
  return {x = value.x, y = value.y, z = value.z}
end

return guide
