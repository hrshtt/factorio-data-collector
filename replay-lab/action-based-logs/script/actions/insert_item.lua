--@insert_item.lua
--@description Insert item action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local insert_item = {}
local shared_utils = require("script.shared-utils")

function insert_item.register_events()
  script.on_event(defines.events.on_player_fast_transferred, function(e)
    if not shared_utils.is_player_event(e) then return end
    if not e.from_player then return end
    local player = game.players[e.player_index]
    local rec = shared_utils.create_base_record("on_player_fast_transferred", e)
    rec.action = "insert_item"
    rec.entity = e.entity and e.entity.name or nil
    rec.is_split = e.is_split
    shared_utils.add_player_context_if_missing(rec, player)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("insert_item", line)
  end)
end

return insert_item 