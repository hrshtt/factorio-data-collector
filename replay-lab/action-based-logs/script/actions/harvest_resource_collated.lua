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

local function round(value)   return string.format("%.1f", value) end
local function key(event)     return event.player_index .. ":" .. round(event.entity.position.x) .. ":" .. round(event.entity.position.y) end
local function check_mining_complete(rec) return rec and rec.entity and rec.entity.mined and rec.items end

--------------------------------------------------------------------
-- EVENT REGISTRATION
--------------------------------------------------------------------
function harvest_module.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_selected_entity_changed, function(event)
    if not util.is_player_event(event) then return end
    ensure_partial_mine()
    local rec = global.partial_mine
    if check_mining_complete(rec) then
      rec.key = nil
      local clean_rec = util.clean_record(rec)
      local line = game.table_to_json(clean_rec)
      util.buffer_event("harvest_resource_collated", line)
      rec = {}
    end

    local player = game.players[event.player_index]
    if player.selected then
      event.entity = {
        name = player.selected.name,
        position = player.selected.position,
        type = player.selected.type
      }
      rec = util.create_base_record("harvest_resource_collated", event, player)
      rec.start_tick = event.tick
      rec.key = key(event)
      global.partial_mine = rec
    elseif event.last_entity and rec.entity then
      event.entity = {
        name = event.last_entity.name,
        position = event.last_entity.position,
        type = event.last_entity.type
      }
      if key(event) ~= rec.key then
        global.partial_mine = {}
      end
    else
      global.partial_mine = {}
    end
  end)

  ---------------------------------------------------------------
  -- (2) Entity destruction confirmation
  ----------------------------------------------------------------
  event_dispatcher.register_handler(defines.events.on_player_mined_entity, function(event)
    if not util.is_player_event(event) then return end
    
    local mining_record = global.partial_mine
    if mining_record then
      if not mining_record.entity then 
        mining_record.entity = {
          name = event.entity.name,
          position = event.entity.position,
          type = event.entity.type,
        }
        mining_record.start_tick = event.tick
      end
      mining_record.entity.mined = true
      mining_record.entity.type = event.entity and event.entity.type
      mining_record.end_tick = event.tick
      mining_record.items = {}
    end
    global.partial_mine = mining_record
  end)

  ------------------------------------------------------------
  -- (3) one or more item-drops for the same tick/player
  ----------------------------------------------------------------
  event_dispatcher.register_handler(defines.events.on_player_mined_item, function(event)
    if not util.is_player_event(event) then return end
    
  local mining_record = global.partial_mine
    if mining_record and event.item_stack then
      table.insert(mining_record.items, {
        name  = event.item_stack.name,
        count = event.item_stack.count,
        tick = event.tick
      })
    end
  end)

  ----------------------------------------------------------------
  -- (4) Handle tile mining separately (different pattern)
  ----------------------------------------------------------------
  event_dispatcher.register_handler(defines.events.on_player_mined_tile, function(event)
    if not util.is_player_event(event) then return end

    local rec = util.create_base_record("harvest_resource_collated", event, player)
    
    -- Tiles don't follow the same pre/post pattern, log immediately
    rec.type = "tile"
    rec.tiles = event.tiles or {}
    rec.start_tick = event.tick  -- For tiles, start and end are the same
    rec.end_tick = event.tick
    rec.duration_ticks = 0
    
  
    local clean_rec = util.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    util.buffer_event("harvest_resource_collated", line)
  end)
end

return harvest_module