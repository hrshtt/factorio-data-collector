--@player_inventory.lua
--@description Player inventory tracking with per-tick diffs and context tagging
--@author Harshit Sharma  
--@version 1.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("script.shared-utils")
local player_inventory = {}

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

-- Storage structure:
-- global.player_inventory_state[player_index] = {
--   last_snapshot = {item_name = count, ...},
--   pending_contexts = {event_name = context_data, ...},
--   current_tick_context = "CONTEXT_LABEL" or nil
-- }

function player_inventory.init_player_state(player_index)
  if not global.player_inventory_state then
    global.player_inventory_state = {}
  end
  
  if not global.player_inventory_state[player_index] then
    global.player_inventory_state[player_index] = {
      last_snapshot = {},
      pending_contexts = {},
      current_tick_context = nil
    }
  end
end

function player_inventory.get_inventory_snapshot(player)
  if not player or not player.valid then
    return {}
  end
  
  local inventory = player.get_main_inventory()
  if not inventory or not inventory.valid then
    return {}
  end
  
  local snapshot = {}
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack and stack.valid_for_read then
      local name = stack.name
      snapshot[name] = (snapshot[name] or 0) + stack.count
    end
  end
  
  return snapshot
end

function player_inventory.compute_diff(old_snapshot, new_snapshot)
  local diff = {}
  
  -- Items that changed or were removed
  for item, old_count in pairs(old_snapshot) do
    local new_count = new_snapshot[item] or 0
    local delta = new_count - old_count
    if delta ~= 0 then
      diff[item] = delta
    end
  end
  
  -- Items that were added
  for item, new_count in pairs(new_snapshot) do
    if not old_snapshot[item] then
      diff[item] = new_count
    end
  end
  
  return diff
end

-- ============================================================================
-- EVENT HANDLERS - PRE/POST PAIRS (require buffering)
-- ============================================================================

function player_inventory.handle_on_pre_player_mined_item(event_data)
  local player_index = event_data.player_index
  if not player_index then return end
  
  player_inventory.init_player_state(player_index)
  local state = global.player_inventory_state[player_index]
  
  -- Store context for the upcoming POST event
  state.pending_contexts["on_pre_player_mined_item"] = {
    context = "MINE_ENTITY",
    entity = event_data.entity and event_data.entity.name,
    position = event_data.position
  }
end

function player_inventory.handle_on_player_mined_entity(event_data)
  player_inventory.merge_pending_context(event_data.player_index, "on_pre_player_mined_item", "MINE_ENTITY")
end

function player_inventory.handle_on_player_mined_item(event_data)
  player_inventory.merge_pending_context(event_data.player_index, "on_pre_player_mined_item", "MINE_ENTITY")
end

function player_inventory.handle_on_player_mined_tile(event_data)
  player_inventory.merge_pending_context(event_data.player_index, "on_pre_player_mined_item", "MINE_ENTITY")
end

function player_inventory.handle_on_pre_build(event_data)
  local player_index = event_data.player_index
  if not player_index then return end
  
  player_inventory.init_player_state(player_index)
  local state = global.player_inventory_state[player_index]
  
  -- Store context for the upcoming POST event
  state.pending_contexts["on_pre_build"] = {
    context = "BUILD_ENTITY",
    direction = event_data.direction,
    position = event_data.position
  }
end

function player_inventory.handle_on_built_entity(event_data)
  player_inventory.merge_pending_context(event_data.player_index, "on_pre_build", "BUILD_ENTITY")
end

function player_inventory.handle_on_pre_player_crafted_item(event_data)
  local player_index = event_data.player_index
  if not player_index then return end
  
  player_inventory.init_player_state(player_index)
  local state = global.player_inventory_state[player_index]
  
  -- Store context for the upcoming POST event  
  state.pending_contexts["on_pre_player_crafted_item"] = {
    context = "CRAFT",
    recipe = event_data.recipe and event_data.recipe.name,
    queued_count = event_data.queued_count
  }
end

function player_inventory.handle_on_player_crafted_item(event_data)
  player_inventory.merge_pending_context(event_data.player_index, "on_pre_player_crafted_item", "CRAFT")
end

