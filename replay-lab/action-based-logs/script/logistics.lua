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

function logistics.get_inventory_contents(entity)
  if not entity or not entity.valid then return {} end

  local contents = {}
  local inventory = entity.get_inventory(defines.inventory.chest)

  -- Try different inventory types based on entity type
  if not inventory then
    if entity.type == "assembling-machine" or entity.type == "oil-refinery" or entity.type == "chemical-plant" then
      inventory = entity.get_inventory(defines.inventory.assembling_machine_input)
    elseif entity.type == "furnace" then
      inventory = entity.get_inventory(defines.inventory.furnace_source)
    elseif entity.type == "character" then
      inventory = entity.get_inventory(defines.inventory.character_main)
    elseif entity.type == "lab" then
      inventory = entity.get_inventory(defines.inventory.lab_input)
    elseif entity.type == "mining-drill" then
      inventory = entity.get_inventory(defines.inventory.mining_drill_modules)
    elseif entity.type == "roboport" then
      inventory = entity.get_inventory(defines.inventory.roboport_robot)
    elseif entity.type == "turret" or entity.type == "ammo-turret" then
      inventory = entity.get_inventory(defines.inventory.turret_ammo)
    end
  end

  if inventory and inventory.valid then
    contents = inventory.get_contents()
  end

  return contents or {}
end

function logistics.get_inventory_contents_by_holder(holder, inventory_type)
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
  elseif entity.type == "assembling-machine" or entity.type == "oil-refinery" or entity.type == "chemical-plant" then
    return defines.inventory.assembling_machine_input
  elseif entity.type == "furnace" then
    return defines.inventory.furnace_source
  elseif entity.type == "mining-drill" then
    return defines.inventory.mining_drill_modules
  elseif entity.type == "lab" then
    return defines.inventory.lab_input
  elseif entity.type == "turret" or entity.type == "ammo-turret" then
    return defines.inventory.turret_ammo
  elseif entity.type == "artillery-turret" then
    return defines.inventory.artillery_turret_ammo
  elseif entity.type == "roboport" then
    return defines.inventory.roboport_robot
  elseif entity.type == "beacon" then
    return defines.inventory.beacon_modules
  elseif entity.type == "character" then
    return defines.inventory.character_main
  elseif entity.type == "car" or entity.type == "tank" then
    return defines.inventory.car_trunk
  elseif entity.type == "spider-vehicle" then
    return defines.inventory.spider_trunk
  elseif entity.type == "cargo-wagon" then
    return defines.inventory.cargo_wagon
  elseif entity.type == "artillery-wagon" then
    return defines.inventory.artillery_wagon_ammo
  elseif entity.type == "reactor" then
    return defines.inventory.fuel
  elseif entity.type == "boiler" or entity.type == "burner-generator" then
    return defines.inventory.fuel
  else
    return defines.inventory.chest -- fallback for unknown types
  end
end

