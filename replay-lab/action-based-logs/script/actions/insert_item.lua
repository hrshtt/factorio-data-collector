--@insert_item.lua
--@description Player-to-entity item insertion logger
--@author Harshit Sharma
--@version 2.3.0
--@date 2025-01-27
--@note Tracks only player insertions into entity inventories (furnaces, assemblers, etc.)

local insert_item = {}
local shared_utils = require("script.shared-utils")

-- ============================================================================
-- PLAYER STATE TRACKING
-- ============================================================================
local function initialize_player_state(player_index)
  if not global.insert_item_state then
    global.insert_item_state = {}
  end
  if not global.insert_item_state[player_index] then
    global.insert_item_state[player_index] = {
      previous_main_inventory = {},
      previous_cursor_stack = nil,
      open_gui_entity = nil,
      selected_entity = nil,
      selected_entity_snapshot = {},
      cursor_became_empty_tick = nil
    }
  end
end

local function get_inventory_snapshot(inventory)
  if not inventory or not inventory.valid then return {} end
  
  local snapshot = {}
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read then
      local key = stack.name
      snapshot[key] = (snapshot[key] or 0) + stack.count
    end
  end
  return snapshot
end

local function get_entity_inventory_snapshot(entity)
  if not entity or not entity.valid then return {} end
  
  -- Try to get the main inventory (works for chests, assemblers, etc.)
  local inventory = entity.get_inventory(defines.inventory.chest)
  if not inventory then
    -- Try other inventory types
    inventory = entity.get_inventory(defines.inventory.furnace_source)
    if not inventory then
      inventory = entity.get_inventory(defines.inventory.assembling_machine_input)
    end
  end
  
  return get_inventory_snapshot(inventory)
end

local function get_cursor_stack_info(player)
  if not player.cursor_stack or not player.cursor_stack.valid_for_read then
    return nil, 0
  end
  return player.cursor_stack.name, player.cursor_stack.count
end

local function compute_inventory_delta(old_inv, new_inv)
  local delta = {}
  
  -- Check for increases
  for item, new_count in pairs(new_inv) do
    local old_count = old_inv[item] or 0
    if new_count > old_count then
      delta[item] = new_count - old_count
    end
  end
  
  -- Check for decreases
  for item, old_count in pairs(old_inv) do
    local new_count = new_inv[item] or 0
    if old_count > new_count then
      delta[item] = -(old_count - new_count)
    end
  end
  
  return delta
end

-- ============================================================================
-- LOGGING HELPERS
-- ============================================================================
local function log_insertion(event_name, player, transfer_type, details)
  local rec = shared_utils.create_base_record(event_name, {
    tick = game.tick,
    player_index = player.index
  })
  
  rec.action = "insert_item"
  rec.transfer_type = transfer_type
  
  -- Add details
  for key, value in pairs(details) do
    rec[key] = value
  end
  
  shared_utils.add_player_context_if_missing(rec, player)
  local clean_rec = shared_utils.clean_record(rec)
  local line = game.table_to_json(clean_rec)
  shared_utils.buffer_event("insert_item", line)
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- 1. Fast transfer (Ctrl/Shift + Click with GUI closed) - only log TO entity
local function on_fast_transferred(e)
  if not shared_utils.is_player_event(e) then return end
  
  -- Only log when items go FROM player TO entity
  if not e.from_player then return end
  
  local player = game.players[e.player_index]
  
  log_insertion("on_player_fast_transferred", player, "fast_transfer_to_entity", {
    entity = e.entity and e.entity.name or nil,
    is_split = e.is_split
  })
end

-- 2. Selected entity changed (for Z-key context tracking)
local function on_selected_entity_changed(e)
  if not shared_utils.is_player_event(e) then return end
  
  initialize_player_state(e.player_index)
  local state = global.insert_item_state[e.player_index]
  
  -- Store the selected entity and its inventory snapshot
  state.selected_entity = e.last_entity
  if e.last_entity and e.last_entity.valid then
    state.selected_entity_snapshot = get_entity_inventory_snapshot(e.last_entity)
  else
    state.selected_entity_snapshot = {}
  end
end

-- 3. Cursor stack changes (for intent tracking)
local function on_cursor_stack_changed(e)
  if not shared_utils.is_player_event(e) then return end
  
  local player = game.players[e.player_index]
  initialize_player_state(e.player_index)
  
  local state = global.insert_item_state[e.player_index]
  local cursor_item, cursor_count = get_cursor_stack_info(player)
  
  -- Track when cursor becomes empty (useful for some edge cases)
  if not cursor_item and state.previous_cursor_stack then
    state.cursor_became_empty_tick = game.tick
  end
  
  state.previous_cursor_stack = cursor_item and {name = cursor_item, count = cursor_count} or nil
end

