-- ============================================================================
-- UTILITY FUNCTIONS MODULE
-- ============================================================================
local utils = {}

function utils.get_item_info(stack)
  if not stack or not stack.valid_for_read then
    return nil, nil
  end
  return stack.name, stack.count
end

function utils.get_entity_info(entity)
  if not entity or not entity.valid then
    return nil
  end
  return entity.name
end

function utils.get_player_context(player)
  if not player or not player.valid then
    return {}
  end
  
  local context = {}
  
  -- Current cursor item
  if player.cursor_stack and player.cursor_stack.valid_for_read then
    context.cursor_item = player.cursor_stack.name
    context.cursor_count = player.cursor_stack.count
  end
  
  -- Current position (rounded for cleaner logs)
  if player.position then
    context.px = string.format("%.1f", player.position.x)
    context.py = string.format("%.1f", player.position.y)
  end
  
  -- What the player is currently doing
  if player.selected then
    context.selected = player.selected.name
  end
  
  return context
end

function utils.clean_record(rec)
  local clean_rec = {}
  for k, v in pairs(rec) do
    if v ~= nil then
      clean_rec[k] = v
    end
  end
  return clean_rec
end

-- ============================================================================
-- PLAYER VALIDATOR MODULE
-- ============================================================================
local player_validator = {}

function player_validator.is_player_event(e)
  if not e.player_index then
    return false
  end
  
  local player = game.players[e.player_index]
  if not player or not player.valid or not player.connected then
    return false
  end
  
  return true
end

-- ============================================================================
-- EVENT REGISTRY MODULE
-- ============================================================================
local event_registry = {}

event_registry.tracked_events = {
  -- Core building/mining actions
  defines.events.on_built_entity,
  defines.events.on_player_mined_entity,
  
  -- Crafting
  defines.events.on_player_crafted_item,
  defines.events.on_player_cancelled_crafting,
  
  -- Important cursor/pipette actions
  defines.events.on_player_cursor_stack_changed,
  defines.events.on_player_pipette,
  
  -- GUI interactions
  defines.events.on_gui_click,
  defines.events.on_gui_text_changed,
  defines.events.on_gui_checked_state_changed,
  
  -- Research
  defines.events.on_research_started,
  defines.events.on_research_finished,
  
  -- Combat
  defines.events.on_player_used_capsule,
  
  -- Blueprint and planning
  defines.events.on_player_configured_blueprint,
  defines.events.on_player_setup_blueprint,
  defines.events.on_player_deconstructed_area,
  
  -- Transportation
  defines.events.on_player_driving_changed_state,
  defines.events.on_player_used_spider_remote,
  
  -- Equipment
  defines.events.on_player_placed_equipment,
  defines.events.on_player_removed_equipment,
  
  -- Communication
  defines.events.on_console_chat,
  defines.events.on_player_joined_game,
  defines.events.on_player_left_game,
  
  -- Important interactions
  defines.events.on_player_dropped_item,
  defines.events.on_player_fast_transferred,
  defines.events.on_player_rotated_entity,
  
  -- Movement and position
  defines.events.on_player_changed_position,
  
  -- Mining and item interactions
  defines.events.on_player_mined_tile,
  defines.events.on_player_mined_item,
  defines.events.on_picked_up_item,
  
  -- Radar and scanning
  -- defines.events.on_sector_scanned,
  
  -- Train operations
  defines.events.on_train_changed_state,
  
  -- Rocket operations
  defines.events.on_rocket_launch_ordered,
  defines.events.on_rocket_launched,
  
  -- World generation
  -- defines.events.on_chunk_generated,
}

function event_registry.get_event_name(event_id)
  for name, id in pairs(defines.events) do
    if id == event_id then
      return name
    end
  end
  return nil
end

-- ============================================================================
-- CONTEXT EXTRACTORS MODULE
-- ============================================================================
local context_extractors = {}

function context_extractors.on_player_cursor_stack_changed(e, rec, player)
  local ctx = utils.get_player_context(player)
  
  -- Only log if there's actual cursor data
  if not ctx.cursor_item then
    return false -- Skip logging this event
  end
  
  rec.cursor_item = ctx.cursor_item
  rec.cursor_count = ctx.cursor_count
end

function context_extractors.on_player_main_inventory_changed(e, rec, player)
  -- Skip logging this - too noisy and usually consequence of other actions
  return false -- Signal to skip this event
end

function context_extractors.on_player_pipette(e, rec, player)
  rec.pipette_item = e.item and e.item.name
end

function context_extractors.on_built_entity(e, rec, player)
  rec.action = "build"
  -- Item info is usually in created_entity for these events
  if e.created_entity then
    rec.ent = utils.get_entity_info(e.created_entity)
  end
