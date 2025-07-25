--@control.lua
--@description Raw Events Logger for Factorio 1.1.110
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27
--@license MIT
--@category Other
--@tags events, logger, raw, factorio, 1.1.110

-- ============================================================================
-- MODULE IMPORTS
-- ============================================================================
local shared_utils = require("script.shared-utils")
local tick_overlay = require("script.tick_overlay")
local logistics = require("script.logistics")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local FLUSH_EVERY = 600        -- 10 s at 60 UPS

-- ============================================================================
-- CENTRALIZED EVENT DISPATCHER
-- ============================================================================
local event_dispatcher = {}

-- Table to store multiple handlers per event
local event_handlers = {}

function event_dispatcher.register_handler(event_id, handler_func)
  if not event_handlers[event_id] then
    event_handlers[event_id] = {}
    -- Register the dispatcher for this event only once
    script.on_event(event_id, function(event)
      -- Call all registered handlers for this event
      for _, handler in pairs(event_handlers[event_id]) do
        handler(event)
      end
    end)
  end
  table.insert(event_handlers[event_id], handler_func)
end

function event_dispatcher.register_nth_tick_handler(tick_interval, handler_func)
  -- For nth tick events, we'll use a similar pattern
  if not event_handlers["nth_tick_" .. tick_interval] then
    event_handlers["nth_tick_" .. tick_interval] = {}
    script.on_nth_tick(tick_interval, function(event)
      for _, handler in pairs(event_handlers["nth_tick_" .. tick_interval]) do
        handler(event)
      end
    end)
  end
  table.insert(event_handlers["nth_tick_" .. tick_interval], handler_func)
end

-- ============================================================================
-- RAW EVENT LOGGER
-- ============================================================================
local raw_logger = {}

