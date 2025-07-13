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

  local function is_production_machine(entity)
    if not entity or not entity.valid then return false end
    local t = entity.type
    return t == "assembling-machine" or t == "furnace" or t == "oil-refinery" or t == "chemical-plant"
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
    local player_index = e.player_index
    local entity = e.entity
    local recipe = entity.get_recipe()
    local new_recipe = recipe and recipe.name or nil
    local state = global.set_entity_recipe_state[player_index]
    local old_recipe = state and state.entity_unit_number == entity.unit_number and state.old_recipe or nil
    -- Only log if recipe changed (including from nil)
    if old_recipe ~= new_recipe then
      local rec = shared_utils.create_base_record("set_entity_recipe", e)
      rec.action = "set_entity_recipe"
      rec.entity = entity.name
      rec.entity_type = entity.type
      rec.old_recipe = old_recipe
      rec.new_recipe = new_recipe
      shared_utils.add_player_context_if_missing(rec, game.players[player_index])
      local clean_rec = shared_utils.clean_record(rec)
      local line = game.table_to_json(clean_rec)
      shared_utils.buffer_event("set_entity_recipe", line)
    end
    -- Clean up state
    global.set_entity_recipe_state[player_index] = nil
  end

  event_dispatcher.register_handler(defines.events.on_gui_opened, on_gui_opened)
  event_dispatcher.register_handler(defines.events.on_gui_closed, on_gui_closed)
end

return set_entity_recipe