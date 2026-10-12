local rain = false
local elapsed = 0
return {
  on_start = function(api)
    api.environment.set("daylight", "dusk", {intensity = 0.65})
    api.environment.set("haze", "desert", {intensity = 0.5})
    api.environment.set("wind", "breeze", {intensity = 0.6})
    api.environment.set("precipitation", "dust", {intensity = 0.65})
    api.timer.after("weather", 30)
  end,
  on_tick = function(api, context)
    elapsed = elapsed + context.delta
    local blend = 0.35 + 0.3 * (0.5 + 0.5 * math.sin(elapsed / 30))
    api.environment.set("daylight", "dusk", {intensity = blend})
    api.environment.set("haze", "desert", {intensity = blend})
  end,
  on_event = function(api, event)
    if event.kind == "timer" and event.key == "weather" then
      rain = not rain
      api.environment.set("precipitation", rain and "rain" or "dust", {intensity = 0.65})
      api.timer.after("weather", 30)
    end
  end
}
