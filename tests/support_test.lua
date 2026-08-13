-- ROM-free support adapter tests. Run from the mod root with Lua/LuaJIT:
--   lua tests/support_test.lua

local passed, failed = 0, 0

local function check(name, condition, detail)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    io.stderr:write(("FAIL: %s%s\n"):format(name,
      detail and (" (" .. tostring(detail) .. ")") or ""))
  end
end

local function near(a, b, epsilon)
  return type(a) == "number" and type(b) == "number"
    and math.abs(a - b) <= (epsilon or 1e-6)
end

local function installer(name)
  local candidates = {
    "modules/" .. name .. ".lua",
    "../modules/" .. name .. ".lua",
  }
  for _, path in ipairs(candidates) do
    local chunk = loadfile(path)
    if chunk then return chunk() end
  end
  error("could not load modules/" .. name .. ".lua")
end

local saveBucket = {}
local handles = {}
local mod = {
  save = {
    get = function(_, key, default)
      local value = saveBucket[key]
      return value == nil and default or value
    end,
    set = function(_, key, value) saveBucket[key] = value end,
  },
  find = function(first, second)
    return handles[second == nil and first or second]
  end,
}
local shared = {}

-- A small Bag double preserves the engine's call signatures without a ROM.
package.preload["src.inventory.Bag"] = function()
  local Bag = {}
  function Bag.order(save) return save.bagOrder or {} end
  function Bag.remove(save, id, qty)
    local left = (save.inventory[id] or 0) - (qty or 1)
    save.inventory[id] = left > 0 and left or nil
  end
  function Bag.add(save, id, qty)
    local count = save.inventory[id] or 0
    if count + (qty or 1) > 99 then return false end
    save.inventory[id] = count + (qty or 1)
    return true
  end
  return Bag
end

-- trajectory ---------------------------------------------------------------
local trajectory = installer("trajectory")(mod, shared)
check("trajectory installs shared API", shared.trajectory == trajectory)
check("trajectory exposes five stages", #trajectory.RANGE_STAGES == 5
  and trajectory.RANGE_STAGES[1] == 1 and trajectory.RANGE_STAGES[5] == 5)
check("trajectory stage wraps", trajectory:nextStage(5, 1) == 1
  and trajectory:nextStage(1, -1) == 5)

local flight = assert(trajectory:start(
  { x = 10, y = 4, z = 20 }, { x = 0, y = 0, z = 1 }, 3,
  { arcHeight = 12, duration = 1 }))
check("trajectory uses 16px blocks", near(flight.finish.z, 68)
  and near(flight.finish.x, 10))
local atStart = trajectory:positionAt(flight, 0)
local atMiddle = trajectory:positionAt(flight, 0.5)
local atFinish = trajectory:positionAt(flight, 1)
check("trajectory endpoints are exact", near(atStart.x, 10)
  and near(atStart.y, 4) and near(atFinish.z, 68))
check("trajectory is parabolic", near(atMiddle.y, 16))
local again = trajectory:positionAt(flight, 0.5)
check("trajectory is deterministic", near(again.x, atMiddle.x)
  and near(again.y, atMiddle.y) and near(again.z, atMiddle.z))
local hit, hitT = trajectory:sweep(
  { x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 },
  { position = { x = 5, y = 1, z = 0 }, radius = 1 }, 0.25, 1)
check("trajectory swept hit", hit and hitT > 0 and hitT < 1)

-- inventory ----------------------------------------------------------------
local game = {
  save = {
    inventory = { POKE_BALL = 3, CUSTOM_BALL = 2 },
    bagOrder = { "CUSTOM_BALL", "POKE_BALL" },
  },
  data = {
    items = {
      POKE_BALL = { name = "POKE BALL" },
      CUSTOM_BALL = { name = "CUSTOM BALL" },
      SAFARI_BALL = { name = "SAFARI BALL" },
    },
    balls = {
      POKE_BALL = { randMax = 255 },
      CUSTOM_BALL = { randMax = 100 },
      SAFARI_BALL = { randMax = 150 },
    },
  },
}
local inventory = installer("inventory")(mod, shared)
check("inventory installs shared API", shared.inventory == inventory)
local available = inventory:available(game)
check("inventory discovers custom merged ball", #available == 2
  and available[1].id == "CUSTOM_BALL")
