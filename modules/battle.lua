-- Interactive wild-battle capture throws.
--
-- BagMenu removes a selected ball before BattleState:throwBall is called.
-- This module parks that one catchable wild battle in a private phase while
-- the player aims.  Cancelling returns precisely that ball; launching settles
-- the existing debit and the engine's catchAttempt/storeCaughtMon methods own
-- every consequential capture rule afterwards.

local PHASE = "letsGoCatchThrow"
local PATCH_KEY = "_letsGoCatchThrowBattlePatchV1"
local ARM_DELAY = 0.20
local unpack = table.unpack or unpack

local TIER_MULTIPLIER = {
  nice = 1.10,
  great = 1.50,
  excellent = 2.00,
}

local THROW_TIME = { slow = 0.82, normal = 0.58, fast = 0.40 }
local RESULT_TIME = { classic = 0.72, lets_go = 0.92, fast = 0.24 }
local RING_SPEED = { slow = 0.65, normal = 1.00, fast = 1.55 }
local SENSITIVITY = { low = 0.72, normal = 1.00, high = 1.38 }
local ASSIST_REMAINDER = { off = 1.00, low = 0.84, normal = 0.64, high = 0.36 }

local function pack(...)
  return { n = select("#", ...), ... }
end

local function clamp(value, low, high)
  value = tonumber(value) or 0
  if value < low then return low end
  if value > high then return high end
  return value
end

local function lower(value, fallback)
  if type(value) ~= "string" then return fallback end
  return value:lower()
end

local function callFunction(object, name, ...)
  local fn = type(object) == "table" and object[name] or nil
  if type(fn) ~= "function" then return false, nil, false end
  local ok, value = pcall(fn, ...)
  if not ok then return false, value, true end
  return true, value, true
end

