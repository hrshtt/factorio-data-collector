--@harvest_resource.lua
--@description Harvest resource action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local harvest_resource = {}
local shared_utils = require("script.shared-utils")

function harvest_resource.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_player_mined_entity, function(e)
    if not shared_utils.is_player_event(e) then return end
    local player = game.players[e.player_index]
    local rec = shared_utils.create_base_record("on_player_mined_entity", e)
    rec.action = "harvest_resource"
    rec.entity = e.entity and e.entity.name or nil
    shared_utils.add_player_context_if_missing(rec, player)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("harvest_resource", line)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_mined_item, function(e)
    if not shared_utils.is_player_event(e) then return end
    local player = game.players[e.player_index]
    local rec = shared_utils.create_base_record("on_player_mined_item", e)
    rec.action = "harvest_resource"
    rec.item_stack = e.item_stack
    shared_utils.add_player_context_if_missing(rec, player)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("harvest_resource", line)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_mined_tile, function(e)
    if not shared_utils.is_player_event(e) then return end
    local player = game.players[e.player_index]
    local rec = shared_utils.create_base_record("on_player_mined_tile", e)
    rec.action = "harvest_resource"
    rec.positions = e.positions
    rec.tiles = e.tiles
    shared_utils.add_player_context_if_missing(rec, player)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("harvest_resource", line)
  end)
end

return harvest_resource 