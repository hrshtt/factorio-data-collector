--@tick_overlay.lua
--@description Light-weight tick overlay using local flying text
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27
--@license MIT
--@category Other
--@tags tick, overlay, replay, factorio, flying-text

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
local SHOW_EVERY = 60      -- once per in-game second (60 UPS)
local TTL = 60             -- time to live (shorter than SHOW_EVERY to prevent pile-up)

-- ============================================================================
-- TICK OVERLAY MODULE
-- ============================================================================
local tick_overlay = {}

-- ============================================================================
-- TICK DISPLAY FUNCTION
-- ============================================================================
function tick_overlay.show_tick(e)
  -- Only show in multiplayer or replay mode
  if game.is_multiplayer() or game.is_replay then
    -- Show tick overlay for all connected players
    for _, player in pairs(game.connected_players) do
      player.create_local_flying_text{
        text = ("T=%d"):format(e.tick),
        create_at_cursor = true,   -- hovers under the mouse
        time_to_live = TTL         -- shorter than SHOW_EVERY so it never piles up
      }
    end
  end
end

-- ============================================================================
-- EVENT REGISTRATION
-- ============================================================================
function tick_overlay.register_events(event_dispatcher)
  -- Register periodic tick update (every 60 ticks = 1 second)
  event_dispatcher.register_nth_tick_handler(SHOW_EVERY, function(event)
    tick_overlay.show_tick(event)
  end)
end

-- ============================================================================
-- MODULE EXPORTS
-- ============================================================================
return tick_overlay 