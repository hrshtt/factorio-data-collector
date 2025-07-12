--@gui.lua
--@description GUI category logging module
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("script.shared-utils")
local gui = {}

-- ============================================================================
-- EVENT REGISTRATION
-- ============================================================================
function gui.register_events()
  -- Register GUI-related events
  script.on_event(defines.events.on_gui_click, function(e)
    if shared_utils.is_player_event(e) then
      gui.handle_event("on_gui_click", e)
    end
  end)
  
  script.on_event(defines.events.on_gui_text_changed, function(e)
    if shared_utils.is_player_event(e) then
      gui.handle_event("on_gui_text_changed", e)
    end
  end)
  
  script.on_event(defines.events.on_gui_checked_state_changed, function(e)
    if shared_utils.is_player_event(e) then
      gui.handle_event("on_gui_checked_state_changed", e)
    end
  end)
  
  -- script.on_event(defines.events.on_player_cursor_stack_changed, function(e)
  --   if shared_utils.is_player_event(e) then
  --     gui.handle_event("on_player_cursor_stack_changed", e)
  --   end
  -- end)
  
  script.on_event(defines.events.on_player_pipette, function(e)
    if shared_utils.is_player_event(e) then
      gui.handle_event("on_player_pipette", e)
    end
  end)
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================
function gui.handle_event(event_name, event_data)
  local player = event_data.player_index and game.players[event_data.player_index]
  
  -- Create base record
  local rec = shared_utils.create_base_record(event_name, event_data)
  
  -- Apply event-specific context extraction
  local extractor = gui.get_extractor(event_name)
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
  
  -- Buffer to gui category
  shared_utils.buffer_event("gui", line)
end

-- ============================================================================
-- CONTEXT EXTRACTORS
-- ============================================================================
-- function gui.on_player_cursor_stack_changed(e, rec, player)
--   local ctx = shared_utils.get_player_context(player)
  
--   -- Only log if there's actual cursor data
--   if not ctx.cursor_item then
--     return false -- Skip logging this event
--   end
  
--   rec.gui_type = "cursor"
--   rec.cursor_item = ctx.cursor_item
--   rec.cursor_count = ctx.cursor_count
-- end

function gui.on_player_pipette(e, rec, player)
  rec.gui_type = "pipette"
  rec.pipette_item = e.item and e.item.name
end

function gui.on_gui_click(e, rec, player)
  rec.gui_type = "click"
  rec.gui_element = e.element and e.element.name
  rec.button = e.button -- left/right/middle click
end

function gui.on_gui_text_changed(e, rec, player)
  rec.gui_type = "text"
  rec.gui_element = e.element and e.element.name
  rec.text = e.text
end

function gui.on_gui_checked_state_changed(e, rec, player)
  rec.gui_type = "checkbox"
  rec.gui_element = e.element and e.element.name
  rec.state = e.state -- true/false
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================
function gui.get_extractor(event_name)
  return gui[event_name] or function() end -- Default no-op
end

return gui 