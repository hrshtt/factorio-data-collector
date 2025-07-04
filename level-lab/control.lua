-- level-lab: minimal Factorio mod entrypoint
--
-- This mod currently does nothing except log a message when the game is initialised.
-- More functionality will be added in subsequent steps.

local gui = require("scripts.gui")

script.on_init(function()
  log("Level Dump Lab mod initialised")
  for _, player in pairs(game.players) do
    gui.build_button(player)
  end
end)

script.on_event(defines.events.on_player_created, function(event)
  local player = game.get_player(event.player_index)
  gui.build_button(player)
end)

script.on_event(defines.events.on_gui_click, function(event)
  if event.element and event.element.valid and event.element.name == "level_dump_toggle" then
    local player = game.get_player(event.player_index)
    gui.toggle_frame(player)
  end
end) 