-- ============================================================================
-- EVENT HANDLERS - SINGLE-SHOT EVENTS (no buffering)
-- ============================================================================

function player_inventory.handle_on_player_fast_transferred(event_data)
  player_inventory.set_current_context(event_data.player_index, "FAST_TRANSFER")
end

function player_inventory.handle_on_picked_up_item(event_data)
  player_inventory.set_current_context(event_data.player_index, "PICKUP")
end

function player_inventory.handle_on_player_dropped_item(event_data)
  player_inventory.set_current_context(event_data.player_index, "DROP")
end

function player_inventory.handle_on_player_placed_equipment(event_data)
  player_inventory.set_current_context(event_data.player_index, "EQUIP_ADD")
end

function player_inventory.handle_on_player_removed_equipment(event_data)
  player_inventory.set_current_context(event_data.player_index, "EQUIP_REM")
end

function player_inventory.handle_on_player_repaired_entity(event_data)
  player_inventory.set_current_context(event_data.player_index, "REPAIR")
end

function player_inventory.handle_on_market_item_purchased(event_data)
  player_inventory.set_current_context(event_data.player_index, "MARKET_BUY")
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

function player_inventory.merge_pending_context(player_index, pre_event_name, context_label)
  if not player_index then return end
  
  player_inventory.init_player_state(player_index)
  local state = global.player_inventory_state[player_index]
  
  -- Check if we have a pending context from the PRE event
  if state.pending_contexts[pre_event_name] then
    state.current_tick_context = context_label
    -- Clear the pending context since we've used it
    state.pending_contexts[pre_event_name] = nil
  end
end

function player_inventory.set_current_context(player_index, context_label)
  if not player_index then return end
  
  player_inventory.init_player_state(player_index)
  local state = global.player_inventory_state[player_index]
  state.current_tick_context = context_label
end

-- ============================================================================
-- PLAYER LIFECYCLE HANDLERS
-- ============================================================================

function player_inventory.handle_on_player_joined_game(event_data)
  local player_index = event_data.player_index
  if not player_index then return end
  
  local player = game.players[player_index]
  if not player or not player.valid then return end
  
  -- Initialize player state and take initial inventory snapshot
  player_inventory.init_player_state(player_index)
  local state = global.player_inventory_state[player_index]
  
  -- Take initial snapshot to establish baseline
  state.last_snapshot = player_inventory.get_inventory_snapshot(player)
  
  log(string.format("[player_inventory] Initialized baseline inventory for player %d", player_index))
end

-- ============================================================================
-- MAIN UPDATE FUNCTION
-- ============================================================================

function player_inventory.update(event_data, event_name)
  -- Dispatch to specific handler
  local handler_name = "handle_" .. event_name
  local handler = player_inventory[handler_name]
  
  if handler then
    handler(event_data)
  else
    log(string.format("[player_inventory] No handler for event: %s", event_name))
  end
end

-- ============================================================================
-- TICK PROCESSING
-- ============================================================================

function player_inventory.process_tick(tick)
  if not global.player_inventory_state then
    return
  end
  
  for player_index, state in pairs(global.player_inventory_state) do
    local player = game.players[player_index]
    if player and player.valid and player.connected then
      -- Take current snapshot
      local current_snapshot = player_inventory.get_inventory_snapshot(player)
      
      -- Compute diff vs last snapshot
      local diff = player_inventory.compute_diff(state.last_snapshot, current_snapshot)
      
      -- If there's a non-empty diff, create a log record
      if next(diff) then
        local context = state.current_tick_context or "UNKNOWN"
        
        local rec = {
          t = tick,
          p = player_index,
          ev = "PlayerInventoryDelta",
          context = context,
          diff = diff
        }
        
        -- Add player position
        if player.position then
          rec.x = string.format("%.1f", player.position.x)
          rec.y = string.format("%.1f", player.position.y)
        end
        
        local clean_rec = shared_utils.clean_record(rec)
        local line = game.table_to_json(clean_rec)
        shared_utils.buffer_event("player_inventory", line)
      end
      
      -- Update state for next tick
      state.last_snapshot = current_snapshot
      state.current_tick_context = nil  -- Clear context after processing
    end
  end
end

return player_inventory 