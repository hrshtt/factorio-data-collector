--@extract_item.lua
--@description Extract item action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local extract_item = {}
local shared_utils = require("script.shared-utils")
local logistics = require("script.logistics")

-- Initialize logistics if not already done
local function ensure_logistics_initialized()
  if not global.player_contexts then
    global.player_contexts = {}
  end
  if not global.entity_snapshots then
    global.entity_snapshots = {}
  end
end

function extract_item.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_player_fast_transferred, function(e)
    if not shared_utils.is_player_event(e) then return end
    if e.from_player then return end -- Only handle extractions (from entity to player)
    
    -- Ensure logistics is initialized
    ensure_logistics_initialized()
    
    local player = game.players[e.player_index]
    local entity = e.entity
    if not (player and player.valid and entity and entity.valid) then
      return
    end

    local inventory_index = logistics.find_primary_inventory_index(entity)
    if not inventory_index then
      return -- Nothing transferable
    end

    -- Get current state (after transfer)
    local curr_player = logistics.get_inventory_contents(player, defines.inventory.character_main)
    local curr_entity = logistics.get_inventory_contents(entity, inventory_index)
    
    -- Get the stored snapshots
    local ctx = logistics.get_player_context(e.player_index)
    local prev_player = ctx.last_player_snapshot
    
    -- Initialize player snapshot if it doesn't exist
    if not prev_player or not next(prev_player) then
      prev_player = {}
      ctx.last_player_snapshot = prev_player
    end
    
    local prev_entity = logistics.get_entity_snapshot(entity, inventory_index)

    -- Calculate diffs
    local player_deltas = logistics.diff_tables(prev_player, curr_player)
    local entity_deltas = logistics.diff_tables(prev_entity, curr_entity)

    -- Use entity deltas if they exist, otherwise fall back to player deltas
    local transfers_to_log = {}
    
    if next(entity_deltas) then
      -- Entity inventory changed - use these deltas
      transfers_to_log = entity_deltas
    elseif next(player_deltas) then
      -- No entity change but player changed - use player deltas (flipped)
      for item, delta in pairs(player_deltas) do
        transfers_to_log[item] = -delta -- Flip because we want entity perspective
      end
    end

    -- Log each extracted item (only when entity loses items)
    for item, delta in pairs(transfers_to_log) do
      if delta < 0 then -- Entity lost items, so player gained them (extraction)
        local rec = shared_utils.create_base_record("on_player_fast_transferred", e)
        rec.action = "extract_item"
        rec.entity = entity.name
        rec.entity_position = entity.position.x .. "," .. entity.position.y
        rec.is_split = e.is_split
        rec.item = item
        rec.quantity = math.abs(delta)
        shared_utils.add_player_context_if_missing(rec, player)
        local clean_rec = shared_utils.clean_record(rec)
        local line = game.table_to_json(clean_rec)
        shared_utils.buffer_event("extract_item", line)
      end
    end

    -- Update snapshots
    logistics.update_player_snapshot(e.player_index)
    logistics.update_entity_snapshot(entity, inventory_index)
  end)
end

return extract_item 