function raw_logger.log_event(event_name, event_data)
  local INSERTABLE_EVENTS_ONLY = false
  local CRAFTING_QUEUE_DATA = false
  local SELECTED_ENTITY_DATA = false

  -- Add event name to the event data
  event_data.event_name = event_name
  if not event_data.player_index then return end
  local player = game.get_player(event_data.player_index)
  if not player then return end
  
  -- Auto-enhance with common context if available (generic, no bespoke formatting)
  if event_data.player_index then
    if player and player.valid then
      -- Add player context
      local ctx = shared_utils.get_player_context(player)
      if SELECTED_ENTITY_DATA and ctx.selected_entity then
        event_data.selected_entity = ctx.selected_entity
        event_data.selected_entity_key = ctx.selected_entity.name .. " (" .. string.format("%.1f", ctx.selected_entity.position.x) .. ", " .. string.format("%.1f", ctx.selected_entity.position.y) .. ")"
        ctx.selected_entity = nil
      end
      if INSERTABLE_EVENTS_ONLY and not logistics.can_be_inserted(ctx.cursor_item) then
        return
      end
      event_data.player = ctx
      event_data.player.index = event_data.player_index
    end
  end

  if CRAFTING_QUEUE_DATA and player.crafting_queue then
    event_data.crafting_queue = player.crafting_queue
    event_data.crafting_queue_size = player.crafting_queue_size
    event_data.crafting_queue_progress = player.crafting_queue_progress
  end

  if event_data.recipe then
    event_data.recipe = {
      name = event_data.recipe.name,
      category = event_data.recipe.category,
      ingredients = event_data.recipe.ingredients,
      products = event_data.recipe.products,
    }
  end
  
  -- Add entity name if entity exists
  if event_data.entity then
    event_data.entity = {
      name = event_data.entity.name,
      position = event_data.entity.position,
      type = event_data.entity.type
    }
  end

  -- Add last_entity name if last_entity exists (for on_selected_entity_changed)
  if event_data.last_entity then
    event_data.last_entity = {
      name = event_data.last_entity.name,
      position = event_data.last_entity.position,
      type = event_data.last_entity.type
    }
  end
  
  -- Add item info if stack exists
  if event_data.stack then
    event_data.item_name, event_data.item_count = shared_utils.get_item_info(event_data.stack)
  elseif event_data.item_stack then
    event_data.item_name, event_data.item_count = shared_utils.get_item_info(event_data.item_stack)
  elseif event_data.item then
    -- GUI events use 'item' field, not 'stack' or 'item_stack'
    pcall(function()
      event_data.item_name, event_data.item_count = shared_utils.get_item_info(event_data.item)
    end)
  end
  
  -- Add GUI-specific context
  if event_data.gui_type then
    pcall(function()
      -- Convert gui_type enum to readable string - build table safely
      local gui_type_names = {}
      
      -- Only add entries if the defines actually exist
      if defines.gui_type then
        if defines.gui_type.achievement then gui_type_names[defines.gui_type.achievement] = "achievement" end
        if defines.gui_type.blueprint_library then gui_type_names[defines.gui_type.blueprint_library] = "blueprint_library" end
        if defines.gui_type.bonus then gui_type_names[defines.gui_type.bonus] = "bonus" end
        if defines.gui_type.controller then gui_type_names[defines.gui_type.controller] = "controller" end
        if defines.gui_type.custom then gui_type_names[defines.gui_type.custom] = "custom" end
        if defines.gui_type.entity then gui_type_names[defines.gui_type.entity] = "entity" end
        if defines.gui_type.equipment then gui_type_names[defines.gui_type.equipment] = "equipment" end
        if defines.gui_type.item then gui_type_names[defines.gui_type.item] = "item" end
        if defines.gui_type.logistic then gui_type_names[defines.gui_type.logistic] = "logistic" end
        if defines.gui_type.none then gui_type_names[defines.gui_type.none] = "none" end
        if defines.gui_type.other_player then gui_type_names[defines.gui_type.other_player] = "other_player" end
        if defines.gui_type.permissions then gui_type_names[defines.gui_type.permissions] = "permissions" end
        if defines.gui_type.production then gui_type_names[defines.gui_type.production] = "production" end
        if defines.gui_type.research then gui_type_names[defines.gui_type.research] = "research" end
        if defines.gui_type.server_management then gui_type_names[defines.gui_type.server_management] = "server_management" end
        if defines.gui_type.tile then gui_type_names[defines.gui_type.tile] = "tile" end
      end
      
      -- Safe lookup with fallback
      local gui_type_value = event_data.gui_type
      if gui_type_value and gui_type_names[gui_type_value] then
        event_data.gui_type_name = gui_type_names[gui_type_value]
      else
        event_data.gui_type_name = "unknown_" .. tostring(gui_type_value or "nil")
      end
    end)
  end
  
  -- Add equipment info if equipment exists
  if event_data.equipment and event_data.equipment.valid then
    pcall(function()
      event_data.equipment_name = event_data.equipment.name
      event_data.equipment_type = event_data.equipment.type
    end)
  end
  
  -- Add other player info if other_player exists
  if event_data.other_player and event_data.other_player.valid then
    pcall(function()
      event_data.other_player_name = event_data.other_player.name
      event_data.other_player_index = event_data.other_player.index
    end)
  end
  
  -- Add GUI element info if element exists
  if event_data.element and event_data.element.valid then
    pcall(function()
      event_data.element_name = event_data.element.name
      event_data.element_type = event_data.element.type
      if event_data.element.caption then
        event_data.element_caption = event_data.element.caption
      end
    end)
  end
  
  -- Add inventory info if inventory exists
  if event_data.inventory and event_data.inventory.valid then
    pcall(function()
      event_data.inventory_type = event_data.inventory.name
      event_data.inventory_size = #event_data.inventory
    end)
  end
  
  -- Add technology info if technology exists
  if event_data.technology and event_data.technology.valid then
    pcall(function()
      event_data.technology_name = event_data.technology.name
      event_data.technology_level = event_data.technology.level
    end)
  end
  
  -- Format position if available
  -- if event_data.position then
  --   event_data.pos_x = string.format("%.1f", event_data.position.x)
  --   event_data.pos_y = string.format("%.1f", event_data.position.y)
  -- end
  
  -- Convert event data to JSON and log it
  event_data.player_index = nil
  
  -- Define priority order for keys
  local priority_keys = {
    "tick", "event_name", "entity", "selected_entity", "last_entity", "player"
  }
  
  local sorted_event_data = {}
  local remaining_keys = {}
  
  -- Add priority keys first (only if they exist)
  for _, key in ipairs(priority_keys) do
    if event_data[key] ~= nil then
      sorted_event_data[key] = event_data[key]
    end
  end
  
  -- Add remaining keys in alphabetical order
  for key in pairs(event_data) do
    local is_priority = false
    for _, priority_key in ipairs(priority_keys) do
      if key == priority_key then
        is_priority = true
        break
      end
    end
    
    if not is_priority then
      table.insert(remaining_keys, key)
    end
  end
  
  table.sort(remaining_keys)
  for _, key in ipairs(remaining_keys) do
    sorted_event_data[key] = event_data[key]
  end
  
  local line = game.table_to_json(sorted_event_data)
  shared_utils.buffer_event("raw_events", line)
