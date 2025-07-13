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

-- Helper function to safely get entity name
local function get_entity_name_safe(entity)
  if entity and entity.valid then
    return entity.name
  end
  return nil
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
    log("DEBUG: get_cursor_stack_info - cursor empty or invalid")
    return nil, 0
  end
  log("DEBUG: get_cursor_stack_info - cursor has " .. player.cursor_stack.name .. " x" .. player.cursor_stack.count)
  return player.cursor_stack.name, player.cursor_stack.count
end

local function compute_inventory_delta(old_inv, new_inv)
  local delta = {}
  
  -- Check for increases
  for item, new_count in pairs(new_inv) do
    local old_count = old_inv[item] or 0
    if new_count > old_count then
      delta[item] = new_count - old_count
      log("DEBUG: compute_inventory_delta - " .. item .. " increased by " .. delta[item])
    end
  end
  
  -- Check for decreases
  for item, old_count in pairs(old_inv) do
    local new_count = new_inv[item] or 0
    if old_count > new_count then
      delta[item] = -(old_count - new_count)
      log("DEBUG: compute_inventory_delta - " .. item .. " decreased by " .. math.abs(delta[item]))
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
  log("DEBUG: on_fast_transferred called")
  if not shared_utils.is_player_event(e) then 
    log("DEBUG: on_fast_transferred - not player event, returning")
    return 
  end
  
  -- Only log when items go FROM player TO entity
  if not e.from_player then 
    log("DEBUG: on_fast_transferred - not from player, returning")
    return 
  end
  
  log("DEBUG: on_fast_transferred - processing transfer")
  local player = game.players[e.player_index]
  
  log_insertion("on_player_fast_transferred", player, "fast_transfer_to_entity", {
    entity = e.entity and e.entity.name or nil,
    is_split = e.is_split
  })
  log("DEBUG: on_fast_transferred - logged insertion")
end

-- 2. Selected entity changed (for Z-key context tracking)
local function on_selected_entity_changed(e)
  log("DEBUG: on_selected_entity_changed called")
  if not shared_utils.is_player_event(e) then 
    log("DEBUG: on_selected_entity_changed - not player event, returning")
    return 
  end
  
  initialize_player_state(e.player_index)
  local state = global.insert_item_state[e.player_index]
  log("DEBUG: on_selected_entity_changed - state initialized")
  
  -- Check if we have a previous entity and cursor stack for Z-key insert detection
  if state.selected_entity and state.selected_entity.valid and state.previous_cursor_stack then
    log("DEBUG: on_selected_entity_changed - checking for Z-key insert")
    local player = game.players[e.player_index]
    local current_cursor_item, current_cursor_count = get_cursor_stack_info(player)
    log("DEBUG: on_selected_entity_changed - current cursor: " .. tostring(current_cursor_item) .. " x" .. tostring(current_cursor_count))
    log("DEBUG: on_selected_entity_changed - previous cursor: " .. tostring(state.previous_cursor_stack.name) .. " x" .. tostring(state.previous_cursor_stack.count))
    
    -- If cursor has fewer items than before and we had a selected entity, this might be a Z-key insert
    if current_cursor_item == state.previous_cursor_stack.name and current_cursor_count < state.previous_cursor_stack.count then
      log("DEBUG: on_selected_entity_changed - cursor decreased, checking entity")
      local entity_snapshot = get_entity_inventory_snapshot(state.selected_entity)
      local entity_delta = compute_inventory_delta(state.selected_entity_snapshot, entity_snapshot)
      log("DEBUG: on_selected_entity_changed - previous inventory: " .. game.table_to_json(state.selected_entity_snapshot))
      log("DEBUG: on_selected_entity_changed - current inventory: " .. game.table_to_json(entity_snapshot))
      log("DEBUG: on_selected_entity_changed - inventory delta: " .. game.table_to_json(entity_delta))
      
      -- Check if the entity gained the items that were removed from the cursor
      local cursor_item = state.previous_cursor_stack.name
      local items_removed = state.previous_cursor_stack.count - current_cursor_count
      local entity_gained = entity_delta[cursor_item] or 0
      log("DEBUG: on_selected_entity_changed - items_removed: " .. tostring(items_removed) .. ", entity_gained: " .. tostring(entity_gained))
      
      if entity_gained > 0 and entity_gained == items_removed then
        log("DEBUG: on_selected_entity_changed - logging Z-key insert")
        -- Add validity check before accessing entity.name
        if state.selected_entity and state.selected_entity.valid then
          log_insertion("on_selected_entity_changed", player, "z_key_insert", {
            item = cursor_item,
            count = items_removed,
            target_entity = get_entity_name_safe(state.selected_entity)
          })
        else
          log("DEBUG: on_selected_entity_changed - selected entity became invalid, skipping log")
        end
      end
    end
  else
    log("DEBUG: on_selected_entity_changed - no previous entity or cursor stack")
  end
  
  -- Store the selected entity and its inventory snapshot
  log("DEBUG: on_selected_entity_changed - updating selected entity to: " .. tostring(e.last_entity and e.last_entity.name or "nil"))
  state.selected_entity = e.last_entity
  if e.last_entity and e.last_entity.valid then
    state.selected_entity_snapshot = get_entity_inventory_snapshot(e.last_entity)
    log("DEBUG: on_selected_entity_changed - updated entity snapshot")
  else
    log("DEBUG: on_selected_entity_changed - no entity snapshot")
  end
