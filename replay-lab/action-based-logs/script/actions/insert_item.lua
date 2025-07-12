--@insert_item.lua
--@description Comprehensive item transfer action logger
--@author Harshit Sharma
--@version 2.0.0
--@date 2025-01-27
--@note Implements full item transfer detection based on Factorio 1.1.110 event landscape

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

-- 1. Fast transfer (Ctrl/Shift + Click with GUI closed)
local function on_fast_transferred(e)
  if not shared_utils.is_player_event(e) then return end
  
  local player = game.players[e.player_index]
  local transfer_type = e.from_player and "fast_transfer_to_entity" or "fast_transfer_from_entity"
  
  log_transfer("on_player_fast_transferred", player, transfer_type, {
    entity = e.entity and e.entity.name or nil,
    is_split = e.is_split,
    from_player = e.from_player
  })
end

-- 2. Drop to ground (Z key over empty space)
local function on_dropped_item(e)
  if not shared_utils.is_player_event(e) then return end
  
  local player = game.players[e.player_index]
  local item_name, item_count = shared_utils.get_item_info(e.entity.stack)
  
  log_transfer("on_player_dropped_item", player, "drop_to_ground", {
    item = item_name,
    count = item_count,
    entity = "item-on-ground"
  })
end

-- 3. Cursor stack changes (for intent tracking)
local function on_cursor_stack_changed(e)
  if not shared_utils.is_player_event(e) then return end
  
  local player = game.players[e.player_index]
  initialize_player_state(e.player_index)
  
  local state = global.insert_item_state[e.player_index]
  local cursor_item, cursor_count = get_cursor_stack_info(player)
  
  -- Track when cursor becomes empty (useful for Z-key insert detection)
  if not cursor_item and state.previous_cursor_stack then
    state.cursor_became_empty_tick = game.tick
    state.selected_entity = player.selected and player.selected.name or nil
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

-- 5. Main inventory changed (handles everything else via diffing)
local function on_main_inventory_changed(e)
  if not shared_utils.is_player_event(e) then return end
  
  local player = game.players[e.player_index]
  initialize_player_state(e.player_index)
  
  local state = global.insert_item_state[e.player_index]
  local current_inventory = get_inventory_snapshot(player.get_main_inventory())
  
  -- Compute delta
  local delta = compute_inventory_delta(state.previous_main_inventory, current_inventory)
  
  -- Only log if there's actually a change
  local has_changes = false
  for item, change in pairs(delta) do
    if change ~= 0 then
      has_changes = true
      break
    end
  end
  
  if has_changes then
    -- Determine transfer context
    local transfer_type = "unknown_transfer"
    local target_entity = nil
    
    if state.open_gui_entity then
      -- GUI was open - this is likely a stack transfer or drag-drop
      transfer_type = "gui_transfer"
      target_entity = state.open_gui_entity
    elseif state.cursor_became_empty_tick and (game.tick - state.cursor_became_empty_tick) <= 2 then
      -- Cursor became empty recently, likely Z-key insert
      transfer_type = "z_key_insert"
      target_entity = state.selected_entity
    else
      -- Some other kind of transfer
      transfer_type = "inventory_change"
    end
    
    -- Log each item change
    for item, change in pairs(delta) do
      if change ~= 0 then
        log_transfer("on_player_main_inventory_changed", player, transfer_type, {
          item = item,
          count = math.abs(change),
          direction = change > 0 and "to_player" or "from_player",
          target_entity = target_entity
        })
      end
    end
  end
  
  -- Update state
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
end

-- ============================================================================
-- PUBLIC INTERFACE
-- ============================================================================
function insert_item.register_events()
  -- Core transfer events
  script.on_event(defines.events.on_player_fast_transferred, on_fast_transferred)
  script.on_event(defines.events.on_player_dropped_item, on_dropped_item)
  script.on_event(defines.events.on_player_main_inventory_changed, on_main_inventory_changed)
  
  -- Context tracking events
  script.on_event(defines.events.on_player_cursor_stack_changed, on_cursor_stack_changed)
  script.on_event(defines.events.on_gui_opened, on_gui_opened)
  script.on_event(defines.events.on_gui_closed, on_gui_closed)
  
  -- Player lifecycle
  script.on_event(defines.events.on_player_joined_game, on_player_joined)
end

return insert_item 