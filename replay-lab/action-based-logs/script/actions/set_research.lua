--@set_research.lua
--@description Set research action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local set_research = {}
local shared_utils = require("script.shared-utils")

function set_research.register_events()
  script.on_event(defines.events.on_research_started, function(e)
    local rec = shared_utils.create_base_record("on_research_started", e)
    rec.action = "set_research"
    rec.technology = e.research and e.research.name or nil
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("set_research", line)
  end)
  script.on_event(defines.events.on_research_finished, function(e)
    local rec = shared_utils.create_base_record("on_research_finished", e)
    rec.action = "set_research"
    rec.technology = e.research and e.research.name or nil
    rec.by_script = e.by_script
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("set_research", line)
  end)
  script.on_event(defines.events.on_research_cancelled, function(e)
    local rec = shared_utils.create_base_record("on_research_cancelled", e)
    rec.action = "set_research"
    rec.technology = e.research and e.research.name or nil
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("set_research", line)
  end)
end

return set_research 