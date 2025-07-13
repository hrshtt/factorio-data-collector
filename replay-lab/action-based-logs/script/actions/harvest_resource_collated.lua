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
-- MINING DURATION CALCULATION
--------------------------------------------------------------------
local function calculate_mining_duration_ticks(entity, player)
  if not (entity and entity.valid and player and player.valid) then
    return 0
  end
  
  -- Get the entity's base mining time (in seconds)
  local mining_time_seconds = 0.5 -- Default mining time
  if entity.prototype and entity.prototype.mineable_properties then
    mining_time_seconds = entity.prototype.mineable_properties.mining_time or 0.5
  end
  
  -- Get player's base mining speed from character prototype
  local base_mining_speed = 1.0 -- Default base mining speed
  if player.character and player.character.valid and player.character.prototype then
    base_mining_speed = player.character.prototype.mining_speed or 1.0
  end
  
  -- Get force mining speed modifier
  local force_mining_modifier = 0.0
  if player.force and player.force.valid then
    force_mining_modifier = player.force.manual_mining_speed_modifier or 0.0
  end
  
  -- Get character mining speed modifier
  local character_mining_modifier = 0.0
  if player.character_mining_speed_modifier then
    character_mining_modifier = player.character_mining_speed_modifier
  end
  
  -- Calculate final mining speed: base_speed * (1 + force_modifier) * (1 + character_modifier)
  local final_mining_speed = base_mining_speed * (1 + force_mining_modifier) * (1 + character_mining_modifier)
  
  -- Calculate actual mining duration: mining_time / mining_speed
  local duration_seconds = mining_time_seconds / final_mining_speed
  
  -- Convert to ticks (60 ticks per second)
  local duration_ticks = math.ceil(duration_seconds * 60)
  
  return duration_ticks
end

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
      
      -- Calculate duration: use calculated duration if available, otherwise fall back to tick difference
      if mining_record.calculated_duration_ticks then
        mining_record.duration_ticks = mining_record.calculated_duration_ticks
      elseif mining_record.end_tick then
        mining_record.duration_ticks = mining_record.end_tick - mining_record.start_tick
      else
        mining_record.duration_ticks = 0
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
function harvest_module.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_pre_player_mined_item, function(event)
    if not util.is_player_event(event) then return end
    
    ensure_partial_mine()
    
    -- Safe access to entity position
    local entity_name = event.entity and event.entity.name
    local pos_x, pos_y
    if event.entity and event.entity.position then
      pos_x = round(event.entity.position.x)
      pos_y = round(event.entity.position.y)
    end

    -- Calculate the actual mining duration
    local player = game.players[event.player_index]
    local calculated_duration = calculate_mining_duration_ticks(event.entity, player)

    global.partial_mine[key(event)] = {
      tick         = event.tick,
      player_index = event.player_index,
      action       = "harvest_resource_collated",
      entity       = entity_name,
      x            = pos_x,
      y            = pos_y,
      start_tick   = event.tick,                  -- Start tick is when pre-mining begins
      calculated_duration_ticks = calculated_duration, -- Store calculated duration
      items        = {}                           -- will be filled below
    }
  end)

  ----------------------------------------------------------------
  -- (2) one or more item-drops for the same tick/player
  ----------------------------------------------------------------
  event_dispatcher.register_handler(defines.events.on_player_mined_item, function(event)
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
  event_dispatcher.register_handler(defines.events.on_player_mined_entity, function(event)
    if not util.is_player_event(event) then return end
    
    ensure_partial_mine()
    
    local mining_record = global.partial_mine[key(event)]
    if mining_record then
      mining_record.entity_mined = true
      mining_record.entity_type = event.entity and event.entity.type
      mining_record.end_tick = event.tick  -- Mark the actual completion tick
    end
  end)

  ----------------------------------------------------------------
  -- (4) Handle tile mining separately (different pattern)
  ----------------------------------------------------------------
  event_dispatcher.register_handler(defines.events.on_player_mined_tile, function(event)
    if not util.is_player_event(event) then return end
    
    -- Tiles don't follow the same pre/post pattern, log immediately
    local rec = {
      tick = event.tick,
      player_index = event.player_index,
      action = "harvest_resource_collated",
      type = "tile",
      tiles = event.tiles or {},
      start_tick = event.tick,  -- For tiles, start and end are the same
      end_tick = event.tick,
      duration_ticks = 0
    }
    local line = game.table_to_json(rec)
    util.buffer_event("harvest_resource_collated", line)
  end)
end

-- Export the tick handler so it can be called from main control.lua
harvest_module.process_partial_mining = process_partial_mining

return harvest_module