end

-- ============================================================================
-- MAIN MODULE - EVENT REGISTRATION
-- ============================================================================
local main = {}

function main.initialize()
  -- Register tick overlay events
  tick_overlay.register_events(event_dispatcher)
  
  -- Register ALL Factorio 1.1.110 events
  
  -- CustomInputEvent - handled separately via script.on_event for custom inputs
  
  -- AI/Unit events
  -- event_dispatcher.register_handler(defines.events.on_ai_command_completed, function(e)
  --   raw_logger.log_event("on_ai_command_completed", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_unit_added_to_group, function(e)
  --   raw_logger.log_event("on_unit_added_to_group", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_unit_group_created, function(e)
  --   raw_logger.log_event("on_unit_group_created", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_unit_group_finished_gathering, function(e)
  --   raw_logger.log_event("on_unit_group_finished_gathering", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_unit_removed_from_group, function(e)
  --   raw_logger.log_event("on_unit_removed_from_group", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_spider_command_completed, function(e)
  --   raw_logger.log_event("on_spider_command_completed", e)
  -- end)
  
  -- -- Area/Surface events  
  -- event_dispatcher.register_handler(defines.events.on_area_cloned, function(e)
  --   raw_logger.log_event("on_area_cloned", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_brush_cloned, function(e)
  --   raw_logger.log_event("on_brush_cloned", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_surface_created, function(e)
  --   raw_logger.log_event("on_surface_created", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_surface_deleted, function(e)
  --   raw_logger.log_event("on_surface_deleted", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_surface_imported, function(e)
  --   raw_logger.log_event("on_surface_imported", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_surface_renamed, function(e)
  --   raw_logger.log_event("on_surface_renamed", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_surface_cleared, function(e)
  --   raw_logger.log_event("on_surface_cleared", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_pre_surface_cleared, function(e)
  --   raw_logger.log_event("on_pre_surface_cleared", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_pre_surface_deleted, function(e)
  --   raw_logger.log_event("on_pre_surface_deleted", e)
  -- end)
  
  -- -- Biter/Enemy events
  -- event_dispatcher.register_handler(defines.events.on_biter_base_built, function(e)
  --   raw_logger.log_event("on_biter_base_built", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_build_base_arrived, function(e)
  --   raw_logger.log_event("on_build_base_arrived", e)
  -- end)
  
  -- Build/Construction events
  event_dispatcher.register_handler(defines.events.on_built_entity, function(e)
    raw_logger.log_event("on_built_entity", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_robot_built_entity, function(e)
    raw_logger.log_event("on_robot_built_entity", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_robot_built_tile, function(e)
    raw_logger.log_event("on_robot_built_tile", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_build, function(e)
    raw_logger.log_event("on_pre_build", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_built_tile, function(e)
    raw_logger.log_event("on_player_built_tile", e)
  end)
  
  -- Character/Corpse events
  event_dispatcher.register_handler(defines.events.on_character_corpse_expired, function(e)
    raw_logger.log_event("on_character_corpse_expired", e)
  end)
  
  -- Chart events
  event_dispatcher.register_handler(defines.events.on_chart_tag_added, function(e)
    raw_logger.log_event("on_chart_tag_added", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_chart_tag_modified, function(e)
    raw_logger.log_event("on_chart_tag_modified", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_chart_tag_removed, function(e)
    raw_logger.log_event("on_chart_tag_removed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_sector_scanned, function(e)
    raw_logger.log_event("on_sector_scanned", e)
  end)
  
  -- Chunk events
  -- event_dispatcher.register_handler(defines.events.on_chunk_charted, function(e)
  --   raw_logger.log_event("on_chunk_charted", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_chunk_deleted, function(e)
  --   raw_logger.log_event("on_chunk_deleted", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_chunk_generated, function(e)
  --   raw_logger.log_event("on_chunk_generated", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_pre_chunk_deleted, function(e)
  --   raw_logger.log_event("on_pre_chunk_deleted", e)
  -- end)
  
  -- -- Combat events
  -- event_dispatcher.register_handler(defines.events.on_combat_robot_expired, function(e)
  --   raw_logger.log_event("on_combat_robot_expired", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_worker_robot_expired, function(e)
  --   raw_logger.log_event("on_worker_robot_expired", e)
  -- end)
  
  -- -- Console events
  -- event_dispatcher.register_handler(defines.events.on_console_chat, function(e)
  --   raw_logger.log_event("on_console_chat", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_console_command, function(e)
  --   raw_logger.log_event("on_console_command", e)
  -- end)
  
  -- Cutscene events
  -- event_dispatcher.register_handler(defines.events.on_cutscene_cancelled, function(e)
  --   raw_logger.log_event("on_cutscene_cancelled", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_cutscene_finished, function(e)
  --   raw_logger.log_event("on_cutscene_finished", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_cutscene_started, function(e)
  --   raw_logger.log_event("on_cutscene_started", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_cutscene_waypoint_reached, function(e)
  --   raw_logger.log_event("on_cutscene_waypoint_reached", e)
  -- end)
  
  -- Deconstruction events
  event_dispatcher.register_handler(defines.events.on_cancelled_deconstruction, function(e)
    raw_logger.log_event("on_cancelled_deconstruction", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_cancelled_upgrade, function(e)
    raw_logger.log_event("on_cancelled_upgrade", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_marked_for_deconstruction, function(e)
    raw_logger.log_event("on_marked_for_deconstruction", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_marked_for_upgrade, function(e)
    raw_logger.log_event("on_marked_for_upgrade", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_deconstructed_area, function(e)
    raw_logger.log_event("on_player_deconstructed_area", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_ghost_deconstructed, function(e)
    raw_logger.log_event("on_pre_ghost_deconstructed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_ghost_upgraded, function(e)
    raw_logger.log_event("on_pre_ghost_upgraded", e)
  end)
  
  -- Difficulty events
  event_dispatcher.register_handler(defines.events.on_difficulty_settings_changed, function(e)
    raw_logger.log_event("on_difficulty_settings_changed", e)
  end)
  
  -- Entity events
  event_dispatcher.register_handler(defines.events.on_entity_cloned, function(e)
    raw_logger.log_event("on_entity_cloned", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_entity_color_changed, function(e)
    raw_logger.log_event("on_entity_color_changed", e)
  end)
  
  -- event_dispatcher.register_handler(defines.events.on_entity_damaged, function(e)
  --   raw_logger.log_event("on_entity_damaged", e)
  -- end)
  
  event_dispatcher.register_handler(defines.events.on_entity_destroyed, function(e)
    raw_logger.log_event("on_entity_destroyed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_entity_died, function(e)
    raw_logger.log_event("on_entity_died", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_post_entity_died, function(e)
    raw_logger.log_event("on_post_entity_died", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_entity_logistic_slot_changed, function(e)
    raw_logger.log_event("on_entity_logistic_slot_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_entity_renamed, function(e)
    raw_logger.log_event("on_entity_renamed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_entity_settings_pasted, function(e)
    raw_logger.log_event("on_entity_settings_pasted", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_entity_settings_pasted, function(e)
    raw_logger.log_event("on_pre_entity_settings_pasted", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_entity_spawned, function(e)
    raw_logger.log_event("on_entity_spawned", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_selected_entity_changed, function(e)
    raw_logger.log_event("on_selected_entity_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_trigger_created_entity, function(e)
    raw_logger.log_event("on_trigger_created_entity", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_trigger_fired_artillery, function(e)
    raw_logger.log_event("on_trigger_fired_artillery", e)
  end)
  
  -- Equipment events
  event_dispatcher.register_handler(defines.events.on_equipment_inserted, function(e)
    raw_logger.log_event("on_equipment_inserted", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_equipment_removed, function(e)
    raw_logger.log_event("on_equipment_removed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_placed_equipment, function(e)
    raw_logger.log_event("on_player_placed_equipment", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_removed_equipment, function(e)
    raw_logger.log_event("on_player_removed_equipment", e)
  end)
  
  -- Force events
  event_dispatcher.register_handler(defines.events.on_force_cease_fire_changed, function(e)
    raw_logger.log_event("on_force_cease_fire_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_force_created, function(e)
    raw_logger.log_event("on_force_created", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_force_friends_changed, function(e)
    raw_logger.log_event("on_force_friends_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_force_reset, function(e)
    raw_logger.log_event("on_force_reset", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_forces_merged, function(e)
    raw_logger.log_event("on_forces_merged", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_forces_merging, function(e)
    raw_logger.log_event("on_forces_merging", e)
  end)
  
  -- Game events
  event_dispatcher.register_handler(defines.events.on_game_created_from_scenario, function(e)
    raw_logger.log_event("on_game_created_from_scenario", e)
  end)
  
  -- GUI events
  event_dispatcher.register_handler(defines.events.on_gui_checked_state_changed, function(e)
    raw_logger.log_event("on_gui_checked_state_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_gui_click, function(e)
    raw_logger.log_event("on_gui_click", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_gui_closed, function(e)
    raw_logger.log_event("on_gui_closed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_gui_confirmed, function(e)
    raw_logger.log_event("on_gui_confirmed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_gui_elem_changed, function(e)
    raw_logger.log_event("on_gui_elem_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_gui_hover, function(e)
    raw_logger.log_event("on_gui_hover", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_gui_leave, function(e)
    raw_logger.log_event("on_gui_leave", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_gui_location_changed, function(e)
    raw_logger.log_event("on_gui_location_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_gui_opened, function(e)
    raw_logger.log_event("on_gui_opened", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_gui_selected_tab_changed, function(e)
    raw_logger.log_event("on_gui_selected_tab_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_gui_selection_state_changed, function(e)
    raw_logger.log_event("on_gui_selection_state_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_gui_switch_state_changed, function(e)
    raw_logger.log_event("on_gui_switch_state_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_gui_text_changed, function(e)
    raw_logger.log_event("on_gui_text_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_gui_value_changed, function(e)
    raw_logger.log_event("on_gui_value_changed", e)
  end)
  
  -- Land mine events
  event_dispatcher.register_handler(defines.events.on_land_mine_armed, function(e)
    raw_logger.log_event("on_land_mine_armed", e)
  end)
  
  -- Lua shortcut events
  event_dispatcher.register_handler(defines.events.on_lua_shortcut, function(e)
    raw_logger.log_event("on_lua_shortcut", e)
  end)
  
  -- Market events
  event_dispatcher.register_handler(defines.events.on_market_item_purchased, function(e)
    raw_logger.log_event("on_market_item_purchased", e)
  end)
  
  -- Mod events
  event_dispatcher.register_handler(defines.events.on_mod_item_opened, function(e)
    raw_logger.log_event("on_mod_item_opened", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_runtime_mod_setting_changed, function(e)
    raw_logger.log_event("on_runtime_mod_setting_changed", e)
  end)
  
  -- Permission events
  event_dispatcher.register_handler(defines.events.on_permission_group_added, function(e)
    raw_logger.log_event("on_permission_group_added", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_permission_group_deleted, function(e)
    raw_logger.log_event("on_permission_group_deleted", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_permission_group_edited, function(e)
    raw_logger.log_event("on_permission_group_edited", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_permission_string_imported, function(e)
    raw_logger.log_event("on_permission_string_imported", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_permission_group_deleted, function(e)
    raw_logger.log_event("on_pre_permission_group_deleted", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_permission_string_imported, function(e)
    raw_logger.log_event("on_pre_permission_string_imported", e)
  end)
  
  -- Player events
  event_dispatcher.register_handler(defines.events.on_picked_up_item, function(e)
    raw_logger.log_event("on_picked_up_item", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_alt_reverse_selected_area, function(e)
    raw_logger.log_event("on_player_alt_reverse_selected_area", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_alt_selected_area, function(e)
    raw_logger.log_event("on_player_alt_selected_area", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_ammo_inventory_changed, function(e)
    raw_logger.log_event("on_player_ammo_inventory_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_armor_inventory_changed, function(e)
    raw_logger.log_event("on_player_armor_inventory_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_banned, function(e)
    raw_logger.log_event("on_player_banned", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_cancelled_crafting, function(e)
    raw_logger.log_event("on_player_cancelled_crafting", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_changed_force, function(e)
    raw_logger.log_event("on_player_changed_force", e)
  end)
  
  -- event_dispatcher.register_handler(defines.events.on_player_changed_position, function(e)
  --   raw_logger.log_event("on_player_changed_position", e)
  -- end)
  
  event_dispatcher.register_handler(defines.events.on_player_changed_surface, function(e)
    raw_logger.log_event("on_player_changed_surface", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_cheat_mode_disabled, function(e)
    raw_logger.log_event("on_player_cheat_mode_disabled", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_cheat_mode_enabled, function(e)
    raw_logger.log_event("on_player_cheat_mode_enabled", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_clicked_gps_tag, function(e)
    raw_logger.log_event("on_player_clicked_gps_tag", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_configured_blueprint, function(e)
    raw_logger.log_event("on_player_configured_blueprint", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_configured_spider_remote, function(e)
    raw_logger.log_event("on_player_configured_spider_remote", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_crafted_item, function(e)
    raw_logger.log_event("on_player_crafted_item", e)
  end)
  
  -- event_dispatcher.register_handler(defines.events.on_player_created, function(e)
  --   raw_logger.log_event("on_player_created", e)
  -- end)
  
  event_dispatcher.register_handler(defines.events.on_player_cursor_stack_changed, function(e)
    raw_logger.log_event("on_player_cursor_stack_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_demoted, function(e)
    raw_logger.log_event("on_player_demoted", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_died, function(e)
    raw_logger.log_event("on_player_died", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_display_resolution_changed, function(e)
    raw_logger.log_event("on_player_display_resolution_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_display_scale_changed, function(e)
    raw_logger.log_event("on_player_display_scale_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_driving_changed_state, function(e)
    raw_logger.log_event("on_player_driving_changed_state", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_dropped_item, function(e)
    raw_logger.log_event("on_player_dropped_item", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_fast_transferred, function(e)
    raw_logger.log_event("on_player_fast_transferred", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_flushed_fluid, function(e)
    raw_logger.log_event("on_player_flushed_fluid", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_gun_inventory_changed, function(e)
    raw_logger.log_event("on_player_gun_inventory_changed", e)
  end)
  
  -- event_dispatcher.register_handler(defines.events.on_player_input_method_changed, function(e)
  --   raw_logger.log_event("on_player_input_method_changed", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_player_joined_game, function(e)
  --   raw_logger.log_event("on_player_joined_game", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_player_kicked, function(e)
  --   raw_logger.log_event("on_player_kicked", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_player_left_game, function(e)
  --   raw_logger.log_event("on_player_left_game", e)
  -- end)
  
  event_dispatcher.register_handler(defines.events.on_player_main_inventory_changed, function(e)
    raw_logger.log_event("on_player_main_inventory_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_mined_entity, function(e)
    raw_logger.log_event("on_player_mined_entity", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_mined_item, function(e)
    raw_logger.log_event("on_player_mined_item", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_mined_tile, function(e)
    raw_logger.log_event("on_player_mined_tile", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_muted, function(e)
    raw_logger.log_event("on_player_muted", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_pipette, function(e)
    raw_logger.log_event("on_player_pipette", e)
  end)
  
  -- event_dispatcher.register_handler(defines.events.on_player_promoted, function(e)
  --   raw_logger.log_event("on_player_promoted", e)
  -- end)
  
  -- event_dispatcher.register_handler(defines.events.on_player_removed, function(e)
  --   raw_logger.log_event("on_player_removed", e)
  -- end)
  
  event_dispatcher.register_handler(defines.events.on_player_repaired_entity, function(e)
    raw_logger.log_event("on_player_repaired_entity", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_respawned, function(e)
    raw_logger.log_event("on_player_respawned", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_reverse_selected_area, function(e)
    raw_logger.log_event("on_player_reverse_selected_area", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_rotated_entity, function(e)
    raw_logger.log_event("on_player_rotated_entity", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_selected_area, function(e)
    raw_logger.log_event("on_player_selected_area", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_set_quick_bar_slot, function(e)
    raw_logger.log_event("on_player_set_quick_bar_slot", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_setup_blueprint, function(e)
    raw_logger.log_event("on_player_setup_blueprint", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_toggled_alt_mode, function(e)
    raw_logger.log_event("on_player_toggled_alt_mode", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_toggled_map_editor, function(e)
    raw_logger.log_event("on_player_toggled_map_editor", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_trash_inventory_changed, function(e)
    raw_logger.log_event("on_player_trash_inventory_changed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_unbanned, function(e)
    raw_logger.log_event("on_player_unbanned", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_unmuted, function(e)
    raw_logger.log_event("on_player_unmuted", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_used_capsule, function(e)
    raw_logger.log_event("on_player_used_capsule", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_used_spider_remote, function(e)
    raw_logger.log_event("on_player_used_spider_remote", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_player_crafted_item, function(e)
    raw_logger.log_event("on_pre_player_crafted_item", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_player_died, function(e)
    raw_logger.log_event("on_pre_player_died", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_player_left_game, function(e)
    raw_logger.log_event("on_pre_player_left_game", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_player_mined_item, function(e)
    raw_logger.log_event("on_pre_player_mined_item", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_player_removed, function(e)
    raw_logger.log_event("on_pre_player_removed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_player_toggled_map_editor, function(e)
    raw_logger.log_event("on_pre_player_toggled_map_editor", e)
  end)
  
  -- Research events
  event_dispatcher.register_handler(defines.events.on_research_cancelled, function(e)
    raw_logger.log_event("on_research_cancelled", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_research_finished, function(e)
    raw_logger.log_event("on_research_finished", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_research_reversed, function(e)
    raw_logger.log_event("on_research_reversed", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_research_started, function(e)
    raw_logger.log_event("on_research_started", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_technology_effects_reset, function(e)
    raw_logger.log_event("on_technology_effects_reset", e)
  end)
  
  -- Resource events
  event_dispatcher.register_handler(defines.events.on_resource_depleted, function(e)
    raw_logger.log_event("on_resource_depleted", e)
  end)
  
  -- Robot events
  event_dispatcher.register_handler(defines.events.on_robot_exploded_cliff, function(e)
    raw_logger.log_event("on_robot_exploded_cliff", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_robot_mined, function(e)
    raw_logger.log_event("on_robot_mined", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_robot_mined_entity, function(e)
    raw_logger.log_event("on_robot_mined_entity", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_robot_mined_tile, function(e)
    raw_logger.log_event("on_robot_mined_tile", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_robot_pre_mined, function(e)
    raw_logger.log_event("on_robot_pre_mined", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_robot_exploded_cliff, function(e)
    raw_logger.log_event("on_pre_robot_exploded_cliff", e)
  end)
  
  -- Rocket events
  event_dispatcher.register_handler(defines.events.on_rocket_launch_ordered, function(e)
    raw_logger.log_event("on_rocket_launch_ordered", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_rocket_launched, function(e)
    raw_logger.log_event("on_rocket_launched", e)
  end)
  
  -- Script events
  event_dispatcher.register_handler(defines.events.on_script_inventory_resized, function(e)
    raw_logger.log_event("on_script_inventory_resized", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_script_path_request_finished, function(e)
    raw_logger.log_event("on_script_path_request_finished", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_script_trigger_effect, function(e)
    raw_logger.log_event("on_script_trigger_effect", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_script_inventory_resized, function(e)
    raw_logger.log_event("on_pre_script_inventory_resized", e)
  end)
  
  -- String translation events
  event_dispatcher.register_handler(defines.events.on_string_translated, function(e)
    raw_logger.log_event("on_string_translated", e)
  end)
  
  -- Tick events
  -- event_dispatcher.register_handler(defines.events.on_tick, function(e)
  --   raw_logger.log_event("on_tick", e)
  -- end)
  
  -- Train events
  event_dispatcher.register_handler(defines.events.on_train_changed_state, function(e)
    raw_logger.log_event("on_train_changed_state", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_train_created, function(e)
    raw_logger.log_event("on_train_created", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_train_schedule_changed, function(e)
    raw_logger.log_event("on_train_schedule_changed", e)
  end)
  
  -- Script raised events
  event_dispatcher.register_handler(defines.events.script_raised_built, function(e)
    raw_logger.log_event("script_raised_built", e)
  end)
  
  event_dispatcher.register_handler(defines.events.script_raised_destroy, function(e)
    raw_logger.log_event("script_raised_destroy", e)
  end)
  
  event_dispatcher.register_handler(defines.events.script_raised_revive, function(e)
    raw_logger.log_event("script_raised_revive", e)
  end)
  
  event_dispatcher.register_handler(defines.events.script_raised_set_tiles, function(e)
    raw_logger.log_event("script_raised_set_tiles", e)
  end)
  
  event_dispatcher.register_handler(defines.events.script_raised_teleported, function(e)
    raw_logger.log_event("script_raised_teleported", e)
  end)
end

-- ============================================================================
-- SCRIPT INITIALIZATION
-- ============================================================================
script.on_init(function()
  -- Initialize buffer for raw events
  shared_utils.initialize_category_buffer("raw_events")
  
  log('[raw-events-logger] Raw events logging armed')
  log('[raw-events-logger] Writing to raw_events.jsonl')
  log('[tick-overlay] Tick overlay enabled for replays and multiplayer')
end)

script.on_load(function()
  -- Initialize buffer on load
  shared_utils.initialize_category_buffer("raw_events")
end)

-- ============================================================================
-- SYSTEM HANDLERS
-- ============================================================================
function main.register_system_handlers()
  -- Periodic flush using dispatcher
  event_dispatcher.register_nth_tick_handler(FLUSH_EVERY, function()
    shared_utils.flush_all_buffers()
  end)
  
  -- Flush on game end
  event_dispatcher.register_handler(defines.events.on_pre_player_left_game, function(event)
    shared_utils.flush_all_buffers()
  end)
end

-- Initialize the raw event logger
main.initialize()
main.register_system_handlers()

-- ============================================================================
-- LEGACY MODULES (NEVER REMOVE)
-- ============================================================================
local handler = require("event_handler")
handler.add_lib(require("freeplay"))
handler.add_lib(require("silo-script")) 