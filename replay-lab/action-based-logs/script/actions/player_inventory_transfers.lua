--@player_inventory_transfers.lua
--@description Player inventory transfers action logger, logs insert_item and extract_item
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local player_inventory_transfers = {}
local shared_utils = require("script.shared-utils")
local logistics = require("script.logistics")


-- =========================
-- Fast Transfer Logic
-- =========================
local fast_transfer_logic = {}

-- Storage for tracking sessions
local sessions = {}

-- Helper function to generate session key
local function get_session_key(tick, selected_name, selected_x, selected_y)
  return tick .. ":" .. selected_name .. ":" .. selected_x .. ":" .. selected_y
end

-- Helper function to create a transfer record
local function create_transfer_record(player, action_type, entity, item_deltas, event_name, is_no_op)
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
  rec.no_op = is_no_op or false
  
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
  
  -- Get current combined inventory state (all relevant inventories)
  local current_contents = logistics.get_combined_inventory_contents(entity)
  local item_deltas = logistics.diff_tables(session.inventory_snapshot, current_contents)
  
  -- Always log the event, even if no items moved (with no_op flag)
  local has_changes = next(item_deltas) ~= nil
  local is_no_op = not has_changes
  
  if from_player ~= nil then
    local action_type = "insert_item"
    if from_player == false then
      action_type = "extract_item"
    end
    
    local rec = create_transfer_record(player, action_type, entity, item_deltas, "fast_transfer", is_no_op)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("player_inventory_transfers", line)
  end
  
  -- Instead of deleting the session, update it with fresh snapshot for next transfer
  if has_changes then
    session.inventory_snapshot = current_contents
    session.last_activity_tick = end_tick
  end
  
  -- Only clean up if the entity is no longer selected or player left
  local context = shared_utils.get_player_context(player)
  if not context.selected or context.selected ~= entity.name or 
     string.format("%.1f", entity.position.x) ~= context.selected_x or
     string.format("%.1f", entity.position.y) ~= context.selected_y then
    sessions[session_key] = nil
  end
end

function fast_transfer_logic.on_selected_entity_changed(event)
  if not shared_utils.is_player_event(event) then return end
  
  local player = game.players[event.player_index]
  if not player or not player.valid then return end
  
  -- Clean up any existing sessions for this player (entity deselection)
  for session_key, session in pairs(sessions) do
    if session.player_index == event.player_index then
      sessions[session_key] = nil
    end
  end
  
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
  
  -- Get combined inventory snapshot (all relevant inventories)
  local inventory_snapshot = logistics.get_combined_inventory_contents(selected_entity)
  
  -- Create new session
  sessions[session_key] = {
    player_index = event.player_index,
    entity = selected_entity,
    inventory_snapshot = inventory_snapshot,
    start_tick = event.tick,
    last_activity_tick = event.tick
  }
end

function fast_transfer_logic.on_player_fast_transferred(event)
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

function fast_transfer_logic.on_player_left_game(event)
  local player_index = event.player_index
  
  -- Finalize any active sessions for this player
  for session_key, session in pairs(sessions) do
    if session.player_index == player_index then
      finalize_session(session_key, event.tick, nil)
    end
  end
end

function fast_transfer_logic.cleanup_old_sessions()
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

-- =========================
-- Cursor Stack Logic
-- =========================
local cursor_stack_logic = {}

-- Storage for tracking cursor states
local cursor_states = {}

function cursor_stack_logic.on_player_cursor_stack_changed(event)
  if not shared_utils.is_player_event(event) then return end
  
  local player = game.players[event.player_index]
  if not player or not player.valid then return end
  
  local context = shared_utils.get_player_context(player)
  
  -- Get previous cursor state
  local prev_state = cursor_states[event.player_index]
  
  -- Store current state
  cursor_states[event.player_index] = {
    cursor_item = context.cursor_item,
    cursor_count = context.cursor_count or 0,
    selected = context.selected,
    selected_x = context.selected_x,
    selected_y = context.selected_y,
    tick = event.tick
  }
  
  -- If we don't have a previous state, just return
  if not prev_state then return end
  
  -- Check if we have a selected entity that's player accessible
  local selected_entity = player.selected
  if not selected_entity or not selected_entity.valid then return end
  if not logistics.is_player_accessible(selected_entity) then return end
  
  -- Check if cursor item is the same and count decreased by exactly 1
  if prev_state.cursor_item == context.cursor_item and
     prev_state.cursor_item and
     prev_state.cursor_count and context.cursor_count and
     prev_state.cursor_count - context.cursor_count == 1 and
     prev_state.selected == context.selected and
     prev_state.selected_x == context.selected_x and
     prev_state.selected_y == context.selected_y then
    
    -- Make sure it's an insertable item (not a building or equipment)
    if logistics.can_be_inserted(context.cursor_item) then
      -- Create insert_item record using the helper function
      local item_deltas = {[context.cursor_item] = 1}
      local rec = create_transfer_record(player, "insert_item", selected_entity, item_deltas, "on_player_cursor_stack_changed", false)
      
      local clean_rec = shared_utils.clean_record(rec)
      local line = game.table_to_json(clean_rec)
      shared_utils.buffer_event("player_inventory_transfers", line)
    end
  end
end

function cursor_stack_logic.on_player_left_game(event)
  -- Clean up cursor state for player
  cursor_states[event.player_index] = nil
end

-- =========================
-- Registration & Module API
-- =========================

function player_inventory_transfers.register_events(event_dispatcher)
  -- Register the fast transfer events
  event_dispatcher.register_handler(defines.events.on_selected_entity_changed, fast_transfer_logic.on_selected_entity_changed)
  event_dispatcher.register_handler(defines.events.on_player_fast_transferred, fast_transfer_logic.on_player_fast_transferred)
  event_dispatcher.register_handler(defines.events.on_player_left_game, fast_transfer_logic.on_player_left_game)
  event_dispatcher.register_nth_tick_handler(300, fast_transfer_logic.cleanup_old_sessions)

  -- Register the cursor stack events
  event_dispatcher.register_handler(defines.events.on_player_cursor_stack_changed, cursor_stack_logic.on_player_cursor_stack_changed)
  event_dispatcher.register_handler(defines.events.on_player_left_game, cursor_stack_logic.on_player_left_game)
end

function player_inventory_transfers.on_init()
  if not global.player_inventory_transfers then
    global.player_inventory_transfers = {
      sessions = {},
      cursor_states = {}
    }
  end
  sessions = global.player_inventory_transfers.sessions
  cursor_states = global.player_inventory_transfers.cursor_states
end

function player_inventory_transfers.on_load()
  if global.player_inventory_transfers then
    sessions = global.player_inventory_transfers.sessions
    cursor_states = global.player_inventory_transfers.cursor_states
  end
end

return player_inventory_transfers