-- harvest_resource_collated.lua
-- Minimal POC: collate mined-resource events into one log line

local harvest_module = {}
local util = require("script.shared-utils")

--------------------------------------------------------------------
-- INTERNAL STATE HELPERS
--------------------------------------------------------------------
local function ensure_partial_mine()
  if not global.partial_mine then
    global.partial_mine = {}
  end
end

local function key(event)     return event.player_index .. ":" .. event.tick end
local function round(value)   return string.format("%.1f", value) end

--------------------------------------------------------------------
-- TICK HANDLER FOR COLLATION
--------------------------------------------------------------------
local function process_partial_mining(event)
  ensure_partial_mine()
  
  for mine_key, mining_record in pairs(global.partial_mine) do
    local should_flush = false
    local age_in_ticks = event.tick - mining_record.tick
    
    if age_in_ticks >= 1 then                    -- Normal completion (one tick delay)
      should_flush = true
    elseif age_in_ticks >= 300 then              -- Timeout after 5 seconds (300 ticks)
      mining_record.status = "timeout_incomplete"
      should_flush = true
    end
    
    if should_flush then
      -- Mark empty item lists as potentially cancelled
      if #mining_record.items == 0 then
        mining_record.status = mining_record.status or "no_items_received"
      end
      
      local line = game.table_to_json(mining_record)
      util.buffer_event("harvest_resource_collated", line)
      global.partial_mine[mine_key] = nil
    end
  end
end

--------------------------------------------------------------------
-- EVENT REGISTRATION
--------------------------------------------------------------------
function harvest_module.register_events()
  -- ensure the buffer exists
  util.initialize_category_buffer("harvest_resource_collated")

  ----------------------------------------------------------------
  -- (1) action starts  ──────────────────────────────────────────
  ----------------------------------------------------------------
  script.on_event(defines.events.on_pre_player_mined_item, function(event)
    if not util.is_player_event(event) then return end
    
    ensure_partial_mine()
    
    -- Safe access to entity position
    local entity_name = event.entity and event.entity.name
    local pos_x, pos_y
    if event.entity and event.entity.position then
      pos_x = round(event.entity.position.x)
      pos_y = round(event.entity.position.y)
    end

    global.partial_mine[key(event)] = {
      tick         = event.tick,
      player_index = event.player_index,
      action       = "harvest_resource_collated",
      entity       = entity_name,
      x            = pos_x,
      y            = pos_y,
      items        = {}                               -- will be filled below
    }
  end)

  ----------------------------------------------------------------
  -- (2) one or more item-drops for the same tick/player
  ----------------------------------------------------------------
  script.on_event(defines.events.on_player_mined_item, function(event)
    if not util.is_player_event(event) then return end
    
    ensure_partial_mine()
    
    local mining_record = global.partial_mine[key(event)]
    if mining_record and event.item_stack then
      table.insert(mining_record.items, {
        name  = event.item_stack.name,
        count = event.item_stack.count
      })
    end
  end)

  ----------------------------------------------------------------
  -- (3) Entity destruction confirmation
  ----------------------------------------------------------------
  script.on_event(defines.events.on_player_mined_entity, function(event)
    if not util.is_player_event(event) then return end
    
    ensure_partial_mine()
    
    local mining_record = global.partial_mine[key(event)]
    if mining_record then
      mining_record.entity_mined = true
      mining_record.entity_type = event.entity and event.entity.type
    end
  end)

  ----------------------------------------------------------------
  -- (4) Handle tile mining separately (different pattern)
  ----------------------------------------------------------------
  script.on_event(defines.events.on_player_mined_tile, function(event)
    if not util.is_player_event(event) then return end
    
    -- Tiles don't follow the same pre/post pattern, log immediately
    local rec = {
      tick = event.tick,
      player_index = event.player_index,
      action = "harvest_resource_collated",
      type = "tile",
      tiles = event.tiles or {}
    }
    local line = game.table_to_json(rec)
    util.buffer_event("harvest_resource_collated", line)
  end)
end

-- Export the tick handler so it can be called from main control.lua
harvest_module.process_partial_mining = process_partial_mining

return harvest_module