-- Get all relevant inventories for an entity (for comprehensive diffing)
function logistics.get_all_relevant_inventories(entity)
  if not (entity and entity.valid) then
    return {}
  end

  local inventories = {}
  
  if entity.type == "furnace" then
    -- For furnaces, track fuel, result, and modules slots since players interact with all
    inventories[defines.inventory.furnace_source] = "source"
    inventories[defines.inventory.furnace_result] = "result"
    if entity.get_inventory(defines.inventory.furnace_modules) then
      inventories[defines.inventory.furnace_modules] = "modules"
    end
  elseif entity.type == "mining-drill" then
    -- For mining drills, track modules and fuel (for burner drills)
    if entity.get_inventory(defines.inventory.mining_drill_modules) then
      inventories[defines.inventory.mining_drill_modules] = "modules"
    end
    -- Burner mining drills have a fuel inventory
    if entity.get_inventory(defines.inventory.fuel) then
      inventories[defines.inventory.fuel] = "fuel"
    end
    -- Note: Mining drills don't have an output inventory accessible via API
    -- They output directly to belts/inserters, which is why extractions appear as no-ops
  elseif entity.type == "assembling-machine" or entity.type == "oil-refinery" or entity.type == "chemical-plant" then
    inventories[defines.inventory.assembling_machine_input] = "input"
    inventories[defines.inventory.assembling_machine_output] = "output"
    inventories[defines.inventory.assembling_machine_modules] = "modules"
  elseif entity.name == "rocket-silo" then
    inventories[defines.inventory.rocket_silo_input] = "input"
    inventories[defines.inventory.rocket_silo_output] = "output"
    inventories[defines.inventory.rocket_silo_modules] = "modules"
    if entity.get_inventory(defines.inventory.rocket_silo_result) then
      inventories[defines.inventory.rocket_silo_result] = "result"
    end
    if entity.get_inventory(defines.inventory.rocket_silo_rocket) then
      inventories[defines.inventory.rocket_silo_rocket] = "rocket"
    end
  elseif entity.type == "lab" then
    inventories[defines.inventory.lab_input] = "input"
    inventories[defines.inventory.lab_modules] = "modules"
  elseif entity.type == "beacon" then
    -- For beacons, track modules
    if entity.get_inventory(defines.inventory.beacon_modules) then
      inventories[defines.inventory.beacon_modules] = "modules"
    end
  elseif entity.type == "roboport" then
    -- For roboports, track both robots and repair materials
    if entity.get_inventory(defines.inventory.roboport_robot) then
      inventories[defines.inventory.roboport_robot] = "robots"
    end
    if entity.get_inventory(defines.inventory.roboport_material) then
      inventories[defines.inventory.roboport_material] = "materials"
    end
  elseif entity.type == "car" or entity.type == "tank" then
    -- For cars/tanks, track trunk and ammo
    if entity.get_inventory(defines.inventory.car_trunk) then
      inventories[defines.inventory.car_trunk] = "trunk"
    end
    if entity.get_inventory(defines.inventory.car_ammo) then
      inventories[defines.inventory.car_ammo] = "ammo"
    end
  elseif entity.type == "spider-vehicle" then
    -- For spider vehicles, track trunk, ammo, and trash
    if entity.get_inventory(defines.inventory.spider_trunk) then
      inventories[defines.inventory.spider_trunk] = "trunk"
    end
    if entity.get_inventory(defines.inventory.spider_ammo) then
      inventories[defines.inventory.spider_ammo] = "ammo"
    end
    if entity.get_inventory(defines.inventory.spider_trash) then
      inventories[defines.inventory.spider_trash] = "trash"
    end
  elseif entity.type == "artillery-turret" then
    -- For artillery turrets, use the specific artillery ammo inventory
    if entity.get_inventory(defines.inventory.artillery_turret_ammo) then
      inventories[defines.inventory.artillery_turret_ammo] = "ammo"
    end
  elseif entity.type == "character" then
    -- For characters, track all relevant inventories
    if entity.get_inventory(defines.inventory.character_main) then
      inventories[defines.inventory.character_main] = "main"
    end
    if entity.get_inventory(defines.inventory.character_guns) then
      inventories[defines.inventory.character_guns] = "guns"
    end
    if entity.get_inventory(defines.inventory.character_ammo) then
      inventories[defines.inventory.character_ammo] = "ammo"
    end
    if entity.get_inventory(defines.inventory.character_armor) then
      inventories[defines.inventory.character_armor] = "armor"
    end
    if entity.get_inventory(defines.inventory.character_trash) then
      inventories[defines.inventory.character_trash] = "trash"
    end
  else
    -- For simple entities, just use the primary inventory
    local primary_idx = logistics.find_primary_inventory_index(entity)
    if primary_idx then
      inventories[primary_idx] = "primary"
    end
  end

  return inventories
end

-- Get combined inventory contents from all relevant inventories
function logistics.get_combined_inventory_contents(entity)
  if not (entity and entity.valid) then
    return {}
  end

  local combined_contents = {}
  local relevant_inventories = logistics.get_all_relevant_inventories(entity)
  
  for inventory_idx, inventory_type in pairs(relevant_inventories) do
    local inventory = entity.get_inventory(inventory_idx)
    if inventory and inventory.valid then
      local contents = inventory.get_contents()
      for item_name, count in pairs(contents) do
        combined_contents[item_name] = (combined_contents[item_name] or 0) + count
      end
    end
  end
  
  return combined_contents
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
  ctx.last_player_snapshot = logistics.get_inventory_contents_by_holder(player, defines.inventory.character_main)
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
    snapshot = logistics.get_inventory_contents_by_holder(entity, inventory_index)
    global.entity_snapshots[unit_number] = snapshot
  end
  return snapshot
end

function logistics.update_entity_snapshot(entity, inventory_index)
  if not (entity and entity.valid and entity.unit_number) then
    return
  end

  local unit_number = entity.unit_number
  local contents = logistics.get_inventory_contents_by_holder(entity, inventory_index)
  global.entity_snapshots[unit_number] = contents
end

function logistics.cleanup_entity_snapshot(entity)
  if entity and entity.unit_number then
    global.entity_snapshots[entity.unit_number] = nil
  end
end

-- Entities where a player can manually add/remove items
logistics.player_accessible_types = {
  ["assembling-machine"] = true,
  ["oil-refinery"] = true,
  ["chemical-plant"] = true,
  ["rocket-silo"] = true,
  ["furnace"] = true,
  ["container"] = true,
  ["logistic-container"] = true,
  ["infinity-container"] = true,
  ["linked-container"] = true,
  ["cargo-wagon"] = true,
  ["car"] = true,
  ["tank"] = true,
  ["spider-vehicle"] = true,
  ["artillery-wagon"] = true,
  ["mining-drill"] = true,
  ["turret"] = true,
  ["ammo-turret"] = true,
  ["artillery-turret"] = true,
  ["lab"] = true,
  ["roboport"] = true,
  ["beacon"] = true,
  ["reactor"] = true,
  ["boiler"] = true,
  ["inserter"] = true,
  ["burner-generator"] = true,
  ["market"] = true,
  ["character"] = true,
  ["character-corpse"] = true,
}

function logistics.is_player_accessible(entity)
  return entity and entity.valid and logistics.player_accessible_types[entity.type]
end

function logistics.can_be_inserted(item_name)
  if not item_name then return false end
  
  local item_prototype = game.item_prototypes[item_name]
  if not item_prototype then return false end
  
  return not item_prototype.place_result and not item_prototype.place_as_equipment_result
 end
-- Helper function to get inventory contents as a table

return logistics
