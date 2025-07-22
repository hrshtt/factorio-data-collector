--@player_inventory_transfers.lua
--@description Player inventory transfers action logger, logs insert_item and extract_item
--@author Harshit Sharma
--@version 2.0.0
--@date 2025-01-27
--
-- SINGLE-SESSION FLOW IMPLEMENTATION:
-- -----------------------------------
-- This module uses a single active session per player to prevent duplicate transfer rows
-- when the player's cursor jitters over the same entity multiple times.
--
-- Key Design:
-- 1. current_sessions[player_index] stores ONE session per player (not keyed by tick/position)
-- 2. on_selected_entity_changed: Overwrites the current session with fresh inventory snapshot
-- 3. on_player_fast_transferred: Uses current session to diff and log ONE record per Ctrl-click
-- 4. After logging, refreshes snapshot for consecutive transfers on same entity
-- 5. Sessions auto-cleanup on entity deselection, player logout, or 300-tick timeout
--
-- Benefits:
-- - Eliminates duplicate rows from cursor jitter
-- - Maintains accurate consecutive transfer logging  
-- - Covers all inventory types (fuel, result, modules) via combined inventory contents
-- - Logs no-op transfers with no_op=true flag for alignment with raw events

local player_inventory_transfers = {}
local shared_utils = require("script.shared-utils")
local logistics = require("script.logistics")


-- =========================
-- Fast Transfer Logic
-- =========================
local fast_transfer_logic = {}

-- Storage for tracking current session per player (single session per player)
local current_sessions = {}

-- Helper function to create a transfer record
local function create_transfer_record(player, action_type, entity, item_deltas, event_name, is_no_op)
  local rec = shared_utils.create_base_record("player_inventory_transfers", {
    -- name = defines.events.on_player_fast_transferred,
    tick = game.tick,
    -- player_index = player.index
  }, player)
  
  rec.action = action_type -- "insert_item" or "extract_item"
  rec.entity = {}
  rec.entity.name = entity.name
  if entity.position then
    rec.entity.x = string.format("%.1f", entity.position.x)
    rec.entity.y = string.format("%.1f", entity.position.y)
  end
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

