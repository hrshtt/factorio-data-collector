--@move_to.lua
--@description Move to action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local move_to = {}
local shared_utils = require("script.shared-utils")

function move_to.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_player_changed_position, function(e)
    if not shared_utils.is_player_event(e) then return end
    local player = game.players[e.player_index]
    local rec = shared_utils.create_base_record("on_player_changed_position", e)
    rec.action = "move_to"
    rec.old_position = e.old_position
    rec.new_position = player.position
    shared_utils.add_player_context_if_missing(rec, player)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("move_to", line)
  end)
end

return move_to 