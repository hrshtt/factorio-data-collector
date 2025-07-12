--@construction.lua
--@description State-driven construction logging with context tracking (following logistics pattern)
--@author Harshit Sharma
--@version 3.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("script.shared-utils")
local construction = {}

-- ============================================================================
-- CORE LOGGING FUNCTION
-- ============================================================================

function construction.log_construction_action(record)
  -- record = {
  --   tick         = <number>,
  --   player       = <index>,
  --   action       = <string>,
  --   entity       = <string>,
  --   context      = <table>
  -- }
  
  -- Add position if available in context
  if record.context and record.context.position then
    record.x = string.format("%.1f", record.context.position.x)
    record.y = string.format("%.1f", record.context.position.y)
  end
  
  local clean_record = shared_utils.clean_record(record)
  local json = game.table_to_json(clean_record)
  shared_utils.buffer_event("construction", json)
end

-- ============================================================================
-- PLAYER CONTEXT MANAGEMENT (same pattern as logistics)
-- ============================================================================

function construction.get_player_context(player_index)
  if not global.construction_contexts then
    global.construction_contexts = {}
  end
  
  if not global.construction_contexts[player_index] then
    global.construction_contexts[player_index] = {
      gui = nil,           -- Same as logistics: track GUI context
      ephemeral = nil,     -- Same as logistics: temporary action context
      blueprint_state = {} -- Simple blueprint tracking
    }
  end
  
  return global.construction_contexts[player_index]
end

function construction.initialize()
  if not global.construction_contexts then
    global.construction_contexts = {}
  end
end

-- ============================================================================
-- GUI CONTEXT TRACKING (adapted from logistics pattern)
-- ============================================================================

function construction.handle_gui_opened(event)
  if event.gui_type == defines.gui_type.blueprint_library and event.player_index then
    local ctx = construction.get_player_context(event.player_index)
    ctx.gui = {
      type = "blueprint_library",
      opened_tick = event.tick
    }
  elseif event.gui_type == defines.gui_type.blueprint_book and event.player_index then
    local ctx = construction.get_player_context(event.player_index)
    ctx.gui = {
      type = "blueprint_book", 
      opened_tick = event.tick
    }
  end
end

function construction.handle_gui_closed(event)
  if not event.player_index then
    return
  end

  local ctx = global.construction_contexts and global.construction_contexts[event.player_index]
  if ctx and ctx.gui then
    -- Log blueprint session if it was a blueprint-related GUI
    if ctx.gui.type == "blueprint_library" or ctx.gui.type == "blueprint_book" then
      construction.log_construction_action{
        tick = event.tick,
        player = event.player_index,
        action = "blueprint_session",
        context = {
          action = "blueprint_session_ended",
          gui_type = ctx.gui.type,
          duration = event.tick - (ctx.gui.opened_tick or event.tick)
        }
      }
    end
    ctx.gui = nil
  end
end

-- ============================================================================
-- DIRECT EVENT HANDLERS (following logistics pattern exactly)
-- ============================================================================

function construction.handle_built_entity(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  -- Set ephemeral context (like logistics does for builds)
  local ctx = construction.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "build",
    entity = event.created_entity and event.created_entity.name,
    position = event.created_entity and event.created_entity.position
  }
  
  -- Direct logging for construction action
  construction.log_construction_action{
    tick = event.tick,
    player = event.player_index,
    action = "build",
    entity = event.created_entity and event.created_entity.name,
    context = ctx.ephemeral
  }
  
  -- Clear ephemeral like logistics does
  ctx.ephemeral = nil
end

