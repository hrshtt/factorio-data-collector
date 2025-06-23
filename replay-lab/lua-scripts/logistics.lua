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

function log_inventory_change(record)
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
  end
  
  local clean_record = shared_utils.clean_record(record)
  local json = game.table_to_json(clean_record)
  shared_utils.buffer_event("logistics", json)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

function diff_tables(old_contents, new_contents)
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

function get_inventory_contents(holder, inventory_type)
  if not (holder and holder.valid) then
    return {}
  end
  
  local inventory = holder.get_inventory and holder.get_inventory(inventory_type)
  if not (inventory and inventory.valid) then
    return {}
  end
  
  return inventory.get_contents() or {}
end

function find_primary_inventory_index(entity)
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

function get_player_context(player_index)
  if not global.player_contexts then
    global.player_contexts = {}
  end
  
  if not global.player_contexts[player_index] then
    global.player_contexts[player_index] = {
      gui = nil,
      ephemeral = nil,
      last_player_snapshot = {}
    }
  end
  
  return global.player_contexts[player_index]
end

function update_player_snapshot(player_index)
  local player = game.players[player_index]
  if not (player and player.valid) then
    return
  end

  local ctx = get_player_context(player_index)
  ctx.last_player_snapshot = get_inventory_contents(player, defines.inventory.character_main)
end

function matches_entity_gui(gui_event, entity)
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
end

-- ============================================================================
-- GUI CONTEXT TRACKING
-- ============================================================================

function handle_gui_opened(event)
  if event.gui_type == defines.gui_type.entity and event.entity and event.player_index then
    local player = game.players[event.player_index]
    if not (player and player.valid) then
      return
    end
    
    local ctx = get_player_context(event.player_index)
    local inventory_index = find_primary_inventory_index(event.entity)
    
    if inventory_index then
      -- Take initial snapshots
      ctx.gui = {
        entity = event.entity,
        entity_inventory_index = inventory_index,
        player_snapshot = get_inventory_contents(player, defines.inventory.character_main),
        entity_snapshot = get_inventory_contents(event.entity, inventory_index)
      }
      
      -- Update last player snapshot if not set
      if not next(ctx.last_player_snapshot) then
        ctx.last_player_snapshot = ctx.gui.player_snapshot
      end
    end
      end
    end

function handle_gui_closed(event)
  if not event.player_index then
      return
    end

  local ctx = global.player_contexts and global.player_contexts[event.player_index]
  if ctx and ctx.gui and matches_entity_gui(event, ctx.gui.entity) then
    ctx.gui = nil
  end
end

-- ============================================================================
-- CORE DIFF LISTENER
-- ============================================================================

function handle_player_inventory_changed(event)
  local ctx = get_player_context(event.player_index)
  local player = game.players[event.player_index]
  if not (player and player.valid) then
    return
  end

  -- Get current player inventory
  local new_player_contents = get_inventory_contents(player, defines.inventory.character_main)
  
  -- Diff player inventory vs last snapshot
  local player_deltas = diff_tables(ctx.last_player_snapshot, new_player_contents)
  
  for item, delta in pairs(player_deltas) do
    local source, destination
    if delta > 0 then
      source = ctx.gui and ctx.gui.entity.name or "unknown"
      destination = "player"
    else
      source = "player"
      destination = ctx.gui and ctx.gui.entity.name or "unknown"
    end
    
    log_inventory_change{
      tick = event.tick,
      player = event.player_index,
      item = item,
      delta = delta,
      source = source,
      destination = destination,
      context = ctx.ephemeral or (ctx.gui and { 
        action = "gui_transfer", 
        entity = ctx.gui.entity.name,
        position = ctx.gui.entity.position
      }) or { action = "unknown" }
    }
