--@place_entity.lua
--@description Place entity action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local place_entity = {}
local shared_utils = require("script.shared-utils")

function place_entity.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_built_entity, function(e)
    if not shared_utils.is_player_event(e) then return end
    local player = game.players[e.player_index]
    local rec = shared_utils.create_base_record("on_built_entity", e)
    rec.action = "place_entity"
    rec.entity = e.entity and e.entity.name or nil
    rec.position = e.entity and e.entity.position or nil
    shared_utils.add_player_context_if_missing(rec, player)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("place_entity", line)
  end)
end

return place_entity 