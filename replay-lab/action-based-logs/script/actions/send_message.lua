--@send_message.lua
--@description Send message action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local send_message = {}
local shared_utils = require("script.shared-utils")

function send_message.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_console_chat, function(e)
    if not shared_utils.is_player_event(e) then return end
    local player = game.players[e.player_index]
    local rec = shared_utils.create_base_record("send_message", e, player)
    rec.message = e.message
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("send_message", line)
  end)
end

return send_message 