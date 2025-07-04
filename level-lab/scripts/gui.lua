local gui = {}

local mod_gui = require("mod-gui")

function gui.build_button(player)
  local flow = mod_gui.get_button_flow(player)
  if flow.level_dump_toggle then return end
  flow.add{
    type = "button",
    name = "level_dump_toggle",
    caption = "LD",
    tooltip = {"mod-name.level-dump"}
  }
end

function gui.build_frame(player)
  local screen = player.gui.screen
  if screen.level_dump_frame then return end

  local frame = screen.add{
    type = "frame",
    name = "level_dump_frame",
    caption = {"mod-name.level-dump"},
    direction = "vertical"
  }
  frame.auto_center = true
  frame.add{type = "label", caption = "Level Dump Lab loaded."}
  frame.add{type = "button", name = "level_dump_close", caption = "Close"}
end

function gui.toggle_frame(player)
  local frame = player.gui.screen.level_dump_frame
  if frame and frame.valid then
    frame.destroy()
  else
    gui.build_frame(player)
  end
end

return gui 