function fast_transfer_logic.on_selected_entity_changed(event)
  if not shared_utils.is_player_event(event) then return end
  
  local player = game.players[event.player_index]
  if not player or not player.valid then return end
  
  -- Find the selected entity
  local selected_entity = player.selected
  if not selected_entity or not selected_entity.valid then 
    -- Clear current session if no entity is selected
    current_sessions[event.player_index] = nil
    return 
  end
  
  -- Only track player-accessible entities
  if not logistics.is_player_accessible(selected_entity) then 
    current_sessions[event.player_index] = nil
    return 
  end
  
  -- Get combined inventory snapshot (all relevant inventories)
  local inventory_snapshot = logistics.get_combined_inventory_contents(selected_entity)
  
  -- SINGLE-SESSION FLOW: Overwrite any existing session for this player
  -- This eliminates duplicates from cursor jitter - only the latest entity selection matters
  current_sessions[event.player_index] = {
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
  
  -- Retrieve current session for this player
  local current_session = current_sessions[event.player_index]
  if not current_session then return end
  
  local entity = current_session.entity
  if not entity or not entity.valid then
    -- Clean up invalid session
    current_sessions[event.player_index] = nil
    return
  end
  
  -- Verify the session entity matches the currently selected entity
  if entity ~= player.selected then
    -- Session entity doesn't match current selection, ignore this transfer
    return
  end
  
  -- Get current combined inventory state (all relevant inventories)
  local current_contents = logistics.get_combined_inventory_contents(entity)
  local item_deltas = logistics.diff_tables(current_session.inventory_snapshot, current_contents)
  
  -- Always log the event, even if no items moved (with no_op flag)
  local has_changes = next(item_deltas) ~= nil
  local is_no_op = not has_changes
  
  if event.from_player ~= nil then
    local action_type = "insert_item"
    if event.from_player == false then
      action_type = "extract_item"
    end
    
    local rec = create_transfer_record(player, action_type, entity, item_deltas, "fast_transfer", is_no_op)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("player_inventory_transfers", line)
  end
  
  -- SINGLE-SESSION FLOW: Refresh snapshot for consecutive transfers on same entity
  -- This allows multiple Ctrl-clicks on same entity to be tracked separately
  current_session.inventory_snapshot = current_contents
  current_session.last_activity_tick = event.tick
end

function fast_transfer_logic.on_player_left_game(event)
  -- Clear current session for the player who left
  current_sessions[event.player_index] = nil
end

function fast_transfer_logic.cleanup_old_sessions()
  local current_tick = game.tick
  -- Keep sessions alive for only 300 ticks as requested
  local timeout_ticks = 300

  for player_index, session in pairs(current_sessions) do
    if (current_tick - session.last_activity_tick) >= timeout_ticks then
      -- Timeout - clean up without logging
      current_sessions[player_index] = nil
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
-- GUI Transfer Logic
-- =========================
local gui_transfer_logic = {}

-- Storage for tracking GUI sessions
local gui_sessions = {}

function gui_transfer_logic.on_gui_opened(event)
  if not shared_utils.is_player_event(event) then return end
  
  local player = game.players[event.player_index]
  if not player or not player.valid then return end
  
  -- Only track entity GUIs
  if event.gui_type ~= defines.gui_type.entity then return end
  
  local entity = event.entity
  if not entity or not entity.valid then return end
  
  -- Only track player-accessible entities
  if not logistics.is_player_accessible(entity) then return end
  
  -- Get combined inventory snapshot and cursor state
  local entity_inventory = logistics.get_combined_inventory_contents(entity)
  local cursor_stack = player.cursor_stack
  local cursor_item = cursor_stack and cursor_stack.valid_for_read and cursor_stack.name or nil
  local cursor_count = cursor_stack and cursor_stack.valid_for_read and cursor_stack.count or 0
  
  -- Create GUI session
  gui_sessions[event.player_index] = {
    entity = entity,
    last_entity_inv = entity_inventory,
    last_cursor_item = cursor_item,
    last_cursor_count = cursor_count,
    last_tick_logged = 0,
    opened_tick = event.tick
  }
end

function gui_transfer_logic.on_gui_closed(event)
  if not shared_utils.is_player_event(event) then return end
  
  -- Clear GUI session for this player
  gui_sessions[event.player_index] = nil
end

function gui_transfer_logic.on_player_cursor_stack_changed(event)
  if not shared_utils.is_player_event(event) then return end
  
  local player = game.players[event.player_index]
  if not player or not player.valid then return end
  
  -- Check if we have an active GUI session
  local session = gui_sessions[event.player_index]
  if not session then return end
  
  local entity = session.entity
  if not entity or not entity.valid then
    -- Clean up invalid session
    gui_sessions[event.player_index] = nil
    return
  end
  
  -- Duplicate suppression: prevent double-logging with fast transfers
  if event.tick == session.last_tick_logged then return end
  
  -- Get current cursor state
  local cursor_stack = player.cursor_stack
  local cursor_item = cursor_stack and cursor_stack.valid_for_read and cursor_stack.name or nil
  local cursor_count = cursor_stack and cursor_stack.valid_for_read and cursor_stack.count or 0
  
  -- Get current entity inventory state
  local current_entity_inv = logistics.get_combined_inventory_contents(entity)
  local entity_delta = logistics.diff_tables(session.last_entity_inv, current_entity_inv)
  
  -- If no entity inventory change, ignore (filters out crafting, bot deliveries, etc.)
  if next(entity_delta) == nil then
    -- Update cursor state for next comparison
    session.last_cursor_item = cursor_item
    session.last_cursor_count = cursor_count
    return
  end
  
  -- Determine transfer direction based on cursor count change
  local cursor_count_delta = cursor_count - session.last_cursor_count
  local action_type = nil
  
  if cursor_count_delta < 0 then
    -- Cursor count decreased -> player put items into entity
    action_type = "insert_item"
  elseif cursor_count_delta > 0 then
    -- Cursor count increased -> player took items from entity
    action_type = "extract_item"
  else
    -- Cursor count unchanged, use entity delta sign to determine direction
    -- Positive delta in entity = items added = insert_item
    -- Negative delta in entity = items removed = extract_item
    local total_entity_delta = 0
    for _, delta in pairs(entity_delta) do
      total_entity_delta = total_entity_delta + delta
    end
    
    if total_entity_delta > 0 then
      action_type = "insert_item"
    elseif total_entity_delta < 0 then
      action_type = "extract_item"
    else
      -- No net change, skip logging
      session.last_entity_inv = current_entity_inv
      session.last_cursor_item = cursor_item
      session.last_cursor_count = cursor_count
      return
    end
  end
  
  -- Create and log the transfer record
  local rec = create_transfer_record(player, action_type, entity, entity_delta, "gui_transfer", false)
  local clean_rec = shared_utils.clean_record(rec)
  local line = game.table_to_json(clean_rec)
  shared_utils.buffer_event("player_inventory_transfers", line)
  
  -- Update session state
  session.last_entity_inv = current_entity_inv
  session.last_cursor_item = cursor_item
  session.last_cursor_count = cursor_count
  session.last_tick_logged = event.tick
end

function gui_transfer_logic.on_player_left_game(event)
  -- Clean up GUI session for player
  gui_sessions[event.player_index] = nil
end

function gui_transfer_logic.cleanup_old_sessions()
  local current_tick = game.tick
  local timeout_ticks = 300
  
  for player_index, session in pairs(gui_sessions) do
    if (current_tick - session.opened_tick) >= timeout_ticks then
      -- Timeout - clean up session
      gui_sessions[player_index] = nil
    end
  end
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

  -- Register the GUI transfer events
  event_dispatcher.register_handler(defines.events.on_gui_opened, gui_transfer_logic.on_gui_opened)
  event_dispatcher.register_handler(defines.events.on_gui_closed, gui_transfer_logic.on_gui_closed)
  event_dispatcher.register_handler(defines.events.on_player_cursor_stack_changed, gui_transfer_logic.on_player_cursor_stack_changed)
  event_dispatcher.register_handler(defines.events.on_player_left_game, gui_transfer_logic.on_player_left_game)
  event_dispatcher.register_nth_tick_handler(300, gui_transfer_logic.cleanup_old_sessions)
end

function player_inventory_transfers.on_init()
  if not global.player_inventory_transfers then
    global.player_inventory_transfers = {
      current_sessions = {}, -- Single session per player (indexed by player_index)
      cursor_states = {},     -- Cursor stack tracking per player
      gui_sessions = {}      -- GUI session tracking per player
    }
  end
  current_sessions = global.player_inventory_transfers.current_sessions
  cursor_states = global.player_inventory_transfers.cursor_states
  gui_sessions = global.player_inventory_transfers.gui_sessions
end

function player_inventory_transfers.on_load()
  if global.player_inventory_transfers then
    current_sessions = global.player_inventory_transfers.current_sessions
    cursor_states = global.player_inventory_transfers.cursor_states
    gui_sessions = global.player_inventory_transfers.gui_sessions
  end
end

return player_inventory_transfers