-- ROM-free contract tests for modules/battle.lua.
local checks, failures = 0, 0

local function check(value, message)
  checks = checks + 1
  if not value then
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
  end
end

local function equal(actual, expected, message)
  check(actual == expected, message .. " (expected " .. tostring(expected)
    .. ", got " .. tostring(actual) .. ")")
end

local listeners, hookChains = {}, {}
local function on(_, name, callback)
  listeners[name] = listeners[name] or {}
  local list = listeners[name]
  list[#list + 1] = callback
  return function()
    for i, candidate in ipairs(list) do
      if candidate == callback then table.remove(list, i) break end
    end
  end
end

local function emit(name, payload)
  local copy = {}
  for i, callback in ipairs(listeners[name] or {}) do copy[i] = callback end
  for _, callback in ipairs(copy) do callback(payload) end
end

local function wrap(_, name, callback)
  hookChains[name] = hookChains[name] or {}
  local list = hookChains[name]
  list[#list + 1] = callback
  return function()
    for i, candidate in ipairs(list) do
      if candidate == callback then table.remove(list, i) break end
    end
  end
end

local nativeEvents = {}
package.loaded["src.mods.Runtime"] = nil
package.preload["src.mods.Runtime"] = function()
  return {
    emit = function(name, payload)
      nativeEvents[#nativeEvents + 1] = { name = name, payload = payload }
    end,
  }
end

local BattleState = {}
BattleState.__index = BattleState

function BattleState:throwBall(ball, marker)
  self.vanillaThrows = self.vanillaThrows + 1
  return "vanilla_throw", ball, marker
end

function BattleState:safariAction(choice, marker)
  self.vanillaSafari = self.vanillaSafari + 1
  if choice == "ball" and self.safari then
    self.safari.balls = self.safari.balls - 1
  end
  return "vanilla_safari", choice, marker
end

function BattleState:battleKind()
  if self.safari then return "safari" end
  if self.demo then return "oldman" end
  if self.ghost then return "ghost" end
  return self.kind
end

function BattleState:catchAttempt(ball, rateOverride)
  self.catchCalls = self.catchCalls + 1
  self.catchBall = ball
  self.catchRate = rateOverride
  if self.catchError then error(self.catchError, 0) end
  return self.captureResult, self.captureShakes
end

function BattleState:storeCaughtMon()
  self.storeCalls = self.storeCalls + 1
  self.result = "caught"
end

function BattleState:say(text)
  self.messages[#self.messages + 1] = text
end

function BattleState:act(callback)
  callback()
end

function BattleState:ballMissMessage(shakes)
  self.lastMissShakes = shakes
  return "miss:" .. tostring(shakes)
end

function BattleState:enemyAction()
  self.enemyActionCalls = self.enemyActionCalls + 1
  return { id = "TACKLE" }
end

function BattleState:executeAction(enemy, player, action)
  self.executeCalls = self.executeCalls + 1
  self.executedAction = action and action.id
end

function BattleState:queueResidual(player, enemy)
  self.residualCalls = self.residualCalls + 1
end

function BattleState:endOfTurn()
  self.endTurnCalls = self.endTurnCalls + 1
end

function BattleState:safariEnemyTurn()
  self.safariEnemyCalls = self.safariEnemyCalls + 1
end

function BattleState:ballDef(ball)
  return { autoCatch = ball == "MASTER_BALL" }
end

package.loaded["src.battle.BattleState"] = BattleState
package.preload["src.battle.BattleState"] = function() return BattleState end

local originalThrow = BattleState.throwBall
local originalSafari = BattleState.safariAction

local options = {
  lets_go_mode = "catch_only",
  battle_catch_throw = true,
  throw_input = "both",
  throw_sensitivity = "normal",
  battle_throw_speed = "fast",
  battle_aim_assist = "normal",
  battle_throw_arc = true,
  battle_ball_trail = true,
  catch_ring = "full",
  catch_ring_speed = "normal",
  battle_throw_sound = false,
  battle_impact_effect = true,
  capture_animation = "fast",
  debug_battle_throw = false,
  overworld_capture = false,
  hit_starts_capture = false,
  failed_catch_starts_battle = true,
  ball_select_mode = "last_used",
}

local inventoryCounts = {}
local ledger = { commits = 0, refunds = 0, remembers = 0 }
local inventory = {}
function inventory.count(game, ball) return inventoryCounts[ball] or 0 end
function inventory.refund(game, ball, amount)
  ledger.refunds = ledger.refunds + 1
  inventoryCounts[ball] = (inventoryCounts[ball] or 0) + (amount or 1)
  return true
end
function inventory.commit(game, ball, amount)
  amount = amount or 1
  if (inventoryCounts[ball] or 0) < amount then return false end
  ledger.commits = ledger.commits + 1
  inventoryCounts[ball] = inventoryCounts[ball] - amount
  return true
end
function inventory.choose(game, preference)
  for _, ball in ipairs({ "POKE_BALL", "GREAT_BALL", "ULTRA_BALL",
                           "MASTER_BALL" }) do
    if (inventoryCounts[ball] or 0) > 0 then return ball end
  end
end
function inventory.remember(ball)
  ledger.remembers = ledger.remembers + 1
  ledger.lastBall = ball
end

local shared = {
  state = {},
  settings = {
    get = function(_, key, fallback)
      local value = options[key]
      if value == nil then return fallback end
      return value
    end,
  },
  inventory = inventory,
}

local warnings = {}
local mod = {
  id = "LETS_GO_CATCH_THROW",
  hooks = { wrap = wrap },
  events = { on = on },
  log = {
    warn = function(_, message, ...)
      warnings[#warnings + 1] = message:format(...)
    end,
  },
}

local install = assert(loadfile("modules/battle.lua"))()
local feature = install(mod, shared)
equal(feature.installed, true, "installer exposes active controller")
equal(shared.battle, feature, "controller is published on shared.battle")
check(BattleState.throwBall ~= originalThrow, "wild throw method is patched")
check(BattleState.safariAction ~= originalSafari, "Safari method is patched")

local function newBattle(kind, species, level)
  local game = {
    save = { inventory = inventoryCounts, player = { name = "RED" } },
    data = {},
    input = { pressQueue = {} },
  }
  local battle = setmetatable({
    kind = kind or "wild",
    phase = "menu",
    game = game,
    enemy = {
      name = species or "PIDGEY",
      mon = { species = species or "PIDGEY", level = level or 5 },
      def = { catchRate = 100 },
    },
    player = { mon = {} },
    messages = {},
    vanillaThrows = 0,
    vanillaSafari = 0,
    catchCalls = 0,
    storeCalls = 0,
    enemyActionCalls = 0,
    executeCalls = 0,
    residualCalls = 0,
    endTurnCalls = 0,
    safariEnemyCalls = 0,
    captureResult = true,
    captureShakes = 3,
  }, BattleState)
  game.stack = { top = function() return battle end }
  return battle, game
end

local function drive(game, seconds)
  local steps = math.ceil(seconds / 0.025)
  for _ = 1, steps do feature:update(game, 0.025) end
end

-- OFF and every intrinsically non-catchable battle delegate once with exact
-- arguments/results instead of consuming any part of the input sequence.
do
  options.lets_go_mode = "off"
  local battle = newBattle("wild")
  local a, b, c = battle:throwBall("POKE_BALL", "marker")
  equal(a, "vanilla_throw", "OFF returns vanilla first value")
  equal(b, "POKE_BALL", "OFF preserves vanilla ball argument")
  equal(c, "marker", "OFF preserves trailing arguments")
  equal(battle.vanillaThrows, 1, "OFF delegates exactly once")
  equal(shared.state.battle, nil, "OFF starts no session")

  options.lets_go_mode = "catch_only"
  local trainer = newBattle("trainer")
  trainer:throwBall("POKE_BALL")
  equal(trainer.vanillaThrows, 1, "trainer throw remains vanilla")
  local ghost = newBattle("wild")
  ghost.ghost = true
  ghost:throwBall("POKE_BALL")
  equal(ghost.vanillaThrows, 1, "ghost throw remains vanilla")
  local sealed = newBattle("wild")
  sealed.noCatch = true
  sealed:throwBall("MASTER_BALL")
  equal(sealed.vanillaThrows, 1, "scripted no-catch throw remains vanilla")

  options.battle_catch_throw = false
  local disabled = newBattle("wild")
  disabled:throwBall("POKE_BALL")
  equal(disabled.vanillaThrows, 1,
    "battle throw toggle delegates while mode remains selected")
  options.battle_catch_throw = true
end

-- BagMenu already spent this ball. The A that selected it is protected by an
-- arm delay; B then refunds once and returns to the command menu.
do
  inventoryCounts.POKE_BALL = 0
  local beforeRefunds = ledger.refunds
  local battle, game = newBattle("wild")
  battle:throwBall("POKE_BALL")
  local session = shared.state.battle
  check(session ~= nil, "catch-only Bag throw begins aim session")
  equal(session.inventorySettled, true, "Bag debit is recognized as settled")
  equal(battle.phase, feature.PHASE, "battle is parked while aiming")
  game.input.pressQueue = { "a" }
  feature:update(game, 0.01)
  equal(session.committed, false, "selection A cannot immediately launch")
  game.input.pressQueue = {}
  feature:update(game, 0.21)
  game.input.pressQueue = { "b" }
  feature:update(game, 0.01)
  equal(shared.state.battle, nil, "B closes uncommitted session")
  equal(inventoryCounts.POKE_BALL, 1, "B restores pre-consumed ball")
  equal(ledger.refunds, beforeRefunds + 1, "cancel calls refund exactly once")
  equal(battle.phase, "menu", "cancel returns to battle command menu")
  equal(battle.catchCalls, 0, "cancel performs no capture roll")
end

-- Touch owns one pointer from press through release and commits the release
-- using normalized window coordinates, without requiring graphics/ROM data.
do
  options.throw_input = "touch"
  inventoryCounts.POKE_BALL = 0
  local battle, game = newBattle("wild")
  battle:throwBall("POKE_BALL")
  equal(feature:pointer(game, {
    phase = "pressed", id = 7, nx = 0.50, ny = 0.36,
  }), true, "touch press is claimed while aiming")
  equal(feature:pointer(game, {
    phase = "moved", id = 7, nx = 0.53, ny = 0.37,
  }), true, "owned touch move updates aim")
  equal(feature:pointer(game, {
    phase = "released", id = 7, nx = 0.50, ny = 0.36,
  }), true, "owned touch release is claimed")
  equal(shared.state.battle.committed, true,
    "touch release commits the selected Bag ball")
  equal(shared.state.battle.commitSource, "touch",
    "session records touch launch source")
  drive(game, 2)
  equal(battle.catchCalls, 1, "touch release reaches one native catch roll")
end

-- Android suspend/focus loss cancels the live touch gesture, not the battle
-- session: it cannot throw, refund, or make FULL flee on the player's behalf.
do
  options.throw_input = "touch"
  inventoryCounts.POKE_BALL = 0
  local beforeRefunds = ledger.refunds
  local battle, game = newBattle("wild")
  battle:throwBall("POKE_BALL")
  feature:pointer(game, {
    phase = "pressed", id = 8, nx = 0.60, ny = 0.50,
  })
  equal(feature:pointer(game, {
    phase = "cancelled", id = 8, nx = 0.60, ny = 0.50,
  }), true, "lost touch is claimed")
  check(shared.state.battle ~= nil, "lost touch keeps aim session active")
  equal(shared.state.battle.committed, false, "lost touch does not launch")
  equal(ledger.refunds, beforeRefunds, "lost touch does not alter inventory")
  feature:cancel("test_cleanup")
end

-- All desktop mouse buttons share Gen1Recomp's "mouse" pointer id. A rejected
-- right-button click/release cannot complete an in-progress left-button drag.
do
  options.throw_input = "touch"
  inventoryCounts.POKE_BALL = 0
  local battle, game = newBattle("wild")
  battle:throwBall("POKE_BALL")
  equal(feature:pointer(game, {
    phase = "pressed", source = "mouse", id = "mouse", button = 1,
    nx = 0.50, ny = 0.36,
  }), true, "left mouse button owns aim gesture")
  equal(feature:pointer(game, {
    phase = "pressed", source = "mouse", id = "mouse", button = 2,
    nx = 0.50, ny = 0.36,
  }), false, "right mouse press cannot replace owned gesture")
  equal(feature:pointer(game, {
    phase = "released", source = "mouse", id = "mouse", button = 2,
    nx = 0.50, ny = 0.36,
  }), false, "right mouse release cannot launch left drag")
  equal(shared.state.battle.committed, false,
    "mismatched mouse release leaves aim uncommitted")
  equal(feature:pointer(game, {
    phase = "released", source = "mouse", id = "mouse", button = 1,
    nx = 0.50, ny = 0.36,
  }), true, "initiating mouse button release is claimed")
  equal(shared.state.battle.committed, true,
    "initiating mouse button commits exactly once")
  drive(game, 2)
end

-- The right stick is sampled on the fixed step. A quick upward motion is a
-- manual flick; unlike A, it retains the player's aim rather than auto-centre.
do
  options.throw_input = "stick"
  inventoryCounts.GREAT_BALL = 0
  local battle, game = newBattle("wild")
  battle:throwBall("GREAT_BALL")
  feature:setStick(0, 0)
  feature:update(game, 0.21)
  feature:setStick(0.25, -1)
  feature:update(game, 0.016)
  local session = shared.state.battle
  equal(session.committed, true, "upward right-stick flick commits")
  equal(session.commitSource, "stick", "session records stick launch source")
  check(math.abs(session.aim.x) > 0,
    "stick launch retains non-zero manual lateral aim")
  feature:setStick(nil, nil)
  drive(game, 2)
  equal(battle.catchCalls, 1, "stick flick reaches one native catch roll")
end

-- AUTO is an input mode, not an inventory shortcut: it waits through the
-- aiming presentation and launches the already selected Bag ball once.
do
  options.throw_input = "auto"
  inventoryCounts.ULTRA_BALL = 0
  local battle, game = newBattle("wild")
  battle:throwBall("ULTRA_BALL")
  drive(game, 0.60)
  equal(shared.state.battle.committed, false,
    "AUTO preserves a visible aiming beat")
  drive(game, 0.06)
  equal(shared.state.battle.committed, true, "AUTO eventually commits")
  equal(shared.state.battle.commitSource, "auto",
    "session records automatic launch source")
  drive(game, 2)
  equal(battle.catchCalls, 1, "AUTO reaches one native catch roll")
  options.throw_input = "both"
end

-- A committed hit calls the real battle calculation once. Its interactive
-- EXCELLENT grade changes only the species catch-rate override, and success
-- reaches storeCaughtMon rather than rebuilding party/box logic in the mod.
do
  inventoryCounts.POKE_BALL = 0 -- selected Bag ball is already gone
  local beforeCommits = ledger.commits
  local beforeEvents = #nativeEvents
  local battle, game = newBattle("wild", "CATERPIE", 4)
  battle.captureResult, battle.captureShakes = true, 3
  battle:throwBall("POKE_BALL")
  local session = shared.state.battle
  session.forcedGrade = "excellent"
  equal(feature:commit("touch"), true, "first launch commits")
  equal(feature:commit("touch"), false, "second launch is rejected")
  equal(session.commitCount, 1, "session records one committed launch")
  equal(ledger.commits, beforeCommits,
    "pre-consumed Bag ball is not charged a second time")
  drive(game, 2)
  equal(battle.catchCalls, 1, "capture calculation runs exactly once")
  equal(battle.catchRate, 200, "EXCELLENT doubles catch rate")
  equal(battle.storeCalls, 1, "success delegates storage to storeCaughtMon")
  equal(battle.lastBall, "POKE_BALL", "native last-ball field is preserved")
  equal(#nativeEvents, beforeEvents + 1, "one ball-thrown event is emitted")
  equal(nativeEvents[#nativeEvents].payload.grade, "excellent",
    "event reports interactive grade")
end

-- An automatic-catch ball cannot miss due to bad interactive aim, but still
-- goes through catchAttempt so the native/custom ball definition decides it.
do
  inventoryCounts.MASTER_BALL = 0
  local battle, game = newBattle("wild", "MEWTWO", 70)
  battle.captureResult, battle.captureShakes = true, 3
  battle:throwBall("MASTER_BALL")
  local session = shared.state.battle
  session.aim = { x = 1.5, y = 1.5 }
  feature:commit("touch")
  drive(game, 2)
  equal(battle.catchCalls, 1, "Master Ball still calls native calculation")
  equal(battle.catchBall, "MASTER_BALL", "native roll receives Master Ball")
  equal(battle.storeCalls, 1, "Master Ball success stores caught Pokemon")
  equal(nativeEvents[#nativeEvents].payload.missed, false,
    "Master Ball's interactive path forces contact")
end

-- A queue-faithful stand-in verifies the important success ordering: caught
-- fanfare action, caught text, then native storage. The visible epilogue is
-- retained until storeCaughtMon actually runs, not merely until it is queued.
do
  inventoryCounts.POKE_BALL = 0
  local battle, game = newBattle("wild", "PIKACHU", 7)
  battle.queue = {}
  function battle:act(callback)
    self.queue[#self.queue + 1] = { kind = "act", callback = callback }
  end
  function battle:say(text)
    self.messages[#self.messages + 1] = text
    self.queue[#self.queue + 1] = { kind = "text", text = text }
  end
  battle:throwBall("POKE_BALL")
  feature:commit("a")
  drive(game, 2)
  local session = shared.state.battle
  check(session and session.phase == "epilogue",
    "success retains renderer epilogue until storage action")
  equal(battle.storeCalls, 0, "storage does not execute while merely queued")
  equal(battle.queue[1].kind, "act", "caught fanfare queues first")
  equal(battle.queue[2].kind, "text", "caught text queues second")
  equal(battle.queue[3].kind, "act", "native storage queues last")
  table.remove(battle.queue, 1).callback()
  table.remove(battle.queue, 1)
  equal(battle.storeCalls, 0, "dismissed caught text precedes storage")
  table.remove(battle.queue, 1).callback()
  equal(battle.storeCalls, 1, "storage executes from final queued action")
  equal(shared.state.battle, nil, "storage action ends renderer epilogue")
end

-- The failure queue mirrors the engine's item-turn order: miss text, enemy
-- action, player residual, and end-of-turn. This test does not execute acts
-- eagerly, so it catches accidental phase/order regressions hidden by stubs.
do
  inventoryCounts.GREAT_BALL = 0
  local battle, game = newBattle("wild", "SPEAROW", 8)
  battle.captureResult, battle.captureShakes = false, 2
  battle.queue = {}
  function battle:say(text)
    self.messages[#self.messages + 1] = text
    self.queue[#self.queue + 1] = { kind = "text", text = text }
  end
  function battle:act(callback)
    self.queue[#self.queue + 1] = { kind = "act", callback = callback }
  end
  function battle:queueResidual()
    self.queue[#self.queue + 1] = {
      kind = "residual",
      callback = function() self.residualCalls = self.residualCalls + 1 end,
    }
  end
  battle:throwBall("GREAT_BALL")
  feature:commit("a")
  drive(game, 2)
  equal(shared.state.battle, nil, "ordinary failure releases renderer session")
  equal(battle.queue[1].kind, "text", "miss text queues first")
  equal(battle.queue[2].kind, "act", "enemy action queues second")
  equal(battle.queue[3].kind, "residual", "residual queues third")
  equal(battle.queue[4].kind, "act", "end-of-turn queues fourth")
  for _, row in ipairs(battle.queue) do
    if row.callback then row.callback() end
  end
  equal(battle.executeCalls, 1, "queued enemy action executes once")
  equal(battle.residualCalls, 1, "queued residual executes once")
  equal(battle.endTurnCalls, 1, "queued end-of-turn executes once")
end

-- A normal breakout queues the same foe action, residual, and end-of-turn
-- seams as BattleState:throwBall's native failure branch.
do
  inventoryCounts.GREAT_BALL = 0
  local battle, game = newBattle("wild")
  battle.captureResult, battle.captureShakes = false, 2
  battle:throwBall("GREAT_BALL")
  feature:commit("a")
  drive(game, 2)
  equal(battle.catchCalls, 1, "failed hit rolls once")
  equal(battle.lastMissShakes, 2, "native miss text receives shake count")
  equal(battle.enemyActionCalls, 1, "foe selects one revenge action")
  equal(battle.executeCalls, 1, "foe executes one revenge action")
  equal(battle.residualCalls, 1, "player residual is queued")
  equal(battle.endTurnCalls, 1, "failure completes the turn once")
  equal(battle.storeCalls, 0, "failure never stores the Pokemon")
end

-- A broken catch hook/custom ball is not a valid failed roll. Once paid, the
-- interactive layer hands the throw to the saved native path rather than
-- silently consuming even a guaranteed ball as an ordinary breakout.
do
  inventoryCounts.MASTER_BALL = 0
  local beforeEvents = #nativeEvents
  local battle, game = newBattle("wild", "SNORLAX", 30)
  battle.catchError = "broken catch hook"
  battle:throwBall("MASTER_BALL")
  feature:commit("a")
  drive(game, 1)
  equal(shared.state.battle, nil,
    "catch calculation exception retires interactive session")
  equal(battle.vanillaThrows, 1,
    "catch calculation exception delegates one already-paid native throw")
  equal(#nativeEvents, beforeEvents,
    "exception is not forged into a failed ball-thrown event")
  check(#warnings > 0 and warnings[#warnings]:find("delegating", 1, true),
    "capture exception reports native fallback")
end

-- Safari fallback restores its committed counter before native safariAction
-- takes ownership, so delegation cannot charge the virtual ball twice.
do
  local battle, game = newBattle("wild", "CHANSEY", 24)
  battle.safari = { balls = 2 }
  battle.safariCatchRate = 30
  battle.catchError = "broken Safari catch hook"
  battle:safariAction("ball")
  feature:commit("a")
  equal(battle.safari.balls, 1, "interactive Safari launch initially pays once")
  drive(game, 1)
  equal(battle.vanillaSafari, 1,
    "Safari capture exception delegates to native action")
  equal(battle.safari.balls, 1,
    "Safari native fallback retains exactly one total debit")
end

-- Safari balls are a dedicated counter. Aim/cancel is free; launch decrements
-- once and a breakout uses safariEnemyTurn, never ordinary party combat.
do
  local battle, game = newBattle("wild")
  battle.safari = { balls = 3 }
  battle.safariCatchRate = 80
  battle.captureResult, battle.captureShakes = false, 1
  local beforeRefunds = ledger.refunds
  battle:safariAction("ball")
  equal(battle.safari.balls, 3, "Safari aim does not spend a ball")
  feature:cancel("test")
  equal(battle.safari.balls, 3, "Safari cancel spends no ball")
  equal(ledger.refunds, beforeRefunds, "Safari cancel does not touch Bag")

  battle:safariAction("ball")
  shared.state.battle.forcedGrade = "nice"
  equal(feature:commit("a"), true, "Safari launch commits")
  equal(feature:commit("a"), false, "Safari duplicate commit is rejected")
  equal(battle.safari.balls, 2, "Safari launch decrements exactly once")
  drive(game, 2)
  equal(battle.catchRate, 88,
    "Safari's working catch rate receives the interactive NICE bonus")
  equal(battle.safariEnemyCalls, 1, "Safari breakout runs Safari foe turn")
  equal(battle.executeCalls, 0, "Safari breakout runs no party-battle action")
end

-- FULL waits for the native intro to reach its command menu, uses a real Bag
-- ball on launch, skips fabricated foe combat, and rearms only if another
-- real ball remains.
do
  options.lets_go_mode = "full"
  inventoryCounts.POKE_BALL = 2
  local beforeCommits = ledger.commits
  local battle, game = newBattle("wild", "RATTATA", 3)
  battle.phase = "messages"
  battle.captureResult, battle.captureShakes = false, 1
  emit("battle.started", { battle = battle, kind = "wild" })
  feature:update(game, 0.05)
  equal(shared.state.battle, nil, "FULL does not skip native intro queue")
  battle.phase = "menu"
  feature:update(game, 0.05)
  local session = shared.state.battle
  check(session and session.full, "FULL auto-enters after intro")
  equal(inventoryCounts.POKE_BALL, 2, "FULL aim is free")
  feature:commit("a")
  equal(inventoryCounts.POKE_BALL, 1, "FULL launch spends one real ball")
  equal(ledger.commits, beforeCommits + 1, "FULL uses inventory adapter once")
  drive(game, 2)
  equal(session.phase, "await", "FULL breakout waits through miss message")
  equal(battle.executeCalls, 0, "FULL does not invent a foe combat turn")
  battle.phase = "menu"
  feature:update(game, 0.05)
  equal(shared.state.battle, session, "FULL rearms existing capture session")
  equal(session.phase, "aim", "FULL presents next available ball")
  feature:cancel("leave")
  equal(battle.result, "run", "FULL cancel cleanly leaves encounter")
end

-- FULL can still encounter the ordinary Bag path. Since BagMenu removed the
-- selection first, backing out of that aim refunds before leaving the fight.
do
  inventoryCounts.POKE_BALL = 0
  local beforeRefunds = ledger.refunds
  local battle = newBattle("wild")
  battle:throwBall("POKE_BALL")
  equal(feature:cancel("leave"), true, "manual FULL aim can be cancelled")
  equal(inventoryCounts.POKE_BALL, 1,
    "manual FULL cancellation restores pre-consumed ball")
  equal(ledger.refunds, beforeRefunds + 1,
    "manual FULL cancellation refunds exactly once")
  equal(battle.result, "run", "manual FULL cancellation leaves encounter")
end

-- An error/teardown after a FULL pre-consumed Bag aim must also return that
-- ball; no active session may strand a paid but never launched selection.
do
  inventoryCounts.POKE_BALL = 0
  local beforeRefunds = ledger.refunds
  local battle = newBattle("wild")
  battle:throwBall("POKE_BALL")
  battle.result = "run"
  feature:update(battle.game, 0.02)
  equal(shared.state.battle, nil, "forced FULL teardown clears aim session")
  equal(inventoryCounts.POKE_BALL, 1,
    "forced FULL teardown restores pre-consumed ball")
  equal(ledger.refunds, beforeRefunds + 1,
    "forced FULL teardown refunds exactly once")
end

-- FULL never exposes a normal FIGHT menu merely because the Bag is empty.
-- It holds an explicit empty-hand capture session where A or B can leave.
do
  inventoryCounts.POKE_BALL = 0
  inventoryCounts.GREAT_BALL = 0
  inventoryCounts.ULTRA_BALL = 0
  inventoryCounts.MASTER_BALL = 0
  local battle, game = newBattle("wild", "MAGIKARP", 5)
  battle.phase = "messages"
  emit("battle.started", { battle = battle, kind = "wild" })
  battle.phase = "menu"
  feature:update(game, 0.02)
  local session = shared.state.battle
  check(session and session.empty == true,
    "zero-ball FULL creates an empty-hand session")
  equal(battle.phase, feature.PHASE,
    "zero-ball FULL keeps classic command menu parked")
  equal(feature:commit("a"), false, "empty hand cannot commit a throw")
  equal(session.inventoryCount, 0, "empty hand reports zero inventory")
  game.input.pressQueue = { "b" }
  feature:update(game, 0.02)
  equal(shared.state.battle, nil, "B leaves empty FULL encounter")
  equal(battle.result, "run", "empty FULL encounter exits as run")
end

-- When the last FULL ball breaks out, the next command-menu beat rearms an
-- empty hand instead of exposing combat choices.
do
  inventoryCounts.POKE_BALL = 1
  local battle, game = newBattle("wild", "DITTO", 23)
  battle.phase = "messages"
  battle.captureResult, battle.captureShakes = false, 1
  emit("battle.started", { battle = battle, kind = "wild" })
  battle.phase = "menu"
  feature:update(game, 0.02)
  feature:commit("a")
  drive(game, 2)
  battle.phase = "menu" -- stand in for the native miss TextBox draining
  feature:update(game, 0.02)
  local session = shared.state.battle
  check(session and session.empty == true,
    "last-ball breakout rearms an empty hand")
  equal(battle.phase, feature.PHASE,
    "last-ball breakout never exposes normal combat menu")
  feature:cancel("test")
end

-- A Wilds/overworld hit has already spent its ball. The matching battle waits
-- out its native intro, auto-hits with the supplied grade, and neither commits
-- nor refunds inventory a second time.
do
  options.lets_go_mode = "off"
  options.overworld_capture = true
  options.hit_starts_capture = true
  inventoryCounts.ULTRA_BALL = 0
  local beforeCommits, beforeRefunds = ledger.commits, ledger.refunds
  shared.state.pendingCapture = {
    ballId = "ULTRA_BALL",
    consumed = true,
    grade = "great",
    target = { species = "EEVEE", level = 18 },
  }
  local battle, game = newBattle("wild", "EEVEE", 18)
  battle.phase = "messages"
  battle.captureResult, battle.captureShakes = true, 3
  emit("battle.started", { battle = battle, kind = "wild",
                            species = "EEVEE", level = 18 })
  equal(shared.state.pendingCapture, nil, "matching pending hit is claimed")
  equal(shared.state.battle, nil, "pending hit preserves battle intro")
  battle.phase = "menu"
  feature:update(game, 0.05)
  check(shared.state.battle and shared.state.battle.source == "overworld",
    "pending hit begins an overworld-sourced capture session")
  drive(game, 2)
  equal(battle.catchCalls, 1, "pending hit performs one native catch roll")
  equal(battle.catchRate, 150, "pending GREAT grade multiplies catch rate")
  equal(battle.storeCalls, 1, "pending hit success uses native storage")
  equal(ledger.commits, beforeCommits, "pending hit is not charged twice")
  equal(ledger.refunds, beforeRefunds, "pending hit is never refunded")
end

-- A failed overworld hit follows its explicit transition setting. OFF returns
-- after the miss text without a free enemy action; ON converts to normal combat.
do
  options.overworld_capture = true
  options.hit_starts_capture = true
  options.failed_catch_starts_battle = false
  shared.state.pendingCapture = {
    ballId = "POKE_BALL", consumed = true,
    target = { species = "VENONAT", level = 14 },
  }
  local battle, game = newBattle("wild", "VENONAT", 14)
  battle.phase = "messages"
  battle.captureResult, battle.captureShakes = false, 1
  emit("battle.started", { battle = battle, kind = "wild" })
  battle.phase = "menu"
  feature:update(game, 0.02)
  drive(game, 2)
  equal(battle.result, "run",
    "disabled failed-catch battle returns to overworld")
  equal(battle.afterQueue, "finish",
    "disabled failed-catch battle finishes after miss text")
  equal(battle.executeCalls, 0,
    "disabled failed-catch battle gives foe no combat turn")

  options.failed_catch_starts_battle = true
  shared.state.pendingCapture = {
    ballId = "GREAT_BALL", consumed = true,
    target = { species = "PARAS", level = 10 },
  }
  local combat, combatGame = newBattle("wild", "PARAS", 10)
  combat.phase = "messages"
  combat.captureResult, combat.captureShakes = false, 2
  emit("battle.started", { battle = combat, kind = "wild" })
  combat.phase = "menu"
  feature:update(combatGame, 0.02)
  drive(combatGame, 2)
  equal(combat.result, nil,
    "enabled failed-catch battle remains an active encounter")
  equal(combat.executeCalls, 1,
    "enabled failed-catch battle queues the normal foe turn")
end

-- If capture integration is switched off during the battle transition, the
-- already-paid pending ball falls back to the saved native throw exactly once.
do
  options.overworld_capture = false
  options.hit_starts_capture = false
  shared.state.pendingCapture = {
    ballId = "ULTRA_BALL", consumed = true,
    target = { species = "DROWZEE", level = 16 },
  }
  local battle = newBattle("wild", "DROWZEE", 16)
  battle.phase = "messages"
  emit("battle.started", { battle = battle, kind = "wild" })
  equal(shared.state.pendingCapture, nil,
    "disabled transition still claims paid handoff")
  equal(battle.vanillaThrows, 1,
    "disabled transition delegates one native paid throw")
  equal(shared.state.battle, nil,
    "disabled transition starts no interactive session")
end

-- A handoff is single-use. If the next wild battle does not match its target,
-- discard it so a later same-species encounter cannot inherit the spent ball.
do
  options.overworld_capture = true
  options.hit_starts_capture = true
  inventoryCounts.POKE_BALL = 0
  local beforeRefunds = ledger.refunds
  shared.state.pendingCapture = {
    ballId = "POKE_BALL", consumed = true,
    target = { species = "ZUBAT", level = 9 },
  }
  local battle = newBattle("wild", "ODDISH", 12)
  emit("battle.started", { battle = battle, kind = "wild" })
  equal(shared.state.pendingCapture, nil,
    "mismatched next battle clears pending handoff")
  equal(shared.state.battle, nil,
    "mismatched handoff starts no capture session")
  equal(inventoryCounts.POKE_BALL, 1,
    "mismatched paid handoff returns its ball")
  equal(ledger.refunds, beforeRefunds + 1,
    "mismatched handoff refunds exactly once")
  check(#warnings > 0 and warnings[#warnings]:find("mismatched", 1, true),
    "mismatched handoff produces a diagnostic warning")
end

-- A scripted no-catch wild cannot inherit a paid handoff, and must not leave it
-- armed for a later encounter; the unfulfillable transaction is refunded.
do
  inventoryCounts.GREAT_BALL = 0
  local beforeRefunds = ledger.refunds
  shared.state.pendingCapture = {
    ballId = "GREAT_BALL", consumed = true,
    target = { species = "MAROWAK", level = 30 },
  }
  local battle = newBattle("wild", "MAROWAK", 30)
  battle.noCatch = true
  emit("battle.started", { battle = battle, kind = "wild" })
  equal(shared.state.pendingCapture, nil,
    "non-catchable next wild retires pending handoff")
  equal(inventoryCounts.GREAT_BALL, 1,
    "non-catchable next wild refunds pending ball")
  equal(ledger.refunds, beforeRefunds + 1,
    "non-catchable handoff refunds exactly once")
end

-- Teardown refunds an interrupted Bag aim and restores only wrappers still
-- directly owned by this module.
do
  options.lets_go_mode = "catch_only"
  inventoryCounts.POKE_BALL = 0
  local beforeRefunds = ledger.refunds
  local battle = newBattle("wild")
  battle:throwBall("POKE_BALL")
  feature.cleanup()
  equal(ledger.refunds, beforeRefunds + 1,
    "cleanup refunds interrupted pre-consumed aim")
  equal(BattleState.throwBall, originalThrow, "cleanup restores throwBall")
  equal(BattleState.safariAction, originalSafari,
    "cleanup restores safariAction")
  equal(#(hookChains["input.step"] or {}), 0,
    "cleanup removes fixed-step hook")
  equal(#(hookChains["input.pointer"] or {}), 0,
    "cleanup removes pointer hook")
  equal(#(listeners["battle.started"] or {}), 0,
    "cleanup removes battle-start listener")
  equal(shared.battle, nil, "cleanup retires shared controller")
end


-- Cleanup after launch cannot refund or silently restore the command menu. It
-- delegates the already-paid regular throw to the saved engine method once.
do
  feature = install(mod, shared)
  options.lets_go_mode = "catch_only"
  inventoryCounts.POKE_BALL = 0
  local beforeRefunds = ledger.refunds
  local battle = newBattle("wild")
  battle:throwBall("POKE_BALL")
  feature:commit("a")
  feature.cleanup()
  equal(battle.vanillaThrows, 1,
    "mid-flight cleanup delegates one native paid throw")
  equal(ledger.refunds, beforeRefunds,
    "mid-flight cleanup never refunds a launched ball")
  equal(shared.state.battle, nil,
    "mid-flight cleanup retires interactive session")
  feature.cleanup()
  equal(battle.vanillaThrows, 1,
    "cleanup is idempotent after committed fallback")
end

-- Safari cleanup restores its private counter before native safariAction owns
-- the debit, preserving exactly one total spent Safari Ball.
do
  feature = install(mod, shared)
  local battle = newBattle("wild")
  battle.safari = { balls = 2 }
  battle.safariCatchRate = 80
  battle:safariAction("ball")
  feature:commit("a")
  equal(battle.safari.balls, 1, "Safari launch pays before cleanup")
  feature.cleanup()
  equal(battle.vanillaSafari, 1,
    "mid-flight Safari cleanup delegates to native action")
  equal(battle.safari.balls, 1,
    "mid-flight Safari cleanup keeps one total counter debit")
end

-- The short pending pre-aim is already financially committed even before its
-- automatic launch. Cleanup settles it through native throw rather than losing
-- or refunding the ball.
do
  feature = install(mod, shared)
  options.overworld_capture = true
  options.hit_starts_capture = true
  shared.state.pendingCapture = {
    ballId = "ULTRA_BALL", consumed = true,
    target = { species = "GASTLY", level = 19 },
  }
  local battle, game = newBattle("wild", "GASTLY", 19)
  battle.phase = "messages"
  emit("battle.started", { battle = battle, kind = "wild" })
  battle.phase = "menu"
  feature:update(game, 0.02)
  check(shared.state.battle and shared.state.battle.committed == false,
    "pending pre-aim exists before automatic launch")
  feature.cleanup()
  equal(battle.vanillaThrows, 1,
    "pending pre-aim cleanup delegates one native paid throw")
end

-- A paid pending throw can be torn down while the native intro is still
-- running; cleanup queues the saved native path rather than dropping the ball.
do
  feature = install(mod, shared)
  options.overworld_capture = true
  options.hit_starts_capture = true
  shared.state.pendingCapture = {
    ballId = "GREAT_BALL", consumed = true,
    target = { species = "CLEFAIRY", level = 12 },
  }
  local battle = newBattle("wild", "CLEFAIRY", 12)
  battle.phase = "messages"
  emit("battle.started", { battle = battle, kind = "wild" })
  equal(battle.vanillaThrows, 0,
    "pending cleanup test remains deferred during intro")
  feature.cleanup()
  equal(battle.vanillaThrows, 1,
    "cleanup delegates deferred paid handoff to native throw")
  equal(BattleState.throwBall, originalThrow,
    "final cleanup restores regular throw wrapper")
  equal(BattleState.safariAction, originalSafari,
    "final cleanup restores Safari wrapper")
end

if failures > 0 then
  error(("%d/%d battle checks failed"):format(failures, checks), 0)
end
print(("Let's Go battle: %d checks passed"):format(checks))
