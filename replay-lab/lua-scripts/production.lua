--@production.lua
--@description Production category logging module with state-diff layer
--@author Harshit Sharma
--@version 2.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("shared-utils")
local production = {}

-- ============================================================================
-- INVENTORY SNAPSHOT SYSTEM
-- ============================================================================

-- Global inventory snapshots: global.inventory_snapshots[unit_number] = {inv_id = {name=count}}
function production.initialize_snapshots()
  if not global.inventory_snapshots then
    global.inventory_snapshots = {}
  end
end

-- Get inventory IDs for an entity (handles different entity types)
function production.get_entity_inventory_ids(entity)
  if not entity or not entity.valid then
    return {}
  end
  
  local inventory_ids = {}
  
  -- Use entity type-based detection (inventory_size doesn't exist on prototype)
  if entity.type == "container" or entity.type == "logistic-container" then
    table.insert(inventory_ids, defines.inventory.chest)
  elseif entity.type == "assembling-machine" then
    table.insert(inventory_ids, defines.inventory.assembling_machine_input)
    table.insert(inventory_ids, defines.inventory.assembling_machine_output)
  elseif entity.type == "furnace" then
    table.insert(inventory_ids, defines.inventory.furnace_source)
    table.insert(inventory_ids, defines.inventory.furnace_result)
  elseif entity.type == "car" or entity.type == "cargo-wagon" then
    table.insert(inventory_ids, defines.inventory.car_trunk)
  elseif entity.type == "rocket-silo" then
    table.insert(inventory_ids, defines.inventory.rocket_silo_rocket)
    table.insert(inventory_ids, defines.inventory.rocket_silo_result)
  else
    -- Default fallback for unknown entity types
    table.insert(inventory_ids, defines.inventory.chest)
  end
  
  return inventory_ids
end

-- Take snapshot of specified inventories for a controller (player/entity)
function production.snapshot_inventory(controller, inventory_ids)
  if not controller or not controller.valid then
    return {}
  end
  
  local snap = {}
  for _, inv_id in pairs(inventory_ids) do
    local inv = controller.get_inventory(inv_id)
    if inv and inv.valid then
      snap[inv_id] = inv.get_contents()
    end
  end
  return snap
end

-- Clean up old snapshots to prevent memory bloat
function production.cleanup_snapshots()
  if not global.inventory_snapshots then
    return
  end
  
  local current_tick = game.tick
  local max_age = 3600 -- Keep snapshots for 1 minute (60 seconds * 60 UPS)
  
  for unit_number, snapshot in pairs(global.inventory_snapshots) do
    if snapshot.last_used and (current_tick - snapshot.last_used) > max_age then
      global.inventory_snapshots[unit_number] = nil
    end
  end
end

-- Update snapshot with timestamp
function production.update_snapshot(unit_number, snapshot)
  if not global.inventory_snapshots then
    global.inventory_snapshots = {}
  end
  
  snapshot.last_used = game.tick
  global.inventory_snapshots[unit_number] = snapshot
end

-- Diff two inventory snapshots to get delta
function production.diff_inventory(old_snap, new_snap)
  local delta = {}
  
  -- Check for removed/decreased items
  for inv_id, old_contents in pairs(old_snap) do
    -- Skip metadata fields like last_used
    if type(inv_id) == "number" and type(old_contents) == "table" then
      local new_contents = new_snap[inv_id] or {}
      for item_name, old_count in pairs(old_contents) do
        local new_count = new_contents[item_name] or 0
        local diff = new_count - old_count
        if diff ~= 0 then
          delta[item_name] = (delta[item_name] or 0) + diff
        end
      end
    end
  end
  
  -- Check for added items (completely new stacks)
  for inv_id, new_contents in pairs(new_snap) do
    -- Skip metadata fields like last_used
    if type(inv_id) == "number" and type(new_contents) == "table" then
      local old_contents = old_snap[inv_id] or {}
      for item_name, new_count in pairs(new_contents) do
        if not old_contents[item_name] then
          delta[item_name] = (delta[item_name] or 0) + new_count
        end
      end
    end
  end
  
  return delta
end

-- Convert delta to comma-separated string for JSONL
function production.delta_to_string(delta)
  if not delta or not next(delta) then
    return nil
  end
  
  local parts = {}
  for item_name, count in pairs(delta) do
    table.insert(parts, item_name .. ":" .. count)
  end
  return table.concat(parts, ",")
end

-- ============================================================================
-- STABLE RECORD SCHEMA
-- ============================================================================

-- Create a record with stable schema (all fields present, nil for missing data)
function production.create_stable_record(event_name, event_data)
  local rec = {
    -- Meta fields (always present)
    t = event_data.tick,
    p = event_data.player_index,
    ev = event_name,
    act = nil,  -- action type
    
    -- Position fields
    x = nil,
    y = nil,
    
    -- Target fields
    ent = nil,      -- entity name
    item = nil,     -- item name
    cnt = nil,      -- item count
    recipe = nil,   -- recipe name
    tech = nil,     -- technology name
    
    -- Inventory delta fields
    delta_player = nil,
    delta_entity = nil,
    
    -- Additional context fields
    tiles = nil,
    tile = nil,
    stack_item = nil,
    stack_count = nil,
    surface = nil,
    tile_count = nil,
    tile_positions = nil,
    gained = nil,
    consumed = nil,
    direction = nil,
    is_split = nil,
    available_in_entity = nil,
    item_info_available = nil,
    cancel_count = nil,
    old_state = nil,
    new_state = nil,
    rocket_ent = nil,
    train_ent = nil
  }
  
  -- Add position if available in event
  if event_data.position then
    rec.x = string.format("%.1f", event_data.position.x)
    rec.y = string.format("%.1f", event_data.position.y)
  end
  
  return rec
end

-- ============================================================================
-- EVENT REGISTRATION
-- ============================================================================

function production.register_events()
  production.initialize_snapshots()
  
  -- Define event handlers after all functions are defined
  local EVENT_HANDLERS = {
    -- Player events
    on_built_entity = production.handle_built_entity,
    on_player_mined_entity = production.handle_mined_entity,
    on_player_mined_item = production.handle_mined_item,
    on_player_mined_tile = production.handle_mined_tile,
    on_player_built_tile = production.handle_built_tile,
    on_player_crafted_item = production.handle_crafted_item,
    on_pre_player_crafted_item = production.handle_pre_crafted_item,
    on_player_cancelled_crafting = production.handle_cancelled_crafting,
    on_player_dropped_item = production.handle_dropped_item,
    on_player_fast_transferred = production.handle_fast_transferred,
    on_player_rotated_entity = production.handle_rotated_entity,
    on_player_placed_equipment = production.handle_placed_equipment,
    on_player_removed_equipment = production.handle_removed_equipment,
    on_picked_up_item = production.handle_picked_up_item,
    
    -- Global events
    on_research_started = production.handle_research_started,
    on_research_finished = production.handle_research_finished,
    on_rocket_launch_ordered = production.handle_rocket_ordered,
    on_rocket_launched = production.handle_rocket_launched,
    
    -- Inventory change events (for snapshot management)
    on_player_main_inventory_changed = production.handle_inventory_changed
  }
  
  -- Register all events from the registry
  for event_name, handler in pairs(EVENT_HANDLERS) do
    script.on_event(defines.events[event_name], function(e)
      if shared_utils.is_player_event(e) then
        handler(e)
      end
    end)
  end
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- Generic handler for inventory-based events
function production.handle_inventory_event(event_name, event_data, action_name, extract_context)
  local player = event_data.player_index and game.players[event_data.player_index]
  
  -- Create stable record
  local rec = production.create_stable_record(event_name, event_data)
  rec.act = action_name
  
  -- Extract additional context if provided
  if extract_context then
    extract_context(event_data, rec, player)
  end
  
  -- Add player context if missing
  shared_utils.add_player_context_if_missing(rec, player)
  
  -- Clean and buffer
  local clean_rec = shared_utils.clean_record(rec)
  shared_utils.buffer_event("production", game.table_to_json(clean_rec))
end

-- Simple entity action handler
function production.handle_entity_action(event_name, event_data, action_name, entity_field)
  production.handle_inventory_event(event_name, event_data, action_name, function(e, rec, player)
    if e[entity_field or "entity"] then
      rec.ent = shared_utils.get_entity_info(e[entity_field or "entity"])
    end
  end)
end

-- Simple item action handler
function production.handle_item_action(event_name, event_data, action_name, item_field)
  production.handle_inventory_event(event_name, event_data, action_name, function(e, rec, player)
    local item_data = e[item_field or "item_stack"]
    if item_data then
      rec.item = item_data.name
      rec.cnt = item_data.count
    end
  end)
end

-- ============================================================================
-- SPECIFIC EVENT HANDLERS
-- ============================================================================

function production.handle_built_entity(e)
  production.handle_entity_action("on_built_entity", e, "build", "created_entity")
end

function production.handle_mined_entity(e)
  production.handle_inventory_event("on_player_mined_entity", e, "mine", function(e, rec, player)
    if e.buffer then
      local items = {}
      for i = 1, #e.buffer do
        local stack = e.buffer[i]
        if stack and stack.valid_for_read then
          table.insert(items, stack.name .. ":" .. stack.count)
        end
      end
      if #items > 0 then
        rec.gained = table.concat(items, ",")
      end
    end
  end)
end

function production.handle_crafted_item(e)
  production.handle_inventory_event("on_player_crafted_item", e, "craft", function(e, rec, player)
    rec.recipe = e.recipe and e.recipe.name
  end)
end

function production.handle_pre_crafted_item(e)
  production.handle_inventory_event("on_pre_player_crafted_item", e, "queue_craft", function(e, rec, player)
    rec.recipe = e.recipe and e.recipe.name
    rec.cnt = e.queued_count
    
    if e.items then
      local consumed_items = {}
      for name, count in pairs(e.items.get_contents()) do
        if count > 0 then
          table.insert(consumed_items, name .. ":" .. count)
        end
      end
      if #consumed_items > 0 then
        rec.consumed = table.concat(consumed_items, ",")
      end
    end
  end)
end

function production.handle_research_started(e)
  production.handle_inventory_event("on_research_started", e, "research_start", function(e, rec, player)
    rec.tech = e.research and e.research.name
  end)
end

function production.handle_research_finished(e)
  production.handle_inventory_event("on_research_finished", e, "research_done", function(e, rec, player)
    rec.tech = e.research and e.research.name
  end)
end

-- State-diff based fast transfer handler
function production.handle_fast_transferred(e)
  local player = game.players[e.player_index]
  local entity = e.entity
  
  -- Get pre-transfer snapshots
  local pre_player_snap = global.inventory_snapshots[player.index] or {}
  local pre_entity_snap = entity and global.inventory_snapshots[entity.unit_number] or {}
  
  -- Take post-transfer snapshots with proper inventory detection
  local post_player_snap = production.snapshot_inventory(player, {defines.inventory.character_main})
  local post_entity_snap = {}
  
  if entity and entity.valid then
    local entity_inv_ids = production.get_entity_inventory_ids(entity)
    post_entity_snap = production.snapshot_inventory(entity, entity_inv_ids)
  end
  
  -- Create record
  local rec = production.create_stable_record("on_player_fast_transferred", e)
  rec.act = "transfer"
  rec.direction = e.from_player and "player_to_entity" or "entity_to_player"
  rec.is_split = e.is_split
  
  if entity then
    rec.ent = shared_utils.get_entity_info(entity)
  end
  
  -- Calculate and store deltas
  local player_delta = production.diff_inventory(pre_player_snap, post_player_snap)
  local entity_delta = production.diff_inventory(pre_entity_snap, post_entity_snap)
  
  rec.delta_player = production.delta_to_string(player_delta)
  rec.delta_entity = production.delta_to_string(entity_delta)
  
  -- Add player context
  shared_utils.add_player_context_if_missing(rec, player)
  
  -- Clean and buffer
  local clean_rec = shared_utils.clean_record(rec)
  shared_utils.buffer_event("production", game.table_to_json(clean_rec))
  
  -- Update snapshots with timestamps
  production.update_snapshot(player.index, post_player_snap)
  if entity and entity.unit_number then
    production.update_snapshot(entity.unit_number, post_entity_snap)
  end
end

-- Inventory change handler for snapshot management
function production.handle_inventory_changed(e)
  local player = game.players[e.player_index]
  if player and player.valid then
    -- Update player snapshot when inventory changes
    local new_snap = production.snapshot_inventory(player, {defines.inventory.character_main})
    production.update_snapshot(player.index, new_snap)
  end
end

function production.handle_dropped_item(e)
  production.handle_entity_action("on_player_dropped_item", e, "drop")
end

function production.handle_rotated_entity(e)
  production.handle_entity_action("on_player_rotated_entity", e, "rotate")
end

function production.handle_mined_tile(e)
  production.handle_inventory_event("on_player_mined_tile", e, "mine_tile", function(e, rec, player)
    if e.tiles then
      local tiles = {}
      for _, tile in pairs(e.tiles) do
        if tile and tile.name then
          table.insert(tiles, tile.name)
        end
      end
      if #tiles > 0 then
        rec.tiles = table.concat(tiles, ",")
      end
    end
  end)
end

function production.handle_built_tile(e)
  production.handle_inventory_event("on_player_built_tile", e, "build_tile", function(e, rec, player)
    if e.tile then
      rec.tile = e.tile.name
    end
    
    if e.item then
      rec.item = e.item.name
    end
    
    if e.stack and e.stack.valid_for_read and e.stack.count > 0 then
      rec.stack_item = e.stack.name
      rec.stack_count = e.stack.count
    end
    
    if e.surface_index then
      rec.surface = e.surface_index
    end
    
    if e.tiles and #e.tiles > 0 then
      rec.tile_count = #e.tiles
      local positions = {}
      for i = 1, math.min(3, #e.tiles) do
        local tile_data = e.tiles[i]
        if tile_data and tile_data.position then
          table.insert(positions, string.format("%.1f,%.1f", tile_data.position.x, tile_data.position.y))
        end
      end
      if #positions > 0 then
        rec.tile_positions = table.concat(positions, ";")
      end
    end
  end)
end

function production.handle_mined_item(e)
  production.handle_item_action("on_player_mined_item", e, "pickup")
end

function production.handle_picked_up_item(e)
  production.handle_item_action("on_picked_up_item", e, "pickup")
end

function production.handle_rocket_ordered(e)
  production.handle_inventory_event("on_rocket_launch_ordered", e, "rocket_ordered", function(e, rec, player)
    if e.rocket then
      rec.rocket_ent = shared_utils.get_entity_info(e.rocket)
    end
  end)
end

function production.handle_rocket_launched(e)
  production.handle_inventory_event("on_rocket_launched", e, "rocket_launched", function(e, rec, player)
    if e.rocket then
      rec.rocket_ent = shared_utils.get_entity_info(e.rocket)
    end
  end)
end

function production.handle_cancelled_crafting(e)
  production.handle_inventory_event("on_player_cancelled_crafting", e, "cancel_craft", function(e, rec, player)
    if e.recipe then
      rec.recipe = e.recipe.name
    end
    if e.cancel_count then
      rec.cancel_count = e.cancel_count
    end
  end)
end

function production.handle_placed_equipment(e)
  production.handle_entity_action("on_player_placed_equipment", e, "place_equipment", "equipment")
end

function production.handle_removed_equipment(e)
  production.handle_entity_action("on_player_removed_equipment", e, "remove_equipment", "equipment")
end

return production 