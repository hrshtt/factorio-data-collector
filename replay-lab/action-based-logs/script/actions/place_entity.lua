--@place_entity.lua
--@description Place entity action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local place_entity = {}
local shared_utils = require("script.shared-utils")

-- Direction name mapping for cleaner logs
local D = defines.direction
local dir_names = {
  [D.north] = "N",
  [D.northeast] = "NE", 
  [D.east] = "E",
  [D.southeast] = "SE",
  [D.south] = "S",
  [D.southwest] = "SW",
  [D.west] = "W",
  [D.northwest] = "NW"
}

function place_entity.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_built_entity, function(e)
    if not shared_utils.is_player_event(e) then return end
    local player = game.players[e.player_index]
    local rec = shared_utils.create_base_record("on_built_entity", e)
    rec.action = "place_entity"
    rec.entity = e.entity and e.entity.name or nil
    rec.position = e.entity and e.entity.position or nil
    
    -- Add direction/orientation information
    if e.entity and e.entity.valid then
      local direction = e.entity.direction
      if direction then
        rec.direction = direction
        rec.direction_name = dir_names[direction] or "UNKNOWN"
      end
      
      -- Add orientation-specific information for entities that have it
      if e.entity.orientation then
        rec.orientation = e.entity.orientation
      end
      
      -- Add entity type for context
      rec.entity_type = e.entity.type
    end
    
    shared_utils.add_player_context_if_missing(rec, player)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("place_entity", line)
  end)
end

return place_entity 