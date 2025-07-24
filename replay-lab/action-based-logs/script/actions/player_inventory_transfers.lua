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
  local rec = shared_utils.create_base_record(action_type, {
    tick = game.tick,
    player_index = player.index,
  }, player)
  rec.event_name = event_name

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

    local rec = create_transfer_record(player, action_type, entity, item_deltas, "on_player_fast_transferred", is_no_op)
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
-- local cursor_states = {}
global.item_counts = {}

local function set_item_count(player_index, item_name, count)
  if not global.item_counts[player_index] then
    global.item_counts[player_index] = {}
  end
  global.item_counts[player_index][item_name] = count
end

local function get_item_count(player_index, item_name)
  if not global.item_counts[player_index] or not global.item_counts[player_index][item_name] then
    return nil
  end
  return global.item_counts[player_index][item_name] or 0
end

function cursor_stack_logic.on_player_cursor_stack_changed(event)
  local verbose = false
  if not shared_utils.is_player_event(event) then return end

  local player = game.players[event.player_index]
  if not player or not player.valid then return end

  -- Check if we have a selected entity that's player accessible

  local context = shared_utils.get_player_context(player)
  local selected_entity = context.selected
  if not context.cursor_item then return end
  if not selected_entity then return end
  if not logistics.is_player_accessible(selected_entity) then return end
  if not  logistics.can_be_inserted(context.cursor_item) then return end

  -- Additional validation to ensure entity is still valid and accessible
  if not selected_entity.valid then return end
  if not logistics.is_player_accessible(selected_entity) then return end

  local p_inventory = logistics.get_player_inventory_contents(player)

  
  if verbose then
    local debug = {tick = event.tick}
    -- Store entity info in a way that can be serialized to JSON

    local name = selected_entity.name
    local x = string.format("%.1f", selected_entity.position.x)
    local y = string.format("%.1f", selected_entity.position.y)
    debug.selected_entity = name .. " (" .. x .. ", " .. y .. ")"
    debug.cursor = {
      [context.cursor_item] = context.cursor_count,
    }
    debug.p_inventory = p_inventory
    debug.e_inventory = logistics.get_combined_inventory_contents(selected_entity)

    log(game.table_to_json(debug))
  end

  local current_item_count = (p_inventory[context.cursor_item] or 0) + context.cursor_count
  local previous_item_count = get_item_count(event.player_index, context.cursor_item)
  set_item_count(event.player_index, context.cursor_item, current_item_count)

  -- if the item count is not set, return
  if not previous_item_count then return end
  
  -- calculate the item delta
  local item_delta = current_item_count - previous_item_count

  -- if the item delta is less than -2, its not part of the Z press event tracking
  -- if the item delta is more than 0, means item was sourced from somewhere else
  if item_delta < -2 or item_delta >= 0 then return end
  
  -- Create insert_item record using the helper function
  local rec = create_transfer_record(player, "insert_item", selected_entity, {
    [context.cursor_item] = item_delta,
  },
    "on_player_cursor_stack_changed", false)

  local clean_rec = shared_utils.clean_record(rec)
  local line = game.table_to_json(clean_rec)
  shared_utils.buffer_event("player_inventory_transfers", line)
end

function cursor_stack_logic.on_player_left_game(event)
  -- Clean up cursor state for player
  cursor_states[event.player_index] = nil
end

-- =========================
-- GUI Transfer Logic
-- =========================
local gui_transfer_logic = {}

-- instead of taking just the index, we pass in the LuaPlayer and the entity
local function assure_partial_gui(idx, player, entity)
  global.gui_sessions = global.gui_sessions or {}
  global.gui_sessions[idx] = {
    craft = {},                          -- will collect on_player_crafted_item
    snap  = logistics.gui_snapshot(player, entity),  -- player + inputs + outputs
  }
end

-- in your GUI module, replace everything in register_events with:

