--@entity.lua
--@description Entity domain module for state-based logging
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("script.shared-utils")
local entity = {}

-- ============================================================================
-- DOMAIN UPDATE FUNCTION
-- ============================================================================
function entity.update(event_data, event_name)
  local player_obj = event_data.player_index and game.players[event_data.player_index]
  
  -- Create base record
  local rec = shared_utils.create_base_record(event_name, event_data)
  
  -- Apply event-specific context extraction
  local extractor = entity.get_extractor(event_name)
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
  
  -- Buffer to entity domain category
  shared_utils.buffer_event("entity", line)
end

-- ============================================================================
-- CONTEXT EXTRACTORS - PURE ENTITY EVENTS
-- ============================================================================
function entity.on_entity_settings_pasted(e, rec, player_obj)
  rec.action = "settings-pasted"
  rec.source_entity = e.source and e.source.name
  rec.destination_entity = e.destination and e.destination.name
end

function entity.on_entity_logistic_slot_changed(e, rec, player_obj)
  rec.action = "logistic-slot-changed"
  rec.slot_index = e.slot_index
  rec.old_request = e.old_request
  rec.new_request = e.new_request
end

function entity.on_entity_color_changed(e, rec, player_obj)
  rec.action = "color-changed"
  rec.old_color = e.old_color
  rec.new_color = e.new_color
end

function entity.on_entity_renamed(e, rec, player_obj)
  rec.action = "renamed"
  rec.old_name = e.old_name
  rec.new_name = e.new_name
end

function entity.on_equipment_inserted(e, rec, player_obj)
  rec.action = "equipment-inserted"
  rec.equipment = e.equipment and e.equipment.name
  rec.grid = e.grid and e.grid.get_contents()
end

function entity.on_equipment_removed(e, rec, player_obj)
  rec.action = "equipment-removed"
  rec.equipment = e.equipment
  rec.grid = e.grid and e.grid.get_contents()
  rec.count = e.count
end

function entity.on_entity_damaged(e, rec, player_obj)
  rec.action = "damaged"
  rec.damage_type = e.damage_type and e.damage_type.name
  rec.original_damage_amount = e.original_damage_amount
  rec.final_damage_amount = e.final_damage_amount
  rec.final_health = e.final_health
  rec.cause = e.cause and e.cause.name
end

function entity.on_ai_command_completed(e, rec, player_obj)
  rec.action = "ai-command-completed"
  rec.unit_number = e.unit_number
  rec.result = e.result
end

-- ============================================================================
-- CONTEXT EXTRACTORS - MAP + ENTITY PAIRED EVENTS
-- ============================================================================
function entity.on_entity_cloned(e, rec, player_obj)
  rec.action = "cloned"
  rec.source = e.source and e.source.name
  rec.destination = e.destination and e.destination.name
end

function entity.on_entity_died(e, rec, player_obj)
  rec.action = "died"
  rec.cause = e.cause and e.cause.name
  rec.loot = e.loot and e.loot.get_contents()
  rec.force = e.force and e.force.name
end

function entity.on_post_entity_died(e, rec, player_obj)
  rec.action = "post-died"
  rec.ghost = e.ghost and e.ghost.name
  rec.force = e.force and e.force.name
end

function entity.on_resource_depleted(e, rec, player_obj)
  rec.action = "resource-depleted"
end

-- ============================================================================
-- CONTEXT EXTRACTORS - PLAYER + ENTITY PAIRED EVENTS
-- ============================================================================
-- function entity.on_player_fast_transferred(e, rec, player_obj)
--   rec.action = "fast-transferred"
--   rec.from_player = e.from_player
-- end

function entity.on_player_rotated_entity(e, rec, player_obj)
  rec.action = "rotated"
  rec.previous_direction = e.previous_direction
end

function entity.on_player_placed_equipment(e, rec, player_obj)
  rec.action = "equipment-placed"
  rec.equipment = e.equipment and e.equipment.name
  rec.grid = e.grid and e.grid.get_contents()
end

function entity.on_player_removed_equipment(e, rec, player_obj)
  rec.action = "equipment-removed-by-player"
  rec.equipment = e.equipment
  rec.grid = e.grid and e.grid.get_contents()
end

function entity.on_player_flushed_fluid(e, rec, player_obj)
  rec.action = "fluid-flushed"
  rec.fluid = e.fluid
  rec.amount = e.amount
  rec.only_this_entity = e.only_this_entity
end

function entity.on_player_driving_changed_state(e, rec, player_obj)
  rec.action = e.entity and "player-entered" or "player-exited"
end

function entity.on_player_repaired_entity(e, rec, player_obj)
  rec.action = "repaired"
end

function entity.on_player_used_spider_remote(e, rec, player_obj)
  rec.action = "spider-remote-used"
  rec.vehicle = e.vehicle and e.vehicle.name
  rec.success = e.success
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================
function entity.get_extractor(event_name)
  return entity[event_name] or function() end -- Default no-op
end

return entity
