--@blueprint_planner.lua
--@description Blueprint and planning category logging module
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("shared-utils")
local blueprint_planner = {}

-- ============================================================================
-- EVENT REGISTRATION
-- ============================================================================
function blueprint_planner.register_events()
  -- Register blueprint and planning-related events
  script.on_event(defines.events.on_player_setup_blueprint, function(e)
    if shared_utils.is_player_event(e) then
      blueprint_planner.handle_event("on_player_setup_blueprint", e)
    end
  end)
  
  script.on_event(defines.events.on_player_configured_blueprint, function(e)
    if shared_utils.is_player_event(e) then
      blueprint_planner.handle_event("on_player_configured_blueprint", e)
    end
  end)
  
  script.on_event(defines.events.on_player_deconstructed_area, function(e)
    if shared_utils.is_player_event(e) then
      blueprint_planner.handle_event("on_player_deconstructed_area", e)
    end
  end)
end

-- ============================================================================
-- BLUEPRINT UTILITIES
-- ============================================================================
function blueprint_planner.extract_blueprint_data(bp_stack, tag, tick, player_idx)
  -- Safety checks
  if not (bp_stack and bp_stack.valid_for_read and bp_stack.is_blueprint_setup()) then
    return nil -- Nothing to extract
  end
  
  local success, bp_data = pcall(function()
    -- Extract blueprint data safely
    local data = {}
    
    -- Basic metadata
    data.tick = tick
    data.player = player_idx
    data.phase = tag
    
    -- Blueprint string (safe for export/import)
    local export_success, bp_string = pcall(function()
      return bp_stack.export_stack()
    end)
    if export_success and bp_string then
      -- Store the actual blueprint string in the data
      data.bp_string = bp_string
      
      -- Create a more reliable digest using first 32 chars of blueprint string
      -- This avoids hash collisions since blueprint strings are deterministic
      if #bp_string >= 32 then
        data.bp_digest = string.sub(bp_string, 1, 32)
      else
        data.bp_digest = bp_string -- Use full string if shorter than 32 chars
      end
    end
    
    -- Entity data
    local entities_success, entities = pcall(function()
      return bp_stack.get_blueprint_entities() or {}
    end)
    if entities_success and entities then
      data.entity_count = #entities
      -- Store first few entities for quick inspection (limit to avoid huge logs)
      if #entities > 0 then
        data.sample_entities = {}
        for i = 1, math.min(5, #entities) do
          local ent = entities[i]
          if ent and ent.name then
            table.insert(data.sample_entities, {
              name = ent.name,
              position = ent.position
            })
          end
        end
      end
    end
    
    -- Tile data
    local tiles_success, tiles = pcall(function()
      return bp_stack.get_blueprint_tiles and bp_stack.get_blueprint_tiles() or {}
    end)
    if tiles_success and tiles then
      data.tile_count = #tiles
    end
    
    return data
  end)
  
  if not success then
    -- Log the error but don't crash
    log("[blueprint-logger] Error extracting blueprint data: " .. tostring(bp_data))
    return nil
  end
  
  return bp_data
end

function blueprint_planner.get_blueprint_stack_safely(event, player)
  -- Try multiple sources for the blueprint stack based on event type
  local stack = nil
  
  if player and player.cursor_stack then
    -- For configured blueprint (usually in cursor)
    stack = player.cursor_stack
  elseif event.stack then
    -- Direct stack from event (on_player_setup_blueprint in v1.1+)
    stack = event.stack
  elseif player and player.opened_gui_type == defines.gui_type.item and player.opened then
    -- Blueprint in opened GUI
    stack = player.opened
  elseif player and player.blueprint_to_setup then
    -- Fallback for setup phase
    stack = player.blueprint_to_setup
  end
  
  -- Validate the stack
  if stack and stack.valid_for_read and stack.is_blueprint_setup and stack.is_blueprint_setup() then
    return stack
  end
  
  return nil
end


-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================
function blueprint_planner.handle_event(event_name, event_data)
  local player = event_data.player_index and game.players[event_data.player_index]
  
  -- Create base record
  local rec = shared_utils.create_base_record(event_name, event_data)
  
  -- Apply event-specific context extraction
  local extractor = blueprint_planner.get_extractor(event_name)
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
  
  -- Buffer to blueprint_planner category
  shared_utils.buffer_event("blueprint_planner", line)
end

-- ============================================================================
-- CONTEXT EXTRACTORS
-- ============================================================================
function blueprint_planner.on_player_setup_blueprint(e, rec, player)
  rec.action = "blueprint_setup"
  if e.area then
    rec.area_x1 = string.format("%.1f", e.area.left_top.x)
    rec.area_y1 = string.format("%.1f", e.area.left_top.y)
    rec.area_x2 = string.format("%.1f", e.area.right_bottom.x)
    rec.area_y2 = string.format("%.1f", e.area.right_bottom.y)
  end
  if e.item then
    rec.item = e.item
  end
  if e.entities and #e.entities > 0 then
    rec.entity_count = #e.entities
  end
  
  -- Enhanced blueprint logging - extract and log full blueprint data
  local bp_stack = blueprint_planner.get_blueprint_stack_safely(e, player)
  if bp_stack then
    local bp_data = blueprint_planner.extract_blueprint_data(bp_stack, "setup", e.tick, e.player_index)
    if bp_data then
      rec.bp_digest = bp_data.bp_digest
      rec.bp_string = bp_data.bp_string
      rec.bp_entity_count = bp_data.entity_count
    end
  end
end

function blueprint_planner.on_player_configured_blueprint(e, rec, player)
  rec.action = "blueprint_confirmed"
  
  -- Enhanced blueprint logging - the blueprint is now in the player's cursor
  local bp_stack = blueprint_planner.get_blueprint_stack_safely(e, player)
  if bp_stack then
    local bp_data = blueprint_planner.extract_blueprint_data(bp_stack, "confirm", e.tick, e.player_index)
    if bp_data then
      rec.bp_digest = bp_data.bp_digest
      rec.bp_string = bp_data.bp_string
      rec.bp_entity_count = bp_data.entity_count
    end
  end
end

function blueprint_planner.on_player_deconstructed_area(e, rec, player)
  rec.action = "deconstruct_area"
  if e.area then
    rec.area_x1 = string.format("%.1f", e.area.left_top.x)
    rec.area_y1 = string.format("%.1f", e.area.left_top.y)
    rec.area_x2 = string.format("%.1f", e.area.right_bottom.x)
    rec.area_y2 = string.format("%.1f", e.area.right_bottom.y)
  end
  if e.item then
    rec.item = e.item
  end
  if e.alt ~= nil then
    rec.alt_mode = e.alt
  end
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================
function blueprint_planner.get_extractor(event_name)
  return blueprint_planner[event_name] or function() end -- Default no-op
end

return blueprint_planner 