function gui_transfer_logic.register_events(event_dispatcher)
  -- open: snapshot
  event_dispatcher.register_handler(defines.events.on_gui_opened, function(ev)
    assure_partial_gui(ev.player_index)
    if ev.gui_type ~= defines.gui_type.entity then return end
    local p = game.get_player(ev.player_index)
    global.gui_sessions = global.gui_sessions or {}
    global.gui_sessions[p.index] = {
      snap   = logistics.gui_snapshot(p, ev.entity),
      craft  = {}
    }

    assure_partial_gui(ev.player_index, p, ev.entity)
  end)

  -- crafting: record so we can ignore those items
  event_dispatcher.register_handler(defines.events.on_player_crafted_item, function(ev)
    local s = global.gui_sessions[ev.player_index]; if not s then return end
    local name  = (ev.item_stack and ev.item_stack.name)  or ev.item_name
    local count = (ev.item_stack and ev.item_stack.count) or ev.item_count or 0
    s.craft[name] = (s.craft[name] or 0) + count
  end)

  -- close: compute & emit
  event_dispatcher.register_handler(defines.events.on_gui_closed, function(ev)
    if ev.gui_type ~= defines.gui_type.entity then return end
    local idx = ev.player_index
    local session = global.gui_sessions and global.gui_sessions[idx]; if not session then return end
    local p, e = game.players[idx], ev.entity
    local after   = logistics.gui_snapshot(p, e)
    local Xfers   = logistics.gui_compute_transfers(session.snap, after, session.craft)

    -- now Xfers.inserted / extracted are exactly what the player moved;
    -- Xfers.machine_consumed / produced tell you the machine’s internal change.

    -- example: emit only non-empty maps
    if next(Xfers.inserted) then
      shared_utils.buffer_event("player_inventory_transfers",
        game.table_to_json(create_transfer_record(p, "insert_item", e, Xfers.inserted, "on_gui_closed"))
      )
    end
    if next(Xfers.extracted) then
      shared_utils.buffer_event("player_inventory_transfers",
        game.table_to_json(create_transfer_record(p, "extract_item", e, Xfers.extracted, "on_gui_closed"))
      )
    end

    global.gui_sessions[idx] = nil
  end)
end

-- =========================
-- Registration & Module API
-- =========================

function player_inventory_transfers.register_events(event_dispatcher)
  -- Register the fast transfer events
  event_dispatcher.register_handler(defines.events.on_selected_entity_changed,
    fast_transfer_logic.on_selected_entity_changed)
  event_dispatcher.register_handler(defines.events.on_player_fast_transferred,
    fast_transfer_logic.on_player_fast_transferred)
  event_dispatcher.register_handler(defines.events.on_player_left_game, fast_transfer_logic.on_player_left_game)
  event_dispatcher.register_nth_tick_handler(300, fast_transfer_logic.cleanup_old_sessions)

  -- Register the cursor stack events
  event_dispatcher.register_handler(defines.events.on_player_cursor_stack_changed,
    cursor_stack_logic.on_player_cursor_stack_changed)
  event_dispatcher.register_handler(defines.events.on_player_left_game, cursor_stack_logic.on_player_left_game)

  -- Register the GUI transfer events using the helper function
  gui_transfer_logic.register_events(event_dispatcher)
end

function player_inventory_transfers.on_init()
  if not global.player_inventory_transfers then
    global.player_inventory_transfers = {
      current_sessions = {}, -- Single session per player (indexed by player_index)
      cursor_states = {},    -- Cursor stack tracking per player
      gui_sessions = {}      -- GUI session tracking per player
    }
  end
  current_sessions = global.player_inventory_transfers.current_sessions
  cursor_states = global.player_inventory_transfers.cursor_states
  gui_sessions = global.gui_sessions
end

function player_inventory_transfers.on_load()
  if global.player_inventory_transfers then
    current_sessions = global.player_inventory_transfers.current_sessions
    cursor_states = global.player_inventory_transfers.cursor_states
    gui_sessions = global.gui_sessions
  end
end

return player_inventory_transfers
