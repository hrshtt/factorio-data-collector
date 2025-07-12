--@shared-utils.lua
--@description Shared utilities for category-based logging
--@author Harshit Sharma
--@version 1.0.0
--@date 2025-01-27
--@license MIT

local shared_utils = {}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================
function shared_utils.get_item_info(stack)
  if not stack or not stack.valid_for_read then
    return nil, nil
  end
  return stack.name, stack.count
end

function shared_utils.get_entity_info(entity)
  if not entity or not entity.valid then
    return nil
  end
  return entity.name
end

function shared_utils.get_player_context(player)
  if not player or not player.valid then
    return {}
  end
  
  local context = {}
  
  -- Current cursor item
  if player.cursor_stack and player.cursor_stack.valid_for_read then
    context.cursor_item = player.cursor_stack.name
    context.cursor_count = player.cursor_stack.count
  end
  
  -- Current position (rounded for cleaner logs)
  if player.position then
    context.px = string.format("%.1f", player.position.x)
    context.py = string.format("%.1f", player.position.y)
  end
  
  -- What the player is currently doing
  if player.selected then
    context.selected = player.selected.name
  end
  
  return context
end

function shared_utils.clean_record(rec)
  local clean_rec = {}
  for k, v in pairs(rec) do
    if v ~= nil then
      clean_rec[k] = v
    end
  end
  return clean_rec
end

-- ============================================================================
-- PLAYER VALIDATOR
-- ============================================================================
function shared_utils.is_player_event(e)
  if not e.player_index then
    return false
  end
  
  local player = game.players[e.player_index]
  if not player or not player.valid or not player.connected then
    return false
  end
  
  return true
end

-- ============================================================================
-- BASE RECORD CREATION
-- ============================================================================
function shared_utils.create_base_record(evt_name, e)
  local rec = {
    t  = e.tick,
    p  = e.player_index,
    ev = evt_name,
  }
  
  -- Add position if available in event
  if e.position then
    rec.x = string.format("%.1f", e.position.x)
    rec.y = string.format("%.1f", e.position.y)
  end
  
  -- Add entity info if available
  if e.entity then
    rec.entity = shared_utils.get_entity_info(e.entity)
  end
  
  -- Add item/stack info if available
  if e.stack then
    rec.item, rec.count = shared_utils.get_item_info(e.stack)
  elseif e.item_stack then
    rec.item, rec.count = shared_utils.get_item_info(e.item_stack)
  end
  
  return rec
end

function shared_utils.add_player_context_if_missing(rec, player)
  -- Add player context for location-based events if not already present
  if not rec.x and not rec.y and player then
    local ctx = shared_utils.get_player_context(player)
    rec.x = ctx.px
    rec.y = ctx.py
  end
end

-- ============================================================================
-- BUFFER MANAGEMENT
-- ============================================================================
local MAX_BUF_BYTES = 1000    -- ~1 MB safety cap

function shared_utils.initialize_category_buffer(category_name)
  if not global.category_buffers then
    global.category_buffers = {}
  end
  if not global.category_buffers[category_name] then
    global.category_buffers[category_name] = {
      buf = {},
      buf_bytes = 0,
      file_initialized = false
    }
  end
end

function shared_utils.buffer_event(category_name, line)
  shared_utils.initialize_category_buffer(category_name)
  
  local buffer = global.category_buffers[category_name]
  table.insert(buffer.buf, line)
  buffer.buf_bytes = buffer.buf_bytes + #line + 1  -- +1 for "\n"
  
  if buffer.buf_bytes >= MAX_BUF_BYTES then
    shared_utils.flush_category_buffer(category_name)
  end
end

function shared_utils.flush_category_buffer(category_name)
  local buffer = global.category_buffers[category_name]
  if not buffer or #buffer.buf == 0 then return end
  
  local OUT_DIR = "replay-logs/"
  local LOG_PATH = OUT_DIR .. category_name .. ".jsonl"
  
  -- Check if this is the first write of this session
  local is_first_write = not buffer.file_initialized
  if is_first_write then
    buffer.file_initialized = true
  end
  
  -- First write overwrites, subsequent writes append
  game.write_file(LOG_PATH, table.concat(buffer.buf, "\n") .. "\n", not is_first_write)
  buffer.buf, buffer.buf_bytes = {}, 0
end

function shared_utils.flush_all_buffers()
  if global.category_buffers then
    for category_name, _ in pairs(global.category_buffers) do
      shared_utils.flush_category_buffer(category_name)
    end
  end
end

return shared_utils 