--@logistics.lua
--@description Optimized utility functions for logistics
--@author Harshit Sharma
--@version 3.1.0
--@date 2025-07-24
--@license MIT

local shared_utils = require('script.shared-utils')
local logistics = {}

-- Internal cache and special-case registry
local proto_cache = {}
local special_inventories = {
  ['rocket-silo'] = function(e)
    return {
      defines.inventory.rocket_silo_input,
      defines.inventory.rocket_silo_output,
      defines.inventory.rocket_silo_modules,
      defines.inventory.rocket_silo_result,
      defines.inventory.rocket_silo_rocket,
    }
  end,
  ['roboport'] = function(e)
    return {
      defines.inventory.roboport_robot,
      defines.inventory.roboport_material,
    }
  end,
}

-- Dynamic reflection to discover inventories for any entity
local function inventories_for(e)
  local proto = e.prototype
  local name = proto.name
  if proto_cache[name] then return proto_cache[name] end
  local invs = {}
  if special_inventories[name] then
    for _, idx in ipairs(special_inventories[name](e)) do invs[idx] = true end
  else
    for _, idx in pairs(defines.inventory) do
      if proto.get_inventory_size(idx) and proto.get_inventory_size(idx) > 0 then
        invs[idx] = true
      end
    end
  end
  proto_cache[name] = invs
  return invs
end

-- Get a snapshot of all inventories (idx → contents)
function logistics.get_inventory_contents(entity)
  if not (entity and entity.valid) then return {} end
  local snap = {}
  for idx in pairs(inventories_for(entity)) do
    local inv = entity.get_inventory(idx)
    if inv and inv.valid then
      snap[idx] = inv.get_contents()
    end
  end
  return snap
end

-- Combine all snapshots into a flat contents table
function logistics.get_combined_inventory_contents(entity)
  local combined = {}
  for _, snap in pairs(logistics.get_inventory_contents(entity)) do
    for item, count in pairs(snap) do
      combined[item] = (combined[item] or 0) + count
    end
  end
  return combined
end

-- Diff two content tables (item → delta)
function logistics.diff_tables(old_contents, new_contents)
  local deltas = {}
  for item, old_count in pairs(old_contents or {}) do
    local new_count = new_contents[item] or 0
    local delta = new_count - old_count
    if delta ~= 0 then deltas[item] = delta end
  end
  for item, new_count in pairs(new_contents or {}) do
    if not (old_contents and old_contents[item]) then deltas[item] = new_count end
  end
  return deltas
end

-- Find first non-empty inventory index
function logistics.find_primary_inventory_index(entity)
  if not (entity and entity.valid) then return nil end
  for idx in pairs(inventories_for(entity)) do
    local inv = entity.get_inventory(idx)
    if inv and inv.valid and not inv.is_empty() then
      return idx
    end
  end
  return nil
end

-- Check if player can access any inventories
function logistics.is_player_accessible(entity)
  return entity and entity.valid
    and entity.prototype.has_flag('player-creation')
    and next(inventories_for(entity)) ~= nil
end

-- Check if item can be inserted (not placeable)
function logistics.can_be_inserted(item_name)
  if not item_name then return false end
  local proto = game.item_prototypes[item_name]
  return proto and not proto.place_result and not proto.place_as_equipment_result
end

-- Retrieve player inventory contents (flat)
function logistics.get_player_inventory_contents(player)
  if not (player and player.valid) then return {} end
  local combined = {}
  for _, idx in ipairs({
    defines.inventory.character_main,
    -- defines.inventory.character_guns, -- enable when not in peaceful mode
    -- defines.inventory.character_ammo, -- enable when not in peaceful mode
    -- defines.inventory.character_armor, -- enable when not in peaceful mode
    defines.inventory.character_trash,
  }) do
    local inv = player.get_inventory(idx)
    if inv and inv.valid then
      for item, count in pairs(inv.get_contents()) do
        combined[item] = (combined[item] or 0) + count
      end
    end
  end
  return combined
end

-- Context and snapshot management unchanged
function logistics.get_player_context(player_index)
  global.player_contexts = global.player_contexts or {}
  if not global.player_contexts[player_index] then
    global.player_contexts[player_index] = {
      gui = nil,
      ephemeral = nil,
      last_player_snapshot = {},
      last_selected_entity = nil,
      last_craft_start = nil,
    }
  end
  return global.player_contexts[player_index]
end

function logistics.update_player_snapshot(player_index)
  local player = game.players[player_index]
  if player and player.valid then
    logistics.get_player_context(player_index).last_player_snapshot =
      logistics.get_player_inventory_contents(player)
  end
end

function logistics.matches_entity_gui(gui_event, entity)
  return gui_event.entity and gui_event.entity.valid
    and entity and entity.valid
    and gui_event.entity.unit_number == entity.unit_number
end

function logistics.initialize()
  global.player_contexts = global.player_contexts or {}
  global.entity_snapshots = global.entity_snapshots or {}
end

function logistics.get_entity_snapshot(entity, inventory_index)
  if not (entity and entity.valid and entity.unit_number) then return {} end
  local unit = entity.unit_number
  if not global.entity_snapshots[unit] then
    local inv = entity.get_inventory(inventory_index)
    global.entity_snapshots[unit] = inv and inv.get_contents() or {}
  end
  return global.entity_snapshots[unit]
end

function logistics.update_entity_snapshot(entity, inventory_index)
  if entity and entity.valid and entity.unit_number then
    local inv = entity.get_inventory(inventory_index)
    global.entity_snapshots[entity.unit_number] = inv and inv.get_contents() or {}
  end
end

function logistics.cleanup_entity_snapshot(entity)
  if entity and entity.unit_number then
    global.entity_snapshots[entity.unit_number] = nil
  end
end

return logistics