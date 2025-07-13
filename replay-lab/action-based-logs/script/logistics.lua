--@logistics.lua
--@description Utility functions for logistics
--@author Harshit Sharma
--@version 3.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("script.shared-utils")
local logistics = {}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

function logistics.diff_tables(old_contents, new_contents)
  local deltas = {}

  -- Check for removed/decreased items
  for item, old_count in pairs(old_contents or {}) do
    local new_count = new_contents[item] or 0
    local delta = new_count - old_count
    if delta ~= 0 then
      deltas[item] = delta
    end
  end

  -- Check for added/increased items
  for item, new_count in pairs(new_contents or {}) do
    if not old_contents or not old_contents[item] then
      deltas[item] = new_count
    end
  end

  return deltas
end

function logistics.get_inventory_contents(holder, inventory_type)
  if not (holder and holder.valid) then
    return {}
  end

  local inventory = holder.get_inventory and holder.get_inventory(inventory_type)
  if not (inventory and inventory.valid) then
    return {}
  end

  return inventory.get_contents() or {}
end

function logistics.find_primary_inventory_index(entity)
  if not (entity and entity.valid) then
    return nil
  end

  -- Check rocket-silo FIRST before assembling-machine since silos inherit from assembling-machine
  if entity.name == "rocket-silo" then
    return defines.inventory.rocket_silo_input
  elseif entity.type == "container" or entity.type == "logistic-container" then
    return defines.inventory.chest
  elseif entity.type == "assembling-machine" then
    return defines.inventory.assembling_machine_input
  elseif entity.type == "furnace" then
    return defines.inventory.furnace_source
  else
    return defines.inventory.car_trunk
  end
end

function logistics.get_player_context(player_index)
  if not global.player_contexts then
    global.player_contexts = {}
  end

  if not global.player_contexts[player_index] then
    global.player_contexts[player_index] = {
      gui = nil,
      ephemeral = nil,
      last_player_snapshot = {},
      last_selected_entity = nil,
      last_craft_start = nil
    }
  end

  return global.player_contexts[player_index]
end

function logistics.update_player_snapshot(player_index)
  local player = game.players[player_index]
  if not (player and player.valid) then
    return
  end

  local ctx = logistics.get_player_context(player_index)
  ctx.last_player_snapshot = logistics.get_inventory_contents(player, defines.inventory.character_main)
end

function logistics.matches_entity_gui(gui_event, entity)
  return gui_event.entity and gui_event.entity.valid and
      entity and entity.valid and
      gui_event.entity.unit_number == entity.unit_number
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function logistics.initialize()
  if not global.player_contexts then
    global.player_contexts = {}
  end
  if not global.entity_snapshots then
    global.entity_snapshots = {}
  end
end

-- ============================================================================
-- ENTITY SNAPSHOT MANAGEMENT
-- ============================================================================

function logistics.get_entity_snapshot(entity, inventory_index)
  if not (entity and entity.valid and entity.unit_number) then
    return {}
  end

  local unit_number = entity.unit_number
  local snapshot = global.entity_snapshots[unit_number]
  if not snapshot then
    snapshot = logistics.get_inventory_contents(entity, inventory_index)
    global.entity_snapshots[unit_number] = snapshot
  end
  return snapshot
end

function logistics.update_entity_snapshot(entity, inventory_index)
  if not (entity and entity.valid and entity.unit_number) then
    return
  end

  local unit_number = entity.unit_number
  local contents = logistics.get_inventory_contents(entity, inventory_index)
  global.entity_snapshots[unit_number] = contents
end

function logistics.cleanup_entity_snapshot(entity)
  if entity and entity.unit_number then
    global.entity_snapshots[entity.unit_number] = nil
  end
end

return logistics