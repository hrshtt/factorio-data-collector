local layout_dumper = {}

-- Validation functions for format compliance
local function validate_position(position)
  if not position or not position.x256 or not position.y256 then
    return false, "Missing x256 or y256 in position"
  end
  
  -- Check absolute value < 2^31 as per spec
  if math.abs(position.x256) >= 2147483648 or math.abs(position.y256) >= 2147483648 then
    return false, "Position coordinates exceed 2^31 limit"
  end
  
  return true
end

local function validate_entity_record(record)
  -- Check mandatory fields
  if record.kind ~= "entity" then
    return false, "Record kind must be 'entity'"
  end
  
  if not record.entity_number or record.entity_number <= 0 then
    return false, "entity_number must be positive integer"
  end
  
  if not record.name or type(record.name) ~= "string" then
    return false, "name must be string"
  end
  
  local pos_ok, pos_err = validate_position(record.position)
  if not pos_ok then
    return false, "Invalid position: " .. pos_err
  end
  
  -- Check direction range (0-255)
  if record.direction and (record.direction < 0 or record.direction > 255) then
    return false, "direction must be 0-255"
  end
  
  -- Check orientation range (0-1)
  if record.orientation and (record.orientation < 0 or record.orientation >= 1) then
    return false, "orientation must be 0 <= value < 1"
  end
  
  return true
end

local function validate_tile_record(record)
  -- Check mandatory fields
  if record.kind ~= "tile" then
    return false, "Record kind must be 'tile'"
  end
  
  if not record.name or type(record.name) ~= "string" then
    return false, "name must be string"
  end
  
  local pos_ok, pos_err = validate_position(record.position)
  if not pos_ok then
    return false, "Invalid position: " .. pos_err
  end
  
  if not record.stack or type(record.stack) ~= "table" then
    return false, "stack must be array"
  end
  
  if not record.amount or record.amount < 0 then
    return false, "amount must be non-negative"
  end
  
  return true
end

-- Utility functions for coordinate conversion
local function pos_to_x256_y256(position)
  return {
    x256 = math.floor(position.x * 256 + 0.5),
    y256 = math.floor(position.y * 256 + 0.5)
  }
end

local function get_chunk_coords(position)
  return {
    x = math.floor(position.x / 32),
    y = math.floor(position.y / 32)
  }
end

-- Get all active mods with their versions
local function get_active_mods()
  local mods = {}
  for name, version in pairs(script.active_mods) do
    if name ~= "base" then  -- Exclude base game
      mods[name] = version
    end
  end
  return mods
end

-- Generate the manifest header according to spec
local function generate_manifest(surface_name, options)
  options = options or {}
  
  -- Enhanced metadata
  local meta = options.meta or {}
  meta.game_tick = game.tick
  meta.include_tiles = options.include_tiles or false
  meta.dump_area = options.dump_area or "unknown"
  meta.area_size_tiles = options.area_size_tiles
  meta.chunk_coordinates = options.chunk_coordinates
  
  local manifest = {
    format = "factorio-layout/0.3.0",
    generator = "Factorio Layout Dump 0.3.0 (level-lab mod)",
    timestamp = game.tick,  -- Use game tick as timestamp
    factorio_version = script.active_mods.base,
    surface = surface_name,
    mods = get_active_mods(),
    encoding = {
      compression = "none",
      record_order = options.record_order or "chunk-x,y,x256,y256"
    },
    meta = meta
  }
  
  return manifest
end

-- Convert entity direction to raw engine value (0-255)
local function get_entity_direction(entity)
  if entity.direction then
    return entity.direction
  end
  return 0
end

-- Get entity orientation (0-1 for rolling stock, curved rails)
local function get_entity_orientation(entity)
  if entity.orientation then
    return entity.orientation
  end
  return 0
end

-- Get entity recipe(s)
local function get_entity_recipe(entity)
  -- Recipe detection requires entity-specific handling
  -- For now, return nil to avoid API issues
  -- TODO: Implement proper recipe detection per entity type
  return nil
end

-- Get entity modules
local function get_entity_modules(entity)
  -- Module detection requires entity-specific handling
  -- For now, return nil to avoid API issues
  -- TODO: Implement proper module detection per entity type
  return nil
end

-- Get entity inventory contents
local function get_entity_inventory(entity)
  -- Inventory detection is complex and entity-specific
  -- For now, return nil to avoid API issues
  -- TODO: Implement proper inventory detection per entity type
  return nil
end

-- Get circuit connections
local function get_circuit_connections(entity)
  -- Circuit connection detection is complex and entity-specific
  -- For now, return nil to avoid API issues
  -- TODO: Implement proper circuit connection detection per entity type
  return nil
end

-- Get fluid box information
local function get_fluid_boxes(entity)
  -- Fluid box detection is complex and entity-specific
  -- For now, return nil to avoid API issues
  -- TODO: Implement proper fluid box detection per entity type
  return nil
end

