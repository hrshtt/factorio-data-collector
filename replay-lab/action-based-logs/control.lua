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
local craft_item_collated = require("script.actions.craft_item_collated")
local harvest_resource_collated = require("script.actions.harvest_resource_collated")
local launch_rocket = require("script.actions.launch_rocket")
local pickup_entity = require("script.actions.pickup_entity")
local place_entity = require("script.actions.place_entity")
local rotate_entity = require("script.actions.rotate_entity")
local send_message = require("script.actions.send_message")
local set_entity_recipe = require("script.actions.set_entity_recipe")
local set_research = require("script.actions.set_research")
local player_inventory_transfers = require("script.actions.player_inventory_transfers")

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
local move_to_collated = require("script.actions.move_to_collated")

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
-- CORE-META EVENT HANDLERS
-- ============================================================================
local core_meta = {}

function core_meta.log_event(event_name, e)
  local player = game.players[e.player_index]
  local rec = shared_utils.create_base_record(event_name, e, player)
  local extractor = core_meta.get_extractor(event_name)
  extractor(e, rec, player)
  local clean_rec = shared_utils.clean_record(rec)
  local line = game.table_to_json(clean_rec)
  shared_utils.buffer_event("core-meta", line)
end

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
-- MAIN MODULE - EVENT REGISTRATION
-- ============================================================================
local main = {}

function main.initialize()
  -- Register core-meta events using dispatcher
  event_dispatcher.register_handler(defines.events.on_player_joined_game, function(e)
    core_meta.log_event("on_player_joined_game", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_player_left_game, function(e)
    core_meta.log_event("on_player_left_game", e)
  end)
  
  event_dispatcher.register_handler(defines.events.on_pre_player_left_game, function(e)
    core_meta.log_event("on_pre_player_left_game", e)
  end)
  
  -- Register tick overlay events
  tick_overlay.register_events(event_dispatcher)
  
  -- Register action module handlers
  craft_item_collated.register_events(event_dispatcher)
  harvest_resource_collated.register_events(event_dispatcher)
  launch_rocket.register_events(event_dispatcher)
  move_to_collated.register_events(event_dispatcher)
  pickup_entity.register_events(event_dispatcher)
  place_entity.register_events(event_dispatcher)
  rotate_entity.register_events(event_dispatcher)
  send_message.register_events(event_dispatcher)
  set_entity_recipe.register_events(event_dispatcher)
  set_research.register_events(event_dispatcher)
  player_inventory_transfers.register_events(event_dispatcher)
  
  -- Observation actions
  get_entities.register_events(event_dispatcher)
  get_research_progress.register_events(event_dispatcher)
  inspect_inventory.register_events(event_dispatcher)
  score.register_events(event_dispatcher)
  get_resource_patch.register_events(event_dispatcher)
  
  -- Optional observation actions
  get_entity.register_events(event_dispatcher)
  print_action.register_events(event_dispatcher)
  get_prototype_recipe.register_events(event_dispatcher)
end

-- ============================================================================
-- SCRIPT INITIALIZATION
-- ============================================================================
script.on_init(function()
  -- Initialize category buffers for all actions
  shared_utils.initialize_category_buffer("core-meta")
  shared_utils.initialize_category_buffer("craft_item")
  shared_utils.initialize_category_buffer("craft_item_collated")
  shared_utils.initialize_category_buffer("extract_item")
  shared_utils.initialize_category_buffer("harvest_resource")
  shared_utils.initialize_category_buffer("harvest_resource_collated")
  shared_utils.initialize_category_buffer("insert_item")
  shared_utils.initialize_category_buffer("insert_item_collated")
  shared_utils.initialize_category_buffer("launch_rocket")
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
  shared_utils.initialize_category_buffer("move_to_collated")
  shared_utils.initialize_category_buffer("player_inventory_transfers")
  
  -- Initialize collated modules
  craft_item_collated.on_init()
  -- insert_item_collated.on_init()
  move_to_collated.on_init()
  
  log('[actions-based-logger] Action-based logging armed')
  log('[actions-based-logger] Writing to individual action jsonl files')
  log('[tick-overlay] Tick overlay enabled for replays and multiplayer')
end)

script.on_load(function()
  -- Initialize category buffers on load
  shared_utils.initialize_category_buffer("core-meta")
  shared_utils.initialize_category_buffer("craft_item")
  shared_utils.initialize_category_buffer("craft_item_collated")
  shared_utils.initialize_category_buffer("extract_item")
  shared_utils.initialize_category_buffer("harvest_resource")
  shared_utils.initialize_category_buffer("harvest_resource_collated")
  shared_utils.initialize_category_buffer("insert_item")
  shared_utils.initialize_category_buffer("insert_item_collated")
  shared_utils.initialize_category_buffer("launch_rocket")
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
  shared_utils.initialize_category_buffer("move_to_collated")
  shared_utils.initialize_category_buffer("player_inventory_transfers")
  -- Initialize collated modules
  craft_item_collated.on_load()
  move_to_collated.on_load()
end)



-- ============================================================================
-- REPLAY MARKERS & COLLATION PROCESSING
-- ============================================================================
-- Register additional system handlers after module initialization
function main.register_system_handlers()
  -- First-tick detection (headless or local view) + collated event processing
  event_dispatcher.register_handler(defines.events.on_tick, function(event)
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
    
    -- Process collated harvest resource events
    -- harvest_resource_collated.process_partial_mining(event)
  end)

  -- Replay end detection when player leaves
  event_dispatcher.register_handler(defines.events.on_pre_player_left_game, function(event)
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
  
  -- Periodic flush using dispatcher
  event_dispatcher.register_nth_tick_handler(FLUSH_EVERY, function()
    shared_utils.flush_all_buffers()
  end)
end

-- Initialize the action-based logger
main.initialize()
main.register_system_handlers()

-- ============================================================================
-- LEGACY MODULES (NEVER REMOVE)
-- ============================================================================
local handler = require("event_handler")
handler.add_lib(require("freeplay"))
handler.add_lib(require("silo-script"))