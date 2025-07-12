--@craft_item.lua
--@description Craft item action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local craft_item = {}
local shared_utils = require("script.shared-utils")

function craft_item.register_events()
  script.on_event(defines.events.on_player_crafted_item, function(e)
    if not shared_utils.is_player_event(e) then return end
    local player = game.players[e.player_index]
    local rec = shared_utils.create_base_record("on_player_crafted_item", e)
    rec.action = "craft_item"
    rec.recipe = e.recipe and e.recipe.name or nil
    shared_utils.add_player_context_if_missing(rec, player)
    local clean_rec = shared_utils.clean_record(rec)
    local line = game.table_to_json(clean_rec)
    shared_utils.buffer_event("craft_item", line)
  end)
end

return craft_item 