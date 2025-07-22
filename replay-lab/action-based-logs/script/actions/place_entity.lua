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
    
    -- Use created_entity instead of entity (correct field for on_built_entity event)
    if e.created_entity then
      rec.entity = e.created_entity.name
      
      -- Format entity position with precision
      if e.created_entity.position then
        rec.entity_x = string.format("%.1f", e.created_entity.position.x)
        rec.entity_y = string.format("%.1f", e.created_entity.position.y)
      end
    end

    if player.position then
      rec.px = string.format("%.1f", player.position.x)
      rec.py = string.format("%.1f", player.position.y)
    end
    
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("place_entity", line)
  end)
end

return place_entity 