end

  -- Update player snapshot
  ctx.last_player_snapshot = new_player_contents

  -- If in a GUI, also diff the entity's inventory
  if ctx.gui and ctx.gui.entity and ctx.gui.entity.valid then
    local new_entity_contents = get_inventory_contents(ctx.gui.entity, ctx.gui.entity_inventory_index)
    local entity_deltas = diff_tables(ctx.gui.entity_snapshot, new_entity_contents)
    
    for item, delta in pairs(entity_deltas) do
      local source, destination
      if delta > 0 then
        source = "player"
        destination = ctx.gui.entity.name
      else
        source = ctx.gui.entity.name
        destination = "player"
      end
      
      log_inventory_change{
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

function handle_fast_transferred(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  local from, to
  if event.from_player then
    from = "player"
    to = event.entity and event.entity.name or "unknown"
  else
    from = event.entity and event.entity.name or "unknown"
    to = "player"
  end
  
  -- Extract item info - handle both old and new event formats
  local item_name, item_count
  if event.item_stack then
    item_name = event.item_stack.name
    item_count = event.item_stack.count
  elseif event.entity and event.entity.last_user then
    -- Fallback: we'll log without specific item details
    item_name = "unknown"
    item_count = 1
  else
    return -- Can't determine what was transferred
  end
  
  log_inventory_change{
    tick = event.tick,
    player = event.player_index,
    item = item_name,
    delta = event.from_player and -item_count or item_count,
    source = from,
    destination = to,
    context = { 
      action = "fast_transfer",
      entity = event.entity and event.entity.name,
      position = event.entity and event.entity.position,
      is_split = event.is_split
    }
  }
  
  -- Update snapshot so the diff listener sees no net change
  update_player_snapshot(event.player_index)
end

function handle_crafted_item(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  log_inventory_change{
    tick = event.tick,
    player = event.player_index,
    item = event.item_stack.name,
    delta = event.item_stack.count,
    source = "crafting",
    destination = "player",
    context = { 
      action = "craft",
      recipe = event.recipe and event.recipe.name
    }
  }
  
  update_player_snapshot(event.player_index)
end

function handle_mined_entity(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  if event.buffer then
    local buffer_contents = event.buffer.get_contents()
    for item, count in pairs(buffer_contents) do
      log_inventory_change{
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
  
  update_player_snapshot(event.player_index)
end

function handle_built_entity(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  -- For building, we typically consume items from player inventory
  -- The actual consumption will be caught by the diff listener
  -- But we set ephemeral context so it knows this was a build action
  local ctx = get_player_context(event.player_index)
  ctx.ephemeral = {
    action = "build",
    entity = event.created_entity and event.created_entity.name,
    position = event.created_entity and event.created_entity.position
  }
end

function handle_dropped_item(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  log_inventory_change{
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
  
  update_player_snapshot(event.player_index)
end

function handle_picked_up_item(event)
  if not shared_utils.is_player_event(event) then
    return
  end
  
  log_inventory_change{
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
  
  update_player_snapshot(event.player_index)
end

function handle_rocket_launched(event)
  -- Rocket launches affect the silo inventory but don't have a specific player
  local silo = event.rocket_silo
  if not (silo and silo.valid) then
    return
  end

  -- For rocket launch, we'll log as a system action
  -- The rocket consumes items from the silo
  log_inventory_change{
    tick = event.tick,
    player = event.player_index or 0, -- Use 0 for system events
    item = "rocket-part", -- Simplified - rockets consume rocket parts
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

-- ============================================================================
-- EVENT REGISTRATION
-- ============================================================================

function logistics.register_events()
  logistics.initialize()

  -- GUI context tracking
  script.on_event(defines.events.on_gui_opened, handle_gui_opened)
  script.on_event(defines.events.on_gui_closed, handle_gui_closed)

  -- Core diff listener for GUI transfers
  script.on_event(defines.events.on_player_main_inventory_changed, handle_player_inventory_changed)

  -- Direct "builder" events
  script.on_event(defines.events.on_player_fast_transferred, handle_fast_transferred)
  script.on_event(defines.events.on_player_crafted_item, handle_crafted_item)
  script.on_event(defines.events.on_player_mined_entity, handle_mined_entity)
  script.on_event(defines.events.on_built_entity, handle_built_entity)
  script.on_event(defines.events.on_player_dropped_item, handle_dropped_item)
  script.on_event(defines.events.on_picked_up_item, handle_picked_up_item)
  script.on_event(defines.events.on_rocket_launched, handle_rocket_launched)
end

return logistics 