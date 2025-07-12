--@get_entity.lua
--@description Get entity optional observation action logger
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27

local get_entity = {}
local shared_utils = require("script.shared-utils")

function get_entity.register_events(event_dispatcher)
  -- This module doesn't register any events - it's called by other modules
end

return get_entity 