-- 4. GUI opened/closed (for context tracking)
local function on_gui_opened(e)
  if not shared_utils.is_player_event(e) then return end
  
  initialize_player_state(e.player_index)
  local state = global.insert_item_state[e.player_index]
  
  state.open_gui_entity = e.entity and e.entity.name or nil
end

local function on_gui_closed(e)
  if not shared_utils.is_player_event(e) then return end
  
  initialize_player_state(e.player_index)
  local state = global.insert_item_state[e.player_index]
  
  state.open_gui_entity = nil
end

-- 5. Main inventory changed (handles everything via diffing) - only log clear FROM player insertions
local function on_main_inventory_changed(e)
  if not shared_utils.is_player_event(e) then return end
  
  local player = game.players[e.player_index]
  initialize_player_state(e.player_index)
  
  local state = global.insert_item_state[e.player_index]
  local current_inventory = get_inventory_snapshot(player.get_main_inventory())
  
  -- Compute player inventory delta
  local player_delta = compute_inventory_delta(state.previous_main_inventory, current_inventory)
  
  -- Only process if there's actually a change
  local has_changes = false
  for item, change in pairs(player_delta) do
    if change ~= 0 then
      has_changes = true
      break
    end
  end
  
  if has_changes then
    -- Get entity delta if we have a selected entity
    local entity_delta = {}
    local current_entity_snapshot = {}
    
    if state.selected_entity and state.selected_entity.valid then
      current_entity_snapshot = get_entity_inventory_snapshot(state.selected_entity)
      entity_delta = compute_inventory_delta(state.selected_entity_snapshot, current_entity_snapshot)
    end
    
    -- Process each item change - ONLY log when player LOSES items (FROM player)
    for item, player_change in pairs(player_delta) do
      if player_change < 0 then  -- Player lost items (FROM player)
        local entity_change = entity_delta[item] or 0
        local transfer_type = nil
        local target_entity = nil
        
        -- Check if this is a clear Z-key insert (player lost items, entity gained them)
        if entity_change > 0 and player_change == -entity_change then
          transfer_type = "z_key_insert"
          target_entity = state.selected_entity.name
        elseif state.open_gui_entity then
          -- GUI was open - this is likely a stack transfer or drag-drop FROM player
          transfer_type = "gui_insert"
          target_entity = state.open_gui_entity
        elseif state.cursor_became_empty_tick and (game.tick - state.cursor_became_empty_tick) <= 2 then
          -- Cursor became empty recently (fallback for edge cases)
          transfer_type = "cursor_insert"
          target_entity = state.selected_entity and state.selected_entity.name or nil
        end
        
        -- Only log if we have a clear transfer type (no ambiguous cases)
        if transfer_type then
          log_insertion("on_player_main_inventory_changed", player, transfer_type, {
            item = item,
            count = math.abs(player_change),
            target_entity = target_entity
          })
        end
        -- Note: We ignore ambiguous cases (crafting, mining, etc.) where we can't determine the target
      end
      -- Note: We ignore player_change > 0 (player GAINED items) - those are extractions, not insertions
    end
    
    -- Update entity snapshot after processing
    if state.selected_entity and state.selected_entity.valid then
      state.selected_entity_snapshot = current_entity_snapshot
    end
  end
  
  -- Update player inventory state
  state.previous_main_inventory = current_inventory
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
local function on_player_joined(e)
  initialize_player_state(e.player_index)
  local player = game.players[e.player_index]
  local state = global.insert_item_state[e.player_index]
  
  -- Initialize with current inventory state
  state.previous_main_inventory = get_inventory_snapshot(player.get_main_inventory())
  state.previous_cursor_stack = get_cursor_stack_info(player)
  
  -- Initialize selected entity state
  if player.selected and player.selected.valid then
    state.selected_entity = player.selected
    state.selected_entity_snapshot = get_entity_inventory_snapshot(player.selected)
  end
end

-- ============================================================================
-- PUBLIC INTERFACE
-- ============================================================================
function insert_item.register_events(event_dispatcher)
  -- Core transfer events
  event_dispatcher.register_handler(defines.events.on_player_fast_transferred, on_fast_transferred)
  event_dispatcher.register_handler(defines.events.on_player_main_inventory_changed, on_main_inventory_changed)
  
  -- Context tracking events
  event_dispatcher.register_handler(defines.events.on_selected_entity_changed, on_selected_entity_changed)
  event_dispatcher.register_handler(defines.events.on_player_cursor_stack_changed, on_cursor_stack_changed)
  event_dispatcher.register_handler(defines.events.on_gui_opened, on_gui_opened)
  event_dispatcher.register_handler(defines.events.on_gui_closed, on_gui_closed)
  
  -- Player lifecycle
  event_dispatcher.register_handler(defines.events.on_player_joined_game, on_player_joined)
end

return insert_item 