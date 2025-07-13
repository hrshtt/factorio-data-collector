--@player_inventory_transfers.lua
--@description Player inventory transfers action logger, logs insert_item and extract_item
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local player_inventory_transfers = {}
local shared_utils = require("script.shared-utils")
local logistics = require("script.logistics")

-- =============================== log schema ===============================
-- insert_item: entity, item, count, event_name (gui, fast_transfer, selected_entity_changed)
-- extract_item: entity, item, count, event_name (gui, fast_transfer, selected_entity_changed)
-- =============================== log schema ===============================

-- Storage for tracking sessions
local sessions = {}

-- Helper function to generate session key
local function get_session_key(tick, selected_name, selected_x, selected_y)
  return tick .. ":" .. selected_name .. ":" .. selected_x .. ":" .. selected_y
end

-- Helper function to create a transfer record
local function create_transfer_record(player, action_type, entity, item_deltas, event_name)
  local rec = shared_utils.create_base_record("player_inventory_transfers", {
    name = defines.events.on_player_fast_transferred,
    tick = game.tick,
    player_index = player.index
  })
  
  rec.action = action_type -- "insert_item" or "extract_item"
  rec.event_name = event_name
  rec.entity = entity.name
  rec.entity_x = string.format("%.1f", entity.position.x)
  rec.entity_y = string.format("%.1f", entity.position.y)
  rec.items = {}
  
  -- Convert item deltas to transfer records
  for item_name, delta in pairs(item_deltas) do
    if delta ~= 0 then
      table.insert(rec.items, {
        item = item_name,
        count = math.abs(delta)
      })
    end
  end
  
  shared_utils.add_player_context_if_missing(rec, player)
  return rec
end

-- Helper function to finalize a session
local function finalize_session(session_key, end_tick, from_player)
  local session = sessions[session_key]
  if not session then return end
  
  local player = game.players[session.player_index]
  if not player or not player.valid then
    sessions[session_key] = nil
    return
  end
  
  local entity = session.entity
  if not entity or not entity.valid then
    sessions[session_key] = nil
    return
  end
  
  -- Get current inventory state
  local inventory_index = logistics.find_primary_inventory_index(entity)
  if not inventory_index then
    sessions[session_key] = nil
    return
  end
  
  local current_contents = logistics.get_inventory_contents_by_holder(entity, inventory_index)
  local item_deltas = logistics.diff_tables(session.inventory_snapshot, current_contents)
  
  -- Only log if there are actual changes and we have transfer direction info
  if next(item_deltas) and from_player ~= nil then
    local action_type = "insert_item"
    if from_player == false then
      action_type = "extract_item"
    end
    
    local rec = create_transfer_record(player, action_type, entity, item_deltas, "fast_transfer")
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("player_inventory_transfers", line)
  end
  
  -- Clean up the session
  sessions[session_key] = nil
end

-- Handler for when player selects an entity
local function on_selected_entity_changed(event)
  if not shared_utils.is_player_event(event) then return end
  
  local player = game.players[event.player_index]
  if not player or not player.valid then return end
  
  -- Get player context to find selected entity
  local context = shared_utils.get_player_context(player)
  if not context.selected then return end
  
  -- Find the selected entity
  local selected_entity = player.selected
  if not selected_entity or not selected_entity.valid then return end
  
  -- Only track player-accessible entities
  if not logistics.is_player_accessible(selected_entity) then return end
  
  -- Create session key
  local session_key = get_session_key(event.tick, context.selected, context.selected_x, context.selected_y)
  
  -- Get inventory snapshot
  local inventory_index = logistics.find_primary_inventory_index(selected_entity)
  if not inventory_index then return end
  
  local inventory_snapshot = logistics.get_inventory_contents_by_holder(selected_entity, inventory_index)
  
  -- Create new session
  sessions[session_key] = {
    player_index = event.player_index,
    entity = selected_entity,
    inventory_snapshot = inventory_snapshot,
    start_tick = event.tick,
    last_activity_tick = event.tick
  }
end

-- Handler for fast transfer
local function on_player_fast_transferred(event)
  if not shared_utils.is_player_event(event) then return end
  
  local player = game.players[event.player_index]
  if not player or not player.valid then return end
  
  -- Get player context to find selected entity
  local context = shared_utils.get_player_context(player)
  if not context.selected then return end
  
  -- Find matching session - we need to check recent sessions since the exact tick might not match
  local matching_session = nil
  local matching_key = nil
  
  for session_key, session in pairs(sessions) do
    if session.player_index == event.player_index and 
       session.entity and session.entity.valid and
       session.entity == player.selected then
      matching_session = session
      matching_key = session_key
      break
    end
  end
  
  if matching_session then
    -- Update activity and finalize the session
    matching_session.last_activity_tick = event.tick
    finalize_session(matching_key, event.tick, event.from_player)
  end
end

-- Clean up sessions for disconnected players
local function on_player_left_game(event)
  local player_index = event.player_index
  
  -- Finalize any active sessions for this player
  for session_key, session in pairs(sessions) do
    if session.player_index == player_index then
      finalize_session(session_key, event.tick, nil)
    end
  end
end

-- Clean up sessions periodically to prevent memory leaks
local function cleanup_old_sessions()
  local current_tick = game.tick
  -- Keep sessions alive for only 300 ticks as requested
  local timeout_ticks = 300

  for session_key, session in pairs(sessions) do
    if (current_tick - session.last_activity_tick) >= timeout_ticks then
      -- Timeout - clean up without logging
      sessions[session_key] = nil
    end
  end
end

function player_inventory_transfers.register_events(event_dispatcher)
  -- Register the main events
  event_dispatcher.register_handler(defines.events.on_selected_entity_changed, on_selected_entity_changed)
  event_dispatcher.register_handler(defines.events.on_player_fast_transferred, on_player_fast_transferred)
  
  -- Register cleanup events
  event_dispatcher.register_handler(defines.events.on_player_left_game, on_player_left_game)
  
  -- Register periodic cleanup (every 300 ticks = 5 seconds)
  event_dispatcher.register_nth_tick_handler(300, cleanup_old_sessions)
end

-- Initialize storage on script load
function player_inventory_transfers.on_init()
  if not global.player_inventory_transfers then
    global.player_inventory_transfers = {
      sessions = {}
    }
  end
  sessions = global.player_inventory_transfers.sessions
end

function player_inventory_transfers.on_load()
  if global.player_inventory_transfers then
    sessions = global.player_inventory_transfers.sessions
  end
end

return player_inventory_transfers