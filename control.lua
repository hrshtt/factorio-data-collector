-- ============================================================================
-- UTILITY FUNCTIONS MODULE
-- ============================================================================
local OUT_DIR = "factorio_replays/"
local LOG_PATH = OUT_DIR .. "replay-log.jsonl"
local utils = {}

-- Buffer configuration
local FLUSH_EVERY     = 600        -- 10 s at 60 UPS
local MAX_BUF_BYTES   = 1000000    -- ~1 MB safety cap

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
-- BLUEPRINT UTILITIES MODULE
-- ============================================================================
local blueprint_utils = {}

function blueprint_utils.extract_blueprint_data(bp_stack, tag, tick, player_idx)
  -- Safety checks
  if not (bp_stack and bp_stack.valid_for_read and bp_stack.is_blueprint_setup()) then
    return nil -- Nothing to extract
  end
  
  local success, bp_data = pcall(function()
    -- Extract blueprint data safely
    local data = {}
    
    -- Basic metadata
    data.tick = tick
    data.player = player_idx
    data.phase = tag
    data.label = bp_stack.label or ""
    
    -- Blueprint string (safe for export/import)
    local export_success, bp_string = pcall(function()
      return bp_stack.export_stack()
    end)
    if export_success and bp_string then
      -- Create digest for correlation
      local digest_success, bp_digest = pcall(function()
        return string.sub(game.encode_string(bp_string), 1, 12)
      end)
      if digest_success and bp_digest then
        data.bp_digest = bp_digest
        
        -- Log blueprint string to separate file
        local write_success = pcall(function()
          local line = string.format("[%d] %s %s %s %s\n", 
            tick, bp_digest, tag, data.label, bp_string)
          game.write_file(OUT_DIR .. "blueprint-strings.txt", line, true)
        end)
        if not write_success then
          log("[blueprint-logger] Error writing blueprint string to file")
        end
      end
    end
    
    -- Entity data
    local entities_success, entities = pcall(function()
      return bp_stack.get_blueprint_entities() or {}
    end)
    if entities_success and entities then
      data.entity_count = #entities
      -- Store first few entities for quick inspection (limit to avoid huge logs)
      if #entities > 0 then
        data.sample_entities = {}
        for i = 1, math.min(5, #entities) do
          local ent = entities[i]
          if ent and ent.name then
            table.insert(data.sample_entities, {
              name = ent.name,
              position = ent.position
            })
          end
        end
      end
    end
    
    -- Tile data
    local tiles_success, tiles = pcall(function()
      return bp_stack.get_blueprint_tiles and bp_stack.get_blueprint_tiles() or {}
    end)
    if tiles_success and tiles then
      data.tile_count = #tiles
    end
    
    return data
  end)
  
  if not success then
    -- Log the error but don't crash
    log("[blueprint-logger] Error extracting blueprint data: " .. tostring(bp_data))
    return nil
  end
  
  return bp_data
end

function blueprint_utils.get_blueprint_stack_safely(event, player)
  -- Try multiple sources for the blueprint stack based on event type
  local stack = nil
  
  if player and player.cursor_stack then
    -- For configured blueprint (usually in cursor)
    stack = player.cursor_stack
  elseif event.stack then
    -- Direct stack from event (on_player_setup_blueprint in v1.1+)
    stack = event.stack
  elseif player and player.opened_gui_type == defines.gui_type.item and player.opened then
    -- Blueprint in opened GUI
    stack = player.opened
  elseif player and player.blueprint_to_setup then
    -- Fallback for setup phase
    stack = player.blueprint_to_setup
  end
  
  -- Validate the stack
  if stack and stack.valid_for_read and stack.is_blueprint_setup and stack.is_blueprint_setup() then
    return stack
  end
  
  return nil
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
  defines.events.on_pre_player_crafted_item,
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
  defines.events.on_pre_player_left_game,
  
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
    rec.entity = utils.get_entity_info(e.created_entity)
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

function context_extractors.on_pre_player_crafted_item(e, rec, player)
  rec.action = "queue_craft"
  rec.recipe = e.recipe and e.recipe.name
  rec.count = e.queued_count
  
  -- Log items consumed from inventory
  if e.items then
    local consumed_items = {}
    for name, count in pairs(e.items.get_contents()) do
      if count > 0 then
        table.insert(consumed_items, name .. ":" .. count)
      end
    end
    if #consumed_items > 0 then
      rec.consumed = table.concat(consumed_items, ",")
    end
  end
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
    rec.entity = utils.get_entity_info(e.entity)
  end
end

function context_extractors.on_player_dropped_item(e, rec, player)
  rec.action = "drop"
  if e.entity then
    rec.entity = utils.get_entity_info(e.entity)
  end
end

function context_extractors.on_player_rotated_entity(e, rec, player)
  rec.action = "rotate"
  if e.entity then
    rec.entity = utils.get_entity_info(e.entity)
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
    rec.item = e.item_stack.name
    rec.count = e.item_stack.count
  end
end

function context_extractors.on_picked_up_item(e, rec, player)
  rec.action = "pickup"
  if e.item_stack then
    rec.item = e.item_stack.name
    rec.count = e.item_stack.count
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
    rec.area_x1 = string.format("%.1f", e.area.left_top.x)
    rec.area_y1 = string.format("%.1f", e.area.left_top.y)
    rec.area_x2 = string.format("%.1f", e.area.right_bottom.x)
    rec.area_y2 = string.format("%.1f", e.area.right_bottom.y)
  end
  if e.item then
    rec.item = e.item
  end
  if e.entities and #e.entities > 0 then
    rec.entity_count = #e.entities
  end
  
  -- Enhanced blueprint logging - extract and log full blueprint data
  local bp_stack = blueprint_utils.get_blueprint_stack_safely(e, player)
  if bp_stack then
    local bp_data = blueprint_utils.extract_blueprint_data(bp_stack, "setup", e.tick, e.player_index)
    if bp_data then
      rec.bp_digest = bp_data.bp_digest
      rec.bp_label = bp_data.label
      rec.bp_entity_count = bp_data.entity_count
    end
  end
end

function context_extractors.on_player_configured_blueprint(e, rec, player)
  rec.action = "blueprint_confirmed"
  
  -- Enhanced blueprint logging - the blueprint is now in the player's cursor
  local bp_stack = blueprint_utils.get_blueprint_stack_safely(e, player)
  if bp_stack then
    local bp_data = blueprint_utils.extract_blueprint_data(bp_stack, "confirm", e.tick, e.player_index)
    if bp_data then
      rec.bp_digest = bp_data.bp_digest
      rec.bp_label = bp_data.label
      rec.bp_entity_count = bp_data.entity_count
    end
  end
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
    rec.area_x1 = string.format("%.1f", e.area.left_top.x)
    rec.area_y1 = string.format("%.1f", e.area.left_top.y)
    rec.area_x2 = string.format("%.1f", e.area.right_bottom.x)
    rec.area_y2 = string.format("%.1f", e.area.right_bottom.y)
  end
  if e.item then
    rec.item = e.item
  end
  if e.alt ~= nil then
    rec.alt_mode = e.alt
  end
end

function context_extractors.on_pre_player_left_game(e, rec, player)
  rec.action = "leaving_game"
  rec.reason = e.reason -- disconnect reason
end

function context_extractors.get_extractor(evt_name)
  return context_extractors[evt_name] or function() end -- Default no-op
end

-- ============================================================================
-- LOGGER MODULE
-- ============================================================================
local logger = {}

function logger.emit(record)
  -- Check if this is the first write of this session
  local is_first_write = not global.file_initialized
  if is_first_write then
    global.file_initialized = true
  end
  
  -- First write overwrites, subsequent writes append
  game.write_file(LOG_PATH, game.table_to_json(record) .. "\n", not is_first_write)
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
    rec.entity = utils.get_entity_info(e.entity)
  end
  
  -- Add item/stack info if available
  if e.stack then
    rec.item , rec.count = utils.get_item_info(e.stack)
  elseif e.item_stack then
    rec.item , rec.count = utils.get_item_info(e.item_stack)
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
  
  -- Clean up nil values and buffer the event
  local clean_rec = utils.clean_record(rec)
  local line = game.table_to_json(clean_rec)
  
  -- Ensure global buffer is initialized
  if not global.log_buf then
    global.log_buf = {}
    global.buf_bytes = 0
  end
  
  table.insert(global.log_buf, line)
  global.buf_bytes = global.buf_bytes + #line + 1      -- +1 for "\n"

  if global.buf_bytes >= MAX_BUF_BYTES then  -- emergency flush
    flush_buffer()
  end
end

-- ============================================================================
-- BUFFER MANAGEMENT
-- ============================================================================
local function flush_buffer()
  if not global.log_buf or #global.log_buf == 0 then return end
  
  -- Check if this is the first write of this session
  local is_first_write = not global.file_initialized
  if is_first_write then
    global.file_initialized = true
  end
  
  -- First write overwrites, subsequent writes append
  game.write_file(LOG_PATH, table.concat(global.log_buf, "\n") .. "\n", not is_first_write)
  global.log_buf, global.buf_bytes = {}, 0
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
  -- Initialize global buffer
  global.log_buf   = global.log_buf   or {}   -- survives save/load
  global.buf_bytes = global.buf_bytes or 0
  global.file_initialized = false  -- Track if we've written to file yet
  
  log('[enhanced-player-logger] armed – writing contextual player actions to ' .. LOG_PATH)
end)

script.on_load(function()
  -- Initialize global buffer on load
  global.log_buf   = global.log_buf   or {}
  global.buf_bytes = global.buf_bytes or 0
  global.file_initialized = global.file_initialized or false
end)

-- Periodic flush every FLUSH_EVERY ticks
script.on_nth_tick(FLUSH_EVERY, flush_buffer)

-- Final-tick detection (headless or local view)
script.on_event(defines.events.on_tick, function(event)
  -- First tick detection for replay start
  if event.tick == 1 then
    log('[REPLAY-START] First tick detected, replay begins')
  end
  
end)

-- Replay end detection when player leaves
script.on_event(defines.events.on_pre_player_left_game, function(event)
  log('[REPLAY-END] Player leaving game, replay ends at tick ' .. event.tick)
end)

-- Initialize the modular logger
main.initialize()

-- ============================================================================
-- LEGACY MODULES (UNCHANGED)
-- ============================================================================
local handler = require("event_handler")
handler.add_lib(require("freeplay"))
handler.add_lib(require("silo-script"))