-- Get entity bounding box
local function get_bounding_box(entity)
  local box = entity.bounding_box
  if box then
    return {
      left_top = pos_to_x256_y256(box.left_top),
      right_bottom = pos_to_x256_y256(box.right_bottom)
    }
  end
  return nil
end

-- Convert entity to record format
local function entity_to_record(entity, surface_name)
  local position_256 = pos_to_x256_y256(entity.position)
  local chunk = get_chunk_coords(entity.position)
  
  local record = {
    kind = "entity",
    entity_number = entity.unit_number,
    name = entity.name,
    position = position_256,
    chunk = chunk,
    direction = get_entity_direction(entity),
    orientation = get_entity_orientation(entity),
    force = entity.force.name,
    prototype = entity.type,  -- Entity type as prototype family
  }
  
  -- Add surface if different from header
  if surface_name ~= "nauvis" then
    record.surface = surface_name
  end
  
  -- Optional fields
  local recipe = get_entity_recipe(entity)
  if recipe then
    record.recipe = recipe
  end
  
  local modules = get_entity_modules(entity)
  if modules then
    record.modules = modules
  end
  
  local inventory = get_entity_inventory(entity)
  if inventory then
    record.inventory = inventory
  end
  
  local circuit_connections = get_circuit_connections(entity)
  if circuit_connections then
    record.circuit_connections = circuit_connections
  end
  
  local fluid_boxes = get_fluid_boxes(entity)
  if fluid_boxes then
    record.fluid_boxes = fluid_boxes
  end
  
  local bounding_box = get_bounding_box(entity)
  if bounding_box then
    record.bounding_box = bounding_box
  end
  
  -- Entity flags
  record.flags = {
    ghost = entity.type == "entity-ghost",
    deconstructed = entity.to_be_deconstructed()
  }
  
  return record
end

-- Convert tile to record format
local function tile_to_record(tile, surface_name)
  local position_256 = pos_to_x256_y256(tile.position)
  local chunk = get_chunk_coords(tile.position)
  
  local record = {
    kind = "tile",
    name = tile.name,
    position = position_256,
    chunk = chunk,
    stack = {tile.name},  -- Single item stack for now
    amount = 0  -- Default for non-resource tiles
  }
  
  -- Add surface if different from header
  if surface_name ~= "nauvis" then
    record.surface = surface_name
  end
  
  -- Check if tile has resources
  if tile.name:match(".*%-ore$") or tile.name == "crude-oil" then
    -- This is a simplification - actual resource amount would need surface.get_resource_counts()
    record.amount = 1000  -- Placeholder
  end
  
  return record
end

