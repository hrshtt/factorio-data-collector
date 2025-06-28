--@logistics.lua
--@description Unified inventory change logging with diff-based detection
--@author Harshit Sharma
--@version 3.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("shared-utils")
local logistics = {}

-- ============================================================================
-- CORE LOGGING FUNCTION
-- ============================================================================

function logistics.log_inventory_change(record)
  -- record = {
  --   tick         = <number>,
  --   player       = <index>,
  --   item         = <string>,
  --   delta        = <integer>,
  --   source       = <"player"|"entity-name"|"crafting"|…>,
  --   destination  = <"player"|"entity-name"|"ground"|…>,
  --   context      = <table: { action=<string>, … } >
  -- }

  -- Add position if available in context
  if record.context and record.context.position then
    record.x = string.format("%.1f", record.context.position.x)
    record.y = string.format("%.1f", record.context.position.y)
  else
    -- Fallback to player position if no position in context
    local player = game.players[record.player]
    if player and player.valid and player.position then
      record.x = string.format("%.1f", player.position.x)
      record.y = string.format("%.1f", player.position.y)
    end
  end

  -- Debug unknown sources/destinations
  logistics.log_unknown_source_debug(record, record.context and record.context.action or "unknown_context")

  local clean_record = shared_utils.clean_record(record)
  local json = game.table_to_json(clean_record)
  shared_utils.buffer_event("logistics", json)
end

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

-- ============================================================================
-- GUI CONTEXT TRACKING
-- ============================================================================

function logistics.handle_gui_opened(event)
  if event.gui_type == defines.gui_type.entity and event.entity and event.player_index then
    local player = game.players[event.player_index]
    if not (player and player.valid) then
      return
    end

    local ctx = logistics.get_player_context(event.player_index)
    local inventory_index = logistics.find_primary_inventory_index(event.entity)

    if inventory_index then
      -- Take initial snapshots
      ctx.gui = {
        entity = event.entity,
        entity_inventory_index = inventory_index,
        player_snapshot = logistics.get_inventory_contents(player, defines.inventory.character_main),
        entity_snapshot = logistics.get_inventory_contents(event.entity, inventory_index)
      }

      -- Update last player snapshot if not set
      if not next(ctx.last_player_snapshot) then
        ctx.last_player_snapshot = ctx.gui.player_snapshot
      end
    end
  end
end

function logistics.handle_gui_closed(event)
  if not event.player_index then
    return
  end

  local ctx = global.player_contexts and global.player_contexts[event.player_index]
  if ctx and ctx.gui and logistics.matches_entity_gui(event, ctx.gui.entity) then
    ctx.gui = nil
  end
end

-- ============================================================================
-- CORE DIFF LISTENER
-- ============================================================================

