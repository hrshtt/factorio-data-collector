--@control.lua
--@description Observation-based logging to jsonl files
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27
--@license MIT
--@category Other
--@tags observation, logger, replay, factorio, fle

-- ============================================================================
-- MODULE IMPORTS
-- ============================================================================
local shared_utils = require("script.shared-utils")

-- Observation modules
local get_entities = require("script.observations.get_entities")
local get_research_progress = require("script.observations.get_research_progress")
local inspect_inventory = require("script.observations.inspect_inventory")
local nearest = require("script.observations.nearest")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local FLUSH_EVERY = 600        -- 10 s at 60 UPS
local OBSERVATION_INTERVALS = {
  get_entities = 60,           -- Every 1 seconds
  get_research_progress = 600,  -- Every 10 seconds
  inspect_inventory = 600,      -- Every 10 seconds
  nearest = 600                 -- Every 10 seconds
}

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
-- OBSERVATION LOGGING FUNCTIONS
-- ============================================================================
local observation_logger = {}

function observation_logger.log_get_entities(event)
  -- Log entities around each player
  for _, player in pairs(game.players) do
    if player.valid and player.connected then
      local rec = shared_utils.create_base_record("get_entities", event)
      rec.p = player.index
      
      -- Add player context
      shared_utils.add_player_context_if_missing(rec, player)
      
      -- Call the observation script with default parameters
      local radius = 100
      local entity_names_json = "[]"  -- Empty array for all entities
      local position_x = player.position.x
      local position_y = player.position.y
      
      local success, entities_result = pcall(get_entities.get_entities, player.index, radius, entity_names_json, position_x, position_y)
      
      if success then
        -- Parse the result and add to record
        rec.entities_raw = entities_result
      else
        rec.entities_error = entities_result
      end
      
      local clean_rec = shared_utils.clean_record(rec)
      local line = game.table_to_json(clean_rec)
      shared_utils.buffer_event("get_entities", line)
    end
  end
end

function observation_logger.log_get_research_progress(event)
  -- Log research progress for each force
  for _, force in pairs(game.forces) do
    local rec = shared_utils.create_base_record("get_research_progress", event)
    rec.force = force.name
    
    -- Only log for player forces
    if force.name == "player" then
    
    -- Call the observation script for each player in the force
    for _, player in pairs(game.players) do
      if player.valid and player.connected and player.force == force then
        rec.p = player.index
        
        -- Call the observation script with current research
        local technology_name = nil  -- nil means current research
        local success, research_result = pcall(get_research_progress.get_research_progress, player.index, technology_name)
        
        if success then
          -- Parse the result and add to record
          rec.research_raw = research_result
        else
          rec.research_error = research_result
        end
        
        local clean_rec = shared_utils.clean_record(rec)
        local line = game.table_to_json(clean_rec)
        shared_utils.buffer_event("get_research_progress", line)
      end
    end
    end
  end
end

function observation_logger.log_inspect_inventory(event)
  -- Log inventory contents for each player
  for _, player in pairs(game.players) do
    if player.valid and player.connected then
      local rec = shared_utils.create_base_record("inspect_inventory", event)
      rec.p = player.index
      
      -- Call the observation script for player inventory
      local is_character_inventory = true
      local x = player.position.x
      local y = player.position.y
      local entity = nil  -- nil for player inventory
      local all_players = false
      
      local success, inventory_result = pcall(inspect_inventory.inspect_inventory, player.index, is_character_inventory, x, y, entity, all_players)
      
      if success then
        -- Parse the result and add to record
        rec.inventory_raw = inventory_result
      else
        rec.inventory_error = inventory_result
      end
      
      local clean_rec = shared_utils.clean_record(rec)
      local line = game.table_to_json(clean_rec)
      shared_utils.buffer_event("inspect_inventory", line)
    end
  end
end

