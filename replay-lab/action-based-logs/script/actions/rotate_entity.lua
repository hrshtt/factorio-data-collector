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
    local rec = shared_utils.create_base_record("rotate_entity", e, player)
    rec.entity = {}

    -- Entity info and position
    if e.entity then
      rec.entity.name = e.entity.name
      if e.entity.position then
        rec.entity.x = string.format("%.1f", e.entity.position.x)
        rec.entity.y = string.format("%.1f", e.entity.position.y)
      end
      if e.entity.direction then

        rec.entity.direction = {}
        rec.entity.direction.previous = {}
        rec.entity.direction.new = {}

        rec.entity.direction.previous.name = defines.direction[e.previous_direction]
        rec.entity.direction.previous.value = e.previous_direction
        rec.entity.direction.new.name = e.entity and e.entity.valid and defines.direction[e.entity.direction] or nil
        rec.entity.direction.new.value = e.entity and e.entity.valid and e.entity.direction or nil
      end
    end
    
    -- Direction info
    
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("rotate_entity", line)
  end)
end

return rotate_entity 