function logistics.handle_player_inventory_changed(event)
  local ctx = logistics.get_player_context(event.player_index)
  local player = game.players[event.player_index]
  if not (player and player.valid) then
    return
  end

  -- Get current player inventory
  local new_player_contents = logistics.get_inventory_contents(player, defines.inventory.character_main)

  -- Diff player inventory vs last snapshot
  local player_deltas = logistics.diff_tables(ctx.last_player_snapshot, new_player_contents)

  for item, delta in pairs(player_deltas) do
    local source, destination, context

    -- Determine context FIRST, then set source/destination based on context
    if ctx.ephemeral then
      context = ctx.ephemeral
      
      -- Handle different ephemeral context types
      if ctx.ephemeral.action == "cursor_change" and ctx.ephemeral.target_entity then
        if delta > 0 then
          source = ctx.ephemeral.target_entity
          destination = "player"
        else
          source = "player"
          destination = ctx.ephemeral.target_entity
        end
      elseif ctx.ephemeral.action == "build" then
        source = "player"
        destination = ctx.ephemeral.entity or "construction"
      elseif ctx.ephemeral.action == "trash_change" then
        if delta > 0 then
          source = "trash"
          destination = "player"
        else
          source = "player"
          destination = "trash"
        end
      elseif ctx.ephemeral.action == "armor_change" then
        if delta > 0 then
          source = "armor"
          destination = "player"
        else
          source = "player"
          destination = "armor"
        end
      else
        -- Default ephemeral handling - still better than unknown
        if delta > 0 then
          source = ctx.ephemeral.entity or ctx.ephemeral.action or "unknown"
          destination = "player"
        else
          source = "player"
          destination = ctx.ephemeral.entity or ctx.ephemeral.action or "unknown"
        end
      end
      
    elseif ctx.gui then
      context = {
        action = "gui_transfer",
        entity = ctx.gui.entity.name,
        position = ctx.gui.entity.position
      }
      if delta > 0 then
        source = ctx.gui.entity.name
        destination = "player"
      else
        source = "player"
        destination = ctx.gui.entity.name
      end
      
    elseif delta < 0 and ctx.last_craft_start then
      -- Check if this matches a recent craft start
      context = { action = "craft_start", recipe = ctx.last_craft_start.recipe }
      source = "player"
      destination = "crafting"
      -- Clear the craft start context since we've used it
      ctx.last_craft_start = nil
      
    else
      -- Last resort - unknown cases
      context = { 
        action = "unknown",
        debug_info = {
          has_gui = ctx.gui ~= nil,
          has_ephemeral = ctx.ephemeral ~= nil,
          has_craft_start = ctx.last_craft_start ~= nil,
          opened_entity = ctx.gui and ctx.gui.entity and ctx.gui.entity.name or "none",
          cursor_stack = player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.name or "empty"
        }
      }
      if delta > 0 then
        source = "unknown"
        destination = "player"
      else
        source = "player"
        destination = "unknown"
      end
    end

    logistics.log_inventory_change {
      tick = event.tick,
      player = event.player_index,
      item = item,
      delta = delta,
      source = source,
      destination = destination,
      context = context
    }
  end

  -- Update player snapshot
  ctx.last_player_snapshot = new_player_contents

  -- If in a GUI, also diff the entity's inventory
  if ctx.gui and ctx.gui.entity and ctx.gui.entity.valid then
    local new_entity_contents = logistics.get_inventory_contents(ctx.gui.entity, ctx.gui.entity_inventory_index)
    local entity_deltas = logistics.diff_tables(ctx.gui.entity_snapshot, new_entity_contents)

    for item, delta in pairs(entity_deltas) do
      local source, destination
      if delta > 0 then
        source = "player"
        destination = ctx.gui.entity.name
      else
        source = ctx.gui.entity.name
        destination = "player"
      end

      logistics.log_inventory_change {
        tick = event.tick,
        player = event.player_index,
        item = item,
        delta = delta,
        source = source,
        destination = destination,
        context = {
          action = "gui_transfer",
          entity = ctx.gui.entity.name,
          position = ctx.gui.entity.position
        }
      }
    end

    -- Update entity snapshot
    ctx.gui.entity_snapshot = new_entity_contents
  end

  -- Clear ephemeral context so we don't double-log
  ctx.ephemeral = nil
end

-- ============================================================================
-- DIRECT EVENT HANDLERS
-- ============================================================================

