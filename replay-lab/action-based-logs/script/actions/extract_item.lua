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
    
    -- Add item information
    if e.item_stack and e.item_stack.valid_for_read then
      rec.item = e.item_stack.name
      rec.count = e.item_stack.count
      
      -- Get item prototype for additional information
      local item_prototype = game.item_prototypes[e.item_stack.name]
      if item_prototype then
        rec.item_type = item_prototype.type
        rec.item_subgroup = item_prototype.subgroup and item_prototype.subgroup.name or nil
        rec.item_group = item_prototype.group and item_prototype.group.name or nil
      end
    end
    
    shared_utils.add_player_context_if_missing(rec, player)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("extract_item", line)
  end)
end

return extract_item 