return function(mod, shared)
  shared.state = shared.state or {}

  local feature = {
    installed = true,
    PHASE = PHASE,
    tierMultiplier = TIER_MULTIPLIER,
  }
  shared.battle = feature

  local deferred = setmetatable({}, { __mode = "k" })
  local unsubscribers = {}
  local patch

  local function warn(message, ...)
    local log = mod and mod.log
    if log and type(log.warn) == "function" then
      pcall(log.warn, log, message, ...)
    end
  end

  local function setting(key, fallback)
    local settings = shared.settings
    if type(settings) ~= "table" or type(settings.get) ~= "function" then
      return fallback
    end
    local ok, value = pcall(settings.get, settings, key, fallback)
    if not ok or value == nil then return fallback end
    return value
  end

  local function enabledMode()
    local mode = lower(setting("lets_go_mode", "catch_only"), "catch_only")
    if mode ~= "catch_only" and mode ~= "full" then return "off" end
    if setting("battle_catch_throw", true) == false then return "off" end
    return mode
  end

  local function nativeBag()
    local ok, Bag = pcall(require, "src.inventory.Bag")
    if ok and type(Bag) == "table" then return Bag end
    return nil
  end

  -- Inventory methods in shared.inventory are deliberately called as plain
  -- functions: their public contract is count(game, id), not a colon method.
  local function inventoryCount(game, ballId)
    local inventory = shared.inventory
    local called, value = callFunction(inventory, "count", game, ballId)
    if called and type(value) == "number" then
      return math.max(0, math.floor(value))
    end
    local values = game and game.save and game.save.inventory
    return math.max(0, math.floor(tonumber(values and values[ballId]) or 0))
  end

  local function refundInventory(game, ballId)
    local called, value, attempted = callFunction(shared.inventory, "refund",
                                                   game, ballId, 1)
    if called then return value ~= false end
    -- A throwing adapter may have mutated before it failed.  Never fall
    -- through to a second implementation and risk duplicating the refund.
    if attempted then
      warn("inventory refund adapter failed for %s: %s", tostring(ballId),
           tostring(value))
      return false
    end
    local Bag = nativeBag()
    if not (Bag and game and game.save) then return false end
    return Bag.add(game.save, ballId, 1, game.data) ~= false
  end

  local function commitInventory(game, ballId)
    if inventoryCount(game, ballId) < 1 then return false end
    local called, value, attempted = callFunction(shared.inventory, "commit",
                                                   game, ballId, 1)
    if called then return value ~= false end
    if attempted then
      warn("inventory commit adapter failed for %s: %s", tostring(ballId),
           tostring(value))
      return false
    end
    local Bag = nativeBag()
    if not (Bag and game and game.save) then return false end
    Bag.remove(game.save, ballId, 1)
    return true
  end

  local function rememberBall(ballId)
    callFunction(shared.inventory, "remember", ballId)
  end

  local function chooseBall(game)
    local preference = setting("ball_select_mode",
      setting("default_ball", "last_used"))
    local called, ballId = callFunction(shared.inventory, "choose", game,
                                        preference)
    if not called or type(ballId) ~= "string" then return nil end
    if inventoryCount(game, ballId) < 1 then return nil end
    return ballId
  end

  local function playSound(game, cue)
    local ok, Sound = pcall(require, "src.core.Sound")
    if ok and Sound and type(Sound.play) == "function" then
      pcall(Sound.play, game and game.data, cue)
    end
  end

  local function emitBallThrown(session)
    local ok, Runtime = pcall(require, "src.mods.Runtime")
    if not (ok and Runtime and type(Runtime.emit) == "function") then return end
    pcall(Runtime.emit, "battle.ball_thrown", {
      battle = session.battle,
      ball = session.ballId,
      caught = session.caught == true,
      shakes = session.shakes or 0,
      missed = session.missed == true,
      grade = session.grade,
      multiplier = session.multiplier or 1,
      interactive = true,
    })
  end

  local function battleKind(battle)
    if type(battle) ~= "table" then return nil end
    if type(battle.battleKind) == "function" then
      local ok, kind = pcall(battle.battleKind, battle)
      if ok then return kind end
    end
    if battle.safari then return "safari" end
    if battle.demo then return "oldman" end
    if battle.ghost then return "ghost" end
    return battle.kind
  end

  local function hasCaptureSurface(battle)
    return type(battle) == "table"
      and type(battle.catchAttempt) == "function"
      and type(battle.storeCaughtMon) == "function"
      and type(battle.say) == "function"
      and type(battle.act) == "function"
      and type(battle.ballMissMessage) == "function"
      and type(battle.enemy) == "table"
      and type(battle.enemy.mon) == "table"
      and type(battle.enemy.def) == "table"
      and battle.result == nil
  end

  local function catchableWild(battle)
    return battleKind(battle) == "wild"
      and not battle.demo
      and not battle.ghost
      and not battle.noCatch
      and not battle.safari
      and hasCaptureSurface(battle)
  end

  local function catchableSafari(battle)
    return battleKind(battle) == "safari"
      and type(battle.safari) == "table"
      and (tonumber(battle.safari.balls) or 0) > 0
      and not battle.demo
      and not battle.ghost
      and not battle.noCatch
      and hasCaptureSurface(battle)
      and type(battle.safariEnemyTurn) == "function"
  end

  local function isTop(game, battle)
    local stack = game and game.stack
    if not (stack and type(stack.top) == "function") then return true end
    local ok, top = pcall(stack.top, stack)
    return not ok or top == battle
  end

  local function ballAutomaticallyHits(battle, ballId)
    if ballId == "MASTER_BALL" then return true end
    if type(battle.ballDef) ~= "function" then return false end
    local ok, definition = pcall(battle.ballDef, battle, ballId)
    return ok and type(definition) == "table" and definition.autoCatch == true
  end

  local function normalizedGrade(value)
    if type(value) ~= "string" then return nil end
    value = value:lower():gsub("[%s%-]+", "_")
    if TIER_MULTIPLIER[value] then return value end
    return nil
  end

  local function updateRing(session)
    local mode = lower(setting("catch_ring", "full"), "full")
    session.catchRing = mode
    if mode == "off" then
      session.ringRadius = nil
      session.ring = nil
      return
    end
    local speedName = lower(setting("catch_ring_speed", "normal"), "normal")
    local hz = RING_SPEED[speedName] or RING_SPEED.normal
    local wave = 0.5 + 0.5 * math.cos(session.age * hz * math.pi * 2)
    local radius = 0.27 + wave * 0.73
    if mode == "simple" then radius = 0.62 end
    session.ringRadius = radius
    session.ring = {
      x = 0.5,
      y = 0.36,
      radius = radius,
      mode = mode,
    }
  end

  -- Screen-normalized arc data is renderer-independent and remains useful in
  -- a headless test.  A renderer may project these points into its 2D HUD or
  -- use only their t/z values while drawing a depth-tested 3D prop.
  local function rebuildArc(session)
    local ax, ay = session.aim.x, session.aim.y
    local origin = { x = 0.50, y = 0.88, z = 0.00 }
    local target = {
      x = 0.50 + ax * 0.22,
      y = 0.36 + ay * 0.20,
      z = 1.00,
    }
    local points = {}
    local arcOn = setting("battle_throw_arc", true) ~= false
    for i = 0, 20 do
      local t = i / 20
      local lift = arcOn and math.sin(t * math.pi) * 0.24 or 0
      points[#points + 1] = {
        t = t,
        x = origin.x + (target.x - origin.x) * t,
        y = origin.y + (target.y - origin.y) * t - lift,
        z = t,
      }
    end
    session.origin = origin
    session.targetPoint = target
    session.trajectoryPoints = points
    session.trajectory = points
    if session.phase == "aim" then
      session.position = { x = origin.x, y = origin.y, z = origin.z }
    end
  end

  local function refundSession(session)
    if not session or session.refunded or session.committed
       or not session.refundable then return false end
    session.refunded = true -- at-most-once even if an adapter reports failure
    session.refundSucceeded = refundInventory(session.game, session.ballId)
    if not session.refundSucceeded then
      warn("could not refund cancelled battle throw for %s",
           tostring(session.ballId))
    end
    return session.refundSucceeded
  end

  local function clearSession(session)
    if shared.state.battle == session then shared.state.battle = nil end
    if session then session.active = false end
  end

  -- Once launch has paid for a ball, the only safe degradation is the
  -- engine's own already-paid throw path.  In particular, never translate a
  -- thrown catch.rate/custom-ball exception into a legitimate breakout: that
  -- would silently decide a Master Ball failed.  Safari's native entry owns
  -- its counter debit, so restore that one count before handing it back.
  local function delegateCommittedToNative(session, reason)
    if not session or session.nativeFallback then return false end
    session.nativeFallback = true
    session.fallbackReason = tostring(reason or "interactive throw failed")
    local battle = session.battle
    battle.phase = "messages"
    battle.afterQueue = "menu"
    clearSession(session)

    if session.safari and patch and type(patch.safariAction) == "function" then
      if session.inventorySettled and battle.safari then
        battle.safari.balls = math.min(255,
          math.max(0, tonumber(battle.safari.balls) or 0) + 1)
        session.inventorySettled = false
      end
      patch.safariAction(battle, "ball")
      return true
    end
    if patch and type(patch.throwBall) == "function" then
      patch.throwBall(battle, session.ballId)
      return true
    end
    return false
  end

  local function abandon(session, restorePhase)
    if not session then return end
    refundSession(session)
    local battle = session.battle
    if restorePhase and battle and battle.phase == PHASE then
      battle.phase = session.cancelPhase or "menu"
    end
    clearSession(session)
  end

  local function caughtText(battle)
    local name = battle.enemy and battle.enemy.name or "POKEMON"
    local ok, Strings = pcall(require, "src.core.Strings")
    -- Strings is a callable table in Gen1Recomp 0.1.75, not a Lua function.
    if ok and Strings ~= nil then
      local okText, text = pcall(function()
        return Strings("All right!\n%s was\ncaught!", name)
      end)
      if okText then return text end
    end
    return ("All right!\n%s was\ncaught!"):format(tostring(name))
  end

  local function queueCaught(session)
    local battle = session.battle
    session.phase = "epilogue"
    session.visible = true
    battle.phase = "messages"
    battle.afterQueue = "menu"
    battle:act(function() playSound(session.game, "Caught_Mon") end)
    battle:say(caughtText(battle))
    battle:act(function()
      battle:storeCaughtMon()
      clearSession(session)
    end)
  end

  local function queueFailure(session)
    local battle = session.battle
    battle.phase = "messages"
    battle.afterQueue = "menu"
    battle:say(battle:ballMissMessage(session.shakes or 0))

    -- An overworld hit already transitioned into this battle and paid for its
    -- ball.  This setting decides whether a breakout becomes normal combat or
    -- simply returns to the overworld after the miss text.
    if session.source == "overworld"
       and setting("failed_catch_starts_battle", true) == false then
      session.failedCaptureEndedBattle = true
      battle.result = "run"
      battle.afterQueue = "finish"
      clearSession(session)
      return
    end

    if session.full then
      -- FULL is an all-bag capture encounter: the foe does not receive a
      -- fabricated combat turn, and the next real available ball is offered
      -- only after the miss text drains.  With no ball, control safely falls
      -- back to the normal menu instead of inventing inventory/economy.
      session.phase = "await"
      session.visible = false
      session.timer = 0
      return
    end

    if session.safari then
      battle:act(function() battle:safariEnemyTurn() end)
    else
      battle:act(function()
        battle:executeAction(battle.enemy, battle.player, battle:enemyAction())
      end)
      if type(battle.queueResidual) == "function" then
        battle:queueResidual(battle.player, battle.enemy)
      end
      battle:act(function() battle:endOfTurn() end)
    end
    clearSession(session)
  end

  local function resolveImpact(session)
    if session.resolved then return end
    session.resolved = true

    local launchAim = session.launchAim or session.aim
    local aimX, aimY = launchAim.x, launchAim.y
    session.resolvedAim = { x = aimX, y = aimY }
    local distance = math.sqrt(aimX * aimX + aimY * aimY)
    session.aimDistance = distance

    local autoHit = session.forcedHit
      or ballAutomaticallyHits(session.battle, session.ballId)
    session.hit = autoHit or distance <= 1.0
    session.missed = not session.hit

    local grade = normalizedGrade(session.forcedGrade)
    if session.hit and not grade and session.ringRadius
       and distance <= session.ringRadius then
      if session.ringRadius <= 0.40 then
        grade = "excellent"
      elseif session.ringRadius <= 0.70 then
        grade = "great"
      else
        grade = "nice"
      end
    end
    session.grade = grade
    session.multiplier = TIER_MULTIPLIER[grade] or 1

    if session.hit then
      local battle = session.battle
      local baseRate = session.safari and battle.safariCatchRate
        or (battle.enemy.def and battle.enemy.def.catchRate)
      local rateOverride
      if type(baseRate) == "number"
         and (session.safari or session.multiplier ~= 1) then
        rateOverride = math.min(255,
          math.max(0, math.floor(baseRate * session.multiplier)))
      end
      session.rateOverride = rateOverride
      local result = pack(pcall(battle.catchAttempt, battle, session.ballId,
                                rateOverride))
      if not result[1] then
        session.captureError = tostring(result[2])
        warn("capture calculation failed for %s; delegating to native throw: %s",
             tostring(session.ballId), session.captureError)
        if delegateCommittedToNative(session, session.captureError) then return end
        error(result[2], 0)
      end
      session.captureCompleted = true
      session.caught = result[2] == true
      session.shakes = tonumber(result[3]) or (session.caught and 3 or 0)
    else
      session.caught = false
      session.shakes = 0
    end

    session.battle.lastBall = session.ballId
    emitBallThrown(session)
    session.phase = session.caught and "caught" or "breakout"
    session.timer = 0
    session.impact = true
    session.impactEffect = setting("battle_impact_effect", true) ~= false
    session.ringRadius = nil
    session.ring = nil
  end

  local function resetForNextFullThrow(session, ballId)
    session.ballId = ballId
    session.ball = ballId
    session.empty = ballId == nil
    session.phase = "aim"
    session.age = 0
    session.timer = 0
    session.progress = 0
    session.committed = false
    session.commitCount = 0
    session.commitSource = nil
    session.inventorySettled = false
    session.refundable = false
    session.refunded = false
    session.resolved = false
    session.caught = nil
    session.shakes = nil
    session.hit = nil
    session.missed = nil
    session.grade = nil
    session.multiplier = 1
    session.rateOverride = nil
    session.impact = nil
    session.visible = true
    session.ballVisible = ballId ~= nil
    session.statusText = ballId and nil or "NO BALLS LEFT - A/B: LEAVE"
    session.aim = { x = 0, y = 0 }
    session.rawAim = nil
    session.launchAim = nil
    session.pointerId = nil
    session.pointerSource = nil
    session.pointerButton = nil
    session.stickPrev = nil
    session.stick = nil
    session.trail = {}
    session.inventoryCount = ballId and inventoryCount(session.game, ballId) or 0
    session.battle.phase = PHASE
    updateRing(session)
    rebuildArc(session)
  end

  function feature:begin(battle, ballId, opts)
    opts = opts or {}
    if not feature.installed or shared.state.battle ~= nil then return false end
    local empty = opts.empty == true or ballId == nil
    if empty and opts.full ~= true then return false end
    if not empty and (type(ballId) ~= "string" or ballId == "") then
      return false
    end
    if opts.safari then
      if not catchableSafari(battle) then return false end
    elseif not catchableWild(battle) then
      return false
    end

    local game = battle.game
    if type(game) ~= "table" then return false end
    if not empty and not opts.consumed and not opts.safari
       and inventoryCount(game, ballId) < 1 then return false end

    local inputMode = lower(setting("throw_input", "both"), "both")
    if inputMode ~= "stick" and inputMode ~= "touch"
       and inputMode ~= "both" and inputMode ~= "auto" then
      inputMode = "both"
    end

    local enemy = battle.enemy
    local session = {
      active = true,
      context = "battle",
      source = opts.source or "bag",
      battle = battle,
      game = game,
      ballId = ballId,
      ball = ballId,
      empty = empty,
      phase = "aim",
      previousPhase = battle.phase,
      cancelPhase = opts.cancelPhase or "menu",
      age = 0,
      timer = 0,
      progress = 0,
      committed = false,
      commitCount = 0,
      inventorySettled = opts.consumed == true,
      consumed = opts.consumed == true,
      refundable = opts.refundable == true,
      safari = opts.safari == true,
      full = opts.full == true and not opts.safari,
      declinable = opts.declinable ~= false,
      forcedHit = opts.forcedHit == true,
      forcedGrade = opts.grade,
      autoAt = tonumber(opts.autoAt),
      inputMode = inputMode,
      aim = { x = 0, y = 0 },
      visible = true,
      ballVisible = not empty,
      statusText = empty and "NO BALLS LEFT - A/B: LEAVE" or nil,
      trail = {},
      species = enemy.mon.species,
      level = enemy.mon.level,
      targetName = enemy.name,
      target = {
        species = enemy.mon.species,
        level = enemy.mon.level,
        name = enemy.name,
      },
      inventoryCount = opts.safari and math.max(0,
        math.floor(tonumber(battle.safari.balls) or 0))
        or (ballId and inventoryCount(game, ballId) or 0),
      debug = setting("debug_battle_throw", false) == true,
      showArc = setting("battle_throw_arc", true) ~= false,
      showTrail = setting("battle_ball_trail", true) ~= false,
    }
    updateRing(session)
    rebuildArc(session)
    shared.state.battle = session
    battle.phase = PHASE
    return true
  end

  function feature:beginPending(battle, pending)
    if not catchableWild(battle) or type(pending) ~= "table"
       or type(pending.ballId) ~= "string" then return false end
    local record = { kind = "pending", pending = pending }
    if battle.phase ~= "menu" then
      deferred[battle] = record
      return true
    end
    return self:begin(battle, pending.ballId, {
      consumed = pending.consumed ~= false,
      refundable = false,
      source = "overworld",
      forcedHit = true,
      grade = pending.grade,
      autoAt = 0.12,
      declinable = false,
    })
  end

  function feature:cancel(reason)
    local session = shared.state.battle
    if not session or session.committed or session.phase ~= "aim"
       or not session.declinable then return false end

    if session.full then
      local battle = session.battle
      -- A FULL session normally chose an unspent ball automatically.  It can
      -- also be reached from the ordinary Bag menu, whose selected ball was
      -- already removed; leaving that encounter must still make cancellation
      -- free under the inventory contract.
      refundSession(session)
      battle.phase = "messages"
      battle.afterQueue = "finish"
      battle.result = "run"
      battle:say("Got away safely!")
      session.cancelReason = reason or "cancel"
      clearSession(session)
      playSound(session.game, "Run")
      return true
    end

    refundSession(session)
    session.cancelReason = reason or "cancel"
    if session.battle.phase == PHASE then
      session.battle.phase = session.cancelPhase
    end
    clearSession(session)
    playSound(session.game, "Press_AB")
    return true
  end

  function feature:commit(source)
    local session = shared.state.battle
    if not session or session.phase ~= "aim" or session.committed then
      return false
    end
    if session.empty or type(session.ballId) ~= "string" then
      session.outOfBalls = true
      return false
    end

    if session.safari then
      local balls = tonumber(session.battle.safari.balls) or 0
      if balls < 1 then
        session.outOfBalls = true
        return false
      end
      if not session.inventorySettled then
        session.battle.safari.balls = balls - 1
        session.inventorySettled = true
        session.consumed = true
      end
    elseif not session.inventorySettled then
      if not commitInventory(session.game, session.ballId) then
        session.outOfBalls = true
        session.inventoryCount = 0
        return false
      end
      session.inventorySettled = true
      session.consumed = true
    end

    source = source or "manual"
    session.rawAim = { x = session.aim.x, y = session.aim.y }
    local aimX, aimY = session.aim.x, session.aim.y
    if source == "a" or source == "auto" or source == "pending" then
      aimX, aimY = 0, 0
    else
      local assistName = lower(setting("battle_aim_assist", "normal"),
                               "normal")
      local remainder = ASSIST_REMAINDER[assistName] or ASSIST_REMAINDER.normal
      aimX, aimY = aimX * remainder, aimY * remainder
    end
    session.launchAim = { x = aimX, y = aimY }
    session.aim = { x = aimX, y = aimY }
    rebuildArc(session)

    session.committed = true
    session.commitCount = session.commitCount + 1
    session.commitSource = source
    session.phase = "flight"
    session.progress = 0
    session.timer = 0
    session.refundable = false
    session.battle.lastBall = session.ballId
    rememberBall(session.ballId)
    session.inventoryCount = session.safari
      and math.max(0, math.floor(tonumber(session.battle.safari.balls) or 0))
      or inventoryCount(session.game, session.ballId)
    if setting("battle_throw_sound", true) ~= false then
      playSound(session.game, "Ball_Toss")
    end
    return true
  end

  local function dimensions(payload)
    local width = tonumber(payload and (payload.width or payload.windowWidth))
    local height = tonumber(payload and (payload.height or payload.windowHeight))
    if width and height and width > 0 and height > 0 then return width, height end
    local graphics = love and love.graphics
    if graphics and type(graphics.getDimensions) == "function" then
      local ok, w, h = pcall(graphics.getDimensions)
      if ok and tonumber(w) and tonumber(h) and w > 0 and h > 0 then
        return w, h
      end
    end
    return nil, nil
  end

  local function pointerAim(payload)
    local nx, ny = tonumber(payload.nx), tonumber(payload.ny)
    if not nx or not ny then
      local w, h = dimensions(payload)
      if not w then return nil end
      nx, ny = (tonumber(payload.x) or 0) / w, (tonumber(payload.y) or 0) / h
    end
    local sensitivityName = lower(setting("throw_sensitivity", "normal"),
                                  "normal")
    local sensitivity = SENSITIVITY[sensitivityName] or SENSITIVITY.normal
    return clamp((nx - 0.50) / 0.33 * sensitivity, -1.5, 1.5),
           clamp((ny - 0.36) / 0.28 * sensitivity, -1.5, 1.5)
  end

  function feature:pointer(game, payload)
    local session = shared.state.battle
    if not session or session.phase ~= "aim" or type(payload) ~= "table"
       or session.empty
       or (session.inputMode ~= "touch" and session.inputMode ~= "both")
       or not isTop(game or session.game, session.battle) then return false end

    local phase = payload.phase
    local id = payload.id == nil and "pointer" or payload.id
    if phase == "pressed" then
      if payload.source == "mouse" and payload.button ~= nil
         and payload.button ~= 1 then return false end
      if session.pointerId ~= nil then return false end
      local x, y = pointerAim(payload)
      if not x then return false end
      session.pointerId = id
      session.pointerSource = payload.source
      session.pointerButton = payload.source == "mouse" and payload.button or nil
      session.aim.x, session.aim.y = x, y
      rebuildArc(session)
      return true
    end
    if session.pointerId ~= id then return false end
    if phase == "released" and session.pointerSource == "mouse"
       and payload.button ~= session.pointerButton then
      -- Every mouse button shares the id "mouse" in Gen1Recomp.  A release
      -- from a different button must not launch the owned left-button drag.
      return false
    end
    if phase == "cancelled" then
      -- Focus loss/Android suspend means the gesture disappeared, not that
      -- the player chose B/RUN.  Drop only pointer ownership: no launch, no
      -- inventory change, and FULL never flees merely because the app paused.
      session.pointerId = nil
      session.pointerSource = nil
      session.pointerButton = nil
      return true
    end
    if phase == "moved" or phase == "released" then
      local x, y = pointerAim(payload)
      if x then
        session.aim.x, session.aim.y = x, y
        rebuildArc(session)
      end
      if phase == "released" then
        session.pointerId = nil
        session.pointerSource = nil
        session.pointerButton = nil
        self:commit("touch")
      end
      return true
    end
    return false
  end

  local function takePress(game, button)
    local queue = game and game.input and game.input.pressQueue
    if type(queue) ~= "table" then return false end
    local found = false
    for i = #queue, 1, -1 do
      if queue[i] == button then
        table.remove(queue, i)
        found = true
      end
    end
    return found
  end

  local function pollRightStick()
    if feature._stickOverride then
      return feature._stickOverride.x, feature._stickOverride.y
    end
    local joystick = love and love.joystick
    if not (joystick and type(joystick.getJoysticks) == "function") then
      return 0, 0
    end
    local ok, devices = pcall(joystick.getJoysticks)
    if not ok or type(devices) ~= "table" then return 0, 0 end
    for _, device in ipairs(devices) do
      if device and type(device.getGamepadAxis) == "function" then
        local okX, x = pcall(device.getGamepadAxis, device, "rightx")
        local okY, y = pcall(device.getGamepadAxis, device, "righty")
        if okX and okY and type(x) == "number" and type(y) == "number" then
          return x, y
        end
      end
    end
    return 0, 0
  end

  function feature:setStick(x, y)
    if x == nil and y == nil then
      feature._stickOverride = nil
    else
      feature._stickOverride = { x = tonumber(x) or 0, y = tonumber(y) or 0 }
    end
  end

  local function pendingMatches(pending, battle)
    local target = type(pending) == "table" and pending.target or nil
    target = type(target) == "table" and target or pending
    local species = target and target.species
    local level = target and target.level
    local mon = battle and battle.enemy and battle.enemy.mon
    if not mon then return false end
    if species ~= nil and tostring(species) ~= tostring(mon.species) then
      return false
    end
    if level ~= nil and tonumber(level) ~= tonumber(mon.level) then return false end
    return true
  end

  -- A pending Wilds handoff represents a ball which was paid for before the
  -- battle existed.  If the interactive layer is disabled or torn down during
  -- the intro, queue the saved native throw directly instead of losing that
  -- transaction or debiting it again.
  local function delegatePendingToNative(battle, pending, reason)
    if type(pending) ~= "table" or pending.consumed == false
       or type(pending.ballId) ~= "string" or not patch
       or type(patch.throwBall) ~= "function" then return false end
    local ok, err = pcall(patch.throwBall, battle, pending.ballId)
    if not ok then
      warn("could not delegate pending overworld throw (%s): %s",
           tostring(reason or "fallback"), tostring(err))
      return false
    end
    return true
  end

  local function refundRejectedPending(battle, pending, reason)
    if type(pending) ~= "table" or pending.consumed == false
       or type(pending.ballId) ~= "string" then return false end
    local ok = refundInventory(battle and battle.game, pending.ballId)
    if not ok then
      warn("could not refund rejected overworld handoff (%s) for %s",
           tostring(reason or "invalid handoff"), tostring(pending.ballId))
    end
    return ok
  end

  local function startDeferred(game)
    if shared.state.battle then return false end
    for battle, record in pairs(deferred) do
      if battle.result ~= nil then
        deferred[battle] = nil
      elseif battle.game == game and battle.phase == "menu"
         and isTop(game, battle) then
        deferred[battle] = nil
        if record.kind == "pending" then
          local pending = record.pending
          return feature:begin(battle, pending.ballId, {
            consumed = pending.consumed ~= false,
            refundable = false,
            source = "overworld",
            forcedHit = true,
            grade = pending.grade,
            autoAt = 0.12,
            declinable = false,
          })
        end
        if record.kind == "full" and enabledMode() == "full" then
          local ballId = chooseBall(game)
          return feature:begin(battle, ballId, {
            consumed = false,
            refundable = false,
            source = "full",
            full = true,
            empty = ballId == nil,
            declinable = true,
          })
        end
        return false
      end
    end
    return false
  end

  function feature:update(game, dt)
    if not feature.installed then return end
    dt = clamp(dt or 0, 0, 0.25)
    if startDeferred(game) then return end

    local session = shared.state.battle
    if not session then return end
    if session.battle.result ~= nil then
      abandon(session, false)
      return
    end
    if not isTop(game or session.game, session.battle) then return end

    if session.phase == "await" then
      if session.battle.phase == "menu" then
        local ballId = chooseBall(session.game)
        resetForNextFullThrow(session, ballId)
      end
      return
    end

    session.age = session.age + dt
    session.timer = session.timer + dt

    if session.phase == "aim" then
      updateRing(session)
      if session.empty then
        session.ringRadius = nil
        session.ring = nil
        local leave = takePress(game or session.game, "b")
        leave = takePress(game or session.game, "a") or leave
        if leave then self:cancel("out_of_balls") end
        return
      end
      if session.inputMode == "stick" or session.inputMode == "both" then
        local sx, sy = pollRightStick()
        local magnitude = math.sqrt(sx * sx + sy * sy)
        local previous = session.stickPrev or { x = 0, y = 0 }
        local velocityY = (sy - previous.y) / math.max(dt, 1 / 120)
        session.stickPrev = { x = sx, y = sy }
        session.stick = {
          x = sx, y = sy, magnitude = magnitude, velocityY = velocityY,
        }
        if magnitude > 0.18 then
          local sensitivityName = lower(setting("throw_sensitivity", "normal"),
                                        "normal")
          local sensitivity = SENSITIVITY[sensitivityName]
                              or SENSITIVITY.normal
          session.aim.x = clamp(session.aim.x + sx * sensitivity * dt * 1.8,
                                -1.5, 1.5)
          session.aim.y = clamp(session.aim.y + sy * sensitivity * dt * 1.8,
                                -1.5, 1.5)
          rebuildArc(session)
        end
        -- A quick upward right-stick flick is the controller equivalent of a
        -- finger release.  A remains the accessible auto-aim alternative;
        -- the stick path keeps the player's actual lateral aim and can miss.
        if session.age >= ARM_DELAY and sy < -0.58 and velocityY < -3.0 then
          self:commit("stick")
          return
        end
      end

      if session.declinable and takePress(game or session.game, "b") then
        self:cancel("b")
        return
      end
      if session.age >= ARM_DELAY and takePress(game or session.game, "a") then
        self:commit("a")
        return
      end
      local autoAt = session.autoAt
      if not autoAt and session.inputMode == "auto" then autoAt = 0.65 end
      if autoAt and session.age >= autoAt then
        self:commit(session.source == "overworld" and "pending" or "auto")
      end
      return
    end

    if session.phase == "flight" then
      -- The timing ring keeps breathing while the ball travels; the grade is
      -- sampled on contact, matching what the player sees at that moment.
      updateRing(session)
      local speedName = lower(setting("battle_throw_speed", "normal"), "normal")
      local duration = THROW_TIME[speedName] or THROW_TIME.normal
      session.progress = math.min(1, session.progress + dt / duration)
      local pointIndex = math.floor(session.progress * 20) + 1
      local point = session.trajectoryPoints[math.min(21, pointIndex)]
      if point then
        session.position = { x = point.x, y = point.y, z = point.z }
        if session.showTrail then
          session.trail[#session.trail + 1] = session.position
          if #session.trail > 18 then table.remove(session.trail, 1) end
        end
      end
      if session.progress >= 1 then resolveImpact(session) end
      return
    end

    if session.phase == "caught" or session.phase == "breakout" then
      local animation = lower(setting("capture_animation", "lets_go"),
                              "lets_go")
      local hold = RESULT_TIME[animation] or RESULT_TIME.lets_go
      if session.timer >= hold then
        if session.caught then queueCaught(session) else queueFailure(session) end
      end
    end
  end

  local okBattle, BattleState = pcall(require, "src.battle.BattleState")
  if not okBattle or type(BattleState) ~= "table"
     or type(BattleState.throwBall) ~= "function" then
    error("Gen1Recomp BattleState:throwBall is unavailable", 0)
  end

  patch = {
    owner = mod.id,
    active = true,
    throwBall = BattleState.throwBall,
    safariAction = BattleState.safariAction,
  }

  patch.throwWrapper = function(battle, ballId, ...)
    if patch.active and enabledMode() ~= "off" and catchableWild(battle) then
      local mode = enabledMode()
      local ok, began = pcall(feature.begin, feature, battle, ballId, {
        consumed = true,
        refundable = true,
        source = "bag",
        full = mode == "full",
        declinable = true,
      })
      if ok and began then return nil end
      if not ok then warn("battle throw interception failed: %s", tostring(began)) end
    end
    return patch.throwBall(battle, ballId, ...)
  end

  patch.safariWrapper = function(battle, choice, ...)
    if patch.active and choice == "ball" and enabledMode() ~= "off"
       and catchableSafari(battle) then
      local ok, began = pcall(feature.begin, feature, battle, "SAFARI_BALL", {
        consumed = false,
        refundable = false,
        source = "safari",
        safari = true,
        declinable = true,
      })
      if ok and began then return nil end
      if not ok then warn("Safari throw interception failed: %s", tostring(began)) end
    end
    return patch.safariAction(battle, choice, ...)
  end

  local priorPatch = rawget(BattleState, PATCH_KEY)
  if type(priorPatch) == "table" and priorPatch.active then
    error("another Let's Go Catch & Throw battle patch is already active", 0)
  end
  rawset(BattleState, PATCH_KEY, patch)
  BattleState.throwBall = patch.throwWrapper
  if type(patch.safariAction) == "function" then
    BattleState.safariAction = patch.safariWrapper
  end

  if mod.hooks and type(mod.hooks.wrap) == "function" then
    unsubscribers[#unsubscribers + 1] = mod.hooks:wrap(
      "input.step", function(nextFn, game, dt)
        local result = pack(nextFn(game, dt))
        local ok, err = pcall(feature.update, feature, game, dt)
        if not ok then warn("battle input/update failed: %s", tostring(err)) end
        return unpack(result, 1, result.n)
      end)
    unsubscribers[#unsubscribers + 1] = mod.hooks:wrap(
      "input.pointer", function(nextFn, game, payload)
        local ok, claimed = pcall(feature.pointer, feature, game, payload)
        if ok and claimed then return true end
        if not ok then warn("battle pointer failed: %s", tostring(claimed)) end
        return nextFn(game, payload)
      end)
  end

  if mod.events and type(mod.events.on) == "function" then
    unsubscribers[#unsubscribers + 1] = mod.events:on(
      "battle.started", function(event)
        local battle = type(event) == "table" and event.battle or nil
        local pending = shared.state.pendingCapture
        if not catchableWild(battle) then
          -- A scripted no-catch wild is still the next wild encounter, but it
          -- cannot honor the handoff. Retire and refund it so it cannot leak to
          -- a later unrelated encounter.
          if type(pending) == "table" and battleKind(battle) == "wild" then
            shared.state.pendingCapture = nil
            refundRejectedPending(battle, pending, "next wild is not catchable")
            warn("discarded overworld handoff for non-catchable wild battle")
          end
          return
        end

        if type(pending) == "table" then
          -- The handoff belongs to the *next* wild battle.  Never leave a
          -- mismatched record armed: a later Pokemon with the same species
          -- could otherwise inherit a ball spent on an unrelated encounter.
          shared.state.pendingCapture = nil
          local matches = pendingMatches(pending, battle)
          if matches and setting("overworld_capture", false) == true
             and setting("hit_starts_capture", false) == true then
            if feature:beginPending(battle, pending) then return end
            delegatePendingToNative(battle, pending, "begin failed")
            return
          elseif matches then
            delegatePendingToNative(battle, pending, "setting disabled")
            return
          else
            refundRejectedPending(battle, pending, "target mismatch")
            warn("discarded mismatched overworld capture handoff")
          end
        end

        if enabledMode() == "full" then
          deferred[battle] = { kind = "full" }
        end
      end)

    unsubscribers[#unsubscribers + 1] = mod.events:on(
      "battle.ended", function(event)
        local battle = type(event) == "table" and event.battle or nil
        if battle then deferred[battle] = nil end
        local session = shared.state.battle
        if session and (battle == nil or session.battle == battle) then
          abandon(session, false)
        end
      end)
  end

  function feature.cleanup()
    if not feature.installed then return end
    feature.installed = false
    local session = shared.state.battle
    if session then
      if not session.committed then
        if session.source == "overworld" and session.inventorySettled then
          if not delegateCommittedToNative(session, "module cleanup before auto throw") then
            warn("could not settle reserved overworld throw during cleanup")
            clearSession(session)
          end
        else
          abandon(session, true)
        end
      elseif session.phase == "flight" then
        -- A launched ball may never be refunded.  Let the saved engine path
        -- settle the already-paid throw if the module disappears mid-flight.
        if not delegateCommittedToNative(session, "module cleanup") then
          warn("could not settle committed battle throw during cleanup")
          clearSession(session)
        end
      elseif session.phase == "caught" then
        queueCaught(session)
        clearSession(session)
      elseif session.phase == "breakout" then
        queueFailure(session)
        clearSession(session)
      else
        -- epilogue/await already have their native queue outcome installed.
        clearSession(session)
      end
    end
    for battle, record in pairs(deferred) do
      if record.kind == "pending" then
        delegatePendingToNative(battle, record.pending, "module cleanup")
      end
      deferred[battle] = nil
    end
    for _, stop in ipairs(unsubscribers) do
      if type(stop) == "function" then pcall(stop) end
    end
    patch.active = false
    -- Ownership-safe restoration: if another mod wrapped after us, leave its
    -- chain in place; our now-inert wrapper delegates to the saved method.
    if BattleState.throwBall == patch.throwWrapper then
      BattleState.throwBall = patch.throwBall
    end
    if BattleState.safariAction == patch.safariWrapper then
      BattleState.safariAction = patch.safariAction
    end
    if rawget(BattleState, PATCH_KEY) == patch then
      rawset(BattleState, PATCH_KEY, nil)
    end
    if shared.battle == feature then shared.battle = nil end
  end

  return feature
end
