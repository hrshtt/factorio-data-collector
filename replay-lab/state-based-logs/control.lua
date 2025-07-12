--@control.lua
--@description Central event dispatcher for domain-based logging
--@author Harshit Sharma
--@version 3.0.0
--@date 2025-01-27
--@license MIT

-- ============================================================================
-- MODULE IMPORTS
-- ============================================================================
local shared_utils = require("script.shared-utils")
local map = require("script.map")
local entity = require("script.entity")
local player = require("script.player")
local player_inventory = require("script.player_inventory")
local research = require("script.research")
local tick_overlay = require("script.tick_overlay")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local FLUSH_EVERY = 600        -- 10 s at 60 UPS

-- ============================================================================
-- EVENT DOMAIN MAPPINGS
-- ============================================================================

-- Pure mutations (single domain)
local map_only = {
--   defines.events.on_chunk_generated,
--   defines.events.on_chunk_deleted,
--   defines.events.on_chunk_charted,
  defines.events.on_area_cloned,
  defines.events.on_brush_cloned,
  defines.events.on_pre_chunk_deleted,
--   defines.events.on_surface_created,
--   defines.events.on_surface_cleared,
--   defines.events.on_surface_deleted,
--   defines.events.on_surface_renamed,
  defines.events.on_sector_scanned,
}

local entity_only = {
  defines.events.on_entity_settings_pasted,
  defines.events.on_entity_logistic_slot_changed,
  defines.events.on_entity_color_changed,
  defines.events.on_entity_renamed,
  defines.events.on_equipment_inserted,
  defines.events.on_equipment_removed,
--   defines.events.on_entity_damaged,
  defines.events.on_ai_command_completed,
}

local player_only = {
  defines.events.on_player_cursor_stack_changed,
  defines.events.on_player_changed_position,
  defines.events.on_player_changed_surface,
}

-- Player inventory events (handled by player_inventory module)
local player_inventory_events = {
  -- PRE/POST pairs (require buffering)
  defines.events.on_pre_player_mined_item,
  defines.events.on_player_mined_entity,
  defines.events.on_player_mined_item, 
  defines.events.on_player_mined_tile,
  defines.events.on_pre_build,
  defines.events.on_built_entity,
  defines.events.on_pre_player_crafted_item,
  defines.events.on_player_crafted_item,
  
  -- Single-shot events  
  defines.events.on_player_fast_transferred,
  defines.events.on_picked_up_item,
  defines.events.on_player_dropped_item,
  defines.events.on_player_placed_equipment,
  defines.events.on_player_removed_equipment,
  defines.events.on_player_repaired_entity,
  defines.events.on_market_item_purchased,
}

local research_only = {
  defines.events.on_research_started,
  defines.events.on_research_finished,
  defines.events.on_research_cancelled,
  defines.events.on_research_reversed,
  defines.events.on_technology_effects_reset,
}

-- Paired mutations (two-way couplings)
local map_player = {
  defines.events.on_player_built_tile,
}

local map_entity = {
  defines.events.on_entity_cloned,
  defines.events.on_entity_died,
  defines.events.on_post_entity_died,
  defines.events.on_resource_depleted,
}

local player_entity = {
  defines.events.on_player_rotated_entity,
  defines.events.on_player_flushed_fluid,
  defines.events.on_player_driving_changed_state,
  defines.events.on_player_used_spider_remote,
}

-- Core-meta events (handled in dispatcher)
local core_meta_events = {
  defines.events.on_player_joined_game,
  defines.events.on_player_left_game,
  -- Note: on_pre_player_left_game is handled separately for replay markers
}

-- ============================================================================
-- CENTRAL DISPATCHER
-- ============================================================================

function dispatch_to_domains(event_data, event_name)
  -- Skip invalid player events
  if event_data.player_index and not shared_utils.is_player_event(event_data) then
    return
  end
  
  -- Log the event once in the dispatcher for audit trail
  log(string.format("[DISPATCH] %s -> tick=%d player=%s", 
    event_name, 
    event_data.tick, 
    event_data.player_index or "nil"))
end

-- ============================================================================
-- EVENT REGISTRATION
-- ============================================================================

