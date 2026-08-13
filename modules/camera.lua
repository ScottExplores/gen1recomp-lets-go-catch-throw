-- Read-only camera bridge.  Dramaless Shape 1.6.4 is optional and is read
-- through its published exports; Kanto First Person is reported as status
-- only and never participates in camera calculations.

return function(mod, shared)
  local api = {}

  api.MODE_DIORAMA = "DIORAMA"
  api.MODE_FIRST_PERSON = "1ST"
  api.MODE_THIRD_PERSON = "3RD"
  api.DRAMALESS_VERSION = "1.6.4"
  api.KFP_VERSION = "1.60.0"

  local function find(otherId)
    if type(mod.find) ~= "function" then return nil end
    local ok, handle = pcall(mod.find, otherId)
    if not ok then ok, handle = pcall(mod.find, mod, otherId) end
    return ok and type(handle) == "table" and handle or nil
  end

  local function exportRequire(handle, name)
    local lib = handle and handle.exports and handle.exports.lib
    if type(lib) ~= "table" or type(lib.require) ~= "function" then return nil end
    local ok, value = pcall(lib.require, name)
    if not ok then ok, value = pcall(lib.require, lib, name) end
    return ok and type(value) == "table" and value or nil
  end

  local function dramaless()
    local handle = find("DRAMALESS_SHAPE")
    if not handle then
      return { installed = false, compatible = false, reason = "not installed" }
    end
    local exportedVersion = handle.exports and handle.exports.version
    local version = exportedVersion or handle.version
    local compatible = handle.version == api.DRAMALESS_VERSION
      and (exportedVersion == nil or exportedVersion == api.DRAMALESS_VERSION)
    local result = {
      installed = true,
      compatible = compatible,
      version = version,
      handle = handle,
    }
    if not compatible then
      result.reason = "unsupported Dramaless version"
      return result
    end
    result.voxel = exportRequire(handle, "VoxelState")
    result.firstPerson = exportRequire(handle, "FirstPerson")
    result.voxel3d = exportRequire(handle, "Voxel3D")
    result.available = result.voxel ~= nil and result.voxel3d ~= nil
    if not result.available then result.reason = "camera exports unavailable" end
    return result
  end

  local function kfpStatus()
    local handle = find("ds_fp_ceiling")
    if not handle then
      return { installed = false, compatible = false, reason = "not installed" }
    end
    local status = {
      installed = true,
      compatible = handle.version == api.KFP_VERSION,
      version = handle.version,
    }
    local configFn = handle.exports and handle.exports.config
    if type(configFn) == "function" then
      local ok, config = pcall(configFn)
      if ok and type(config) == "table" then
        status.config = {}
        for key, value in pairs(config) do status.config[key] = value end
      end
    end
    if not status.compatible then status.reason = "unrecognized KFP version" end
    return status
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

  local function worldPoint(value)
    if type(value) ~= "table" then return nil end
    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z }
  end

  local function arrayPoint(value)
    if type(value) ~= "table" then return nil end
    local x, y, z = tonumber(value[1] or value.x),
                    tonumber(value[2] or value.y),
                    tonumber(value[3] or value.z)
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z }
  end

  local function normalized(x, y, z)
    local length = math.sqrt(x * x + y * y + z * z)
    if length <= 1e-9 then return nil end
    return { x = x / length, y = y / length, z = z / length }
  end

  local function callPredicate(object, name, value)
    local fn = object and object[name]
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, value)
    return ok and result == true
  end

  function api.mode(a, b, c)
    local _game, _overworld
    if a == api then _game, _overworld = b, c else _game, _overworld = a, b end
    local ds = dramaless()
    local voxel = ds.compatible and ds.voxel or nil
    if voxel then
      local level = voxel.level
      if callPredicate(voxel, "isFirstPerson", level) then
        return api.MODE_FIRST_PERSON
      end
      if callPredicate(voxel, "isThirdPerson", level) then
        return api.MODE_THIRD_PERSON
      end
    end
    return api.MODE_DIORAMA
  end

  local FACING = {
    up = { x = 0, y = 0, z = -1 },
    down = { x = 0, y = 0, z = 1 },
    left = { x = -1, y = 0, z = 0 },
    right = { x = 1, y = 0, z = 0 },
  }

  function api.direction(a, b, c)
    local game, overworld
    if a == api then game, overworld = b, c else game, overworld = a, b end
    local ds = dramaless()
    if ds.compatible and ds.voxel3d then
      local eye = arrayPoint(ds.voxel3d.eye)
      local focus = arrayPoint(ds.voxel3d.focus)
      if eye and focus then
        local direction = normalized(focus.x - eye.x, focus.y - eye.y,
                                     focus.z - eye.z)
        if direction then return direction end
      end
      local fp = ds.firstPerson
      if fp and type(fp.lookFlat) == "function" then
        local result = { pcall(fp.lookFlat) }
        if result[1] then
          local direction = normalized(tonumber(result[2]) or 0, 0,
                                       tonumber(result[3]) or 0)
          if direction then return direction end
        end
      end
    end

    overworld = overworldOf(game, overworld)
    local facing = overworld and overworld.player and overworld.player.facing
    local fallback = FACING[facing] or FACING.down
    return { x = fallback.x, y = fallback.y, z = fallback.z }
  end

  function api.origin(a, b, c, d)
    local game, overworld, opts
    if a == api then game, overworld, opts = b, c, d
    else game, overworld, opts = a, b, c end
    opts = opts or {}
    local ds = dramaless()
    local mode = api.mode(game, overworld)
    if mode == api.MODE_FIRST_PERSON and ds.compatible and ds.voxel3d then
      local eye = arrayPoint(ds.voxel3d.eye)
      if eye then return eye end
    end

    overworld = overworldOf(game, overworld)
    local player = overworld and overworld.player
    if not player then return nil, "no overworld player" end
    local px = tonumber(player.px)
      or (tonumber(player.cellX) and player.cellX * 16)
    local pz = tonumber(player.py)
      or (tonumber(player.cellY) and player.cellY * 16)
    if not px or not pz then return nil, "player position unavailable" end

    local direction = api.direction(game, overworld)
    local forward = tonumber(opts.forward)
    if forward == nil then forward = mode == api.MODE_DIORAMA and 4 or 5 end
    local side = tonumber(opts.side) or 0
    local rightX, rightZ = -direction.z, direction.x
    return {
      x = px + 8 + direction.x * forward + rightX * side,
      y = tonumber(opts.height) or 10,
      z = pz + 8 + direction.z * forward + rightZ * side,
    }
  end

  function api.project(a, b, c, d)
    local value, game, overworld
    if a == api then value, game, overworld = b, c, d
    else value, game, overworld = a, b, c end
    local point = worldPoint(value)
    if not point then return nil, "invalid world point" end

    local ds = dramaless()
    local project = ds.compatible and ds.voxel3d and ds.voxel3d.project
    if type(project) == "function" then
      local result = { pcall(project, point.x, point.y, point.z) }
      if result[1] and result[2] ~= nil then
        return result[2], result[3], result[4]
      end
    end

    -- Safe 2D core fallback: x/z are map pixels and vertical y rises upward.
    overworld = overworldOf(game, overworld)
    local camera = overworld and overworld.camera
    if not camera then return nil, "projection unavailable" end
    return point.x - (tonumber(camera.x) or 0),
           point.z - (tonumber(camera.y) or 0) - point.y,
           1
  end

  function api.frame(a, b, c)
    local game, overworld
    if a == api then game, overworld = b, c else game, overworld = a, b end
    local origin, err = api.origin(game, overworld)
    if not origin then return nil, err end
    local direction = api.direction(game, overworld)
    return {
      mode = api.mode(game, overworld),
      origin = origin,
      direction = direction,
      right = { x = -direction.z, y = 0, z = direction.x },
      up = { x = 0, y = 1, z = 0 },
    }
  end

  function api.status(a, b, c)
    local game, overworld
    if a == api then game, overworld = b, c else game, overworld = a, b end
    local ds = dramaless()
    return {
      mode = api.mode(game, overworld),
      dramaless = {
        installed = ds.installed,
        compatible = ds.compatible,
        available = ds.available == true,
        version = ds.version,
        reason = ds.reason,
      },
      -- Informational only.  No KFP function is used by origin/direction/project.
      kantoFirstPerson = kfpStatus(),
    }
  end

  shared.camera = api
  return api
end
