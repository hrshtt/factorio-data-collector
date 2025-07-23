--@move_to_collated.lua
--@description Collated move-to action logger - tracks movement segments by direction
--@author Harshit Sharma
--@version 1.0.1
--@date 2025-07-23

local move_to_collated = {}
local util = require("script.shared-utils")

-- Direction constants & names
local D = defines.direction
local dir_names = {
  [D.north]     = "N",
  [D.northeast] = "NE",
  [D.east]      = "E",
  [D.southeast] = "SE",
  [D.south]     = "S",
  [D.southwest] = "SW",
  [D.west]      = "W",
  [D.northwest] = "NW"
}

-- Initialize a fresh partial‐move record
local function ensure_partial_move(event, player)
  local rec = util.create_base_record("move_to_collated", event, player)
  rec.start_tick     = event.tick
  rec.last_tick      = event.tick
  rec.start_position = player.position
  rec.last_position  = player.position
  rec.direction      = nil
  rec.total_events   = 1
  global.partial_move = rec
end

function move_to_collated.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_player_changed_position, function(event)
    -- ignore AI/bots or invalid events
    if not util.is_player_event(event) then return end

    local player = game.players[event.player_index]
    -- first move → set up a record and stop
    if not global.partial_move then
      ensure_partial_move(event, player)
      return
    end

    local pm        = global.partial_move
    local cur_pos   = player.position
    local cur_tick  = event.tick
    local dx, dy    = cur_pos.x - pm.last_position.x, cur_pos.y - pm.last_position.y

    -- no real movement? skip
    if dx == 0 and dy == 0 then return end

    -- figure out the cardinal/octant
    local direction
    if math.abs(dx) > math.abs(dy) then
      direction = (dx > 0) and D.east or D.west
    elseif math.abs(dy) > math.abs(dx) then
      direction = (dy > 0) and D.south or D.north
    else
      if dx > 0 and dy > 0 then
        direction = D.southeast
      elseif dx > 0 and dy < 0 then
        direction = D.northeast
      elseif dx < 0 and dy > 0 then
        direction = D.southwest
      elseif dx < 0 and dy < 0 then
        direction = D.northwest
      end
    end

    -- still going the same way?
    if pm.direction == direction or not pm.direction then
      pm.direction      = direction
      pm.last_position  = cur_pos
      pm.last_tick      = cur_tick
      pm.total_events   = pm.total_events + 1

    else
      -- flush the old segment
      pm.end_tick       = pm.last_tick
      pm.duration_ticks = pm.last_tick - pm.start_tick
      pm.direction_name = dir_names[pm.direction]

      local clean_rec   = util.clean_record(pm)
      local line        = game.table_to_json(clean_rec)
      util.buffer_event("move_to_collated", line)

      -- start a new segment
      ensure_partial_move(event, player)
    end
  end)
end

return move_to_collated