-- Optional Wilds of Kanto bridge.  Discovery is read-only.  The sole private
-- call is SpawnLogic:_startBattle(record), guarded to the audited 1.11.1
-- surface and a still-live record/entity pair; this module never captures,
-- despawns, or mutates Wilds tables directly.

return function(mod, shared)
  local api = {}
  api.MOD_ID = "overworld_wild_spawns"
  api.SUPPORTED_VERSION = "1.11.1"

  local function findWilds()
    if type(mod.find) ~= "function" then return nil end
    local ok, handle = pcall(mod.find, api.MOD_ID)
    if not ok then ok, handle = pcall(mod.find, mod, api.MOD_ID) end
    return ok and type(handle) == "table" and handle or nil
  end

  local function integration()
    local handle = findWilds()
    if not handle then
      return nil, {
        installed = false,
        compatible = false,
        available = false,
        reason = "Wilds of Kanto is not installed",
      }
    end
    local exports = type(handle.exports) == "table" and handle.exports or {}
    local exportedVersion = exports.version
    local compatible = handle.version == api.SUPPORTED_VERSION
      and (exportedVersion == nil or exportedVersion == api.SUPPORTED_VERSION)
    local logic = type(exports.logic) == "table" and exports.logic or nil
    local available = compatible and logic
      and type(logic.entities) == "table"
      and type(logic.spawns) == "table"
      and type(exports.isBattleableWild) == "function"
    local status = {
      installed = true,
      compatible = compatible,
      available = available == true,
      version = exportedVersion or handle.version,
    }
    if not compatible then status.reason = "unsupported Wilds version"
    elseif not available then status.reason = "required Wilds exports unavailable" end
    return available and {
      handle = handle,
      exports = exports,
      logic = logic,
    } or nil, status
  end

  local function gameOf(game)
    if type(game) == "table" and game.save then return game end
    if type(shared.game) == "table" then return shared.game end
    local ok, world = pcall(function() return mod.world end)
    return ok and world and world.game or nil
  end

  local function overworldOf(game, overworld)
    if type(overworld) == "table" and overworld.player then return overworld end
    game = gameOf(game)
    if game and type(game.overworld) == "table" then return game.overworld end
    local ok, world = pcall(function() return mod.world end)
    if ok and world and type(world.overworld) == "function" then
      local found, value = pcall(world.overworld, world)
      if found then return value end
    end
    return nil
  end

  local function battleable(integrationValue, entity)
    local predicate = integrationValue.exports.isBattleableWild
    local ok, result = pcall(predicate, entity)
    if not ok then ok, result = pcall(predicate, integrationValue.exports, entity) end
    return ok and result == true
  end

  local function active(logic)
    if type(logic.featureActive) ~= "function" then return true end
    local ok, result = pcall(logic.featureActive, logic)
    return ok and result ~= false
  end

  local function sameMap(record, entity, overworld)
    local wanted = overworld and overworld.map and overworld.map.id
    if not wanted then return true end
    local actual = (entity and entity.mapId) or (record and record.mapId)
    return actual == nil or actual == wanted
  end

  local function exactPosition(entity, opts)
    local px = tonumber(entity.px)
    local py = tonumber(entity.py)
    if not px and tonumber(entity.cellX) then px = entity.cellX * 16 end
    if not py and tonumber(entity.cellY) then py = entity.cellY * 16 end
    if not px or not py then return nil end
    local lift = math.max(0, tonumber(entity._lastLift) or 0)
    return {
      x = px + (tonumber(opts.centerX) or 8),
      y = (tonumber(opts.targetHeight) or 8) + lift,
      z = py + (tonumber(opts.centerZ) or 8),
    }, px, py
  end

  local function originPoint(opts)
    local origin = opts and opts.origin
    if type(origin) ~= "table" then return nil end
    local x = tonumber(origin.x or origin[1])
    local y = tonumber(origin.y or origin[2])
    local z = tonumber(origin.z or origin[3])
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z }
  end

  function api.status(a)
    local _ = a
    local value, status = integration()
    if value then
      status.active = active(value.logic)
      status.targetCount = 0
      for _id in pairs(value.logic.entities) do
        status.targetCount = status.targetCount + 1
      end
    else
      status.active = false
      status.targetCount = 0
    end
    return status
  end

  function api.targets(a, b, c, d)
    local game, overworld, opts
    if a == api then game, overworld, opts = b, c, d
    else game, overworld, opts = a, b, c end
    opts = opts or {}
    local value, status = integration()
    if not value then return {}, status.reason end
    if not active(value.logic) then return {}, "Wilds feature is disabled" end
    overworld = overworldOf(game, overworld)
    local origin = originPoint(opts)
    local maxRange = tonumber(opts.range or opts.maxRange)
    local maxRangeSquared = maxRange and maxRange * maxRange or nil
    local results = {}

    for id, entity in pairs(value.logic.entities) do
      local record = value.logic.spawns[id]
        or (entity and entity.id and value.logic.spawns[entity.id])
      local visible = entity and (opts.includeHidden == true
        or (entity.visibleSprite ~= false and entity.hiddenEncounter ~= true))
      local ready = entity and entity.canTriggerBattle ~= false
      local available = record and record.state == "available"
      if available and visible and ready and sameMap(record, entity, overworld)
         and battleable(value, entity) then
        local position, px, py = exactPosition(entity, opts)
        if position then
          local dx, dy, dz, distanceSquared
          if origin then
            dx, dy, dz = position.x - origin.x, position.y - origin.y,
                         position.z - origin.z
            distanceSquared = dx * dx + dy * dy + dz * dz
          end
          if not maxRangeSquared or (distanceSquared and distanceSquared <= maxRangeSquared) then
            results[#results + 1] = {
              id = entity.id or record.id or id,
              species = entity.species or record.species,
              level = entity.level or record.level,
              mapId = entity.mapId or record.mapId,
              cellX = entity.cellX or record.x,
              cellY = entity.cellY or record.y,
              pixelX = px,
              pixelY = py,
              position = position,
              radius = tonumber(opts.radius) or 7,
              distanceSquared = distanceSquared,
              -- Opaque identity guards for startBattle; callers should treat
              -- these as tokens, not as mutable Wilds objects.
              _entity = entity,
              _record = record,
              _key = id,
            }
          end
        end
      end
    end

    table.sort(results, function(left, right)
      if left.distanceSquared and right.distanceSquared
         and left.distanceSquared ~= right.distanceSquared then
        return left.distanceSquared < right.distanceSquared
      end
      return tostring(left.id) < tostring(right.id)
    end)
    return results
  end
  api.discover = api.targets

  function api.nearest(a, b, c, d, e)
    local game, overworld, origin, range
    if a == api then game, overworld, origin, range = b, c, d, e
    else game, overworld, origin, range = a, b, c, d end
    local targets = api.targets(game, overworld, { origin = origin, range = range })
    return targets[1]
  end

  function api.startBattle(a, b, c, d)
    local target, game, overworld
    if a == api then target, game, overworld = b, c, d
    else target, game, overworld = a, b, c end
    if type(target) ~= "table" or target.id == nil then
      return false, "invalid Wilds target"
    end
    local value, status = integration()
    if not value then return false, status.reason end
    if not active(value.logic) then return false, "Wilds feature is disabled" end
    if type(value.logic._startBattle) ~= "function" then
      return false, "Wilds battle bridge unavailable"
    end

    local key = target._key or target.id
    local entity = value.logic.entities[key]
    local record = value.logic.spawns[key]
    if not entity or not record then return false, "stale Wilds target" end
    if record.state ~= "available" then return false, "Wilds target is unavailable" end
    if target._entity and target._entity ~= entity then return false, "stale Wilds entity" end
    if target._record and target._record ~= record then return false, "stale Wilds record" end
    overworld = overworldOf(game, overworld)
    if not sameMap(record, entity, overworld) then return false, "target left this map" end
    if not battleable(value, entity) then return false, "target is not battleable" end

    -- Audited 1.11.1 signature: SpawnLogic:_startBattle(record).
    local ok, started = pcall(value.logic._startBattle, value.logic, record)
    if not ok then return false, tostring(started) end
    if started ~= true then return false, "Wilds refused battle start" end
    return true
  end

  shared.wilds = api
  return api
end