function construction.handle_rotated_entity(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  construction.log_construction_action{
    tick = event.tick,
    player = event.player_index,
    action = "rotate",
    entity = event.entity and event.entity.name,
    context = {
      action = "rotate",
      entity = event.entity and event.entity.name,
      position = event.entity and event.entity.position,
      previous_direction = event.previous_direction,
      direction = event.entity.direction
    }
  }
end

function construction.handle_built_tile(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  construction.log_construction_action{
    tick = event.tick,
    player = event.player_index,
    action = "build_tile",
    context = {
      action = "build_tile",
      tile = event.tile and event.tile.name,
      item = event.item and event.item.name,
      tile_count = event.tiles and #event.tiles or 1,
      surface = event.surface_index
    }
  }
end

function construction.handle_placed_equipment(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  construction.log_construction_action{
    tick = event.tick,
    player = event.player_index,
    action = "place_equipment",
    context = {
      action = "place_equipment",
      equipment = event.equipment and event.equipment.name
    }
  }
end

function construction.handle_removed_equipment(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  construction.log_construction_action{
    tick = event.tick,
    player = event.player_index,
    action = "remove_equipment", 
    context = {
      action = "remove_equipment",
      equipment = event.equipment and event.equipment.name
    }
  }
end

-- ============================================================================
-- BLUEPRINT HANDLERS (simplified, no complex state tracking)
-- ============================================================================

function construction.handle_setup_blueprint(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  local ctx = construction.get_player_context(event.player_index)
  
  -- Simple blueprint context (like logistics ephemeral)
  ctx.ephemeral = {
    action = "blueprint_setup",
    area = event.area,
    entities_count = event.entities and #event.entities or 0
  }
  
  construction.log_construction_action{
    tick = event.tick,
    player = event.player_index,
    action = "blueprint_setup",
    context = ctx.ephemeral
  }
  
  -- Don't clear ephemeral yet - let it persist to next blueprint event
end

function construction.handle_configured_blueprint(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  local ctx = construction.get_player_context(event.player_index)
  
  construction.log_construction_action{
    tick = event.tick,
    player = event.player_index,
    action = "blueprint_configured",
    context = ctx.ephemeral or { action = "blueprint_configured" }
  }
  
  -- Clear ephemeral after blueprint is configured
  ctx.ephemeral = nil
end

function construction.handle_deconstructed_area(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  construction.log_construction_action{
    tick = event.tick,
    player = event.player_index,
    action = "deconstruct_area",
    context = {
      action = "deconstruct_area",
      area = event.area,
      alt_mode = event.alt
    }
  }
end

function construction.handle_entity_settings_pasted(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  construction.log_construction_action{
    tick = event.tick,
    player = event.player_index,
    action = "paste_settings",
    context = {
      action = "paste_settings",
      destination = event.destination and event.destination.name,
      source = event.source and event.source.name,
      position = event.destination and event.destination.position
    }
  }
end

-- ============================================================================
-- EVENT REGISTRATION (following logistics pattern)
-- ============================================================================

function construction.register_events()
  construction.initialize()
  
  -- GUI context tracking (like logistics)
  script.on_event(defines.events.on_gui_opened, construction.handle_gui_opened)
  script.on_event(defines.events.on_gui_closed, construction.handle_gui_closed)
  
  -- Direct construction events (like logistics direct events)
  script.on_event(defines.events.on_built_entity, construction.handle_built_entity)
  script.on_event(defines.events.on_player_rotated_entity, construction.handle_rotated_entity)
  script.on_event(defines.events.on_player_built_tile, construction.handle_built_tile)
  script.on_event(defines.events.on_player_placed_equipment, construction.handle_placed_equipment)
  script.on_event(defines.events.on_player_removed_equipment, construction.handle_removed_equipment)
  
  -- Blueprint events
  script.on_event(defines.events.on_player_setup_blueprint, construction.handle_setup_blueprint)
  script.on_event(defines.events.on_player_configured_blueprint, construction.handle_configured_blueprint)
  script.on_event(defines.events.on_player_deconstructed_area, construction.handle_deconstructed_area)
  script.on_event(defines.events.on_entity_settings_pasted, construction.handle_entity_settings_pasted)
end

return construction 