--@control.lua
--@description Enhanced Player Action Logger to jsonl - Category-based
--@author Harshit Sharma
--@version 2.0.0
--@date 2025-01-27
--@license MIT
--@category Other
--@tags player, logger, replay, factorio, categories

-- ============================================================================
-- MODULE IMPORTS
-- ============================================================================
local shared_utils = require("shared-utils")
local movement = require("movement")
local production = require("production")
local gui = require("gui")
local construction = require("construction")
local tick_overlay = require("tick_overlay")

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local FLUSH_EVERY = 600        -- 10 s at 60 UPS

-- ============================================================================
-- CORE-META LOGGING (handled in control.lua)
-- ============================================================================
local core_meta = {}

function core_meta.log_event(event_name, event_data)
  local player = event_data.player_index and game.players[event_data.player_index]
  
  -- Create base record
  local rec = shared_utils.create_base_record(event_name, event_data)
  
  -- Apply event-specific context extraction
  local extractor = core_meta.get_extractor(event_name)
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
  
  -- Buffer to core-meta category
  shared_utils.buffer_event("core-meta", line)
end

-- ============================================================================
-- CORE-META CONTEXT EXTRACTORS
-- ============================================================================
function core_meta.on_player_joined_game(e, rec, player)
  rec.action = "join_game"
end

function core_meta.on_player_left_game(e, rec, player)
  rec.action = "left_game"
end

function core_meta.on_pre_player_left_game(e, rec, player)
  rec.action = "leaving_game"
  rec.reason = e.reason -- disconnect reason
end

function core_meta.get_extractor(event_name)
  return core_meta[event_name] or function() end -- Default no-op
end

-- ============================================================================
-- CORE-META EVENT REGISTRATION
-- ============================================================================
function core_meta.register_events()
  -- Register core-meta events
  script.on_event(defines.events.on_player_joined_game, function(e)
    core_meta.log_event("on_player_joined_game", e)
  end)
  
  script.on_event(defines.events.on_player_left_game, function(e)
    core_meta.log_event("on_player_left_game", e)
  end)
  
  script.on_event(defines.events.on_pre_player_left_game, function(e)
    core_meta.log_event("on_pre_player_left_game", e)
  end)
end

-- ============================================================================
-- MAIN MODULE - EVENT REGISTRATION
-- ============================================================================
local main = {}

function main.initialize()
  -- Register events for each category module
  core_meta.register_events()
  movement.register_events()
  production.register_events()
  gui.register_events()
  construction.register_events()
  tick_overlay.register_events()
end

-- ============================================================================
-- SCRIPT INITIALIZATION
-- ============================================================================
script.on_init(function()
  -- Initialize category buffers
  shared_utils.initialize_category_buffer("core-meta")
  shared_utils.initialize_category_buffer("movement")
  shared_utils.initialize_category_buffer("production")
  shared_utils.initialize_category_buffer("gui")
  shared_utils.initialize_category_buffer("construction")
  
  log('[enhanced-player-logger] Category-based logging armed')
  log('[enhanced-player-logger] Writing to: core-meta.jsonl, movement.jsonl, production.jsonl, gui.jsonl, construction.jsonl')
  log('[tick-overlay] Tick overlay enabled for replays and multiplayer')
end)

script.on_load(function()
  -- Initialize category buffers on load
  shared_utils.initialize_category_buffer("core-meta")
  shared_utils.initialize_category_buffer("movement")
  shared_utils.initialize_category_buffer("production")
  shared_utils.initialize_category_buffer("gui")
  shared_utils.initialize_category_buffer("construction")
end)

-- Periodic flush every FLUSH_EVERY ticks
script.on_nth_tick(FLUSH_EVERY, function()
  shared_utils.flush_all_buffers()
  
  -- Clean up old inventory snapshots to prevent memory bloat
  if production and production.cleanup_snapshots then
    production.cleanup_snapshots()
  end
end)

-- ============================================================================
-- REPLAY MARKERS
-- ============================================================================
-- First-tick detection (headless or local view)
script.on_event(defines.events.on_tick, function(event)
  -- First tick detection for replay start
  if event.tick == 1 then
    log('[REPLAY-START] First tick detected, replay begins')
    -- Log replay start marker
    local rec = {
      t = event.tick,
      msg = "REPLAY-START"
    }
    local line = game.table_to_json(rec)
    shared_utils.buffer_event("core-meta", line)
  end
end)

-- Replay end detection when player leaves
script.on_event(defines.events.on_pre_player_left_game, function(event)
  log('[REPLAY-END] Player leaving game, replay ends at tick ' .. event.tick)
  -- Log replay end marker
  local rec = {
    t = event.tick,
    msg = "REPLAY-END"
  }
  local line = game.table_to_json(rec)
  shared_utils.buffer_event("core-meta", line)
  -- Flush all buffers
  shared_utils.flush_all_buffers()
end)

-- Initialize the modular logger
main.initialize()

-- ============================================================================
-- LEGACY MODULES (UNCHANGED)
-- ============================================================================
local handler = require("event_handler")
handler.add_lib(require("freeplay"))
handler.add_lib(require("silo-script"))