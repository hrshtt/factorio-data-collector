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
    rec.entity = e.entity and e.entity.name or nil
    rec.previous_direction = e.previous_direction
    rec.new_direction = e.entity and e.entity.valid and e.entity.direction or nil
    shared_utils.add_player_context_if_missing(rec, player)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("rotate_entity", line)
  end)
end

return rotate_entity 