function observation_logger.log_nearest(event)
  -- Log nearest resources for each player
  for _, player in pairs(game.players) do
    if player.valid and player.connected then
      local rec = shared_utils.create_base_record("nearest", event)
      rec.p = player.index
      
      -- Find nearest common resources
      local resources = {"iron-ore", "copper-ore", "coal", "stone", "wood", "water"}
      local nearest_resources = {}
      
      for _, resource in ipairs(resources) do
        -- Call the observation script for each resource
        local success, nearest_result = pcall(nearest.nearest, player.index, resource)
        
        if success then
          -- Parse the result and add to record
          nearest_resources[resource] = nearest_result
        else
          nearest_resources[resource .. "_error"] = nearest_result
        end
      end
      
      rec.nearest_resources = nearest_resources
      
      local clean_rec = shared_utils.clean_record(rec)
      local line = game.table_to_json(clean_rec)
      shared_utils.buffer_event("nearest", line)
    end
  end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
local main = {}

function main.initialize()
  -- Initialize category buffers
  shared_utils.initialize_category_buffer("get_entities")
  shared_utils.initialize_category_buffer("get_research_progress")
  shared_utils.initialize_category_buffer("inspect_inventory")
  shared_utils.initialize_category_buffer("nearest")
  
  log('[observation-logs] Observation logging armed')
  log('[observation-logs] Writing to individual observation jsonl files')
end

function main.register_observation_handlers()
  -- Register periodic observation logging
  event_dispatcher.register_nth_tick_handler(OBSERVATION_INTERVALS.get_entities, observation_logger.log_get_entities)
  event_dispatcher.register_nth_tick_handler(OBSERVATION_INTERVALS.get_research_progress, observation_logger.log_get_research_progress)
  event_dispatcher.register_nth_tick_handler(OBSERVATION_INTERVALS.inspect_inventory, observation_logger.log_inspect_inventory)
  event_dispatcher.register_nth_tick_handler(OBSERVATION_INTERVALS.nearest, observation_logger.log_nearest)
  
  -- Register periodic flush
  event_dispatcher.register_nth_tick_handler(FLUSH_EVERY, function()
    shared_utils.flush_all_buffers()
  end)
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================
script.on_init(function()
  main.initialize()
  main.register_observation_handlers()
end)

script.on_load(function()
  -- Initialize category buffers on load
  shared_utils.initialize_category_buffer("get_entities")
  shared_utils.initialize_category_buffer("get_research_progress")
  shared_utils.initialize_category_buffer("inspect_inventory")
  shared_utils.initialize_category_buffer("nearest")
end)

-- ============================================================================
-- REPLAY MARKERS
-- ============================================================================
-- Register additional system handlers after module initialization
function main.register_system_handlers()
  -- First-tick detection for replay start
  event_dispatcher.register_handler(defines.events.on_tick, function(event)
    if event.tick == 1 then
      log('[REPLAY-START] First tick detected, replay begins')
      local rec = {
        t = event.tick,
        msg = "REPLAY-START"
      }
      local line = game.table_to_json(rec)
      shared_utils.buffer_event("core-meta", line)
    end
  end)

  -- Replay end detection when player leaves
  event_dispatcher.register_handler(defines.events.on_pre_player_left_game, function(event)
    log('[REPLAY-END] Player leaving game, replay ends at tick ' .. event.tick)
    local rec = {
      t = event.tick,
      msg = "REPLAY-END"
    }
    local line = game.table_to_json(rec)
    shared_utils.buffer_event("core-meta", line)
    -- Flush all buffers
    shared_utils.flush_all_buffers()
  end)
end

-- Initialize the observation logger
main.initialize()
main.register_observation_handlers()
main.register_system_handlers()

-- ============================================================================
-- LEGACY MODULES (NEVER REMOVE)
-- ============================================================================
local handler = require("event_handler")
handler.add_lib(require("freeplay"))
handler.add_lib(require("silo-script"))