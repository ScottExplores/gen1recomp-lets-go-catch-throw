-- Manual overworld Poké Ball throwing and scoped controller ownership.
--
-- Gen1Recomp 0.1.75 has no public action-binding registry for shoulder
-- buttons.  This adapter therefore claims the configured raw controller
-- buttons only while the ordinary overworld is eligible (or while this mod
-- already owns an aim).  Every other press delegates to the original Game
-- path, including Select display chords and all menu/battle input.

local GAME_PATCH = "_letsGoCatchThrowGamepadV1"
local WORLD_PATCH = "_letsGoCatchThrowWorldInputV1"
local unpack = table.unpack or unpack

-- LÖVE exposes ordinary shoulders as gamepad buttons, but exposes analog
-- triggers as axes named triggerleft/triggerright.  Some controller mappings
-- also synthesize trigger-button events, so the button adapter remains as a
-- compatibility fallback while this axis bridge serves devices such as the
-- AYN Thor.  Separate on/off thresholds prevent trigger noise from creating
-- repeated presses near the actuation point.
local TRIGGER_AXIS = {
  triggerleft = "lefttrigger",
  triggerright = "righttrigger",
}
local TRIGGER_ON = 0.55
local TRIGGER_OFF = 0.30
local NIL_JOYSTICK = {}

local CHARGE_TIME = {
  slow = 0.82, normal = 0.56, fast = 0.34, very_fast = 0.20,
}
local THROW_SPEED = { slow = 64, normal = 96, fast = 144 }
local ARC_FACTOR = { low = 0.14, normal = 0.23, high = 0.34 }
local SNAP = { off = 0, near = 0.16, normal = 0.34, strong = 0.64 }
local ASSIST = { off = 0, low = 0.08, normal = 0.18, high = 0.34 }
local TRAIL_LIMIT = { off = 0, short = 5, normal = 10, long = 18 }
local RUMBLE_TIME = { off = 0, low = 0.035, normal = 0.07, high = 0.12 }

local function pack(...)
  return { n = select("#", ...), ... }
end

local function clamp(value, low, high)
  value = tonumber(value) or low
  if value < low then return low end
  if value > high then return high end
  return value
end

local function normalize(v)
  if type(v) ~= "table" then return nil end
  local x, y, z = tonumber(v.x), tonumber(v.y), tonumber(v.z)
  if not (x and y and z) then return nil end
  local length = math.sqrt(x * x + y * y + z * z)
  if length < 1e-7 then return nil end
  return { x = x / length, y = y / length, z = z / length }
end

local function distance(a, b)
  local x, y, z = b.x - a.x, b.y - a.y, b.z - a.z
  return math.sqrt(x * x + y * y + z * z)
end

local function facingDirection(player)
  local directions = {
    up = { x = 0, y = 0, z = -1 },
    down = { x = 0, y = 0, z = 1 },
    left = { x = -1, y = 0, z = 0 },
    right = { x = 1, y = 0, z = 0 },
  }
  return directions[player and player.facing] or directions.down
end

local function normalizedButton(button)
  local aliases = {
    r = "rightshoulder", l = "leftshoulder",
    r2 = "righttrigger", l2 = "lefttrigger",
    select = "back",
  }
  return aliases[button] or button
end

