local function get_item_info(stack)
  if not stack or not stack.valid_for_read then
    return nil, nil
  end
  return stack.name, stack.count
end

local function get_entity_info(entity)
  if not entity or not entity.valid then
    return nil
  end
  return entity.name
end

local function get_player_context(player)
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

local function log_evt(evt_name, e)
  local player = e.player_index and game.players[e.player_index]
  
  -- Build enhanced record with context
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
    rec.ent = get_entity_info(e.entity)
  end
  
  -- Add item/stack info if available
  if e.stack then
    rec.itm, rec.cnt = get_item_info(e.stack)
  elseif e.item_stack then
    rec.itm, rec.cnt = get_item_info(e.item_stack)
  end
  
  -- Event-specific context extraction
  if evt_name == "on_player_cursor_stack_changed" then
    local ctx = get_player_context(player)
    rec.cursor_item = ctx.cursor_item
    rec.cursor_count = ctx.cursor_count
    
  elseif evt_name == "on_player_main_inventory_changed" then
    -- Skip logging this - too noisy and usually consequence of other actions
    return
    
  elseif evt_name == "on_player_pipette" then
    rec.pipette_item = e.item and e.item.name
    
  elseif evt_name == "on_built_entity" or evt_name == "on_player_built_entity" then
    rec.action = "build"
    -- Item info is usually in created_entity for these events
    if e.created_entity then
      rec.ent = get_entity_info(e.created_entity)
    end
    
  elseif evt_name == "on_player_mined_entity" then
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
    
  elseif evt_name == "on_player_crafted_item" then
    rec.action = "craft"
    rec.recipe = e.recipe and e.recipe.name
    
  elseif evt_name == "on_gui_click" then
    rec.gui_element = e.element and e.element.name
    rec.button = e.button -- left/right/middle click
    
  elseif evt_name == "on_research_started" then
    rec.action = "research_start"
    rec.tech = e.research and e.research.name
    
  elseif evt_name == "on_research_finished" then
    rec.action = "research_done"
    rec.tech = e.research and e.research.name
    
  elseif evt_name == "on_console_chat" then
    rec.msg = e.message
    
  elseif evt_name == "on_player_driving_changed_state" then
    rec.action = e.entity and "enter_vehicle" or "exit_vehicle"
    
  end
  
  -- Add player context for location-based events
  if not rec.x and not rec.y and player then
    local ctx = get_player_context(player)
    rec.x = ctx.px
    rec.y = ctx.py
  end
  
  -- Clean up nil values to make logs cleaner
  local clean_rec = {}
  for k, v in pairs(rec) do
    if v ~= nil then
      clean_rec[k] = v
    end
  end
  
  log(game.table_to_json(clean_rec))
end

-- Function to check if an event is player-initiated
local function is_player_event(e)
  if not e.player_index then
    return false
  end
  
  local player = game.players[e.player_index]
  if not player or not player.valid or not player.connected then
    return false
  end
  
  return true
end

-- Curated list of meaningful player events (excluding noisy ones)
local player_events = {
  -- Core building/mining actions
  defines.events.on_built_entity,
  defines.events.on_player_built_entity,
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
}

-- Subscribe to filtered events
for _, event_id in pairs(player_events) do
  script.on_event(event_id, function(e)
    if is_player_event(e) then
      -- Get event name
      local evt_name = nil
      for name, id in pairs(defines.events) do
        if id == event_id then
          evt_name = name
          break
        end
      end
      
      if evt_name then
        log_evt(evt_name, e)
      end
    end
  end)
end

script.on_init(function()
  log('[enhanced-player-logger] armed – writing contextual player actions to factorio-current.log')
end)

local handler = require("event_handler")
handler.add_lib(require("freeplay"))
handler.add_lib(require("silo-script"))