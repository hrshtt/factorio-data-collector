--@research.lua
--@description Research domain module for state-based logging
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("script.shared-utils")
local research = {}

-- ============================================================================
-- DOMAIN UPDATE FUNCTION
-- ============================================================================
function research.update(event_data, event_name)
  
  local player_obj = event_data.player_index and game.players[event_data.player_index]
  
  -- Create base record
  local rec = shared_utils.create_base_record(event_name, event_data)
  
  -- Apply event-specific context extraction
  local extractor = research.get_extractor(event_name)
  local should_log = extractor(event_data, rec, player_obj)
  
  -- Check if event should be skipped
  if should_log == false then
    return
  end
  
  -- Add player context if missing
  shared_utils.add_player_context_if_missing(rec, player_obj)
  
  -- Clean up nil values and buffer the event
  local clean_rec = shared_utils.clean_record(rec)
  local line = game.table_to_json(clean_rec)
  
  -- Buffer to research domain category
  shared_utils.buffer_event("research", line)
end

-- ============================================================================
-- CONTEXT EXTRACTORS - RESEARCH EVENTS
-- ============================================================================
function research.on_research_started(e, rec, player_obj)
  rec.action = "research-started"
  rec.research = e.research and e.research.name
  rec.force = e.force and e.force.name
  rec.last_user = e.last_user and e.last_user.name
end

function research.on_research_finished(e, rec, player_obj)
  rec.action = "research-finished"
  rec.research = e.research and e.research.name
  rec.force = e.force and e.force.name
  rec.by_script = e.by_script
end

function research.on_research_cancelled(e, rec, player_obj)
  rec.action = "research-cancelled"
  rec.research = e.research and e.research.name
  rec.force = e.force and e.force.name
  rec.last_user = e.last_user and e.last_user.name
end

function research.on_research_reversed(e, rec, player_obj)
  rec.action = "research-reversed"
  rec.research = e.research and e.research.name
  rec.force = e.force and e.force.name
  rec.by_script = e.by_script
end

function research.on_technology_effects_reset(e, rec, player_obj)
  rec.action = "technology-effects-reset"
  rec.force = e.force and e.force.name
  rec.by_script = e.by_script
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================
function research.get_extractor(event_name)
  return research[event_name] or function() end -- Default no-op
end

return research