function register_all_events()
  -- Helper function to get event name from event ID
  local function get_event_name(event_id)
    for name, id in pairs(defines.events) do
      if id == event_id then
        return name
      end
    end
    return "unknown_event"
  end
  
  -- Register single-domain events
  for _, event_id in pairs(map_only) do
    script.on_event(event_id, function(e)
      local event_name = get_event_name(event_id)
      dispatch_to_domains(e, event_name)
      map.update(e, event_name)
    end)
  end
  
  for _, event_id in pairs(entity_only) do
    script.on_event(event_id, function(e)
      local event_name = get_event_name(event_id)
      dispatch_to_domains(e, event_name)
      entity.update(e, event_name)
    end)
  end
  
  for _, event_id in pairs(player_only) do
    script.on_event(event_id, function(e)
      local event_name = get_event_name(event_id)
      dispatch_to_domains(e, event_name)
      player.update(e, event_name)
    end)
  end
  
  for _, event_id in pairs(research_only) do
    script.on_event(event_id, function(e)
      local event_name = get_event_name(event_id)
      dispatch_to_domains(e, event_name)
      research.update(e, event_name)
    end)
  end
  
  for _, event_id in pairs(player_inventory_events) do
    script.on_event(event_id, function(e)
      local event_name = get_event_name(event_id)
      dispatch_to_domains(e, event_name)
      player_inventory.update(e, event_name)
    end)
  end
  
  -- Register two-domain events
  for _, event_id in pairs(map_player) do
    script.on_event(event_id, function(e)
      local event_name = get_event_name(event_id)
      dispatch_to_domains(e, event_name)
      map.update(e, event_name)
      player.update(e, event_name)
    end)
  end
  
  for _, event_id in pairs(map_entity) do
    script.on_event(event_id, function(e)
      local event_name = get_event_name(event_id)
      dispatch_to_domains(e, event_name)
      map.update(e, event_name)
      entity.update(e, event_name)
    end)
  end
  
  for _, event_id in pairs(player_entity) do
    script.on_event(event_id, function(e)
      local event_name = get_event_name(event_id)
      dispatch_to_domains(e, event_name)
      player.update(e, event_name)
      entity.update(e, event_name)
    end)
  end
  
  -- Register core-meta events (handled in dispatcher)
  for _, event_id in pairs(core_meta_events) do
    script.on_event(event_id, function(e)
      local event_name = get_event_name(event_id)
      handle_core_meta_event(e, event_name)
    end)
  end
end

-- ============================================================================
-- CORE-META EVENT HANDLING
-- ============================================================================

function handle_core_meta_event(event_data, event_name)
  local player = event_data.player_index and game.players[event_data.player_index]
  local rec = shared_utils.create_base_record(event_name, event_data)
  
  -- Add event-specific context
  if event_name == "on_player_joined_game" then
    rec.action = "join_game"
    -- Also initialize player inventory baseline
    player_inventory.handle_on_player_joined_game(event_data)
  elseif event_name == "on_player_left_game" then
    rec.action = "left_game"
  elseif event_name == "on_pre_player_left_game" then
    rec.action = "leaving_game"
    rec.reason = event_data.reason
  end
  
  shared_utils.add_player_context_if_missing(rec, player)
  local clean_rec = shared_utils.clean_record(rec)
  local line = game.table_to_json(clean_rec)
  shared_utils.buffer_event("core-meta", line)
end

-- ============================================================================
-- INVARIANT CHECKS
-- ============================================================================

function check_inventory_invariants(tick)
  -- This will be called periodically to validate that inventory deltas sum to zero
  -- TODO: Implement inventory balancing checks across all domains
  -- For now, just a placeholder for the concept
end

-- ============================================================================
-- SCRIPT INITIALIZATION
-- ============================================================================

script.on_init(function()
  -- Initialize domain buffers
  shared_utils.initialize_category_buffer("core-meta")
  shared_utils.initialize_category_buffer("map")
  shared_utils.initialize_category_buffer("entity")
  shared_utils.initialize_category_buffer("player")
  shared_utils.initialize_category_buffer("player_inventory")
  shared_utils.initialize_category_buffer("research")
  
  log('[domain-dispatcher] Domain-based logging initialized')
  log('[domain-dispatcher] Domains: core-meta, map, entity, player, player_inventory, research')
  log('[tick-overlay] Tick overlay enabled for replays and multiplayer')
end)

script.on_load(function()
  -- Initialize domain buffers on load
  shared_utils.initialize_category_buffer("core-meta")
  shared_utils.initialize_category_buffer("map")
  shared_utils.initialize_category_buffer("entity")
  shared_utils.initialize_category_buffer("player")
  shared_utils.initialize_category_buffer("player_inventory")
  shared_utils.initialize_category_buffer("research")
end)

-- Periodic flush and invariant checks
script.on_nth_tick(FLUSH_EVERY, function(event)
  shared_utils.flush_all_buffers()
  check_inventory_invariants(event.tick)
end)

-- ============================================================================
-- REPLAY MARKERS
-- ============================================================================

script.on_event(defines.events.on_tick, function(event)
  if event.tick == 1 then
    log('[REPLAY-START] First tick detected, replay begins')
    local rec = { t = event.tick, msg = "REPLAY-START" }
    local line = game.table_to_json(rec)
    shared_utils.buffer_event("core-meta", line)
  end
  
  -- Process player inventory diffs every tick
  player_inventory.process_tick(event.tick)
end)

script.on_event(defines.events.on_pre_player_left_game, function(event)
  log('[REPLAY-END] Player leaving game, replay ends at tick ' .. event.tick)
  local rec = { t = event.tick, msg = "REPLAY-END" }
  local line = game.table_to_json(rec)
  shared_utils.buffer_event("core-meta", line)
  shared_utils.flush_all_buffers()
end)

-- ============================================================================
-- INITIALIZE
-- ============================================================================

register_all_events()
tick_overlay.register_events()

-- ============================================================================
-- LEGACY MODULES (DO NOT REMOVE)
-- ============================================================================
local handler = require("event_handler")
handler.add_lib(require("freeplay"))
handler.add_lib(require("silo-script"))

