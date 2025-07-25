M = {}

local serialize = require('script.serialize')

local function dump(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dump(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
 end

function M.get_entities(player_index, radius, entity_names_json, position_x, position_y)
    local player = game.players[player_index]
    local position
    if position_x and position_y then
        position = {x = tonumber(position_x), y = tonumber(position_y)}
    else
        position = player.position
    end

    radius = tonumber(radius) or 5
    local entity_names = game.json_to_table(entity_names_json) or {}
    local area = {
        {position.x - radius, position.y - radius},
        {position.x + radius, position.y + radius}
    }

    local filter = {}
    if entity_names and #entity_names > 0 then
        filter = {name = entity_names}
    end

    local entities
    if #entity_names > 0 then
        entities = player.surface.find_entities_filtered{area = area, force = player.force, filter=filter}
    else
        entities = player.surface.find_entities_filtered{area = area, force = player.force}
    end

    local result = {}
    for _, entity in ipairs(entities) do
        if entity.name ~= 'character' then
            local serialized = serialize.serialize_entity(entity)
            table.insert(result, serialized)
        end
    end
    return dump(result)
end

return M