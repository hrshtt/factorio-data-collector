--@insert_item_collated.lua
--@description Collated item transfer action logger with filtering
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27
--@note Filters out inventory changes caused by crafting, building, and mining to prevent duplicate logs

local insert_item_collated = {}
local shared_utils = require("script.shared-utils")

-- ============================================================================
-- FILTERED EVENT TRACKING
-- ============================================================================

-- Track events that cause inventory changes to filter them out
local function initialize_exclusion_tracking()
  if not global.insert_item_collated_exclusions then
    global.insert_item_collated_exclusions = {}
  end
  
  -- Track last explicit log tick per player to prevent any remaining duplicates
  if not global.last_explicit_log_tick then
    global.last_explicit_log_tick = {}
  end
  
  -- Track events that should exclude inventory changes this tick
  local current_tick = game.tick
  if not global.insert_item_collated_exclusions[current_tick] then
    global.insert_item_collated_exclusions[current_tick] = {
      crafting_players = {},      -- Players who are crafting
      building_players = {},      -- Players who are building
      mining_players = {},        -- Players who are mining
      fast_transfer_players = {}, -- Players who did fast transfers
      drop_players = {},          -- Players who dropped items
      robot_building = false      -- Whether robots are building
    }
  end
  
  -- Clean up old exclusions (keep only last 5 ticks for safety)
  for tick, _ in pairs(global.insert_item_collated_exclusions) do
    if tick < current_tick - 5 then
      global.insert_item_collated_exclusions[tick] = nil
    end
  end
end

-- ============================================================================
-- EXCLUSION EVENT HANDLERS
-- ============================================================================

-- Track crafting events that cause inventory changes
local function on_player_crafted_item(e)
  if not shared_utils.is_player_event(e) then return end
  
  initialize_exclusion_tracking()
  local exclusions = global.insert_item_collated_exclusions[game.tick]
  exclusions.crafting_players[e.player_index] = true
end

-- Track building events that cause inventory changes
local function on_built_entity(e)
  if not shared_utils.is_player_event(e) then return end
  
  initialize_exclusion_tracking()
  local exclusions = global.insert_item_collated_exclusions[game.tick]
  exclusions.building_players[e.player_index] = true
end

local function on_robot_built_entity(e)
  initialize_exclusion_tracking()
  local exclusions = global.insert_item_collated_exclusions[game.tick]
  exclusions.robot_building = true
end

-- Track mining events that cause inventory changes
local function on_player_mined_entity(e)
  if not shared_utils.is_player_event(e) then return end
  
  initialize_exclusion_tracking()
  local exclusions = global.insert_item_collated_exclusions[game.tick]
  exclusions.mining_players[e.player_index] = true
end

local function on_player_mined_item(e)
  if not shared_utils.is_player_event(e) then return end
  
  initialize_exclusion_tracking()
  local exclusions = global.insert_item_collated_exclusions[game.tick]
  exclusions.mining_players[e.player_index] = true
end

