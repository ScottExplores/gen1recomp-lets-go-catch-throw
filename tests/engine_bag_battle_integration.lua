-- ROM-free integration probe against a real Gen1Recomp checkout.
--
-- Run with the checkout as the working directory so Data:load sees its
-- generated fixture/content tree:
--   lua <mod>/tests/engine_bag_battle_integration.lua <mod-directory>
--
-- Unlike battle_test.lua, this file does not replace BattleState, Bag, or
-- BagMenu.  It drives the engine's actual BagMenu -> Bag.remove ->
-- BattleState:throwBall path after installing the production mod modules.

local argv = rawget(_G, "arg") or {}
local modRoot = assert(argv[1] or os.getenv("LETSGO_MOD_ROOT"),
  "pass the lets_go_catch_throw directory")
local engineRoot = argv[2] or os.getenv("LETSGO_ENGINE_ROOT") or "."

package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

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

local function moduleInstaller(relative)
  local path = modRoot .. "/" .. relative
  local chunk, err = loadfile(path)
  assert(chunk, err)
  local installer = chunk()
  assert(type(installer) == "function", relative .. " must return installer")
  return installer
end

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
require("src.render.Font").load(Data)

-- The engine's ROM-free fixture dataset intentionally contains only one
-- placeholder ball item. Add stock ball item rows when the generated ROM
-- dataset is absent; the actual Bag/BagMenu/Catching code remains untouched.
Data.items.POKE_BALL = Data.items.POKE_BALL or {
  id = "POKE_BALL", index = 200, name = "POKE BALL", price = 200,
  pocket = "BALL",
}
Data.items.MASTER_BALL = Data.items.MASTER_BALL or {
  id = "MASTER_BALL", index = 201, name = "MASTER BALL", price = 0,
  pocket = "BALL",
}
local PLAYER_SPECIES = Data.pokemon.FIXMON_A and "FIXMON_A" or "BULBASAUR"
local WILD_SPECIES = Data.pokemon.FIXMON_C and "FIXMON_C" or "RATTATA"
local HARD_SPECIES = Data.pokemon.FIXMON_A and "FIXMON_A" or "SNORLAX"

local Bag = require("src.inventory.Bag")
local BagMenu = require("src.ui.BagMenu")
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local originalThrowBall = BattleState.throwBall

local optionRows
local remembered = {}
local warnings = {}
local mod = {
  id = "LETS_GO_CATCH_THROW",
  options = {
    define = function(_, rows) optionRows = rows end,
    get = function() return nil end,
  },
  save = {
    get = function(_, key, fallback)
      local value = remembered[key]
      return value == nil and fallback or value
    end,
    set = function(_, key, value) remembered[key] = value end,
  },
  log = {
    warn = function(_, message, ...)
      warnings[#warnings + 1] = tostring(message):format(...)
    end,
  },
}

local shared = { state = {} }
local Settings = moduleInstaller("modules/settings.lua")(mod, shared)
local Inventory = moduleInstaller("modules/inventory.lua")(mod, shared)
local Battle = moduleInstaller("modules/battle.lua")(mod, shared)

equal(Settings:get("lets_go_mode"), "catch_only",
  "production settings default to Catch Only")
local schemaDefault
for _, row in ipairs(optionRows or {}) do
  if row.key == "lets_go_mode" then schemaDefault = row.default break end
end
equal(schemaDefault, "catch_only", "registered option schema defaults Catch Only")
check(BattleState.throwBall ~= originalThrowBall,
  "production BattleState throwBall is intercepted")

-- Keep this probe headless and quick. These do not change the feature under
-- test: the default mode remains Catch Only and every capture decision still
-- goes through the real BattleState:catchAttempt implementation.
Settings._memory.battle_throw_sound = false
Settings._memory.capture_animation = "fast"
Settings._memory.battle_throw_speed = "fast"
Settings._memory.catch_ring = "off"

local function newStack()
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

local function newInput()
  local input = { pressQueue = {}, pressed = {}, always = false }
  function input:wasPressed(button)
    return self.always or self.pressed[button] == true
  end
  function input:isDown(button)
    return self.always and (button == "a" or button == "b")
  end
  return input
end

local function newCase(ballId, count, species, level)
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, PLAYER_SPECIES, 60) }
  save.inventory = {}
  save.bagOrder = {}
  save.options = save.options or {}
  save.options.textSpeed = 1
  assert(Bag.add(save, ballId, count, Data), "could not seed real Bag")

  local game = {
    data = Data,
    save = save,
    stack = newStack(),
    input = newInput(),
  }
  local battle = BattleState.newWild(game, species or WILD_SPECIES, level or 3)
  battle.phase = "messages"
  battle.afterQueue = "menu"
  game.stack:push(battle)

  local bag = BagMenu.new(game, { battle = battle })
  game.stack:push(bag)
  equal(bag.items[1] and bag.items[1].value, ballId,
    "real BagMenu exposes the seeded ball")
  return game, battle, bag
end

local function chooseFirstBagItem(game, bag)
  game.input.pressed.a = true
  bag:update(0)
  game.input.pressed.a = nil
end