end

-- 3. Cursor stack changes (for intent tracking)
local function on_cursor_stack_changed(e)
  log("DEBUG: on_cursor_stack_changed called")
  if not shared_utils.is_player_event(e) then 
    log("DEBUG: on_cursor_stack_changed - not player event, returning")
    return 
  end
  
  local player = game.players[e.player_index]
  initialize_player_state(e.player_index)
  
  local state = global.insert_item_state[e.player_index]
  local cursor_item, cursor_count = get_cursor_stack_info(player)
  log("DEBUG: on_cursor_stack_changed - current cursor: " .. tostring(cursor_item) .. " x" .. tostring(cursor_count))
  
  -- Check if cursor has fewer items than before and we have a selected entity (potential Z-key insert)
  if state.previous_cursor_stack and state.selected_entity and state.selected_entity.valid then
    log("DEBUG: on_cursor_stack_changed - checking for Z-key insert")
    -- Check if it's the same item but with fewer count
    if cursor_item == state.previous_cursor_stack.name and cursor_count < state.previous_cursor_stack.count then
      log("DEBUG: on_cursor_stack_changed - cursor decreased, checking entity")
      local entity_snapshot = get_entity_inventory_snapshot(state.selected_entity)
      local entity_delta = compute_inventory_delta(state.selected_entity_snapshot, entity_snapshot)
      
      -- Check if the entity gained the items that were removed from the cursor
      local previous_cursor_item = state.previous_cursor_stack.name
      local items_removed = state.previous_cursor_stack.count - cursor_count
      local entity_gained = entity_delta[previous_cursor_item] or 0
      log("DEBUG: on_cursor_stack_changed - items_removed: " .. tostring(items_removed) .. ", entity_gained: " .. tostring(entity_gained))
      
      if entity_gained > 0 and entity_gained == items_removed then
        log("DEBUG: on_cursor_stack_changed - logging Z-key insert")
        -- Add validity check before accessing entity.name
        if state.selected_entity and state.selected_entity.valid then
          log_insertion("on_player_cursor_stack_changed", player, "z_key_insert", {
            item = previous_cursor_item,
            count = items_removed,
            target_entity = get_entity_name_safe(state.selected_entity)
          })
        else
          log("DEBUG: on_cursor_stack_changed - selected entity became invalid, skipping log")
        end
      end
    end
  else
    local entity_name = get_entity_name_safe(state.selected_entity) or "nil"
    log("DEBUG: on_cursor_stack_changed - no previous cursor (" .. tostring(state.previous_cursor_stack) .. ") or selected entity (" .. entity_name .. ")")
  end
  
  -- Track when cursor becomes empty (useful for some edge cases)
  if not cursor_item and state.previous_cursor_stack then
    log("DEBUG: on_cursor_stack_changed - cursor became empty")
    state.cursor_became_empty_tick = game.tick
  end
  
  log("DEBUG: on_cursor_stack_changed - updating previous_cursor_stack to: " .. tostring(cursor_item) .. " x" .. tostring(cursor_count))
  state.previous_cursor_stack = cursor_item and {name = cursor_item, count = cursor_count} or nil
end

-- 4. GUI opened/closed (for context tracking)
local function on_gui_opened(e)
  log("DEBUG: on_gui_opened called")
  if not shared_utils.is_player_event(e) then 
    log("DEBUG: on_gui_opened - not player event, returning")
    return 
  end
  
  initialize_player_state(e.player_index)
  local state = global.insert_item_state[e.player_index]
  
  state.open_gui_entity = e.entity and e.entity.name or nil
  log("DEBUG: on_gui_opened - set open_gui_entity to: " .. tostring(state.open_gui_entity))
end

local function on_gui_closed(e)
  log("DEBUG: on_gui_closed called")
  if not shared_utils.is_player_event(e) then 
    log("DEBUG: on_gui_closed - not player event, returning")
    return 
  end
  
  initialize_player_state(e.player_index)
  local state = global.insert_item_state[e.player_index]
  
  log("DEBUG: on_gui_closed - clearing open_gui_entity (was: " .. tostring(state.open_gui_entity) .. ")")
  state.open_gui_entity = nil
end

