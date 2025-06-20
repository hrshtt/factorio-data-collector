--@production.lua
--@description Production category logging module
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("shared-utils")
local production = {}

-- ============================================================================
-- EVENT REGISTRATION
-- ============================================================================
function production.register_events()
  -- Define events that require player validation
  local events = {
    -- Player events
    "on_built_entity",
    "on_player_mined_entity",
    "on_player_mined_item",
    "on_player_mined_tile",
    "on_player_built_tile",
    "on_player_crafted_item",
    "on_pre_player_crafted_item",
    "on_player_cancelled_crafting",
    "on_player_dropped_item",
    "on_player_fast_transferred",
    "on_player_rotated_entity",
    "on_player_placed_equipment",
    "on_player_removed_equipment",
    "on_picked_up_item",
    -- Global events
    "on_research_started",
    "on_research_finished", 
    "on_rocket_launch_ordered",
    "on_rocket_launched"
  }
  
  -- Register player events
  for _, event_name in ipairs(events) do
    script.on_event(defines.events[event_name], function(e)
      if shared_utils.is_player_event(e) then
        production.handle_event(event_name, e)
      end
    end)
  end
  
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================
function production.handle_event(event_name, event_data)
  local player = event_data.player_index and game.players[event_data.player_index]
  
  -- Create base record
  local rec = shared_utils.create_base_record(event_name, event_data)
  
  -- Apply event-specific context extraction
  local extractor = production.get_extractor(event_name)
  local should_log = extractor(event_data, rec, player)
  
  -- Check if event should be skipped
  if should_log == false then
    return
  end
  
  -- Add player context if missing
  shared_utils.add_player_context_if_missing(rec, player)
  
  -- Clean up nil values and buffer the event
  local clean_rec = shared_utils.clean_record(rec)
  local line = game.table_to_json(clean_rec)
  
  -- Buffer to production category
  shared_utils.buffer_event("production", line)
end

-- ============================================================================
-- CONTEXT EXTRACTORS
-- ============================================================================

-- Helper function for simple entity extraction
function production.extract_entity_action(e, rec, action_name, entity_field)
  rec.action = action_name
  if e[entity_field or "entity"] then
    rec.entity = shared_utils.get_entity_info(e[entity_field or "entity"])
  end
end

-- Helper function for simple item extraction
function production.extract_item_action(e, rec, action_name, item_field)
  rec.action = action_name
  if e[item_field or "item_stack"] then
    local item_data = e[item_field or "item_stack"]
    rec.item = item_data.name
    rec.count = item_data.count
  end
end

-- Helper function for recipe extraction
function production.extract_recipe_action(e, rec, action_name)
  rec.action = action_name
  rec.recipe = e.recipe and e.recipe.name
end

function production.on_built_entity(e, rec, player)
  production.extract_entity_action(e, rec, "build", "created_entity")
end

function production.on_player_mined_entity(e, rec, player)
  rec.action = "mine"
  if e.buffer then
    -- Log what was gained from mining
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
end

function production.on_player_crafted_item(e, rec, player)
  production.extract_recipe_action(e, rec, "craft")
end

function production.on_pre_player_crafted_item(e, rec, player)
  rec.action = "queue_craft"
  rec.recipe = e.recipe and e.recipe.name
  rec.count = e.queued_count
  
  -- Log items consumed from inventory
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
end

function production.on_research_started(e, rec, player)
  rec.action = "research_start"
  rec.tech = e.research and e.research.name
end

function production.on_research_finished(e, rec, player)
  rec.action = "research_done"
  rec.tech = e.research and e.research.name
end

function production.on_player_fast_transferred(e, rec, player)
  rec.action = "transfer"
  rec.direction = e.from_player and "player_to_entity" or "entity_to_player"
  rec.is_split = e.is_split

  if e.entity then
    rec.entity = shared_utils.get_entity_info(e.entity)
  end
  
  if e.item then
    rec.item = shared_utils.get_item_info(e.item)
  end
  
  -- Try to get item info from player's cursor stack (most recent transfer)
  if player and player.cursor_stack and player.cursor_stack.valid_for_read then
    rec.cursor_item = player.cursor_stack.name
    rec.cursor_count = player.cursor_stack.count
  end
end

function production.on_player_dropped_item(e, rec, player)
  production.extract_entity_action(e, rec, "drop")
end

function production.on_player_rotated_entity(e, rec, player)
  production.extract_entity_action(e, rec, "rotate")
end

function production.on_player_mined_tile(e, rec, player)
  rec.action = "mine_tile"
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
end

function production.on_player_built_tile(e, rec, player)
  rec.action = "build_tile"
  
  -- Log the tile that was built
  if e.tile then
    rec.tile = e.tile.name
  end
  
  -- Log the item used to build the tiles
  if e.item then
    rec.item = e.item.name
  end
  
  -- Log the stack used (if available and not empty)
  if e.stack and e.stack.valid_for_read and e.stack.count > 0 then
    rec.stack_item = e.stack.name
    rec.stack_count = e.stack.count
  end
  
  -- Log the surface where tiles were built
  if e.surface_index then
    rec.surface = e.surface_index
  end
  
  -- Log tile positions (limit to first few to avoid huge logs)
  if e.tiles and #e.tiles > 0 then
    rec.tile_count = #e.tiles
    -- Store first few tile positions for context
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
end

-- Both pickup functions are identical, so we'll use the same implementation
function production.on_player_mined_item(e, rec, player)
  production.extract_item_action(e, rec, "pickup")
end

function production.on_picked_up_item(e, rec, player)
  production.extract_item_action(e, rec, "pickup")
end

function production.on_train_changed_state(e, rec, player)
  rec.action = "train_state_change"
  if e.train then
    rec.old_state = e.old_state
    rec.new_state = e.train.state
    if e.train.front_stock then
      rec.train_ent = shared_utils.get_entity_info(e.train.front_stock)
    end
  end
end

function production.on_rocket_launch_ordered(e, rec, player)
  rec.action = "rocket_ordered"
  if e.rocket then
    rec.rocket_ent = shared_utils.get_entity_info(e.rocket)
  end
end

function production.on_rocket_launched(e, rec, player)
  rec.action = "rocket_launched"
  if e.rocket then
    rec.rocket_ent = shared_utils.get_entity_info(e.rocket)
  end
end

function production.on_player_cancelled_crafting(e, rec, player)
  rec.action = "cancel_craft"
  if e.recipe then
    rec.recipe = e.recipe.name
  end
  if e.cancel_count then
    rec.cancel_count = e.cancel_count
  end
end

function production.on_player_placed_equipment(e, rec, player)
  production.extract_entity_action(e, rec, "place_equipment", "equipment")
end

function production.on_player_removed_equipment(e, rec, player)
  production.extract_entity_action(e, rec, "remove_equipment", "equipment")
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================
function production.get_extractor(event_name)
  return production[event_name] or function() end -- Default no-op
end

return production 