--@move_to_collated.lua
--@description Collated move to action logger - tracks movement segments by direction
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local move_to_collated = {}
local shared_utils = require("script.shared-utils")

-- Direction name mapping for cleaner logs
local D = defines.direction
local dir_names = {
  [D.north] = "N",
  [D.northeast] = "NE", 
  [D.east] = "E",
  [D.southeast] = "SE",
  [D.south] = "S",
  [D.southwest] = "SW",
  [D.west] = "W",
  [D.northwest] = "NW"
}

-- Get movement state from global storage
local function get_movement_state()
  if not global.move_to_collated then
    global.move_to_collated = { movement_state = {} }
  end
  return global.move_to_collated.movement_state
end

-- Helper function to create a collated movement record
local function create_collated_record(player, direction_name, start_tick, end_tick, start_pos, end_pos)
  local rec = shared_utils.create_base_record("move_to_direction", {
    tick = end_tick,
    player_index = player.index,
  }, player)

  rec.player.x = nil
  rec.player.y = nil

  rec.player.start_movement = {
    tick = start_tick,
    x = string.format("%.1f", start_pos.x),
    y = string.format("%.1f", start_pos.y)
  }

  rec.player.end_movement = { 
    tick = end_tick,
    x = string.format("%.1f", end_pos.x),
    y = string.format("%.1f", end_pos.y)
  }
  
  rec.direction = direction_name
  rec.duration_ticks = end_tick - start_tick
  -- Calculate distance moved
  local dx = end_pos.x - start_pos.x
  local dy = end_pos.y - start_pos.y
  rec.distance = string.format("%.1f", math.sqrt(dx * dx + dy * dy))
  
  return rec
end

-- Helper function to flush the current movement segment
local function flush_movement_segment(player_index, end_tick)
  local movement_state = get_movement_state()
  local state = movement_state[player_index]
  if not state or not state.direction then return end
  
  local player = game.players[player_index]
  if not player or not player.valid then
    movement_state[player_index] = nil
    return
  end
  
  -- Create the collated record
  local rec = create_collated_record(
    player,
    state.direction_name,
    state.start_tick,
    end_tick,
    state.start_pos,
    player.position
  )
  
  local clean_rec = shared_utils.clean_record(rec)
  local line = game.table_to_json(clean_rec)
  shared_utils.buffer_event("move_to_collated", line)
  
  -- Clear the current segment
  movement_state[player_index] = nil
end

-- Main event handler for player position changes
local function on_player_changed_position(event)
  if not shared_utils.is_player_event(event) then return end
  
  local player = game.players[event.player_index]
  local player_index = event.player_index
  local movement_state = get_movement_state()
  
  -- Initialize player state if needed
  if not movement_state[player_index] then
    movement_state[player_index] = {}
  end
  
  local state = movement_state[player_index]
  local walking_state = player.walking_state
  
  -- Check if player is currently walking
  if not walking_state.walking then
    -- Player stopped - flush current segment
    if state.direction then
      flush_movement_segment(player_index, game.tick)
    end
    return
  end
  
  -- Get current direction
  local current_direction = walking_state.direction
  local current_direction_name = dir_names[current_direction] or "UNKNOWN"
  
  -- Check if direction changed or starting new segment
  if state.direction ~= current_direction then
    -- Direction changed - flush previous segment
    if state.direction then
      flush_movement_segment(player_index, game.tick - 1)
    end
    
    -- Start new segment
    movement_state[player_index] = {
      direction = current_direction,
      direction_name = current_direction_name,
      start_tick = game.tick,
      start_pos = {x = player.position.x, y = player.position.y}
    }
  end
end

-- Clean up movement state when player leaves
local function on_player_left_game(event)
  local player_index = event.player_index
  local movement_state = get_movement_state()
  
  -- Flush any active movement segment
  if movement_state[player_index] then
    flush_movement_segment(player_index, event.tick)
  end
end

-- Periodic cleanup for stale segments (safety net)
local function cleanup_stale_segments()
  local current_tick = game.tick
  local timeout_ticks = 600 -- 10 seconds timeout
  local movement_state = get_movement_state()
  
  for player_index, state in pairs(movement_state) do
    if state.start_tick and (current_tick - state.start_tick) >= timeout_ticks then
      local player = game.players[player_index]
      if player and player.valid then
        -- Check if player is still actually walking
        if not player.walking_state.walking then
          flush_movement_segment(player_index, current_tick)
        end
      else
        -- Player no longer valid, clean up
        movement_state[player_index] = nil
      end
    end
  end
end

-- Register event handlers
function move_to_collated.register_events(event_dispatcher)
  event_dispatcher.register_handler(defines.events.on_player_changed_position, on_player_changed_position)
  
  -- Player lifecycle events
  event_dispatcher.register_handler(defines.events.on_player_left_game, on_player_left_game)
  
  -- Register periodic cleanup (every 10 seconds)
  event_dispatcher.register_nth_tick_handler(600, cleanup_stale_segments)
end

-- Initialize storage on script initialization
function move_to_collated.on_init()
  -- Storage is initialized in get_movement_state() function
end

-- Initialize storage on script load
function move_to_collated.on_load()
  -- Storage is initialized in get_movement_state() function
end

return move_to_collated 