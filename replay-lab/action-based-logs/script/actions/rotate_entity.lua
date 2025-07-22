--@rotate_entity.lua
--@description Rotate entity action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local rotate_entity = {}
local shared_utils = require("script.shared-utils")

function rotate_entity.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_player_rotated_entity, function(e)
    if not shared_utils.is_player_event(e) then return end
    local player = game.players[e.player_index]
    local rec = shared_utils.create_base_record("on_player_rotated_entity", e)
    rec.action = "rotate_entity"
    
    -- Remove x/y fields that create_base_record may have added incorrectly
    -- (on_player_rotated_entity doesn't have a top-level position field)
    rec.x = nil
    rec.y = nil
    
    -- Entity info and position
    if e.entity then
      rec.entity = e.entity.name
      if e.entity.position then
        rec.entity_x = string.format("%.1f", e.entity.position.x)
        rec.entity_y = string.format("%.1f", e.entity.position.y)
      end
    end
    
    -- Player context
    if player.position then
      rec.px = string.format("%.1f", player.position.x)
      rec.py = string.format("%.1f", player.position.y)
    end
    
    -- Direction info
    rec.previous_direction_name = defines.direction[e.previous_direction]
    rec.new_direction_name = e.entity and e.entity.valid and defines.direction[e.entity.direction] or nil
    rec.previous_direction = e.previous_direction
    rec.new_direction = e.entity and e.entity.valid and e.entity.direction or nil
    
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("rotate_entity", line)
  end)
end

return rotate_entity 