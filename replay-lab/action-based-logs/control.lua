--@control.lua
--@description Actions-based Player Action Logger to jsonl
--@author Harshit Sharma
--@version 2.0.0
--@date 2025-01-27
--@license MIT
--@category Other
--@tags player, logger, replay, factorio, actions, fle

-- ============================================================================
-- MODULE IMPORTS
-- ============================================================================
local shared_utils = require("script.shared-utils")
local tick_overlay = require("script.tick_overlay")

-- Core actions
local craft_item = require("script.actions.craft_item")
local extract_item = require("script.actions.extract_item")
local harvest_resource = require("script.actions.harvest_resource")
local insert_item = require("script.actions.insert_item")
local launch_rocket = require("script.actions.launch_rocket")
local move_to = require("script.actions.move_to")
local pickup_entity = require("script.actions.pickup_entity")
local place_entity = require("script.actions.place_entity")
local rotate_entity = require("script.actions.rotate_entity")
local send_message = require("script.actions.send_message")
local set_entity_recipe = require("script.actions.set_entity_recipe")
local set_research = require("script.actions.set_research")

-- Observation actions
local get_entities = require("script.actions.get_entities")
local get_research_progress = require("script.actions.get_research_progress")
local inspect_inventory = require("script.actions.inspect_inventory")
local score = require("script.actions.score")
local get_resource_patch = require("script.actions.get_resource_patch")

-- Optional observation actions
local get_entity = require("script.actions.get_entity")
local print_action = require("script.actions.print_action")
local get_prototype_recipe = require("script.actions.get_prototype_recipe")

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
  -- Register events for each action module
  core_meta.register_events()
  tick_overlay.register_events()
  
  -- Core actions
  craft_item.register_events()
  extract_item.register_events()
  harvest_resource.register_events()
  insert_item.register_events()
  launch_rocket.register_events()
  move_to.register_events()
  pickup_entity.register_events()
  place_entity.register_events()
  rotate_entity.register_events()
  send_message.register_events()
  set_entity_recipe.register_events()
  set_research.register_events()
  
  -- Observation actions
  get_entities.register_events()
  get_research_progress.register_events()
  inspect_inventory.register_events()
  score.register_events()
  get_resource_patch.register_events()
  
  -- Optional observation actions
  get_entity.register_events()
  print_action.register_events()
  get_prototype_recipe.register_events()
end

-- ============================================================================
-- SCRIPT INITIALIZATION
-- ============================================================================
script.on_init(function()
  -- Initialize category buffers for all actions
  shared_utils.initialize_category_buffer("core-meta")
  shared_utils.initialize_category_buffer("craft_item")
  shared_utils.initialize_category_buffer("extract_item")
  shared_utils.initialize_category_buffer("harvest_resource")
  shared_utils.initialize_category_buffer("insert_item")
  shared_utils.initialize_category_buffer("launch_rocket")
  shared_utils.initialize_category_buffer("move_to")
  shared_utils.initialize_category_buffer("pickup_entity")
  shared_utils.initialize_category_buffer("place_entity")
  shared_utils.initialize_category_buffer("rotate_entity")
  shared_utils.initialize_category_buffer("send_message")
  shared_utils.initialize_category_buffer("set_entity_recipe")
  shared_utils.initialize_category_buffer("set_research")
  shared_utils.initialize_category_buffer("get_entities")
  shared_utils.initialize_category_buffer("get_research_progress")
  shared_utils.initialize_category_buffer("inspect_inventory")
  shared_utils.initialize_category_buffer("score")
  shared_utils.initialize_category_buffer("get_resource_patch")
  shared_utils.initialize_category_buffer("get_entity")
  shared_utils.initialize_category_buffer("print_action")
  shared_utils.initialize_category_buffer("get_prototype_recipe")
  
  log('[actions-based-logger] Action-based logging armed')
  log('[actions-based-logger] Writing to individual action jsonl files')
  log('[tick-overlay] Tick overlay enabled for replays and multiplayer')
end)

script.on_load(function()
  -- Initialize category buffers on load
  shared_utils.initialize_category_buffer("core-meta")
  shared_utils.initialize_category_buffer("craft_item")
  shared_utils.initialize_category_buffer("extract_item")
  shared_utils.initialize_category_buffer("harvest_resource")
  shared_utils.initialize_category_buffer("insert_item")
  shared_utils.initialize_category_buffer("launch_rocket")
  shared_utils.initialize_category_buffer("move_to")
  shared_utils.initialize_category_buffer("pickup_entity")
  shared_utils.initialize_category_buffer("place_entity")
  shared_utils.initialize_category_buffer("rotate_entity")
  shared_utils.initialize_category_buffer("send_message")
  shared_utils.initialize_category_buffer("set_entity_recipe")
  shared_utils.initialize_category_buffer("set_research")
  shared_utils.initialize_category_buffer("get_entities")
  shared_utils.initialize_category_buffer("get_research_progress")
  shared_utils.initialize_category_buffer("inspect_inventory")
  shared_utils.initialize_category_buffer("score")
  shared_utils.initialize_category_buffer("get_resource_patch")
  shared_utils.initialize_category_buffer("get_entity")
  shared_utils.initialize_category_buffer("print_action")
  shared_utils.initialize_category_buffer("get_prototype_recipe")
end)

-- Periodic flush every FLUSH_EVERY ticks
script.on_nth_tick(FLUSH_EVERY, function()
  shared_utils.flush_all_buffers()
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

-- Initialize the action-based logger
main.initialize()

-- ============================================================================
-- LEGACY MODULES (UNCHANGED)
-- ============================================================================
local handler = require("event_handler")
handler.add_lib(require("freeplay"))
handler.add_lib(require("silo-script")) 