local selected = inventory:select(game)
check("inventory defaults to Bag order", selected == "CUSTOM_BALL")
shared.settings = { get = function(_, key)
  return key == "default_ball" and "poke_ball" or nil
end }
check("inventory maps preferred setting", inventory.choose(game, "preferred") == "POKE_BALL")
check("inventory spends real Bag count", inventory:commit(game, "CUSTOM_BALL", 1)
  and game.save.inventory.CUSTOM_BALL == 1)
check("inventory persists last used", inventory:lastUsed() == "CUSTOM_BALL")
check("inventory refunds real Bag count", inventory:refund(game, "CUSTOM_BALL", 1)
  and game.save.inventory.CUSTOM_BALL == 2)

-- Native BagMenu has already consumed this ball; cancelling must add it back.
game.save.inventory.POKE_BALL = 2
local reservation = assert(inventory:reserve(game, "POKE_BALL", 1, nil,
  { preconsumed = true }))
check("inventory refunds preconsumed BagMenu ball", inventory:cancel(reservation)
  and game.save.inventory.POKE_BALL == 3)

game.save.safari = { balls = 4, steps = 100 }
local bagBeforeSafari = game.save.inventory.POKE_BALL
check("inventory reads Safari counter", inventory:count(game, "SAFARI_BALL") == 4)
check("inventory spends Safari counter only",
  inventory:commit(game, "SAFARI_BALL", 1)
    and game.save.safari.balls == 3
    and game.save.inventory.POKE_BALL == bagBeforeSafari)
check("inventory refunds Safari counter only",
  inventory:refund(game, "SAFARI_BALL", 1)
    and game.save.safari.balls == 4
    and game.save.inventory.SAFARI_BALL == nil)
game.save.safari = nil

-- camera -------------------------------------------------------------------
local fakeVoxel = {
  level = 6,
  isFirstPerson = function(level) return level == 6 end,
  isThirdPerson = function(level) return level == 7 end,
}
local fakeFirstPerson = { lookFlat = function() return 0, 1 end }
local fakeVoxel3D = {
  eye = { 10, 12, 20 },
  focus = { 10, 12, 30 },
  project = function(x, y, z) return x + 1, z - y, 2 end,
}
handles.DRAMALESS_SHAPE = {
  version = "1.6.4",
  exports = {
    version = "1.6.4",
    lib = { require = function(name)
      return ({ VoxelState = fakeVoxel, FirstPerson = fakeFirstPerson,
                Voxel3D = fakeVoxel3D })[name]
    end },
  },
}
handles.ds_fp_ceiling = {
  version = "1.60.0",
  exports = { config = function() return { ceiling = true } end },
}
local overworld = {
  player = { px = 32, py = 48, facing = "left" },
  camera = { x = 10, y = 20 },
  map = { id = "ROUTE_1" },
}
game.overworld = overworld
local camera = installer("camera")(mod, shared)
check("camera installs shared API", shared.camera == camera)
check("camera detects Dramaless 1ST", camera:mode(game, overworld) == "1ST")
fakeVoxel.level = 7
check("camera detects Dramaless 3RD", camera:mode(game, overworld) == "3RD")
fakeVoxel.level = 3
check("camera detects Dramaless diorama", camera:mode(game, overworld) == "DIORAMA")
fakeVoxel.level = 6
local cameraOrigin = camera:origin(game, overworld)
local cameraDirection = camera:direction(game, overworld)
check("camera reads Dramaless eye", near(cameraOrigin.x, 10)
  and near(cameraOrigin.y, 12) and near(cameraOrigin.z, 20))
