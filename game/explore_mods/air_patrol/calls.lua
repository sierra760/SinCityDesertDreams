-- Radio call flavour for Desert Air Patrol, one module per kind of call.
local calls = {}
calls.medevac = require("calls_medevac")
calls.hikers = require("calls_hikers")
calls.suspects = require("calls_suspects")
calls.officers = require("calls_officers")
calls.traffic_lines = require("calls_traffic")
calls.charters = require("calls_charters")
return calls