function logistics.handle_fast_transferred(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local player = game.players[event.player_index]
  local entity = event.entity
  if not (player and player.valid and entity and entity.valid) then
    return
  end

  local inventory_index = logistics.find_primary_inventory_index(entity)
  if not inventory_index then
    return -- Nothing transferable
  end

  -- Get snapshots *before* the transfer (taken in previous tick)
  local ctx = logistics.get_player_context(event.player_index)
  local prev_player = ctx.last_player_snapshot
  local prev_entity = logistics.get_entity_snapshot(entity, inventory_index)

  -- Current state (after the transfer)
  local curr_player = logistics.get_inventory_contents(player, defines.inventory.character_main)
  local curr_entity = logistics.get_inventory_contents(entity, inventory_index)

  -- Diffs
  local player_deltas = logistics.diff_tables(prev_player, curr_player)

  -- Log changes based on player inventory deltas
  for item, delta in pairs(player_deltas) do
    if delta ~= 0 then
      local source, destination
      if delta > 0 then
        -- Player gained items, so entity lost them
        source = entity.name
        destination = "player"
      else
        -- Player lost items, so entity gained them
        source = "player"
        destination = entity.name
      end

      logistics.log_inventory_change {
        tick = event.tick,
        player = event.player_index,
        item = item,
        delta = math.abs(delta), -- Use positive magnitude
        source = source,
        destination = destination,
        context = {
          action = "fast_transfer",
          entity = entity.name,
          position = entity.position,
          is_split = event.is_split
        }
      }
    end
  end

  -- Update snapshots so future diffs are correct
  logistics.update_player_snapshot(event.player_index)
  logistics.update_entity_snapshot(entity, inventory_index)
end

function logistics.handle_pre_crafted_item(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)

  -- Get the number of items queued to be crafted (this accounts for bulk crafting)
  local queued_count = event.queued_count or 1

  -- Store the craft start info for matching with inventory changes
  ctx.last_craft_start = {
    recipe = event.recipe and event.recipe.name,
    item = event.item_stack and event.item_stack.name,
    count = event.item_stack and event.item_stack.count,
    queued_count = queued_count,
    tick = event.tick
  }

  -- Log the craft start (ingredients consumed) - multiply by queued_count for bulk crafting
  if event.recipe then
    for _, ingredient in pairs(event.recipe.ingredients) do
      logistics.log_inventory_change {
        tick = event.tick,
        player = event.player_index,
        item = ingredient.name,
        delta = -(ingredient.amount * queued_count),
        source = "player",
        destination = "crafting",
        context = {
          action = "craft_start",
          recipe = event.recipe.name,
          item = event.item_stack and event.item_stack.name,
          queued_count = queued_count
        }  -- Position will be filled from player position in log_inventory_change
      }
    end
  end

  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_cancelled_crafting(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  -- Use the exact cancel_count from the event (this was fixed to report exact count)
  local cancel_count = event.cancel_count or 1

  -- The cancelled crafting event has different fields than I assumed
  -- Let's use the item_stack and count from the event directly
  if event.item_stack and event.item_stack.valid_for_read then
    logistics.log_inventory_change {
      tick = event.tick,
      player = event.player_index,
      item = event.item_stack.name,
      delta = event.item_stack.count * cancel_count,
      source = "crafting",
      destination = "player",
      context = {
        action = "craft_cancel",
        item = event.item_stack.name,
        count = event.item_stack.count,
        cancel_count = cancel_count
      }  -- Position will be filled from player position in log_inventory_change
    }
  end

  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_crafted_item(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  -- Note: on_player_crafted_item fires once per completed craft,
  -- so for bulk crafting this will fire multiple times
  logistics.log_inventory_change {
    tick = event.tick,
    player = event.player_index,
    item = event.item_stack.name,
    delta = event.item_stack.count,
    source = "crafting",
    destination = "player",
    context = {
      action = "craft_complete",
      recipe = event.recipe and event.recipe.name
    }  -- Position will be filled from player position in log_inventory_change
  }

  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_player_created(event)
  -- Initialize player snapshot when player is created
  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_player_joined(event)
  -- Initialize player snapshot when player joins
  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_mined_entity(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  if event.buffer then
    local buffer_contents = event.buffer.get_contents()
    for item, count in pairs(buffer_contents) do
      logistics.log_inventory_change {
        tick = event.tick,
        player = event.player_index,
        item = item,
        delta = count,
        source = event.entity and event.entity.name or "unknown",
        destination = "player",
        context = {
          action = "mine",
          entity = event.entity and event.entity.name,
          position = event.entity and event.entity.position
        }
      }
    end
  end

  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_mined_item(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  logistics.log_inventory_change {
    tick = event.tick,
    player = event.player_index,
    item = event.item_stack.name,
    delta = event.item_stack.count,
    source = "resource",
    destination = "player",
    context = { action = "mine_item" }  -- Position will be filled from player position in log_inventory_change
  }

  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_built_entity(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  -- For building, we typically consume items from player inventory
  -- The actual consumption will be caught by the diff listener
  -- But we set ephemeral context so it knows this was a build action
  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "build",
    entity = event.created_entity and event.created_entity.name,
    position = event.created_entity and event.created_entity.position,
    built_by = event.player_index
  }
  
  -- Also immediately update player snapshot since building consumes items
  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_dropped_item(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  logistics.log_inventory_change {
    tick = event.tick,
    player = event.player_index,
    item = event.entity.stack.name,
    delta = -event.entity.stack.count,
    source = "player",
    destination = "ground",
    context = {
      action = "drop",
      position = event.entity and event.entity.position
    }
  }

  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_picked_up_item(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  logistics.log_inventory_change {
    tick = event.tick,
    player = event.player_index,
    item = event.item_stack.name,
    delta = event.item_stack.count,
    source = "ground",
    destination = "player",
    context = {
      action = "pickup",
      position = event.entity and event.entity.position
    }
  }

  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_rocket_launched(event)
  -- Rocket launches affect the silo inventory but don't have a specific player
  local silo = event.rocket_silo
  if not (silo and silo.valid) then
    return
  end

  -- For rocket launch, we'll log as a system action
  -- The rocket consumes items from the silo
  logistics.log_inventory_change {
    tick = event.tick,
    player = event.player_index or 0, -- Use 0 for system events
    item = "rocket-part",             -- Simplified - rockets consume rocket parts
    delta = -1,
    source = silo.name,
    destination = "space",
    context = {
      action = "rocket_launch",
      entity = silo.name,
      position = silo.position
    }
  }
end

function logistics.handle_entity_removed(event)
  -- Clean up entity snapshots when entities are removed
  if event.entity then
    logistics.cleanup_entity_snapshot(event.entity)
  end
end

-- ============================================================================
-- DEBUG LOGGING FOR UNKNOWN SOURCE/DESTINATION
-- ============================================================================

function logistics.log_unknown_source_debug(record, context_type)
  -- Log debug info when we have unknown source/destination
  if record.source == "unknown" or record.destination == "unknown" then
    local debug_info = {
      tick = record.tick,
      player = record.player,
      item = record.item,
      delta = record.delta,
      source = record.source,
      destination = record.destination,
      context_type = context_type,
      action = record.context and record.context.action or "no_action"
    }
    
    -- Log to console for debugging (only in development)
    if settings and settings.global and settings.global["logistics-debug-mode"] and settings.global["logistics-debug-mode"].value then
      game.print("DEBUG UNKNOWN: " .. game.table_to_json(debug_info))
    end
    
    -- Buffer as special debug event
    local debug_json = game.table_to_json(debug_info)
    shared_utils.buffer_event("logistics_debug", debug_json)
  end
end

-- ============================================================================
-- ADDITIONAL EVENT HANDLERS FOR BETTER CONTEXT TRACKING
-- ============================================================================

function logistics.handle_cursor_stack_changed(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local player = game.players[event.player_index]
  if not (player and player.valid) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  
  -- Set ephemeral context for cursor changes which might precede main inventory changes
  -- Try to determine what the cursor is interacting with
  local cursor_context = { action = "cursor_change" }
  
  if player.cursor_stack and player.cursor_stack.valid_for_read then
    cursor_context.cursor_item = player.cursor_stack.name
    cursor_context.cursor_count = player.cursor_stack.count
    
    -- If player has GUI open, cursor is likely interacting with that entity
    if ctx.gui and ctx.gui.entity and ctx.gui.entity.valid then
      cursor_context.target_entity = ctx.gui.entity.name
      cursor_context.position = ctx.gui.entity.position
    -- Use last selected entity if available
    elseif ctx.last_selected_entity and ctx.last_selected_entity.entity and ctx.last_selected_entity.entity.valid then
      cursor_context.target_entity = ctx.last_selected_entity.entity.name
      cursor_context.position = ctx.last_selected_entity.entity.position
    end
  else
    -- Empty cursor - might be placing items or picking up
    cursor_context.cursor_item = "empty"
    cursor_context.cursor_count = 0
    
    -- Still check for target entity for empty cursor operations
    if ctx.gui and ctx.gui.entity and ctx.gui.entity.valid then
      cursor_context.target_entity = ctx.gui.entity.name
      cursor_context.position = ctx.gui.entity.position
    elseif ctx.last_selected_entity and ctx.last_selected_entity.entity and ctx.last_selected_entity.entity.valid then
      cursor_context.target_entity = ctx.last_selected_entity.entity.name
      cursor_context.position = ctx.last_selected_entity.entity.position
    end
  end
  
  ctx.ephemeral = cursor_context
end

function logistics.handle_trash_inventory_changed(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "trash_change",
    inventory_type = "trash"
  }
  
  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_armor_inventory_changed(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "armor_change",
    inventory_type = "armor"
  }
  
  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_ammo_inventory_changed(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "ammo_change", 
    inventory_type = "ammo"
  }
  
  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_gun_inventory_changed(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "gun_change",
    inventory_type = "gun"
  }
  
  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_equipment_inserted(event)
  -- Track equipment insertion which might affect player inventory
  if event.grid and event.grid.entity_owner and event.grid.entity_owner.player then
    local player = event.grid.entity_owner.player
    local ctx = logistics.get_player_context(player.index)
    ctx.ephemeral = {
      action = "equipment_insert",
      equipment = event.equipment and event.equipment.name
    }
    logistics.update_player_snapshot(player.index)
  end
end

function logistics.handle_equipment_removed(event)
  -- Track equipment removal which might affect player inventory  
  if event.grid and event.grid.entity_owner and event.grid.entity_owner.player then
    local player = event.grid.entity_owner.player
    local ctx = logistics.get_player_context(player.index)
    ctx.ephemeral = {
      action = "equipment_remove",
      equipment = event.equipment and event.equipment.name
    }
    logistics.update_player_snapshot(player.index)
  end
end

function logistics.handle_capsule_used(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "use_capsule",
    capsule = event.item and event.item.name,
    position = event.position
  }
  
  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_entity_settings_pasted(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "settings_paste",
    source_entity = event.source and event.source.name,
    destination_entity = event.destination and event.destination.name,
    position = event.destination and event.destination.position
  }
end

function logistics.handle_entity_died(event)
  -- When entities die, they might drop items that get auto-picked up
  -- This can cause inventory changes without clear context
  if event.entity and event.entity.last_user then
    local ctx = logistics.get_player_context(event.entity.last_user.index)
    ctx.ephemeral = {
      action = "entity_death_items",
      entity = event.entity.name,
      position = event.entity.position
    }
  end
  
  -- Also clean up entity snapshots
  logistics.cleanup_entity_snapshot(event.entity)
end

function logistics.handle_market_purchase(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "market_purchase",
    entity = "market", 
    offer_index = event.offer_index,
    count = event.count,
    position = event.market and event.market.position
  }
  
  logistics.update_player_snapshot(event.player_index)
end

function logistics.handle_character_corpse_expired(event)
  -- Character corpses expiring might affect inventories
  if event.corpse and event.corpse.character_corpse_player_index then
    local ctx = logistics.get_player_context(event.corpse.character_corpse_player_index)
    ctx.ephemeral = {
      action = "corpse_expired",
      position = event.corpse.position
    }
  end
end

function logistics.handle_driving_changed_state(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = event.entity and "enter_vehicle" or "exit_vehicle",
    entity = event.entity and event.entity.name,
    position = event.entity and event.entity.position
  }
end

function logistics.handle_player_rotated_entity(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "rotate_entity",
    entity = event.entity and event.entity.name,
    position = event.entity and event.entity.position
  }
end

function logistics.handle_player_configured_blueprint(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "configure_blueprint",
    position = event.position
  }
end

function logistics.handle_player_setup_blueprint(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "setup_blueprint",
    position = event.position
  }
end

function logistics.handle_pre_build(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "pre_build",
    position = event.position
  }
end

function logistics.handle_selected_entity_changed(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  -- This can help with cursor interactions
  local ctx = logistics.get_player_context(event.player_index)
  if event.last_entity then
    ctx.last_selected_entity = {
      entity = event.last_entity,
      tick = event.tick
    }
  end
end

function logistics.handle_player_set_quick_bar_slot(event)
  if not shared_utils.is_player_event(event) then
    return
  end

  local ctx = logistics.get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "quick_bar_change"
  }
end

-- ============================================================================
-- EVENT REGISTRATION
-- ============================================================================

function logistics.register_events()
  logistics.initialize()

  -- GUI context tracking
  script.on_event(defines.events.on_gui_opened, logistics.handle_gui_opened)
  script.on_event(defines.events.on_gui_closed, logistics.handle_gui_closed)

  -- Core diff listener for GUI transfers
  script.on_event(defines.events.on_player_main_inventory_changed, logistics.handle_player_inventory_changed)

  -- Direct "builder" events
  script.on_event(defines.events.on_player_fast_transferred, logistics.handle_fast_transferred)
  script.on_event(defines.events.on_pre_player_crafted_item, logistics.handle_pre_crafted_item)
  script.on_event(defines.events.on_player_cancelled_crafting, logistics.handle_cancelled_crafting)
  script.on_event(defines.events.on_player_crafted_item, logistics.handle_crafted_item)
  script.on_event(defines.events.on_player_mined_entity, logistics.handle_mined_entity)
  script.on_event(defines.events.on_player_mined_item, logistics.handle_mined_item)
  script.on_event(defines.events.on_built_entity, logistics.handle_built_entity)
  script.on_event(defines.events.on_player_dropped_item, logistics.handle_dropped_item)
  script.on_event(defines.events.on_picked_up_item, logistics.handle_picked_up_item)
  script.on_event(defines.events.on_rocket_launched, logistics.handle_rocket_launched)

  -- Additional context-providing events
  script.on_event(defines.events.on_player_cursor_stack_changed, logistics.handle_cursor_stack_changed)
  script.on_event(defines.events.on_equipment_inserted, logistics.handle_equipment_inserted)
  script.on_event(defines.events.on_equipment_removed, logistics.handle_equipment_removed)
  script.on_event(defines.events.on_player_used_capsule, logistics.handle_capsule_used)
  script.on_event(defines.events.on_entity_settings_pasted, logistics.handle_entity_settings_pasted)
  script.on_event(defines.events.on_entity_died, logistics.handle_entity_died)
  script.on_event(defines.events.on_market_item_purchased, logistics.handle_market_purchase)
  script.on_event(defines.events.on_character_corpse_expired, logistics.handle_character_corpse_expired)
  script.on_event(defines.events.on_player_driving_changed_state, logistics.handle_driving_changed_state)
  
  -- Additional inventory change events
  script.on_event(defines.events.on_player_trash_inventory_changed, logistics.handle_trash_inventory_changed)
  script.on_event(defines.events.on_player_armor_inventory_changed, logistics.handle_armor_inventory_changed)
  script.on_event(defines.events.on_player_ammo_inventory_changed, logistics.handle_ammo_inventory_changed)
  script.on_event(defines.events.on_player_gun_inventory_changed, logistics.handle_gun_inventory_changed)
  
  -- Building and blueprint events
  script.on_event(defines.events.on_player_rotated_entity, logistics.handle_player_rotated_entity)
  script.on_event(defines.events.on_player_configured_blueprint, logistics.handle_player_configured_blueprint)
  script.on_event(defines.events.on_player_setup_blueprint, logistics.handle_player_setup_blueprint)
  script.on_event(defines.events.on_pre_build, logistics.handle_pre_build)
  script.on_event(defines.events.on_selected_entity_changed, logistics.handle_selected_entity_changed)
  script.on_event(defines.events.on_player_set_quick_bar_slot, logistics.handle_player_set_quick_bar_slot)

  -- Entity lifecycle events
  script.on_event(defines.events.on_player_mined_entity, logistics.handle_entity_removed)
  script.on_event(defines.events.on_robot_mined_entity, logistics.handle_entity_removed)
  script.on_event(defines.events.on_entity_died, logistics.handle_entity_removed)
end

return logistics