end

function context_extractors.on_player_mined_entity(e, rec, player)
  rec.action = "mine"
  if e.buffer then
    -- Log what was gained from mining
    local items = {}
    for i = 1, #e.buffer do
      local stack = e.buffer[i]
      if stack and stack.valid_for_read then
        table.insert(items, stack.name .. ":" .. stack.count)
      end
    end
    if #items > 0 then
      rec.gained = table.concat(items, ",")
    end
  end
end

function context_extractors.on_player_crafted_item(e, rec, player)
  rec.action = "craft"
  rec.recipe = e.recipe and e.recipe.name
end

function context_extractors.on_gui_click(e, rec, player)
  rec.gui_element = e.element and e.element.name
  rec.button = e.button -- left/right/middle click
end

function context_extractors.on_research_started(e, rec, player)
  rec.action = "research_start"
  rec.tech = e.research and e.research.name
end

function context_extractors.on_research_finished(e, rec, player)
  rec.action = "research_done"
  rec.tech = e.research and e.research.name
end

function context_extractors.on_console_chat(e, rec, player)
  rec.msg = e.message
end

function context_extractors.on_player_driving_changed_state(e, rec, player)
  rec.action = e.entity and "enter_vehicle" or "exit_vehicle"
end

-- Missing extractors for existing events
function context_extractors.on_player_fast_transferred(e, rec, player)
  rec.action = "transfer"
  if e.entity then
    rec.ent = utils.get_entity_info(e.entity)
  end
end

function context_extractors.on_player_dropped_item(e, rec, player)
  rec.action = "drop"
  if e.entity then
    rec.ent = utils.get_entity_info(e.entity)
  end
end

function context_extractors.on_player_rotated_entity(e, rec, player)
  rec.action = "rotate"
  if e.entity then
    rec.ent = utils.get_entity_info(e.entity)
  end
end

-- New context extractors for newly added events
function context_extractors.on_player_changed_position(e, rec, player)
  rec.action = "move"
  -- Position is already added in logger.create_base_record if available in event
  -- Add player context for additional info
  local ctx = utils.get_player_context(player)
  if ctx.cursor_item then
    rec.cursor_item = ctx.cursor_item
    rec.cursor_count = ctx.cursor_count
  end
  if ctx.selected then
    rec.selected = ctx.selected
  end
end

function context_extractors.on_player_mined_tile(e, rec, player)
  rec.action = "mine_tile"
  if e.tiles then
    local tiles = {}
    for _, tile in pairs(e.tiles) do
      if tile and tile.name then
        table.insert(tiles, tile.name)
      end
    end
    if #tiles > 0 then
      rec.tiles = table.concat(tiles, ",")
    end
  end
end

function context_extractors.on_player_mined_item(e, rec, player)
  rec.action = "pickup"
  if e.item_stack then
    -- SimpleItemStack is just a table with name and count
    rec.itm = e.item_stack.name
    rec.cnt = e.item_stack.count
  end
end

function context_extractors.on_picked_up_item(e, rec, player)
  rec.action = "pickup"
  if e.item_stack then
    rec.itm = e.item_stack.name
    rec.cnt = e.item_stack.count
  end
end

-- function context_extractors.on_sector_scanned(e, rec, player)
--   rec.action = "radar_scan"
--   if e.radar then
--     rec.radar_ent = utils.get_entity_info(e.radar)
--   end
--   if e.chunk_position then
--     rec.chunk_x = e.chunk_position.x
--     rec.chunk_y = e.chunk_position.y
--   end
-- end

function context_extractors.on_train_changed_state(e, rec, player)
  rec.action = "train_state_change"
  if e.train then
    rec.old_state = e.old_state
    rec.new_state = e.train.state
    if e.train.front_stock then
      rec.train_ent = utils.get_entity_info(e.train.front_stock)
    end
  end
end

function context_extractors.on_rocket_launch_ordered(e, rec, player)
  rec.action = "rocket_ordered"
  if e.rocket then
    rec.rocket_ent = utils.get_entity_info(e.rocket)
  end
end

function context_extractors.on_rocket_launched(e, rec, player)
  rec.action = "rocket_launched"
  if e.rocket then
    rec.rocket_ent = utils.get_entity_info(e.rocket)
  end
end

-- function context_extractors.on_chunk_generated(e, rec, player)
--   rec.action = "chunk_generated"
--   if e.area then
--     rec.chunk_left_top_x = e.area.left_top.x
--     rec.chunk_left_top_y = e.area.left_top.y
--     rec.chunk_right_bottom_x = e.area.right_bottom.x
--     rec.chunk_right_bottom_y = e.area.right_bottom.y
--   end
--   if e.position then
--     rec.chunk_pos_x = e.position.x
--     rec.chunk_pos_y = e.position.y
--   end
-- end

