--@send_message.lua
--@description Send message action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local send_message = {}
local shared_utils = require("script.shared-utils")

function send_message.register_events()
  script.on_event(defines.events.on_console_chat, function(e)
    local rec = shared_utils.create_base_record("on_console_chat", e)
    rec.action = "send_message"
    rec.message = e.message
    rec.player_index = e.player_index
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("send_message", line)
  end)
end

return send_message 