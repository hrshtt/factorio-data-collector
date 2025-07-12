--@pickup_entity.lua
--@description Pickup entity action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local pickup_entity = {}
local shared_utils = require("script.shared-utils")

function pickup_entity.register_events()
  script.on_event(defines.events.on_picked_up_item, function(e)
    if not shared_utils.is_player_event(e) then return end
    local player = game.players[e.player_index]
    local rec = shared_utils.create_base_record("on_picked_up_item", e)
    rec.action = "pickup_entity"
    shared_utils.add_player_context_if_missing(rec, player)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("pickup_entity", line)
  end)
end

return pickup_entity 