check("camera reads Dramaless direction", near(cameraDirection.x, 0)
  and near(cameraDirection.y, 0) and near(cameraDirection.z, 1))
local projectedX, projectedY, projectedScale = camera:project(
  { x = 5, y = 2, z = 9 }, game, overworld)
check("camera uses Dramaless projection", projectedX == 6
  and projectedY == 7 and projectedScale == 2)
local cameraStatus = camera:status(game, overworld)
check("camera reports KFP without consuming it",
  cameraStatus.kantoFirstPerson.compatible
    and cameraStatus.kantoFirstPerson.config.ceiling == true)

handles.DRAMALESS_SHAPE = nil
local fallbackDirection = camera:direction(game, overworld)
local fallbackX, fallbackY = camera:project({ x = 15, y = 3, z = 27 }, game, overworld)
check("camera core direction fallback", fallbackDirection.x == -1
  and fallbackDirection.z == 0)
check("camera core projection fallback", fallbackX == 5 and fallbackY == 4)

-- Wilds of Kanto -----------------------------------------------------------
local record = {
  id = "wilds_of_kanto_entity_1", mapId = "ROUTE_1", x = 4, y = 5,
  species = "PIDGEY", level = 3, state = "available",
}
local entity = {
  id = record.id, mapId = record.mapId, cellX = 4, cellY = 5,
  px = 66.5, py = 81.25, species = "PIDGEY", level = 3,
  overworldWildSpawn = true, visibleSprite = true, canTriggerBattle = true,
}
local ambientRecord = {
  id = "wilds_of_kanto_entity_2", mapId = "ROUTE_1", x = 8, y = 8,
  species = "RATTATA", level = 2, state = "available",
}
local ambientEntity = {
  id = ambientRecord.id, mapId = ambientRecord.mapId, px = 128, py = 128,
  species = "RATTATA", level = 2, wildsAmbientPokemon = true,
  visibleSprite = true,
}
local startedWith
local logic = {
  entities = { [record.id] = entity, [ambientRecord.id] = ambientEntity },
  spawns = { [record.id] = record, [ambientRecord.id] = ambientRecord },
  featureActive = function() return true end,
  _startBattle = function(_, value) startedWith = value return true end,
}
handles.overworld_wild_spawns = {
  version = "1.11.1",
  exports = {
    version = "1.11.1",
    logic = logic,
    isBattleableWild = function(value)
      return value.overworldWildSpawn == true and not value.wildsAmbientPokemon
    end,
  },
}
local wilds = installer("wilds")(mod, shared)
check("wilds installs shared API", shared.wilds == wilds)
local targets = wilds:targets(game, overworld)
check("wilds discovery is read-only", logic.entities[record.id] == entity
  and logic.spawns[record.id] == record and record.state == "available")
check("wilds discovers only battleable target", #targets == 1
  and targets[1].species == "PIDGEY" and targets[1].level == 3)
check("wilds preserves exact interpolated position",
  near(targets[1].pixelX, 66.5) and near(targets[1].pixelY, 81.25)
    and near(targets[1].position.x, 74.5)
    and near(targets[1].position.z, 89.25))
check("wilds guarded startBattle", wilds:startBattle(targets[1], game, overworld)
  and startedWith == record)

handles.overworld_wild_spawns.version = "1.11.2"
local refused, refusal = wilds:startBattle(targets[1], game, overworld)
check("wilds refuses unverified version", refused == false
  and type(refusal) == "string")
handles.overworld_wild_spawns = nil
local none, absentReason = wilds:targets(game, overworld)
check("wilds has clean absent fallback", #none == 0
  and type(absentReason) == "string")

io.write(("support_test: %d passed, %d failed\n"):format(passed, failed))
if failed > 0 then os.exit(1) end
