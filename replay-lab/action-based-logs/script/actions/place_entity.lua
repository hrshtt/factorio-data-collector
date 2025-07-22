-- place_entity.lua
-- Place-entity action logger               v1.1.0  (2025-07-23)  Harshit Sharma

local place_entity  = {}
local shared_utils  = require("script.shared-utils")

-- Returns quarter-turns (0-3) clockwise from default ‘north’
local function qturns_from_direction(dir)
  dir = dir or 0                     -- nil → north
  return math.floor(dir / 2) % 4     -- 0,1,2,3
end

function place_entity.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_built_entity, function(e)
    if not shared_utils.is_player_event(e) then return end

    local player  = game.players[e.player_index]
    local rec     = shared_utils.create_base_record("on_built_entity", e, player)
    rec.action    = "place_entity"

    local ent = e.created_entity      -- ← correct field for this event
    if ent then
      rec.entity = {}
      rec.entity.name = ent.name
      if ent.position then            -- 1 dp pos for consistency
        rec.entity.x = string.format("%.1f", ent.position.x)
        rec.entity.y = string.format("%.1f", ent.position.y)
      end

      if ent.direction then
        rec.entity.direction = {}
        rec.entity.direction.name = defines.direction[ent.direction]
        rec.entity.direction.value = ent.direction
        rec.entity.direction.number_of_rotations = qturns_from_direction(ent.direction)
      end
      -- single, canonical rotation field
    end


    shared_utils.buffer_event("place_entity", game.table_to_json(shared_utils.clean_record(rec)))
  end)
end

return place_entity