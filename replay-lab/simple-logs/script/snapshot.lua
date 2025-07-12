-- snapshot.lua
-- Factorio 1.1.110-compatible deterministic snapshot module
-- NO EVENTS - direct scan of all entities and inventories at target tick

local shared_utils = require("script.shared-utils")
local Snapshot = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local SNAPSHOT_INTERVAL = 10000  -- Every 10k ticks like the original

-- ============================================================================
-- DIRECT COLLECTION (NO EVENTS)
-- ============================================================================

-- Scan all entities on all surfaces (deterministic order)
local function collect_all_entities()
  local entity_counts = {}
  
  -- Get surfaces in deterministic order
  local surface_names = {}
  for name, _ in pairs(game.surfaces) do
    table.insert(surface_names, name)
  end
  table.sort(surface_names)
  
  for _, surface_name in ipairs(surface_names) do
    local surface = game.surfaces[surface_name]
    if surface and surface.valid then
      local entities = surface.find_entities()
      for _, entity in ipairs(entities) do
        if entity and entity.valid and entity.name then
          -- Skip trivial entities that can cause non-determinism
          if entity.type ~= "item-entity" 
             and entity.type ~= "flying-text"
             and entity.type ~= "particle"
             and entity.type ~= "corpse"
             and entity.type ~= "projectile" then
            entity_counts[entity.name] = (entity_counts[entity.name] or 0) + 1
          end
        end
      end
    end
  end
  
  return entity_counts
end

-- Scan all inventories everywhere (deterministic order)
local function collect_all_items()
  local item_counts = {}
  
  local function merge_inventory(inv)
    if inv and inv.valid then
      local contents = inv.get_contents()
      for item_name, count in pairs(contents) do
        item_counts[item_name] = (item_counts[item_name] or 0) + count
      end
    end
  end
  
  -- Player inventories (deterministic order by index)
  local player_indices = {}
  for idx, _ in pairs(game.players) do
    table.insert(player_indices, idx)
  end
  table.sort(player_indices)
  
  for _, player_idx in ipairs(player_indices) do
    local player = game.players[player_idx]
    if player and player.valid then
      -- All player inventory types
      local player_inventory_types = {
        defines.inventory.character_main,
        defines.inventory.character_guns,
        defines.inventory.character_ammo,
        defines.inventory.character_armor,
        defines.inventory.character_vehicle,
        defines.inventory.character_trash
      }
      
      for _, inv_type in ipairs(player_inventory_types) do
        merge_inventory(player.get_inventory(inv_type))
      end
    end
  end
  
  -- Entity inventories (deterministic surface order)
  local surface_names = {}
  for name, _ in pairs(game.surfaces) do
    table.insert(surface_names, name)
  end
  table.sort(surface_names)
  
  for _, surface_name in ipairs(surface_names) do
    local surface = game.surfaces[surface_name]
    if surface and surface.valid then
      local entities = surface.find_entities()
      for _, entity in ipairs(entities) do
        if entity and entity.valid then
          -- Try all possible inventory slots (entities can have various inventories)
          for i = 1, 20 do
            merge_inventory(entity.get_inventory(i))
          end
          
          -- Handle fluid storage
          if entity.fluidbox then
            for i = 1, #entity.fluidbox do
              local fluid = entity.fluidbox[i]
              if fluid and fluid.amount > 0 then
                local fluid_name = fluid.name
                local fluid_count = math.floor(fluid.amount)
                item_counts[fluid_name] = (item_counts[fluid_name] or 0) + fluid_count
              end
            end
          end
        end
      end
    end
  end
  
  return item_counts
end

-- ============================================================================
-- SNAPSHOT EXECUTION
-- ============================================================================

function Snapshot.take_full_snapshot()
  local current_tick = game.tick
  
  log('[SNAPSHOT] Starting deterministic snapshot at tick ' .. current_tick)
  
  local entity_counts = collect_all_entities()
  local item_counts = collect_all_items()
  
  -- Create snapshot record
  local snapshot_record = {
    tick = current_tick,
    action = "snapshot",
    entities = entity_counts,
    items = item_counts
  }
  
  -- Write using shared_utils for consistency
  local clean_rec = shared_utils.clean_record(snapshot_record)
  local line = game.table_to_json(clean_rec)
  shared_utils.buffer_event("snapshot", line)
  
  log('[SNAPSHOT] Completed deterministic snapshot - entities: ' .. 
      table_size(entity_counts) .. ', items: ' .. table_size(item_counts))
end

-- ============================================================================
-- EVENT REGISTRATION
-- ============================================================================

function Snapshot.register_events()
  -- Use on_nth_tick for deterministic periodic snapshots (like the original)
  script.on_nth_tick(SNAPSHOT_INTERVAL, function(event)
    Snapshot.take_full_snapshot()
  end)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function Snapshot.initialize()
  -- Register events
  Snapshot.register_events()
  
  log("Deterministic snapshot system initialized - taking snapshots every " .. 
      SNAPSHOT_INTERVAL .. " ticks")
end

return Snapshot