--@player.lua
--@description Player domain module for state-based logging
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("script.shared-utils")
local player = {}

-- ============================================================================
-- DOMAIN UPDATE FUNCTION
-- ============================================================================
function player.update(event_data, event_name)
  local player_obj = event_data.player_index and game.players[event_data.player_index]
  
  -- Create base record
  local rec = shared_utils.create_base_record(event_name, event_data)
  
  -- Apply event-specific context extraction
  local extractor = player.get_extractor(event_name)
  local should_log = extractor(event_data, rec, player_obj)
  
  -- Check if event should be skipped
  if should_log == false then
    return
  end
  
  -- Add player context if missing
  shared_utils.add_player_context_if_missing(rec, player_obj)
  
  -- Clean up nil values and buffer the event
  local clean_rec = shared_utils.clean_record(rec)
  local line = game.table_to_json(clean_rec)
  
  -- Buffer to player domain category
  shared_utils.buffer_event("player", line)
end

-- ============================================================================
-- CONTEXT EXTRACTORS - PURE PLAYER EVENTS
-- ============================================================================
function player.on_player_cursor_stack_changed(e, rec, player_obj)
  rec.action = "cursor-change"
  if player_obj and player_obj.cursor_stack and player_obj.cursor_stack.valid_for_read then
    rec.item = player_obj.cursor_stack.name
    rec.count = player_obj.cursor_stack.count
  end
end



function player.on_player_changed_position(e, rec, player_obj)
  rec.action = "move"
  -- Position is already added in create_base_record if available in event
  -- Add player context for additional info
  local ctx = shared_utils.get_player_context(player_obj)
  if ctx.cursor_item then
    rec.cursor_item = ctx.cursor_item
    rec.cursor_count = ctx.cursor_count
  end
  if ctx.selected then
    rec.selected = ctx.selected
  end
end

function player.on_player_changed_surface(e, rec, player_obj)
  rec.action = "change-surface"
  rec.surface = e.surface_index
end



-- ============================================================================
-- CONTEXT EXTRACTORS - MAP + PLAYER PAIRED EVENTS
-- ============================================================================
function player.on_player_built_tile(e, rec, player_obj)
  rec.action = "build-tile"
  rec.tiles = #e.tiles
  rec.tile_name = e.tiles[1] and e.tiles[1].name
end

-- ============================================================================
-- CONTEXT EXTRACTORS - PLAYER + ENTITY PAIRED EVENTS
-- ============================================================================
function player.on_player_rotated_entity(e, rec, player_obj)
  rec.action = "rotate-entity"
  rec.previous_direction = e.previous_direction
end

function player.on_player_flushed_fluid(e, rec, player_obj)
  rec.action = "flush-fluid"
  rec.fluid = e.fluid
  rec.amount = e.amount
  rec.only_this_entity = e.only_this_entity
end

function player.on_player_driving_changed_state(e, rec, player_obj)
  rec.action = e.entity and "enter-vehicle" or "exit-vehicle"
  if e.entity then
    rec.vehicle = shared_utils.get_entity_info(e.entity)
  end
end

function player.on_player_used_spider_remote(e, rec, player_obj)
  rec.action = "use-spider-remote"
  rec.vehicle = e.vehicle and e.vehicle.name
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================
function player.get_extractor(event_name)
  return player[event_name] or function() end -- Default no-op
end

return player