return function(mod, shared)
  shared.state = shared.state or {}

  local feature = { installed = true }
  shared.overworld = feature
  local unsubscribers = {}
  local gamePatch, worldPatch
  local axisStates = setmetatable({}, { __mode = "k" })

  local function warn(message, ...)
    if mod.log and type(mod.log.warn) == "function" then
      pcall(mod.log.warn, mod.log, message, ...)
    end
  end

  local function setting(key, fallback)
    local settings = shared.settings
    if not (settings and type(settings.get) == "function") then return fallback end
    local ok, value = pcall(settings.get, settings, key)
    if not ok or value == nil then return fallback end
    return value
  end

  local function action(actionName)
    local settings = shared.settings
    local value
    if settings and type(settings.actionBinding) == "function" then
      local ok, result = pcall(settings.actionBinding, settings, actionName)
      if ok then value = result end
    end
    if not value then
      local defaults = {
        aim = "righttrigger", cancel = "lefttrigger", ball_select = "back",
        quick_throw = "off", range_up = "dpright", range_down = "dpleft",
        toggle_aim_assist = "rightstick",
      }
      value = defaults[actionName]
    end
    return normalizedButton(value)
  end

  local function playSound(game, cue)
    local ok, Sound = pcall(require, "src.core.Sound")
    if ok and Sound and type(Sound.play) == "function" then
      pcall(Sound.play, game and game.data, cue)
    end
  end

  local function rumble()
    local duration = RUMBLE_TIME[tostring(setting("rumble", "low"))] or 0
    if duration <= 0 then return end
    if love and love.system and type(love.system.vibrate) == "function" then
      pcall(love.system.vibrate, duration)
    end
  end

  local function isSelectHeld(game, joystick)
    local input = game and game.input
    if input and type(input.isDown) == "function" then
      local ok, down = pcall(input.isDown, input, "select")
      if ok and down then return true end
    end
    if joystick and type(joystick.isGamepadDown) == "function" then
      local ok, down = pcall(joystick.isGamepadDown, joystick, "back")
      return ok and down == true
    end
    return false
  end

  local function axisBucket(joystick, create)
    local key = joystick or NIL_JOYSTICK
    local bucket = axisStates[key]
    if not bucket and create then
      bucket = {}
      axisStates[key] = bucket
    end
    return bucket, key
  end

  local function clearAxisOwnership(joystick)
    if joystick ~= nil then
      axisStates[joystick] = nil
      return
    end
    for key in pairs(axisStates) do axisStates[key] = nil end
  end

  local function topIsWorld(game, overworld)
    local stack = game and game.stack
    if not (stack and type(stack.top) == "function") then return true end
    local ok, top = pcall(stack.top, stack)
    return not ok or top == overworld
  end

  local function skyRideActive()
    if type(mod.find) ~= "function" then return false end
    local ok, handle = pcall(mod.find, "DRAMATIC_SKY_RIDE")
    if not ok then ok, handle = pcall(mod.find, mod, "DRAMATIC_SKY_RIDE") end
    local exports = ok and handle and handle.exports
    if type(exports) ~= "table" then return false end
    for _, name in ipairs({ "isFlying", "isGroundRiding", "isWaterRiding" }) do
      if type(exports[name]) == "function" then
        local good, active = pcall(exports[name])
        if good and active == true then return true end
      end
    end
    return false
  end

  local function eligible(game)
    if setting("manual_throw", false) ~= true then return false, "MANUAL THROW is off" end
    if shared.state.battle then return false, "battle throw active" end
    if not game or type(game.overworld) ~= "table" then return false, "overworld unavailable" end
    local ow = game.overworld
    if not topIsWorld(game, ow) then return false, "another screen is open" end
    if not (ow.map and ow.player) then return false, "map unavailable" end
    if ow.transitioning or ow.engaging or ow.emote or ow.teleportOut
       or ow.fishing or ow.flyAnim or ow.flyArrive then
      return false, "world is busy"
    end
    if ow.player.moving then return false, "finish the current step first" end
    if ow.runner and type(ow.runner.isRunning) == "function"
       and ow.runner:isRunning() then return false, "script is running" end
    if type(ow.scriptMoves) == "table" and #ow.scriptMoves > 0 then
      return false, "scripted movement is running"
    end
    if game.linkSession or (game.linkNet and not game.linkNet.closed) then
      return false, "link play"
    end
    if skyRideActive() then return false, "Sky Ride is active" end
    return true, ow
  end

  local BALL_IDS = {
    poke_ball = "POKE_BALL", great_ball = "GREAT_BALL",
    ultra_ball = "ULTRA_BALL", master_ball = "MASTER_BALL",
    safari_ball = "SAFARI_BALL",
  }

  local function chooseBall(game)
    local inventory = shared.inventory
    if not (inventory and type(inventory.select) == "function") then
      return nil, "inventory adapter unavailable"
    end
    local mode = tostring(setting("ball_select_mode", "last_used"))
    local default = tostring(setting("default_ball", "auto"))
    local opts = { strategy = mode }
    if mode == "best_available" then opts.strategy = "best_available" end
    if mode == "manual" or mode == "last_used" then opts.strategy = "last_used" end
    if mode == "preferred" then opts.preferred = BALL_IDS[default] end
    if default ~= "auto" and default ~= "last_used" and BALL_IDS[default]
       and mode ~= "best_available" then
      opts.preferred = BALL_IDS[default]
    elseif default == "last_used" then
      opts.strategy = "last_used"
    end
    local ok, id, entry = pcall(inventory.select, inventory, game, opts)
    if not ok then return nil, tostring(id) end
    if type(id) ~= "string" then return nil, entry or "no supported balls" end
    return id, entry
  end

  local function availableBalls(game)
    local inventory = shared.inventory
    if not (inventory and type(inventory.available) == "function") then return {} end
    local ok, list = pcall(inventory.available, inventory, game)
    return ok and type(list) == "table" and list or {}
  end

  local function ballCount(game, id)
    local inventory = shared.inventory
    if not (inventory and type(inventory.count) == "function") then return 0 end
    local ok, count = pcall(inventory.count, inventory, game, id)
    return ok and math.max(0, math.floor(tonumber(count) or 0)) or 0
  end

  local function commitBall(session)
    local inventory = shared.inventory
    if not (inventory and type(inventory.commit) == "function") then
      return false, "inventory adapter unavailable"
    end
    local ok, spent, err = pcall(inventory.commit, inventory,
                                 session.game, session.ballId, 1)
    if not ok then return false, tostring(spent) end
    if spent == false then return false, err or "ball unavailable" end
    if setting("remember_last_ball", true) == true
       and type(inventory.remember) == "function" then
      pcall(inventory.remember, inventory, session.ballId)
    end
    return true
  end

  local function cameraFrame(game, ow)
    local camera = shared.camera
    if not (camera and type(camera.frame) == "function") then return nil end
    local ok, frame = pcall(camera.frame, camera, game, ow)
    return ok and type(frame) == "table" and frame or nil
  end

  local function adjustedFrame(game, ow)
    local frame = cameraFrame(game, ow)
    if not frame then return nil, "camera adapter unavailable" end
    local playerFacing = facingDirection(ow.player)
    local aimMode = tostring(setting("camera_aim_mode", "smart"))
    local direction = frame.direction
    if aimMode == "player_facing"
       or (aimMode == "smart" and frame.mode == "DIORAMA") then
      direction = playerFacing
    end
    direction = normalize(direction) or playerFacing
    if setting("camera_yaw_affects_throw", true) ~= true then
      direction.x, direction.z = playerFacing.x, playerFacing.z
    end
    if setting("camera_pitch_affects_throw", true) ~= true then direction.y = 0 end
    direction = normalize(direction) or playerFacing

    local origin = { x = frame.origin.x, y = frame.origin.y, z = frame.origin.z }
    local right = { x = -direction.z, y = 0, z = direction.x }
    if frame.mode == "1ST" then
      local style = tostring(setting("first_person_throw_origin", "right_hand"))
      if style == "right_hand" then
        origin.x, origin.y, origin.z = origin.x + right.x * 3.5,
          origin.y - 2.5, origin.z + right.z * 3.5
      elseif style == "low_right" then
        origin.x, origin.y, origin.z = origin.x + right.x * 4.5,
          origin.y - 5, origin.z + right.z * 4.5
      end
    elseif frame.mode == "3RD" then
      local style = tostring(setting("third_person_throw_origin", "shoulder"))
      if style == "shoulder" then
        origin.x, origin.y, origin.z = origin.x + right.x * 3,
          origin.y + 2, origin.z + right.z * 3
      elseif style == "camera_bias" then
        origin.x, origin.y, origin.z = origin.x + right.x * 2 + direction.x * 4,
          origin.y + 2, origin.z + right.z * 2 + direction.z * 4
      end
    elseif setting("diorama_throw_origin", "player") == "tile_center" then
      origin.x = (tonumber(ow.player.cellX) or 0) * 16 + 8
      origin.z = (tonumber(ow.player.cellY) or 0) * 16 + 8
    end
    return { mode = frame.mode, origin = origin, direction = direction,
             right = right, up = { x = 0, y = 1, z = 0 } }
  end

  local function wildsEnabled()
    local value = tostring(setting("wilds_integration", "auto"))
    return value ~= "off", value
  end

  local function targetsFor(session, origin, range)
    local enabled = wildsEnabled()
    if not enabled or not (shared.wilds and type(shared.wilds.targets) == "function") then
      return {}
    end
    local ok, targets, reason = pcall(shared.wilds.targets, shared.wilds,
      session.game, session.overworld, { origin = origin, range = range,
        targetHeight = 8, radius = 7 })
    if not ok then
      session.wildsError = tostring(targets)
      return {}
    end
    if type(targets) ~= "table" then
      session.wildsError = tostring(reason or "target discovery unavailable")
      return {}
    end
    session.wildsError = reason
    return targets
  end

  local function chooseTarget(origin, direction, targets)
    local best, bestScore
    for _, target in ipairs(targets) do
      local delta = { x = target.position.x - origin.x,
                      y = target.position.y - origin.y,
                      z = target.position.z - origin.z }
      local unit = normalize(delta)
      if unit then
        local dot = unit.x * direction.x + unit.y * direction.y
          + unit.z * direction.z
        if dot > 0.35 then
          local d = target.distanceSquared and math.sqrt(target.distanceSquared)
            or distance(origin, target.position)
          local score = (1 - dot) * 160 + d * 0.02
          if not bestScore or score < bestScore then
            best, bestScore = target, score
          end
        end
      end
    end
    return best
  end

  local function estimateChance(game, ballId, target)
    if ballId == "MASTER_BALL" then return 100 end
    local def = game and game.data and game.data.pokemon
      and target and game.data.pokemon[target.species]
    local ball = game and game.data and game.data.balls
      and game.data.balls[ballId]
    if not (def and ball) then return nil end
    if ball.autoCatch then return 100 end
    local rate = clamp(def.catchRate or 0, 0, 255)
    local randMax = math.max(1, tonumber(ball.randMax) or 255)
    local hpFactor = math.max(1, tonumber(ball.hpFactor) or 12)
    local f = math.min(255, math.floor(1020 / hpFactor))
    local first = clamp((rate + 1) / (randMax + 1), 0, 1)
    return math.floor(clamp(first * ((f + 1) / 256) * 100, 0, 100) + 0.5)
  end

  local function arcHeightFor(range)
    local name = tostring(setting("arc_height", "normal"))
    return clamp(range * (ARC_FACTOR[name] or ARC_FACTOR.normal), 7, 30)
  end

  local function buildArc(session)
    local frame, err = adjustedFrame(session.game, session.overworld)
    if not frame then session.error = err return false end
    session.cameraMode = frame.mode
    session.origin = frame.origin
    local direction = frame.direction
    local targetRange = clamp(setting("target_range", 5), 1, 5) * 16
    local targets = targetsFor(session, frame.origin, targetRange)
    session.targets = targets
    local target = chooseTarget(frame.origin, direction, targets)
    session.target = target

    local snap = SNAP[tostring(setting("target_snap", "normal"))] or 0
    local assist = session.aimAssistDisabled and 0
      or (ASSIST[tostring(setting("overworld_aim_assist", "normal"))] or 0)
    local blend = clamp(snap + assist, 0, 0.85)
    if target and blend > 0 then
      local toTarget = normalize({ x = target.position.x - frame.origin.x,
        y = target.position.y - frame.origin.y,
        z = target.position.z - frame.origin.z })
      if toTarget then
        direction = normalize({ x = direction.x * (1 - blend) + toTarget.x * blend,
          y = direction.y * (1 - blend) + toTarget.y * blend,
          z = direction.z * (1 - blend) + toTarget.z * blend }) or direction
      end
    end
    session.direction = direction
    local range = session.stage * 16
    local finish = {
      x = frame.origin.x + direction.x * range,
      y = 2,
      z = frame.origin.z + direction.z * range,
    }
    local height = arcHeightFor(range)
    -- When assistance is active and a target is near the chosen distance,
    -- tune only the parabola's height so the path—not a teleported endpoint—
    -- honestly crosses the target's centre.
    if target and blend > 0.15 then
      local horizontal = math.sqrt((finish.x - frame.origin.x) ^ 2
        + (finish.z - frame.origin.z) ^ 2)
      local targetHorizontal = math.sqrt((target.position.x - frame.origin.x) ^ 2
        + (target.position.z - frame.origin.z) ^ 2)
      local t = horizontal > 0 and targetHorizontal / horizontal or 0
      if t > 0.12 and t < 0.95 then
        local linearY = frame.origin.y + (finish.y - frame.origin.y) * t
        local wanted = (target.position.y - linearY) / (4 * t * (1 - t))
        if wanted > 0 then height = clamp(height * (1 - blend) + wanted * blend, 5, 36) end
      end
    end
    local speed = THROW_SPEED[tostring(setting("overworld_throw_speed", "normal"))]
      or THROW_SPEED.normal
    local trajectory = shared.trajectory
    local ok, arc = pcall(trajectory.arc, trajectory, frame.origin, finish,
                          { arcHeight = height, speed = speed })
    if not ok or type(arc) ~= "table" then
      session.error = tostring(arc or "trajectory unavailable")
      return false
    end
    arc.stage = session.stage
    session.arc = arc
    session.trajectoryPoints = trajectory:sample(arc, 24)
    session.position = session.phase == "aim" and frame.origin or session.position

    if setting("trajectory_length", "current_range") == "full_arc"
       and session.stage < session.maxRange then
      local fullFinish = {
        x = frame.origin.x + direction.x * session.maxRange * 16,
        y = 2,
        z = frame.origin.z + direction.z * session.maxRange * 16,
      }
      local full = trajectory:arc(frame.origin, fullFinish,
        { arcHeight = arcHeightFor(session.maxRange * 16), speed = speed })
      session.fullTrajectoryPoints = trajectory:sample(full, 28)
    else
      session.fullTrajectoryPoints = nil
    end
    session.catchChance = estimateChance(session.game, session.ballId, target)

    if target and setting("auto_face_target", true) == true then
      local dx = target.position.x - frame.origin.x
      local dz = target.position.z - frame.origin.z
      if math.abs(dx) > math.abs(dz) then
        session.overworld.player.facing = dx < 0 and "left" or "right"
      else
        session.overworld.player.facing = dz < 0 and "up" or "down"
      end
    end
    return true
  end

  local function setStage(session, value)
    session.stage = clamp(math.floor(tonumber(value) or session.stage),
                          session.minRange, session.maxRange)
    session.chargeTimer = 0
    buildArc(session)
  end

  function feature:begin(game, opts)
    opts = opts or {}
    if shared.state.overworld then return false, "already aiming" end
    local ok, owOrReason = eligible(game)
    if not ok then return false, owOrReason end
    local ballId, entryOrReason = chooseBall(game)
    if not ballId then
      feature.lastError = tostring(entryOrReason or "NO POKé BALLS")
      playSound(game, "Denied")
      return false, feature.lastError
    end
    local minRange = clamp(math.floor(setting("min_range", 1)), 1, 3)
    local maxRange = clamp(math.floor(setting("max_range", 5)), minRange, 5)
    local stage = opts.quick and math.floor((minRange + maxRange + 1) / 2)
      or minRange
    local session = {
      active = true, context = "overworld", phase = "aim",
      game = game, overworld = owOrReason, ballId = ballId,
      ball = ballId, ballEntry = entryOrReason,
      inventoryCount = ballCount(game, ballId),
      minRange = minRange, maxRange = maxRange, stage = stage,
      age = 0, chargeTimer = 0, elapsed = 0, progress = 0,
      committed = false, trail = {}, actualDistance = 0,
      inputActions = { aim = action("aim"), cancel = action("cancel") },
      claimedButtons = {}, debug = setting("debug_throw", false) == true,
    }
    shared.state.overworld = session
    if not buildArc(session) then
      shared.state.overworld = nil
      return false, session.error
    end
    feature.lastError = nil
    if opts.quick then return self:commit("quick") end
    return true, session
  end

  function feature:cancel(reason)
    local session = shared.state.overworld
    if not session or session.phase ~= "aim" or session.committed then return false end
    session.cancelReason = reason or "cancel"
    session.active = false
    shared.state.overworld = nil
    playSound(session.game, "Press_AB")
    return true
  end

  function feature:commit(source)
    local session = shared.state.overworld
    if not session or session.phase ~= "aim" or session.committed then return false end
    local ok, err = commitBall(session)
    if not ok then
      session.outOfBalls = true
      session.error = err or "NO BALLS"
      session.inventoryCount = ballCount(session.game, session.ballId)
      playSound(session.game, "Denied")
      return false, session.error
    end
    session.committed = true
    session.commitSource = source or "release"
    session.phase = "flight"
    session.elapsed = 0
    session.progress = 0
    session.previousPosition = session.arc.start
    session.position = session.arc.start
    session.inventoryCount = ballCount(session.game, session.ballId)
    if setting("overworld_throw_sound", true) == true then
      playSound(session.game, "Ball_Toss")
    end
    return true
  end

  local function startWildBattle(session, target, capture)
    if not (target and shared.wilds and type(shared.wilds.startBattle) == "function") then
      return false, "no supported Wilds target"
    end
    if capture then
      shared.state.pendingCapture = {
        ballId = session.ballId, consumed = true, target = target,
        grade = session.grade, source = "overworld",
      }
    end
    local ok, started, err = pcall(shared.wilds.startBattle, shared.wilds,
      target, session.game, session.overworld)
    if not ok or started ~= true then
      if capture then shared.state.pendingCapture = nil end
      return false, ok and err or tostring(started)
    end
    session.transitionStarted = true
    return true
  end

  local function impact(session, hit)
    if session.phase == "impact" then return end
    session.phase = "impact"
    session.impactTimer = 0
    session.hit = hit and true or false
    session.collisionState = hit and "target" or (session.collisionState or "ground")
    if setting("overworld_impact_sound", true) == true then
      playSound(session.game, hit and "Tink" or "Collision")
    end
    rumble()

    if hit and session.target then
      local capture = setting("overworld_capture", true) == true
        and setting("hit_starts_capture", true) == true
      local started, err = startWildBattle(session, session.target, capture)
      if not started then session.integrationError = err end
    elseif setting("miss_starts_battle", false) == true
       and shared.wilds and type(shared.wilds.nearest) == "function" then
      local ok, target = pcall(shared.wilds.nearest, shared.wilds,
        session.game, session.overworld, session.position, 12)
      if ok and target then
        local started, err = startWildBattle(session, target, false)
        if not started then session.integrationError = err end
      end
    end
    if not hit and setting("aggro_on_miss", false) == true then
      session.aggroUnavailable = true -- Wilds 1.11.1 exports no safe aggro API.
    end
  end

  local function refreshFlightTargets(session)
    if not session.targets or #session.targets == 0 then return end
    local current = targetsFor(session, session.origin,
                               clamp(setting("target_range", 5), 1, 5) * 16)
    local byId = {}
    for _, target in ipairs(current) do byId[target.id] = target end
    for i, target in ipairs(session.targets) do
      if byId[target.id] then session.targets[i] = byId[target.id] end
    end
    if session.target and byId[session.target.id] then
      session.target = byId[session.target.id]
    end
  end

  local function flightStep(session, dt)
    session.elapsed = session.elapsed + dt
    local point, done, progress = shared.trajectory:flight(session.arc,
                                                           session.elapsed)
    if not point then impact(session, false) return end
    session.progress = progress
    local previous = session.position or session.previousPosition or point
    session.previousPosition, session.position = previous, point
    session.actualDistance = session.actualDistance + distance(previous, point)

    local limit = TRAIL_LIMIT[tostring(setting("overworld_ball_trail", "normal"))]
      or TRAIL_LIMIT.normal
    if limit > 0 then
      session.trail[#session.trail + 1] = { x = point.x, y = point.y, z = point.z }
      while #session.trail > limit do table.remove(session.trail, 1) end
    end

    refreshFlightTargets(session)
    local hit = shared.trajectory:firstHit({ previous, point },
      session.targets or {}, 2.5, 7)
    if hit then
      session.target = hit.target
      session.position = hit.point
      session.hitbox = hit
      impact(session, true)
      return
    end

    local map = session.overworld and session.overworld.map
    if map and type(map.inBounds) == "function" then
      local cx, cy = math.floor(point.x / 16), math.floor(point.z / 16)
      if not map:inBounds(cx, cy) then
        session.collisionState = "bounds"
        impact(session, false)
        return
      end
      if point.y <= 3 and type(map.isWalkableCell) == "function"
         and not map:isWalkableCell(cx, cy) then
        session.collisionState = "terrain"
        impact(session, false)
        return
      end
    end
    if done then impact(session, false) end
  end

  local function openWheel(session)
    local list = availableBalls(session.game)
    if #list == 0 then session.error = "NO BALLS" return false end
    session.wheel = { items = list, index = 1,
      style = setting("ball_wheel_style", "horizontal") }
    for index, entry in ipairs(list) do
      if entry.id == session.ballId then session.wheel.index = index break end
    end
    return true
  end

  local function closeWheel(session, choose)
    local wheel = session.wheel
    if not wheel then return false end
    if choose and wheel.items[wheel.index] then
      local entry = wheel.items[wheel.index]
      session.ballId, session.ball, session.ballEntry = entry.id, entry.id, entry
      session.inventoryCount = entry.count
      buildArc(session)
    end
    session.wheel = nil
    return true
  end

  local function wheelPress(session, button)
    local wheel = session.wheel
    if not wheel then return false end
    if button == "dpleft" then
      wheel.index = ((wheel.index - 2) % #wheel.items) + 1
    elseif button == "dpright" then
      wheel.index = (wheel.index % #wheel.items) + 1
    elseif button == "a" or button == "back"
       or button == normalizedButton(setting("ball_wheel_button", "select")) then
      closeWheel(session, true)
    elseif button == "b" or button == action("cancel") then
      closeWheel(session, false)
    else
      return false
    end
    return true
  end

  function feature:buttonPressed(game, joystick, button)
    button = normalizedButton(button)
    local session = shared.state.overworld
    if session then
      session.lastInput = "pressed:" .. tostring(button)
      -- Once the ball is committed, no new controller action belongs to the
      -- aim state.  A release already claimed before commit is still handled
      -- by buttonReleased below.
      if session.phase ~= "aim" then return false end
      if session.wheel then
        local handled = wheelPress(session, button)
        if handled then session.claimedButtons[button] = true end
        return handled
      end
      if button == action("cancel") and button ~= "off" then
        session.claimedButtons[button] = true
        self:cancel("controller")
        return true
      end
      local wheelButton = normalizedButton(setting("ball_wheel_button", "select"))
      if setting("ball_wheel", true) == true and wheelButton ~= "off"
         and (button == wheelButton or button == action("ball_select")) then
        local opened = openWheel(session)
        if opened then session.claimedButtons[button] = true end
        return opened
      end
      if button == action("range_up") and button ~= "off" then
        session.claimedButtons[button] = true
        setStage(session, session.stage + 1)
        return true
      elseif button == action("range_down") and button ~= "off" then
        session.claimedButtons[button] = true
        setStage(session, session.stage - 1)
        return true
      elseif button == action("toggle_aim_assist") and button ~= "off" then
        session.claimedButtons[button] = true
        session.aimAssistDisabled = not session.aimAssistDisabled
        buildArc(session)
        return true
      elseif button == action("aim") and button ~= "off" then
        session.claimedButtons[button] = true
        if setting("throw_mode", "hold_release") == "press_press" then
          self:commit("second_press")
        end
        return true
      end
      return false
    end

    if button == action("quick_throw") and button ~= "off" then
      local eligibleNow = eligible(game)
      if not eligibleNow then return false end
      self:begin(game, { quick = true })
      return true
    end
    if button == action("aim") then
      local eligibleNow = eligible(game)
      if not eligibleNow then return false end
      local began = self:begin(game, {
        quick = setting("throw_mode", "hold_release") == "quick",
      })
      local started = shared.state.overworld
      if began == true and started then started.claimedButtons[button] = true end
      -- A deliberate configured aim press stays ours even when the only
      -- failure is an empty bag, preventing an accidental speed change.
      return began == true or feature.lastError ~= nil
    end
    return false
  end

  function feature:buttonReleased(game, _joystick, button)
    button = normalizedButton(button)
    local session = shared.state.overworld
    if not session then return false end
    session.lastInput = "released:" .. tostring(button)
    local claimed = session.claimedButtons[button] == true
    session.claimedButtons[button] = nil
    if button == action("aim") and session.phase == "aim"
       and setting("throw_mode", "hold_release") == "hold_release" then
      self:commit("release")
      return true
    end
    return claimed
  end

  function feature:axisChanged(game, joystick, axis, value)
    local button = TRIGGER_AXIS[axis]
    if not button then return false end
    value = tonumber(value)
    if not value then return false end

    local bucket, key = axisBucket(joystick, true)
    local state = bucket[axis]
    if not state then
      state = { down = false, claimed = false }
      bucket[axis] = state
    end

    if not state.down and value >= TRIGGER_ON then
      state.down = true
      -- A pull begun while Select is held belongs to the host's chord path.
      -- Track it as down so becoming eligible mid-pull cannot steal it.
      state.claimed = not isSelectHeld(game, joystick)
        and self:buttonPressed(game, joystick, button) == true
      return state.claimed
    elseif state.down and value <= TRIGGER_OFF then
      local claimed = state.claimed == true
      state.down, state.claimed = false, false
      if claimed then self:buttonReleased(game, joystick, button) end
      bucket[axis] = nil
      if not bucket.triggerleft and not bucket.triggerright then
        axisStates[key] = nil
      end
      return claimed
    end

    -- An owned pull remains owned until it crosses the release threshold.
    -- An ineligible/unclaimed pull and all other axes keep delegating.
    return state.claimed == true
  end

  function feature:update(game, dt)
    if not feature.installed then return end
    shared.game = game or shared.game
    if shared.settings and type(shared.settings.bindGame) == "function" then
      pcall(shared.settings.bindGame, shared.settings, game)
    end
    local session = shared.state.overworld
    if not session then return end
    if not topIsWorld(game or session.game, session.overworld)
       and not session.transitionStarted then
      if not session.committed then self:cancel("state_changed")
      else session.active = false shared.state.overworld = nil end
      return
    end
    dt = clamp(dt, 0, 0.25)
    session.age = session.age + dt
    if session.phase == "aim" and not session.wheel then
      local mode = tostring(setting("throw_mode", "hold_release"))
      if mode ~= "quick" then
        local interval = CHARGE_TIME[tostring(setting("charge_speed", "normal"))]
          or CHARGE_TIME.normal
        session.chargeTimer = session.chargeTimer + dt
        while session.chargeTimer >= interval do
          session.chargeTimer = session.chargeTimer - interval
          if session.stage < session.maxRange then
            session.stage = session.stage + 1
          elseif setting("range_loop", true) == true then
            session.stage = session.minRange
          else
            session.stage = session.maxRange
            session.chargeTimer = 0
          end
          buildArc(session)
        end
      end
    elseif session.phase == "flight" then
      flightStep(session, dt)
    elseif session.phase == "impact" then
      session.impactTimer = session.impactTimer + dt
      if session.impactTimer >= (session.transitionStarted and 0.10 or 0.42) then
        session.active = false
        if shared.state.overworld == session then shared.state.overworld = nil end
      end
    end
  end

  local okGame, Game = pcall(require, "src.core.Game")
  local okWorld, OverworldState = pcall(require, "src.world.OverworldController")
  if not (okGame and type(Game) == "table" and okWorld
          and type(OverworldState) == "table") then
    error("Gen1Recomp controller/world internals are unavailable", 0)
  end

  gamePatch = {
    owner = mod.id, active = true,
    pressed = Game.gamepadpressed, released = Game.gamepadreleased,
    axis = Game.gamepadaxis,
    focus = Game.focus, visible = Game.visible,
    removed = Game.joystickremoved,
  }
  local existingGame = rawget(Game, GAME_PATCH)
  if type(existingGame) == "table" and existingGame.active then
    error("controller adapter is already active", 0)
  end
  local existingWorld = rawget(OverworldState, WORLD_PATCH)
  if type(existingWorld) == "table" and existingWorld.active then
    error("world input adapter is already active", 0)
  end

  worldPatch = { owner = mod.id, active = true,
                 handleInput = OverworldState.handleInput }

  gamePatch.pressedWrapper = function(game, joystick, button, ...)
    local normalized = normalizedButton(button)
    -- The Select press itself may open/close the ball wheel during an active
    -- aim.  Every other Select-held input delegates so host display chords
    -- remain intact.
    local selectHeld = isSelectHeld(game, joystick)
    local selectWheel = normalized == "back"
      and shared.state.overworld and shared.state.overworld.phase == "aim"
    if gamePatch.active and (not selectHeld or selectWheel) then
      local ok, claimed = pcall(feature.buttonPressed, feature, game, joystick, button)
      if ok and claimed then return end
      if not ok then warn("controller press failed: %s", tostring(claimed)) end
    end
    return gamePatch.pressed(game, joystick, button, ...)
  end
  gamePatch.releasedWrapper = function(game, joystick, button, ...)
    if gamePatch.active then
      local ok, claimed = pcall(feature.buttonReleased, feature, game, joystick, button)
      if ok and claimed then return end
      if not ok then warn("controller release failed: %s", tostring(claimed)) end
    end
    return gamePatch.released(game, joystick, button, ...)
  end
  gamePatch.axisWrapper = function(game, joystick, axis, value, ...)
    if gamePatch.active then
      local ok, claimed = pcall(feature.axisChanged, feature, game, joystick,
                                 axis, value)
      if ok and claimed then return end
      if not ok then warn("controller axis failed: %s", tostring(claimed)) end
    end
    return gamePatch.axis(game, joystick, axis, value, ...)
  end
  local function cancelOnLoss(game, ...)
    if shared.state.overworld and not shared.state.overworld.committed then
      pcall(feature.cancel, feature, "input_lost")
    end
  end
  gamePatch.focusWrapper = function(game, focused, ...)
    if focused == false then
      clearAxisOwnership()
      cancelOnLoss(game)
    end
    return gamePatch.focus(game, focused, ...)
  end
  gamePatch.visibleWrapper = function(game, visible, ...)
    if visible == false then
      clearAxisOwnership()
      cancelOnLoss(game)
    end
    return gamePatch.visible(game, visible, ...)
  end
  gamePatch.removedWrapper = function(game, joystick, ...)
    clearAxisOwnership(joystick)
    cancelOnLoss(game)
    return gamePatch.removed(game, joystick, ...)
  end
  rawset(Game, GAME_PATCH, gamePatch)
  Game.gamepadpressed, Game.gamepadreleased, Game.gamepadaxis =
    gamePatch.pressedWrapper, gamePatch.releasedWrapper, gamePatch.axisWrapper
  if type(gamePatch.focus) == "function" then Game.focus = gamePatch.focusWrapper end
  if type(gamePatch.visible) == "function" then Game.visible = gamePatch.visibleWrapper end
  if type(gamePatch.removed) == "function" then
    Game.joystickremoved = gamePatch.removedWrapper
  end

  worldPatch.wrapper = function(ow, ...)
    local session = shared.state.overworld
    if worldPatch.active and session and session.overworld == ow then return end
    return worldPatch.handleInput(ow, ...)
  end
  rawset(OverworldState, WORLD_PATCH, worldPatch)
  OverworldState.handleInput = worldPatch.wrapper

  if mod.hooks and type(mod.hooks.wrap) == "function" then
    local hookOK, stopOrError = pcall(mod.hooks.wrap, mod.hooks,
      "input.step", function(nextFn, game, dt)
        local result = pack(nextFn(game, dt))
        local ok, err = pcall(feature.update, feature, game, dt)
        if not ok then warn("overworld throw update failed: %s", tostring(err)) end
        return unpack(result, 1, result.n)
      end, 950)
    if not hookOK then
      -- Installation is atomic even if the hook registry itself rejects the
      -- contribution after the guarded class patches were prepared.
      gamePatch.active, worldPatch.active = false, false
      if Game.gamepadpressed == gamePatch.pressedWrapper then
        Game.gamepadpressed = gamePatch.pressed
      end
      if Game.gamepadreleased == gamePatch.releasedWrapper then
        Game.gamepadreleased = gamePatch.released
      end
      if Game.gamepadaxis == gamePatch.axisWrapper then
        Game.gamepadaxis = gamePatch.axis
      end
      if Game.focus == gamePatch.focusWrapper then Game.focus = gamePatch.focus end
      if Game.visible == gamePatch.visibleWrapper then Game.visible = gamePatch.visible end
      if Game.joystickremoved == gamePatch.removedWrapper then
        Game.joystickremoved = gamePatch.removed
      end
      if rawget(Game, GAME_PATCH) == gamePatch then rawset(Game, GAME_PATCH, nil) end
      if OverworldState.handleInput == worldPatch.wrapper then
        OverworldState.handleInput = worldPatch.handleInput
      end
      if rawget(OverworldState, WORLD_PATCH) == worldPatch then
        rawset(OverworldState, WORLD_PATCH, nil)
      end
      error("input.step hook installation failed: " .. tostring(stopOrError), 0)
    end
    unsubscribers[#unsubscribers + 1] = stopOrError
  end

  function feature.cleanup()
    if not feature.installed then return end
    feature.installed = false
    local session = shared.state.overworld
    if session and not session.committed then
      pcall(feature.cancel, feature, "unload")
    elseif session then
      -- A committed ball stays spent, but its animation/input ownership must
      -- not survive a hot unload with no update hook left to retire it.
      session.active = false
      shared.state.overworld = nil
    end
    for _, stop in ipairs(unsubscribers) do
      if type(stop) == "function" then pcall(stop) end
    end
    gamePatch.active = false
    if Game.gamepadpressed == gamePatch.pressedWrapper then
      Game.gamepadpressed = gamePatch.pressed
    end
    if Game.gamepadreleased == gamePatch.releasedWrapper then
      Game.gamepadreleased = gamePatch.released
    end
    if Game.gamepadaxis == gamePatch.axisWrapper then
      Game.gamepadaxis = gamePatch.axis
    end
    if Game.focus == gamePatch.focusWrapper then Game.focus = gamePatch.focus end
    if Game.visible == gamePatch.visibleWrapper then Game.visible = gamePatch.visible end
    if Game.joystickremoved == gamePatch.removedWrapper then
      Game.joystickremoved = gamePatch.removed
    end
    if rawget(Game, GAME_PATCH) == gamePatch then rawset(Game, GAME_PATCH, nil) end
    clearAxisOwnership()
    worldPatch.active = false
    if OverworldState.handleInput == worldPatch.wrapper then
      OverworldState.handleInput = worldPatch.handleInput
    end
    if rawget(OverworldState, WORLD_PATCH) == worldPatch then
      rawset(OverworldState, WORLD_PATCH, nil)
    end
    if shared.overworld == feature then shared.overworld = nil end
  end

  return feature
end