-- ============================================================================
-- PLAYER STATE TRACKING
-- ============================================================================
local function initialize_player_state(player_index)
  if not global.insert_item_collated_state then
    global.insert_item_collated_state = {}
  end
  if not global.insert_item_collated_state[player_index] then
    global.insert_item_collated_state[player_index] = {
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
local function log_transfer(event_name, player, transfer_type, details)
  local rec = shared_utils.create_base_record(event_name, {
    tick = game.tick,
    player_index = player.index
  })
  
  rec.action = "insert_item_collated"
  rec.transfer_type = transfer_type
  
  -- Add details
  for key, value in pairs(details) do
    rec[key] = value
  end
  
  shared_utils.add_player_context_if_missing(rec, player)
  local clean_rec = shared_utils.clean_record(rec)
  local line = game.table_to_json(clean_rec)
  shared_utils.buffer_event("insert_item_collated", line)
end

-- ============================================================================
-- MAIN EVENT HANDLERS
-- ============================================================================

-- 1. Fast transfer (Ctrl/Shift + Click with GUI closed) - always log these
local function on_fast_transferred(e)
  if not shared_utils.is_player_event(e) then return end
  
  -- Mark this as an explicit log to prevent diff-based duplicate
  initialize_exclusion_tracking()
  local exclusions = global.insert_item_collated_exclusions[game.tick]
  exclusions.fast_transfer_players[e.player_index] = true
  global.last_explicit_log_tick[e.player_index] = game.tick
  
  local player = game.players[e.player_index]
  local transfer_type = e.from_player and "fast_transfer_to_entity" or "fast_transfer_from_entity"
  
  log_transfer("on_player_fast_transferred", player, transfer_type, {
    entity = e.entity and e.entity.name or nil,
    is_split = e.is_split,
    from_player = e.from_player
  })
end

-- 2. Drop to ground (Z key over empty space) - always log these
local function on_dropped_item(e)
  if not shared_utils.is_player_event(e) then return end
  
  -- Mark this as an explicit log to prevent diff-based duplicate
  initialize_exclusion_tracking()
  local exclusions = global.insert_item_collated_exclusions[game.tick]
  exclusions.drop_players[e.player_index] = true
  global.last_explicit_log_tick[e.player_index] = game.tick
  
  local player = game.players[e.player_index]
  local item_name, item_count = shared_utils.get_item_info(e.entity.stack)
  
  log_transfer("on_player_dropped_item", player, "drop_to_ground", {
    item = item_name,
    count = item_count,
    entity = "item-on-ground"
  })
end

-- 3. Selected entity changed (for Z-key context tracking)
local function on_selected_entity_changed(e)
  if not shared_utils.is_player_event(e) then return end
  
  initialize_player_state(e.player_index)
  local state = global.insert_item_collated_state[e.player_index]
  
  -- Store the selected entity and its inventory snapshot
  state.selected_entity = e.last_entity
  if e.last_entity and e.last_entity.valid then
    state.selected_entity_snapshot = get_entity_inventory_snapshot(e.last_entity)
  else
    state.selected_entity_snapshot = {}
  end
end

-- 4. Cursor stack changes (for intent tracking)
local function on_cursor_stack_changed(e)
  if not shared_utils.is_player_event(e) then return end
  
  local player = game.players[e.player_index]
  initialize_player_state(e.player_index)
  
  local state = global.insert_item_collated_state[e.player_index]
  local cursor_item, cursor_count = get_cursor_stack_info(player)
  
  -- Track when cursor becomes empty (useful for some edge cases)
  if not cursor_item and state.previous_cursor_stack then
    state.cursor_became_empty_tick = game.tick
  end
  
  state.previous_cursor_stack = cursor_item and {name = cursor_item, count = cursor_count} or nil
end

-- 5. GUI opened/closed (for context tracking)
local function on_gui_opened(e)
  if not shared_utils.is_player_event(e) then return end
  
  initialize_player_state(e.player_index)
  local state = global.insert_item_collated_state[e.player_index]
  
  state.open_gui_entity = e.entity and e.entity.name or nil
end

local function on_gui_closed(e)
  if not shared_utils.is_player_event(e) then return end
  
  initialize_player_state(e.player_index)
  local state = global.insert_item_collated_state[e.player_index]
  
  state.open_gui_entity = nil
end

-- 6. Main inventory changed (with filtering for excluded events)
local function on_main_inventory_changed(e)
  if not shared_utils.is_player_event(e) then return end
  
  initialize_exclusion_tracking()
  local exclusions = global.insert_item_collated_exclusions[game.tick]
  
  -- Skip if this inventory change is caused by an excluded event
  if exclusions.crafting_players[e.player_index] or 
     exclusions.building_players[e.player_index] or 
     exclusions.mining_players[e.player_index] or
     exclusions.fast_transfer_players[e.player_index] or
     exclusions.drop_players[e.player_index] or
     exclusions.robot_building then
    return
  end
  
  -- Additional guard: skip if we just logged something explicitly this tick
  if global.last_explicit_log_tick[e.player_index] == game.tick then
    return
  end
  
  local player = game.players[e.player_index]
  initialize_player_state(e.player_index)
  
  local state = global.insert_item_collated_state[e.player_index]
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
    
    -- Process each item change
    for item, player_change in pairs(player_delta) do
      if player_change ~= 0 then
        local entity_change = entity_delta[item] or 0
        local transfer_type = "unknown_transfer"
        local target_entity = nil
        
        -- Check if this is a Z-key insert/extract (player delta negates entity delta)
        if entity_change ~= 0 and player_change == -entity_change then
          if player_change < 0 then
            -- Player lost items, entity gained them
            transfer_type = "z_key_insert"
            -- Add validity check before accessing entity.name
            target_entity = get_entity_name_safe(state.selected_entity)
          else
            -- Player gained items, entity lost them
            transfer_type = "z_key_extract"
            -- Add validity check before accessing entity.name
            target_entity = get_entity_name_safe(state.selected_entity)
          end
        elseif state.open_gui_entity then
          -- GUI was open - this is likely a stack transfer or drag-drop
          transfer_type = "gui_transfer"
          target_entity = state.open_gui_entity
        elseif state.cursor_became_empty_tick and (game.tick - state.cursor_became_empty_tick) <= 2 then
          -- Cursor became empty recently (fallback for edge cases)
          transfer_type = "cursor_insert"
          target_entity = get_entity_name_safe(state.selected_entity)
        else
          -- Some other kind of transfer - but since we filtered out the main causes,
          -- this might be a legitimate transfer we should log
          transfer_type = "inventory_change"
        end
        
        log_transfer("on_player_main_inventory_changed", player, transfer_type, {
          item = item,
          count = math.abs(player_change),
          direction = player_change > 0 and "to_player" or "from_player",
          target_entity = target_entity
        })
      end
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
  local state = global.insert_item_collated_state[e.player_index]
  
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
function insert_item_collated.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_player_crafted_item, on_player_crafted_item)
  event_dispatcher.register_handler(defines.events.on_built_entity, on_built_entity)
  event_dispatcher.register_handler(defines.events.on_robot_built_entity, on_robot_built_entity)
  event_dispatcher.register_handler(defines.events.on_player_mined_entity, on_player_mined_entity)
  event_dispatcher.register_handler(defines.events.on_player_mined_item, on_player_mined_item)
  
  -- Fast transfer and inventory events
  event_dispatcher.register_handler(defines.events.on_player_fast_transferred, on_fast_transferred)
  event_dispatcher.register_handler(defines.events.on_player_dropped_item, on_dropped_item)
  
  -- Inventory tracking
  event_dispatcher.register_handler(defines.events.on_player_main_inventory_changed, on_main_inventory_changed)
  
  -- Context tracking
  event_dispatcher.register_handler(defines.events.on_selected_entity_changed, on_selected_entity_changed)
  event_dispatcher.register_handler(defines.events.on_player_cursor_stack_changed, on_cursor_stack_changed)
  event_dispatcher.register_handler(defines.events.on_gui_opened, on_gui_opened)
  event_dispatcher.register_handler(defines.events.on_gui_closed, on_gui_closed)
  
  -- Player lifecycle
  event_dispatcher.register_handler(defines.events.on_player_joined_game, on_player_joined)
end

function insert_item_collated.on_init()
  if not global.insert_item_collated_exclusions then
    global.insert_item_collated_exclusions = {}
  end
  if not global.insert_item_collated_state then
    global.insert_item_collated_state = {}
  end
  if not global.last_explicit_log_tick then
    global.last_explicit_log_tick = {}
  end
end

function insert_item_collated.on_load()
  -- No special loading required for this module
end

return insert_item_collated 