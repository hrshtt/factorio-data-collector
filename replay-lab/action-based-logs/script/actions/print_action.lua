--@print_action.lua
--@description Print action optional observation action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local print_action = {}
local shared_utils = require("script.shared-utils")

function print_action.register_events(event_dispatcher)
  -- This module doesn't register any events - it's called by other modules
end

return print_action 