local function pressForThrow(game, button)
  game.input.pressQueue[#game.input.pressQueue + 1] = button
  Battle:update(game, 0.25)
end

local function advanceThrow(game, limit)
  for _ = 1, (limit or 20) do Battle:update(game, 0.25) end
end

local function pumpBattle(game, battle, done, limit)
  game.input.always = true
  local reached = done()
  for _ = 1, (limit or 8000) do
    if reached then break end
    battle:updateQueue()
    reached = done()
  end
  game.input.always = false
  return reached
end

-- Cancellation: BagMenu performs the real pre-debit, the interactive phase
-- owns it while aiming, and B refunds exactly once through the real Bag.add.
do
  local game, battle, bag = newCase("POKE_BALL", 2)
  chooseFirstBagItem(game, bag)
  equal(Inventory.count(game, "POKE_BALL"), 1,
    "real BagMenu debits one ball before interactive aim")
  equal(game.stack:top(), battle, "BagMenu closes back to the real battle")
  equal(battle.phase, Battle.PHASE, "real battle parks in interactive phase")
  check(shared.state.battle ~= nil and shared.state.battle.refundable == true,
    "pre-debited Bag throw is marked refundable")

  pressForThrow(game, "b")
  equal(Inventory.count(game, "POKE_BALL"), 2,
    "cancelling refunds the pre-debited ball through real Bag")
  equal(battle.phase, "menu", "cancelling restores the battle menu phase")
  equal(shared.state.battle, nil, "cancelling clears the interactive session")
  check(Battle:cancel("second cancel") == false,
    "a second cancel cannot duplicate the refund")
  equal(Inventory.count(game, "POKE_BALL"), 2,
    "duplicate cancellation leaves Bag quantity unchanged")
end

-- Success: Master Ball guarantees the actual engine catch path. The mod
-- calls the real catchAttempt once and queues the real storeCaughtMon, which
-- adds the caught mon to the actual party and sets the native battle result.
do
  local game, battle, bag = newCase("MASTER_BALL", 1)
  local catchCalls, storeCalls = 0, 0
  local nativeCatch = battle.catchAttempt
  local nativeStore = battle.storeCaughtMon
  battle.catchAttempt = function(self, ...)
    catchCalls = catchCalls + 1
    return nativeCatch(self, ...)
  end
  battle.storeCaughtMon = function(self, ...)
    storeCalls = storeCalls + 1
    return nativeStore(self, ...)
  end

  chooseFirstBagItem(game, bag)
  equal(Inventory.count(game, "MASTER_BALL"), 0,
    "real BagMenu settles the Master Ball debit")
  pressForThrow(game, "a")
  check(shared.state.battle and shared.state.battle.committed == true,
    "A launches the interactive throw after its arm delay")
  advanceThrow(game)
  equal(catchCalls, 1, "interactive hit calls real catchAttempt exactly once")
  check(shared.state.battle and shared.state.battle.caught == true,
    "real Master Ball calculation reports a catch")
  check(pumpBattle(game, battle, function() return battle.result == "caught" end),
    "native battle queue reaches storeCaughtMon")
  equal(storeCalls, 1, "real storeCaughtMon executes exactly once")
  equal(#game.save.party, 2, "real storeCaughtMon adds the caught Pokemon")
  equal(battle.result, "caught", "native capture result is preserved")
  equal(shared.state.battle, nil, "successful native storage clears session")
  equal(Inventory.count(game, "MASTER_BALL"), 0,
    "successful throw never refunds or double-debits the ball")
end

-- Failure: max RNG against a low-rate Snorlax forces the engine's real
-- catchAttempt to reject the Poke Ball. The mod then installs the native miss
-- text, enemy-action, residual, and end-of-turn continuation.
do
  local game, battle, bag = newCase("POKE_BALL", 2, HARD_SPECIES, 30)
  battle.rng = function(_, maximum) return maximum end
  local catchCalls, storeCalls, endTurnCalls = 0, 0, 0
  local nativeCatch = battle.catchAttempt
  local nativeStore = battle.storeCaughtMon
  local nativeEndTurn = battle.endOfTurn
  battle.catchAttempt = function(self, ...)
    catchCalls = catchCalls + 1
    return nativeCatch(self, ...)
  end
  battle.storeCaughtMon = function(self, ...)
    storeCalls = storeCalls + 1
    return nativeStore(self, ...)
  end
  battle.endOfTurn = function(self, ...)
    endTurnCalls = endTurnCalls + 1
    return nativeEndTurn(self, ...)
  end

  chooseFirstBagItem(game, bag)
  equal(Inventory.count(game, "POKE_BALL"), 1,
    "failed-throw case begins with one real Bag debit")
  pressForThrow(game, "a")
  advanceThrow(game)
  equal(catchCalls, 1, "failed interactive hit calls real catchAttempt once")
  equal(storeCalls, 0, "failed catch never calls storeCaughtMon")
  equal(shared.state.battle, nil,
    "failure queues native continuation and releases interactive session")
  check(pumpBattle(game, battle, function() return endTurnCalls > 0 end),
    "native failed-catch queue reaches the real end-of-turn path")
  equal(endTurnCalls, 1, "failed catch spends exactly one battle turn")
  equal(battle.result, nil, "ordinary failed catch keeps the battle active")
  equal(Inventory.count(game, "POKE_BALL"), 1,
    "failed catch consumes exactly the one selected ball")
end

Battle.cleanup()
equal(BattleState.throwBall, originalThrowBall,
  "cleanup restores the actual engine BattleState method")
equal(#warnings, 0, "integration run produced no mod warnings")

if failures > 0 then
  error(("engine Bag/Battle integration: %d/%d checks failed")
    :format(failures, checks), 0)
end
print(("engine Bag/Battle integration: %d checks passed")
  :format(checks))