-- 5. Main inventory changed (handles everything via diffing) - only log clear FROM player insertions
local function on_main_inventory_changed(e)
  log("DEBUG: on_main_inventory_changed called")
  if not shared_utils.is_player_event(e) then 
    log("DEBUG: on_main_inventory_changed - not player event, returning")
    return 
  end
  
  local player = game.players[e.player_index]
  initialize_player_state(e.player_index)
  
  local state = global.insert_item_state[e.player_index]
  local current_inventory = get_inventory_snapshot(player.get_main_inventory())
  log("DEBUG: on_main_inventory_changed - got current inventory snapshot")
  
  -- Compute player inventory delta
  local player_delta = compute_inventory_delta(state.previous_main_inventory, current_inventory)
  log("DEBUG: on_main_inventory_changed - computed player delta")
  
  -- Only process if there's actually a change
  local has_changes = false
  for item, change in pairs(player_delta) do
    if change ~= 0 then
      has_changes = true
      log("DEBUG: on_main_inventory_changed - found change: " .. item .. " = " .. change)
      break
    end
  end
  
  if has_changes then
    log("DEBUG: on_main_inventory_changed - processing changes")
    -- Get entity delta if we have a selected entity
    local entity_delta = {}
    local current_entity_snapshot = {}
    
    if state.selected_entity and state.selected_entity.valid then
      local entity_name = get_entity_name_safe(state.selected_entity)
      log("DEBUG: on_main_inventory_changed - getting entity snapshot for: " .. (entity_name or "unknown"))
      current_entity_snapshot = get_entity_inventory_snapshot(state.selected_entity)
      entity_delta = compute_inventory_delta(state.selected_entity_snapshot, current_entity_snapshot)
    else
      log("DEBUG: on_main_inventory_changed - no valid selected entity")
    end
    
    -- Process each item change - ONLY log when player LOSES items (FROM player)
    for item, player_change in pairs(player_delta) do
      if player_change < 0 then  -- Player lost items (FROM player)
        log("DEBUG: on_main_inventory_changed - player lost " .. math.abs(player_change) .. " " .. item)
        local entity_change = entity_delta[item] or 0
        local transfer_type = nil
        local target_entity = nil
        
        -- Check if this is a clear Z-key insert (player lost items, entity gained them)
        if entity_change > 0 and player_change == -entity_change then
          log("DEBUG: on_main_inventory_changed - detected Z-key insert")
          transfer_type = "z_key_insert"
          -- Add validity check before accessing entity.name
          target_entity = get_entity_name_safe(state.selected_entity)
        elseif state.open_gui_entity then
          log("DEBUG: on_main_inventory_changed - detected GUI insert")
          -- GUI was open - this is likely a stack transfer or drag-drop FROM player
          transfer_type = "gui_insert"
          target_entity = state.open_gui_entity
        elseif state.cursor_became_empty_tick and (game.tick - state.cursor_became_empty_tick) <= 2 then
          log("DEBUG: on_main_inventory_changed - detected cursor insert")
          -- Cursor became empty recently (fallback for edge cases)
          transfer_type = "cursor_insert"
          target_entity = get_entity_name_safe(state.selected_entity)
        end
        
        -- Only log if we have a clear transfer type (no ambiguous cases)
        if transfer_type then
          log("DEBUG: on_main_inventory_changed - logging insertion: " .. transfer_type)
          log_insertion("on_player_main_inventory_changed", player, transfer_type, {
            item = item,
            count = math.abs(player_change),
            target_entity = target_entity
          })
        else
          log("DEBUG: on_main_inventory_changed - no clear transfer type, skipping")
        end
        -- Note: We ignore ambiguous cases (crafting, mining, etc.) where we can't determine the target
      end
      -- Note: We ignore player_change > 0 (player GAINED items) - those are extractions, not insertions
    end
    
    -- Update entity snapshot after processing
    if state.selected_entity and state.selected_entity.valid then
      state.selected_entity_snapshot = current_entity_snapshot
      log("DEBUG: on_main_inventory_changed - updated entity snapshot")
    end
  else
    log("DEBUG: on_main_inventory_changed - no changes detected")
  end
  
  -- Update player inventory state
  state.previous_main_inventory = current_inventory
  log("DEBUG: on_main_inventory_changed - updated player inventory state")
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
local function on_player_joined(e)
  log("DEBUG: on_player_joined called for player " .. tostring(e.player_index))
  initialize_player_state(e.player_index)
  local player = game.players[e.player_index]
  local state = global.insert_item_state[e.player_index]
  
  -- Initialize with current inventory state
  state.previous_main_inventory = get_inventory_snapshot(player.get_main_inventory())
  state.previous_cursor_stack = get_cursor_stack_info(player)
  log("DEBUG: on_player_joined - initialized inventory state")
  
  -- Initialize selected entity state
  if player.selected and player.selected.valid then
    state.selected_entity = player.selected
    state.selected_entity_snapshot = get_entity_inventory_snapshot(player.selected)
    log("DEBUG: on_player_joined - initialized selected entity: " .. player.selected.name)
  else
    log("DEBUG: on_player_joined - no selected entity")
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