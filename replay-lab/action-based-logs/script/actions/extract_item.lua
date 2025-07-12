--@extract_item.lua
--@description Extract item action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local extract_item = {}
local shared_utils = require("script.shared-utils")

function extract_item.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_player_fast_transferred, function(e)
    if not shared_utils.is_player_event(e) then return end
    if e.from_player then return end -- Only handle extractions (from entity to player)
    local player = game.players[e.player_index]
    local rec = shared_utils.create_base_record("on_player_fast_transferred", e)
    rec.action = "extract_item"
    rec.entity = e.entity and e.entity.name or nil
    rec.is_split = e.is_split
    shared_utils.add_player_context_if_missing(rec, player)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("extract_item", line)
  end)
end

return extract_item 