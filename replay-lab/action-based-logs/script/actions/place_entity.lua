--@place_entity.lua
--@description Place entity action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local place_entity = {}
local shared_utils = require("script.shared-utils")

function place_entity.register_events()
  script.on_event(defines.events.on_built_entity, function(e)
    if not shared_utils.is_player_event(e) then return end
    local player = game.players[e.player_index]
    local rec = shared_utils.create_base_record("on_built_entity", e)
    rec.action = "place_entity"
    rec.created_entity = e.created_entity and e.created_entity.name or nil
    rec.item = e.item and e.item.name or nil
    shared_utils.add_player_context_if_missing(rec, player)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("place_entity", line)
  end)
end

return place_entity 