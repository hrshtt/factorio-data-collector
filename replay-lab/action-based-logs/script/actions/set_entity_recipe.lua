--@set_entity_recipe.lua
--@description Set entity recipe action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local set_entity_recipe = {}
local shared_utils = require("script.shared-utils")

function set_entity_recipe.register_events(event_dispatcher)
  -- Track last known recipe per player per entity
  if not global.set_entity_recipe_state then
    global.set_entity_recipe_state = {}
  end

  -- Use a type table for production machines
  local crafting_types = { ["assembling-machine"] = true, ["oil-refinery"] = true, ["chemical-plant"] = true, ["rocket-silo"] = true }
  local function is_production_machine(entity)
    return entity and entity.valid and crafting_types[entity.type]
  end

  -- Track pre-paste recipe for each destination entity
  if not global.set_entity_recipe_pre_paste then
    global.set_entity_recipe_pre_paste = {}
  end

  -- Handler for GUI opened
  local function on_gui_opened(e)
    if not shared_utils.is_player_event(e) then return end
    if e.gui_type ~= defines.gui_type.entity or not e.entity or not is_production_machine(e.entity) then return end
    local player_index = e.player_index
    local entity = e.entity
    local recipe = entity.get_recipe()
    global.set_entity_recipe_state[player_index] = {
      entity = entity,
      entity_unit_number = entity.unit_number,
      old_recipe = recipe and recipe.name or nil
    }
  end

  -- Handler for GUI closed
  local function on_gui_closed(e)
    if not shared_utils.is_player_event(e) then return end
    if e.gui_type ~= defines.gui_type.entity or not e.entity or not is_production_machine(e.entity) then return end
    local player = game.players[e.player_index]
    local player_index = e.player_index
    local entity = e.entity
    local recipe = entity.get_recipe()
    local new_recipe = recipe and recipe.name or nil
    local state = global.set_entity_recipe_state[player_index]
    local old_recipe = state and state.entity_unit_number == entity.unit_number and state.old_recipe or nil
    -- Only log if recipe changed (including from nil)
    if old_recipe ~= new_recipe then
      local rec = shared_utils.create_base_record("set_entity_recipe", e, player)
      rec.entity = {}
      rec.entity.name = entity.name
      rec.entity.type = entity.type
      rec.entity.old_recipe = old_recipe
      rec.entity.new_recipe = new_recipe
      local clean_rec = shared_utils.clean_record(rec)
      local line = game.table_to_json(clean_rec)
      shared_utils.buffer_event("set_entity_recipe", line)
    end
    -- Clean up state
    global.set_entity_recipe_state[player_index] = nil
  end

  -- Pre-paste: snapshot the destination's recipe
  local function on_pre_entity_settings_pasted(e)
    local dst = e.destination
    if is_production_machine(dst) then
      local r = dst.get_recipe()
      global.set_entity_recipe_pre_paste[dst.unit_number] = r and r.name or nil
    end
  end

  -- Post-paste: compare and log if changed
  local function on_entity_settings_pasted(e)
    if not shared_utils.is_player_event(e) then return end
    local player = game.players[e.player_index]
    local src = e.source
    local dst = e.destination
    if not (is_production_machine(src) and is_production_machine(dst)) then return end
    local old = global.set_entity_recipe_pre_paste[dst.unit_number]
    global.set_entity_recipe_pre_paste[dst.unit_number] = nil -- clean up
    local new_r = dst.get_recipe()
    local new = new_r and new_r.name or nil
    if old ~= new then
      local rec = shared_utils.create_base_record("set_entity_recipe", e, player)
      rec.entity = {
        name = dst.name,
        type = dst.type,
        old_recipe = old,
        new_recipe = new
      }
      rec.paste_source_entity = {
        name = src.name,
        type = src.type
      }
      local clean_rec = shared_utils.clean_record(rec)
      local line = game.table_to_json(clean_rec)
      shared_utils.buffer_event("set_entity_recipe", line)
    end
  end

  event_dispatcher.register_handler(defines.events.on_gui_opened, on_gui_opened)
  event_dispatcher.register_handler(defines.events.on_gui_closed, on_gui_closed)
  event_dispatcher.register_handler(defines.events.on_pre_entity_settings_pasted, on_pre_entity_settings_pasted)
  event_dispatcher.register_handler(defines.events.on_entity_settings_pasted, on_entity_settings_pasted)
end

return set_entity_recipe