--@map.lua
--@description Map domain module for state-based logging
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = require("script.shared-utils")
local map = {}

-- ============================================================================
-- DOMAIN UPDATE FUNCTION
-- ============================================================================
function map.update(event_data, event_name)
  local player_obj = event_data.player_index and game.players[event_data.player_index]
  
  -- Create base record
  local rec = shared_utils.create_base_record(event_name, event_data)
  
  -- Apply event-specific context extraction
  local extractor = map.get_extractor(event_name)
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
  
  -- Buffer to map domain category
  shared_utils.buffer_event("map", line)
end

-- ============================================================================
-- CONTEXT EXTRACTORS - PURE MAP EVENTS
-- ============================================================================
function map.on_chunk_generated(e, rec, player_obj)
  rec.action = "chunk-generated"
  rec.area = e.area
  rec.surface = e.surface and e.surface.name
end

function map.on_chunk_deleted(e, rec, player_obj)
  rec.action = "chunk-deleted"
  rec.positions = e.positions
  rec.surface = e.surface and e.surface.name
end

function map.on_chunk_charted(e, rec, player_obj)
  rec.action = "chunk-charted"
  rec.area = e.area
  rec.surface = e.surface and e.surface.name
  rec.force = e.force and e.force.name
end

function map.on_area_cloned(e, rec, player_obj)
  rec.action = "area-cloned"
  rec.source_area = e.source_area
  rec.destination_area = e.destination_area
  rec.source_surface = e.source_surface and e.source_surface.name
  rec.destination_surface = e.destination_surface and e.destination_surface.name
end

function map.on_brush_cloned(e, rec, player_obj)
  rec.action = "brush-cloned"
  rec.source_offset = e.source_offset
  rec.destination_offset = e.destination_offset
  rec.source_surface = e.source_surface and e.source_surface.name
  rec.destination_surface = e.destination_surface and e.destination_surface.name
end

function map.on_pre_chunk_deleted(e, rec, player_obj)
  rec.action = "pre-chunk-deleted"
  rec.positions = e.positions
  rec.surface = e.surface and e.surface.name
end

function map.on_surface_created(e, rec, player_obj)
  rec.action = "surface-created"
  rec.surface_index = e.surface_index
end

function map.on_surface_cleared(e, rec, player_obj)
  rec.action = "surface-cleared"
  rec.surface_index = e.surface_index
end

function map.on_surface_deleted(e, rec, player_obj)
  rec.action = "surface-deleted"
  rec.surface_index = e.surface_index
end

function map.on_surface_renamed(e, rec, player_obj)
  rec.action = "surface-renamed"
  rec.surface_index = e.surface_index
  rec.old_name = e.old_name
  rec.new_name = e.new_name
end

function map.on_sector_scanned(e, rec, player_obj)
  rec.action = "sector-scanned"
  rec.chunk_position = e.chunk_position
  rec.surface = e.surface and e.surface.name
  rec.force = e.force and e.force.name
end

-- ============================================================================
-- CONTEXT EXTRACTORS - MAP + PLAYER PAIRED EVENTS
-- ============================================================================
function map.on_pre_build(e, rec, player_obj)
  rec.action = "pre-build"
  rec.direction = e.direction
  rec.flip_horizontal = e.flip_horizontal
  rec.flip_vertical = e.flip_vertical
end

function map.on_built_entity(e, rec, player_obj)
  rec.action = "entity-built"
  rec.created_entity = e.created_entity and e.created_entity.name
  -- Safely handle potentially invalid LuaItemStack
  if e.stack and e.stack.valid_for_read then
    rec.stack = e.stack.name
  else
    rec.stack = nil
  end
  rec.tags = e.tags
end

function map.on_pre_player_mined_item(e, rec, player_obj)
  rec.action = "pre-mined-item"
end

function map.on_player_mined_entity(e, rec, player_obj)
  rec.action = "entity-mined"
  rec.buffer = e.buffer and e.buffer.get_contents()
end

function map.on_player_mined_item(e, rec, player_obj)
  rec.action = "item-mined"
  rec.item_count = e.item_count
end

function map.on_player_mined_tile(e, rec, player_obj)
  rec.action = "tile-mined"
  rec.tiles = #e.tiles
  rec.surface_index = e.surface_index
end

function map.on_player_built_tile(e, rec, player_obj)
  rec.action = "tile-built"
  rec.tiles = #e.tiles
  rec.tile_name = e.tiles[1] and e.tiles[1].name
  rec.surface_index = e.surface_index
end

function map.on_player_dropped_item(e, rec, player_obj)
  rec.action = "item-dropped"
end

function map.on_picked_up_item(e, rec, player_obj)
  rec.action = "item-picked-up"
end

-- ============================================================================
-- CONTEXT EXTRACTORS - MAP + ENTITY PAIRED EVENTS
-- ============================================================================
function map.on_entity_cloned(e, rec, player_obj)
  rec.action = "entity-cloned"
  rec.source = e.source and e.source.name
  rec.destination = e.destination and e.destination.name
end

function map.on_entity_died(e, rec, player_obj)
  rec.action = "entity-died"
  rec.cause = e.cause and e.cause.name
  rec.loot = e.loot and e.loot.get_contents()
  rec.force = e.force and e.force.name
end

function map.on_post_entity_died(e, rec, player_obj)
  rec.action = "post-entity-died"
  rec.ghost = e.ghost and e.ghost.name
  rec.force = e.force and e.force.name
end

function map.on_resource_depleted(e, rec, player_obj)
  rec.action = "resource-depleted"
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================
function map.get_extractor(event_name)
  return map[event_name] or function() end -- Default no-op
end

return map