-- Dump a specific area
function layout_dumper.dump_area(surface, area, options)
  options = options or {}
  local surface_name = surface.name
  
  -- Generate manifest
  local manifest = generate_manifest(surface_name, options)
  local output_lines = {serpent.line(manifest)}
  
  -- Add area boundary information as a comment
  if options.area_size_tiles then
    local area_info = {
      kind = "area_info",
      message = string.format("Dump area: %s, Size: %dx%d tiles, Coordinates: %s to %s",
        options.dump_area or "unknown",
        options.area_size_tiles.width, options.area_size_tiles.height,
        string.format("(%d,%d)", area[1].x, area[1].y),
        string.format("(%d,%d)", area[2].x, area[2].y)
      )
    }
    table.insert(output_lines, serpent.line(area_info))
  end
  
  -- Get all entities in area
  local entities = surface.find_entities_filtered{area = area}
  
  -- Sort entities by chunk, then by position for consistent ordering
  table.sort(entities, function(a, b)
    local chunk_a = get_chunk_coords(a.position)
    local chunk_b = get_chunk_coords(b.position)
    
    if chunk_a.x ~= chunk_b.x then
      return chunk_a.x < chunk_b.x
    elseif chunk_a.y ~= chunk_b.y then
      return chunk_a.y < chunk_b.y
    elseif a.position.x ~= b.position.x then
      return a.position.x < b.position.x
    else
      return a.position.y < b.position.y
    end
  end)
  
  -- Add entity records
  local validation_errors = {}
  for _, entity in pairs(entities) do
    if entity.unit_number then  -- Only entities with unit numbers
      local record = entity_to_record(entity, surface_name)
      
      -- Validate record before adding
      local valid, error_msg = validate_entity_record(record)
      if valid then
        table.insert(output_lines, serpent.line(record))
      else
        table.insert(validation_errors, string.format("Entity %s at (%s,%s): %s", 
                     entity.name, entity.position.x, entity.position.y, error_msg))
      end
    end
  end
  
  -- Get tiles if requested
  if options.include_tiles then
    local tiles = surface.find_tiles_filtered{area = area}
    
    -- Sort tiles similarly
    table.sort(tiles, function(a, b)
      local chunk_a = get_chunk_coords(a.position)
      local chunk_b = get_chunk_coords(b.position)
      
      if chunk_a.x ~= chunk_b.x then
        return chunk_a.x < chunk_b.x
      elseif chunk_a.y ~= chunk_b.y then
        return chunk_a.y < chunk_b.y
      elseif a.position.x ~= b.position.x then
        return a.position.x < b.position.x
      else
        return a.position.y < b.position.y
      end
    end)
    
    -- Add tile records
    for _, tile in pairs(tiles) do
      local record = tile_to_record(tile, surface_name)
      
      -- Validate tile record before adding
      local valid, error_msg = validate_tile_record(record)
      if valid then
        table.insert(output_lines, serpent.line(record))
      else
        table.insert(validation_errors, string.format("Tile %s at (%s,%s): %s", 
                     tile.name, tile.position.x, tile.position.y, error_msg))
      end
    end
  end
  
  -- Log validation errors if any
  if #validation_errors > 0 then
    log(string.format("Layout dump validation errors (%d total):", #validation_errors))
    for _, error in ipairs(validation_errors) do
      log("  " .. error)
    end
  end
  
  return table.concat(output_lines, "\n")
end

-- Dump current chunk around player
function layout_dumper.dump_current_chunk(player, options)
  if not player or not player.valid then return nil end
  
  local surface = player.surface
  local chunk = get_chunk_coords(player.position)
  local left_top = {x = chunk.x * 32, y = chunk.y * 32}
  local right_bottom = {x = (chunk.x + 1) * 32, y = (chunk.y + 1) * 32}
  local area = {left_top, right_bottom}
  
  -- Add metadata about the dump area
  options = options or {}
  options.dump_area = "single_chunk"
  options.area_size_tiles = {width = 32, height = 32}
  options.chunk_coordinates = {x = chunk.x, y = chunk.y}
  
  local output = layout_dumper.dump_area(surface, area, options)
  
  -- Write to file
  local filename = string.format("level-lab/factorio_layout_chunk_%d_%d.ndjson", chunk.x, chunk.y)
  helpers.write_file(filename, output, false)
  
  -- Count entities for feedback
  local entities = surface.find_entities_filtered{area = area}
  local entity_count = 0
  for _, entity in pairs(entities) do
    if entity.unit_number then
      entity_count = entity_count + 1
    end
  end
  
  local message = {"", "[layout-dump] Single Chunk (32×32): Exported ", entity_count, " entities from chunk (", chunk.x, ",", chunk.y, ") to ", filename}
  if options.include_tiles then
    local tiles = surface.find_tiles_filtered{area = area}
    table.insert(message, " (+ ")
    table.insert(message, #tiles)
    table.insert(message, " tiles)")
  end
  player.print(message)
  
  return output
end

-- Dump larger area around player
function layout_dumper.dump_area_around_player(player, radius_chunks, options)
  if not player or not player.valid then return nil end
  
  local surface = player.surface
  local center_chunk = get_chunk_coords(player.position)
  
  local left_top = {
    x = (center_chunk.x - radius_chunks) * 32,
    y = (center_chunk.y - radius_chunks) * 32
  }
  local right_bottom = {
    x = (center_chunk.x + radius_chunks + 1) * 32,
    y = (center_chunk.y + radius_chunks + 1) * 32
  }
  local area = {left_top, right_bottom}
  
  -- Add metadata about the dump area
  options = options or {}
  local chunks_per_side = (radius_chunks * 2 + 1)
  local tiles_per_side = chunks_per_side * 32
  options.dump_area = string.format("area_%dx%d_chunks", chunks_per_side, chunks_per_side)
  options.area_size_tiles = {width = tiles_per_side, height = tiles_per_side}
  options.chunk_coordinates = {
    center = {x = center_chunk.x, y = center_chunk.y},
    top_left = {x = center_chunk.x - radius_chunks, y = center_chunk.y - radius_chunks},
    bottom_right = {x = center_chunk.x + radius_chunks, y = center_chunk.y + radius_chunks}
  }
  
  local output = layout_dumper.dump_area(surface, area, options)
  
  -- Write to file
  local filename = string.format("level-lab/factorio_layout_area_%dx%d_chunks.ndjson", 
                                 (radius_chunks * 2 + 1), (radius_chunks * 2 + 1))
  helpers.write_file(filename, output, false)
  
  -- Count entities for feedback
  local entities = surface.find_entities_filtered{area = area}
  local entity_count = 0
  for _, entity in pairs(entities) do
    if entity.unit_number then
      entity_count = entity_count + 1
    end
  end
  
  local chunks_per_side = (radius_chunks * 2 + 1)
  local tiles_per_side = chunks_per_side * 32
  local message = {"", "[layout-dump] Multi-Chunk Area (", tiles_per_side, "×", tiles_per_side, "): Exported ", entity_count, " entities from ", 
                chunks_per_side, "×", chunks_per_side, " chunk area centered on (", center_chunk.x, ",", center_chunk.y, ") to ", filename}
  if options.include_tiles then
    local tiles = surface.find_tiles_filtered{area = area}
    table.insert(message, " (+ ")
    table.insert(message, #tiles)
    table.insert(message, " tiles)")
  end
  player.print(message)
  
  return output
end

return layout_dumper 