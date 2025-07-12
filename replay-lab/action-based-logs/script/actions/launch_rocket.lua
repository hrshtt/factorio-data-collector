--@launch_rocket.lua
--@description Launch rocket action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local launch_rocket = {}
local shared_utils = require("script.shared-utils")

function launch_rocket.register_events()
  script.on_event(defines.events.on_rocket_launched, function(e)
    local rec = shared_utils.create_base_record("on_rocket_launched", e)
    rec.action = "launch_rocket"
    rec.rocket = e.rocket and e.rocket.name or nil
    rec.rocket_silo = e.rocket_silo and e.rocket_silo.name or nil
    rec.player_index = e.player_index
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("launch_rocket", line)
  end)
end

return launch_rocket 