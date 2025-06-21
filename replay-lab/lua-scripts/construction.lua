--@construction.lua
--@description Construction category logging module - building, blueprints, and factory layout
--@author Harshit Sharma
--@version 2.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("shared-utils")
local construction = {}

-- ============================================================================
-- EVENT REGISTRATION
-- ============================================================================
function construction.register_events()
  -- Define event handlers after all functions are defined
  local EVENT_HANDLERS = {
    -- Construction events (moved from production)
    on_built_entity = construction.handle_built_entity,
    on_player_built_tile = construction.handle_built_tile,
    on_player_rotated_entity = construction.handle_rotated_entity,
    on_player_placed_equipment = construction.handle_placed_equipment,
    on_player_removed_equipment = construction.handle_removed_equipment,
    
    -- Blueprint events (existing from blueprint_planner)
    on_player_setup_blueprint = construction.handle_setup_blueprint,
    on_player_configured_blueprint = construction.handle_configured_blueprint,
    on_player_deconstructed_area = construction.handle_deconstructed_area,
    
    -- Settings paste events (new)
    on_entity_settings_pasted = construction.handle_entity_settings_pasted
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
-- CONSTRUCTION EVENT HANDLERS
-- ============================================================================

-- Generic handler for construction events
function construction.handle_construction_event(event_name, event_data, action_name, extract_context)
  local player = event_data.player_index and game.players[event_data.player_index]
  
  -- Create base record
  local rec = shared_utils.create_base_record(event_name, event_data)
  rec.act = action_name
  
  -- Extract additional context if provided
  if extract_context then
    extract_context(event_data, rec, player)
  end
  
  -- Add player context if missing
  shared_utils.add_player_context_if_missing(rec, player)
  
  -- Clean and buffer
  local clean_rec = shared_utils.clean_record(rec)
  shared_utils.buffer_event("construction", game.table_to_json(clean_rec))
end

-- Simple entity action handler
function construction.handle_entity_action(event_name, event_data, action_name, entity_field)
  construction.handle_construction_event(event_name, event_data, action_name, function(e, rec, player)
    if e[entity_field or "entity"] then
      rec.ent = shared_utils.get_entity_info(e[entity_field or "entity"])
    end
  end)
end

-- ============================================================================
-- SPECIFIC CONSTRUCTION HANDLERS
-- ============================================================================

function construction.handle_built_entity(e)
  construction.handle_entity_action("on_built_entity", e, "build", "created_entity")
end

function construction.handle_built_tile(e)
  construction.handle_construction_event("on_player_built_tile", e, "build_tile", function(e, rec, player)
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
          table.insert(positions, {x = tile_data.position.x, y = tile_data.position.y})
        end
      end
      if #positions > 0 then
        rec.tile_positions = game.table_to_json(positions)
      end
    end
  end)
end

function construction.handle_rotated_entity(e)
  construction.handle_entity_action("on_player_rotated_entity", e, "rotate")
end

function construction.handle_placed_equipment(e)
  construction.handle_entity_action("on_player_placed_equipment", e, "place_equipment", "equipment")
end

function construction.handle_removed_equipment(e)
  construction.handle_entity_action("on_player_removed_equipment", e, "remove_equipment", "equipment")
end

function construction.handle_entity_settings_pasted(e)
  construction.handle_construction_event("on_entity_settings_pasted", e, "paste_settings", function(e, rec, player)
    if e.destination then
      rec.ent = shared_utils.get_entity_info(e.destination)
    end
    if e.source then
      rec.source_ent = shared_utils.get_entity_info(e.source)
    end
  end)
end

-- ============================================================================
-- BLUEPRINT UTILITIES
-- ============================================================================
function construction.extract_blueprint_data(bp_stack, tag, tick, player_idx)
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
    log("[construction-logger] Error extracting blueprint data: " .. tostring(bp_data))
    return nil
  end
  
  return bp_data
end

function construction.get_blueprint_stack_safely(event, player)
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
-- BLUEPRINT EVENT HANDLERS
-- ============================================================================
function construction.handle_setup_blueprint(e)
  construction.handle_construction_event("on_player_setup_blueprint", e, "blueprint_setup", function(e, rec, player)
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
    local bp_stack = construction.get_blueprint_stack_safely(e, player)
    if bp_stack then
      local bp_data = construction.extract_blueprint_data(bp_stack, "setup", e.tick, e.player_index)
      if bp_data then
        rec.bp_digest = bp_data.bp_digest
        rec.bp_string = bp_data.bp_string
        rec.bp_entity_count = bp_data.entity_count
      end
    end
  end)
end

function construction.handle_configured_blueprint(e)
  construction.handle_construction_event("on_player_configured_blueprint", e, "blueprint_confirmed", function(e, rec, player)
    -- Enhanced blueprint logging - the blueprint is now in the player's cursor
    local bp_stack = construction.get_blueprint_stack_safely(e, player)
    if bp_stack then
      local bp_data = construction.extract_blueprint_data(bp_stack, "confirm", e.tick, e.player_index)
      if bp_data then
        rec.bp_digest = bp_data.bp_digest
        rec.bp_string = bp_data.bp_string
        rec.bp_entity_count = bp_data.entity_count
      end
    end
  end)
end

function construction.handle_deconstructed_area(e)
  construction.handle_construction_event("on_player_deconstructed_area", e, "deconstruct_area", function(e, rec, player)
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
  end)
end

return construction 