--@set_research.lua
--@description Set research action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local set_research = {}
local shared_utils = require("script.shared-utils")

function set_research.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_research_started, function(e)
    local player = game.players[1]
    e.player_index = player.index
    local rec = shared_utils.create_base_record("research_started", e, player)
    rec.research = e.research and e.research.name or nil
    rec.by_script = e.by_script
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("set_research", line)
  end)
  
  event_dispatcher.register_handler(defines.events.on_research_finished, function(e)
    local player = game.players[1]
    e.player_index = player.index
    local rec = shared_utils.create_base_record("research_finished", e, player)
    rec.research = e.research and e.research.name or nil
    rec.by_script = e.by_script
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("set_research", line)
  end)
  
  event_dispatcher.register_handler(defines.events.on_research_cancelled, function(e)
    local player = game.players[1]
    e.player_index = player.index
    local rec = shared_utils.create_base_record("research_cancelled", e, player)
    rec.research = e.research and e.research.name or nil
    rec.by_script = e.by_script
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("set_research", line)
  end)
end

return set_research 