function context_extractors.on_player_setup_blueprint(e, rec, player)
  rec.action = "blueprint_setup"
  if e.area then
    rec.area_x1 = e.area.left_top.x
    rec.area_y1 = e.area.left_top.y
    rec.area_x2 = e.area.right_bottom.x
    rec.area_y2 = e.area.right_bottom.y
  end
  if e.item then
    rec.item = e.item
  end
  if e.entities and #e.entities > 0 then
    rec.entity_count = #e.entities
  end
end

function context_extractors.on_player_configured_blueprint(e, rec, player)
  rec.action = "blueprint_confirmed"
  -- Unfortunately, this event has limited data available
end

function context_extractors.on_player_cancelled_crafting(e, rec, player)
  rec.action = "cancel_craft"
  if e.recipe then
    rec.recipe = e.recipe.name
  end
  if e.cancel_count then
    rec.cancel_count = e.cancel_count
  end
end

function context_extractors.on_player_deconstructed_area(e, rec, player)
  rec.action = "deconstruct_area"
  if e.area then
    rec.area_x1 = e.area.left_top.x
    rec.area_y1 = e.area.left_top.y
    rec.area_x2 = e.area.right_bottom.x
    rec.area_y2 = e.area.right_bottom.y
  end
  if e.item then
    rec.item = e.item
  end
  if e.alt ~= nil then
    rec.alt_mode = e.alt
  end
end

function context_extractors.get_extractor(evt_name)
  return context_extractors[evt_name] or function() end -- Default no-op
end

-- ============================================================================
-- LOGGER MODULE
-- ============================================================================
local logger = {}

function logger.emit(record)
  log(game.table_to_json(record))
end

function logger.create_base_record(evt_name, e)
  local rec = {
    t  = e.tick,
    p  = e.player_index,
    ev = evt_name,
  }
  
  -- Add position if available in event
  if e.position then
    rec.x = string.format("%.1f", e.position.x)
    rec.y = string.format("%.1f", e.position.y)
  end
  
  -- Add entity info if available
  if e.entity then
    rec.ent = utils.get_entity_info(e.entity)
  end
  
  -- Add item/stack info if available
  if e.stack then
    rec.itm, rec.cnt = utils.get_item_info(e.stack)
  elseif e.item_stack then
    rec.itm, rec.cnt = utils.get_item_info(e.item_stack)
  end
  
  return rec
end

function logger.add_player_context_if_missing(rec, player)
  -- Add player context for location-based events if not already present
  if not rec.x and not rec.y and player then
    local ctx = utils.get_player_context(player)
    rec.x = ctx.px
    rec.y = ctx.py
  end
end

function logger.log_event(evt_name, e)
  local player = e.player_index and game.players[e.player_index]
  
  -- Create base record
  local rec = logger.create_base_record(evt_name, e)
  
  -- Apply event-specific context extraction
  local extractor = context_extractors.get_extractor(evt_name)
  local should_log = extractor(e, rec, player)
  
  -- Check if event should be skipped
  if should_log == false then
    return
  end
  
  -- Add player context if missing
  logger.add_player_context_if_missing(rec, player)
  
  -- Clean up nil values and emit
  local clean_rec = utils.clean_record(rec)
  logger.emit(clean_rec)
end

-- ============================================================================
-- MAIN MODULE - EVENT REGISTRATION AND GLUE CODE
-- ============================================================================
local main = {}

function main.register_event_handlers()
  for _, event_id in pairs(event_registry.tracked_events) do
    script.on_event(event_id, function(e)
      -- Some events don't have player_index (rockets, trains, etc.)
      local has_player = e.player_index ~= nil
      
      if has_player then
        -- For player events, validate the player
        if player_validator.is_player_event(e) then
          local evt_name = event_registry.get_event_name(event_id)
          if evt_name then
            logger.log_event(evt_name, e)
          end
        end
      else
        -- For non-player events (rockets, trains, etc.), log directly
        local evt_name = event_registry.get_event_name(event_id)
        if evt_name then
          logger.log_event(evt_name, e)
        end
      end
    end)
  end
end

function main.initialize()
  main.register_event_handlers()
end

-- ============================================================================
-- SCRIPT INITIALIZATION
-- ============================================================================
script.on_init(function()
  log('[enhanced-player-logger] armed – writing contextual player actions to factorio-current.log')
end)

-- Initialize the modular logger
main.initialize()

-- ============================================================================
-- LEGACY MODULES (UNCHANGED)
-- ============================================================================
local handler = require("event_handler")
handler.add_lib(require("freeplay"))
handler.add_lib(require("silo-script"))