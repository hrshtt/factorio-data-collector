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
    caption = "Factorio Layout Dump 0.3.0",
    direction = "vertical"
  }
  frame.auto_center = true
  
  -- Main description
  frame.add{
    type = "label", 
    caption = "Export factory layouts in NDJSON format compatible with analysis tools."
  }
  
  -- Dump options section
  local options_flow = frame.add{type = "flow", direction = "vertical"}
  options_flow.add{type = "label", caption = "Dump Options:"}
  
  -- Include tiles checkbox
  local tiles_checkbox = options_flow.add{
    type = "checkbox",
    name = "include_tiles_checkbox",
    caption = "Include tiles (ground/resources)",
    state = false
  }
  
  -- Dump mode buttons
  local buttons_flow = frame.add{type = "flow", direction = "vertical"}
  buttons_flow.style.vertical_spacing = 4
  
  buttons_flow.add{
    type = "button", 
    name = "level_dump_current_chunk", 
    caption = "Dump Current Chunk (32x32)",
    tooltip = "Export entities and tiles from the chunk you're standing in"
  }
  
  buttons_flow.add{
    type = "button", 
    name = "level_dump_3x3_area", 
    caption = "Dump 3x3 Chunk Area",
    tooltip = "Export a 3x3 chunk area (96x96 tiles) centered on your position"
  }
  
  buttons_flow.add{
    type = "button", 
    name = "level_dump_5x5_area", 
    caption = "Dump 5x5 Chunk Area",
    tooltip = "Export a 5x5 chunk area (160x160 tiles) centered on your position"
  }
  
  -- Info section
  local info_flow = frame.add{type = "flow", direction = "vertical"}
  info_flow.style.top_padding = 8
  
  info_flow.add{
    type = "label", 
    caption = "Output files saved to script-output/level-lab/"
  }
  
  info_flow.add{
    type = "label", 
    caption = "Format: NDJSON (Newline Delimited JSON)"
  }
  
  -- Close button
  local button_flow = frame.add{type = "flow", direction = "horizontal"}
  button_flow.style.top_padding = 8
  button_flow.add{type = "button", name = "level_dump_close", caption = "Close"}
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