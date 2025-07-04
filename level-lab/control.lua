-- level-lab: Factorio Layout Dump 0.3.0
--
-- Comprehensive factory layout dumper implementing the Factorio Layout Dump 0.3.0 specification.
-- Exports loss-less NDJSON format suitable for analysis, ML training, and factory reconstruction.

local gui = require("scripts.gui")
local layout_dumper = require("scripts.layout_dumper")

script.on_init(function()
  log("Factorio Layout Dump 0.3.0 mod initialised")
  for _, player in pairs(game.players) do
    gui.build_button(player)
  end
end)

script.on_event(defines.events.on_player_created, function(event)
  local player = game.get_player(event.player_index)
  gui.build_button(player)
end)

-- Helper function to get dump options from GUI
local function get_dump_options(player)
  local frame = player.gui.screen.level_dump_frame
  if not frame then return {} end
  
  local options = {}
  
  -- Check if include tiles is enabled
  local checkbox = frame["include_tiles_checkbox"]
  if checkbox and checkbox.state then
    options.include_tiles = true
  end
  
  return options
end

script.on_event(defines.events.on_gui_click, function(event)
  if event.element and event.element.valid then
    local player = game.get_player(event.player_index)
    local name = event.element.name
    
    if name == "level_dump_toggle" then
      gui.toggle_frame(player)
    elseif name == "level_dump_close" then
      if player.gui.screen.level_dump_frame then
        player.gui.screen.level_dump_frame.destroy()
      end
    elseif name == "level_dump_current_chunk" then
      local options = get_dump_options(player)
      layout_dumper.dump_current_chunk(player, options)
    elseif name == "level_dump_3x3_area" then
      local options = get_dump_options(player)
      layout_dumper.dump_area_around_player(player, 1, options)  -- 1 chunk radius = 3x3 area
    elseif name == "level_dump_5x5_area" then
      local options = get_dump_options(player)
      layout_dumper.dump_area_around_player(player, 2, options)  -- 2 chunk radius = 5x5 area
    end
  end
end) 