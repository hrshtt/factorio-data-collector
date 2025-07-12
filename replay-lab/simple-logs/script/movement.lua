--@movement.lua
--@description Movement category logging module
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("script.shared-utils")
local movement = {}

-- ============================================================================
-- EVENT REGISTRATION
-- ============================================================================
function movement.register_events()
  -- Register movement-related events
  script.on_event(defines.events.on_player_changed_position, function(e)
    if shared_utils.is_player_event(e) then
      movement.handle_event("on_player_changed_position", e)
    end
  end)
  
  script.on_event(defines.events.on_player_driving_changed_state, function(e)
    if shared_utils.is_player_event(e) then
      movement.handle_event("on_player_driving_changed_state", e)
    end
  end)
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================
function movement.handle_event(event_name, event_data)
  local player = event_data.player_index and game.players[event_data.player_index]
  
  -- Create base record
  local rec = shared_utils.create_base_record(event_name, event_data)
  
  -- Apply event-specific context extraction
  local extractor = movement.get_extractor(event_name)
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
  
  -- Buffer to movement category
  shared_utils.buffer_event("movement", line)
end

-- ============================================================================
-- CONTEXT EXTRACTORS
-- ============================================================================
function movement.on_player_changed_position(e, rec, player)
  rec.action = "move"
  -- Position is already added in create_base_record if available in event
  -- Add player context for additional info
  local ctx = shared_utils.get_player_context(player)
  if ctx.cursor_item then
    rec.cursor_item = ctx.cursor_item
    rec.cursor_count = ctx.cursor_count
  end
  if ctx.selected then
    rec.selected = ctx.selected
  end
end

function movement.on_player_driving_changed_state(e, rec, player)
  rec.action = e.entity and "enter_vehicle" or "exit_vehicle"
  
  -- Add vehicle info if available
  if e.entity then
    rec.vehicle = shared_utils.get_entity_info(e.entity)
  end
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================
function movement.get_extractor(event_name)
  return movement[event_name] or function() end -- Default no-op
end

return movement 