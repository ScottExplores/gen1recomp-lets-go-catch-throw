-- ROM-free controller/overworld integration tests.
-- Run from the mod root with Fengari/Lua:
--   fengari tests/overworld_test.lua

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

local function installer(name)
  for _, path in ipairs({ "modules/" .. name .. ".lua",
                          "../modules/" .. name .. ".lua" }) do
    local chunk = loadfile(path)
    if chunk then return chunk() end
  end
  error("could not load modules/" .. name .. ".lua")
end

local values = {
  manual_throw = true,
  throw_mode = "hold_release",
  min_range = 1,
  max_range = 3,
  charge_speed = "very_fast",
  range_loop = true,
  trajectory_length = "current_range",
  target_range = 5,
  target_snap = "off",
  overworld_aim_assist = "off",
  first_person_throw_origin = "center",
  overworld_throw_speed = "normal",
  overworld_ball_trail = "normal",
  arc_height = "normal",
  ball_wheel = false,
  overworld_capture = true,
  hit_starts_capture = true,
  miss_starts_battle = false,
  remember_last_ball = true,
  default_ball = "auto",
  ball_select_mode = "last_used",
}
local actions = {
  aim = "righttrigger",
  cancel = "lefttrigger",
  ball_select = "back",
  quick_throw = "off",
  range_up = "dpright",
  range_down = "dpleft",
  toggle_aim_assist = "rightstick",
}

local settings = {}
function settings:get(key) return values[key] end
function settings:actionBinding(name) return actions[name] end
function settings:bindGame(game) self.game = game end

local originalPresses, originalReleases, originalAxes = 0, 0, 0
local originalWorldInputs = 0
local Game = {}
function Game.gamepadpressed(_, _, button)
  originalPresses = originalPresses + 1
  return "original-press:" .. tostring(button)
end
function Game.gamepadreleased(_, _, button)
  originalReleases = originalReleases + 1
  return "original-release:" .. tostring(button)
end
function Game.gamepadaxis(_, _, axis, value)
  originalAxes = originalAxes + 1
  return "original-axis:" .. tostring(axis) .. ":" .. tostring(value)
end
function Game.focus(_, focused) return focused end
function Game.visible(_, visible) return visible end
function Game.joystickremoved() return "removed" end

local OverworldController = {}
function OverworldController.handleInput(_, _dt)
  originalWorldInputs = originalWorldInputs + 1
  return "world-input"
end
local originalGamePressed = Game.gamepadpressed
local originalGameReleased = Game.gamepadreleased
local originalGameAxis = Game.gamepadaxis
local originalGameFocus = Game.focus
local originalGameVisible = Game.visible
local originalGameRemoved = Game.joystickremoved
local originalWorldHandle = OverworldController.handleInput

package.preload["src.core.Game"] = function() return Game end
package.preload["src.world.OverworldController"] = function()
  return OverworldController
end
package.preload["src.core.Sound"] = function()
  return { play = function() end }
end
local buzzes = {}
package.preload["src.core.TouchControls"] = function()
  return { buzz = function(level) buzzes[#buzzes + 1] = level return true end }
end

-- Match Gen1Recomp 0.1.88: touching love.system is a hard sandbox error.
love = setmetatable({}, {
  __index = function(_, key)
    if key == "system" then error("love.system is not available to mods") end
  end,
})

local hookWrapper, hookStops = nil, 0
local skyRideFlying = false
local handles = {
  DRAMATIC_SKY_RIDE = {
    exports = {
      isFlying = function() return skyRideFlying end,
      isGroundRiding = function() return false end,
      isWaterRiding = function() return false end,
    },
  },
}
local mod = {
  id = "LETS_GO_CATCH_THROW",
  hooks = {
    wrap = function(_, name, wrapper, priority)
      if name == "input.step" then hookWrapper = wrapper end
      check("input hook uses compatibility priority", priority == 950)
      return function() hookStops = hookStops + 1 end
    end,
  },
  find = function(first, second)
    return handles[second == nil and first or second]
  end,
  log = { warn = function() end },
}

local count, commits, remembers = 5, 0, 0
local inventory = {}
function inventory:select(_game, _opts)
  if count <= 0 then return nil, "no supported balls" end
  return "POKE_BALL", { id = "POKE_BALL", count = count }
end
function inventory:count(_game, id)
  return id == "POKE_BALL" and count or 0
end
function inventory:commit(_game, id, qty)
  if id ~= "POKE_BALL" or count < (qty or 1) then return false, "no balls" end
  count = count - (qty or 1)
  commits = commits + 1
  return true
end
function inventory:remember(id)
  if id == "POKE_BALL" then remembers = remembers + 1 end
  return true
end
function inventory:available()
  if count <= 0 then return {} end
  return { { id = "POKE_BALL", count = count } }
end

local camera = {}
function camera:frame(_game, _ow)
  return {
    mode = "1ST",
    origin = { x = 0, y = 8, z = 0 },
    direction = { x = 0, y = 0, z = 1 },
  }
end

local targetList, battleTarget = {}, nil
local wilds = {}
function wilds:targets(_game, _ow, _opts) return targetList end
function wilds:nearest() return targetList[1] end
function wilds:startBattle(target)
  battleTarget = target
  return true
end

local shared = {
  state = {},
  settings = settings,
  inventory = inventory,
  camera = camera,
  wilds = wilds,
}
installer("trajectory")(mod, shared)

local runnerBusy = false
local mapWalkable, mapBounds = true, true
local ow = {
  map = {
    id = "ROUTE_1",
    inBounds = function() return mapBounds end,
    isWalkableCell = function() return mapWalkable end,
  },
  player = {
    px = 0, py = 0, cellX = 0, cellY = 0,
    facing = "down", moving = false,
  },
  runner = { isRunning = function() return runnerBusy end },
  scriptMoves = {},
}
local topState = ow
local selectHeld = false
local game = {
  overworld = ow,
  save = { inventory = { POKE_BALL = count } },
  data = {
    balls = { POKE_BALL = { randMax = 255 } },
    pokemon = { PIDGEY = { name = "PIDGEY", catchRate = 255 } },
  },
  input = { isDown = function(_, name)
    return name == "select" and selectHeld
  end },
  stack = { top = function() return topState end },
}
local joystick = {
  isGamepadDown = function(_, name)
    return name == "back" and selectHeld
  end,
}

local factory = installer("overworld")
local feature = factory(mod, shared)
check("overworld installs shared API", feature == shared.overworld)
check("controller press patched", Game.gamepadpressed ~= originalGamePressed)
check("controller release patched", Game.gamepadreleased ~= originalGameReleased)
check("controller axis patched", Game.gamepadaxis ~= originalGameAxis)
check("world input patched", OverworldController.handleInput ~= originalWorldHandle)
check("input.step hook installed", type(hookWrapper) == "function")

local function press(button)
  return Game.gamepadpressed(game, joystick, button)
end
local function release(button)
  return Game.gamepadreleased(game, joystick, button)
end
local function axis(name, value)
  return Game.gamepadaxis(game, joystick, name, value)
end
local function finishSession()
  local session = shared.state.overworld
  if session and session.phase == "aim" then feature:cancel("test") end
  for _ = 1, 12 do
    if not shared.state.overworld then break end
    feature:update(game, 0.25)
  end
  shared.state.overworld = nil -- defensive isolation after an asserted failure
end

-- Hold/release and cancel ---------------------------------------------------
local beforePress = originalPresses
local beforeCount = count
press("righttrigger")
check("R2 begins overworld aim", shared.state.overworld
  and shared.state.overworld.phase == "aim")
check("R2 is claimed only in eligible world", originalPresses == beforePress)
check("begin reserves but consumes nothing", count == beforeCount and commits == 0)

feature:update(game, 0.21)
check("held aim advances range", shared.state.overworld.stage == 2)
feature:update(game, 0.21)
feature:update(game, 0.21)
check("held range cycles max to min", shared.state.overworld.stage == 1,
  shared.state.overworld.stage)
press("lefttrigger")
check("L2 cancels aim", shared.state.overworld == nil)
check("cancel consumes no ball", count == beforeCount and commits == 0)

press("righttrigger")
release("righttrigger")
check("R2 release launches flight", shared.state.overworld
  and shared.state.overworld.phase == "flight")
check("release consumes exactly one", count == beforeCount - 1 and commits == 1)
release("righttrigger")
check("duplicate release cannot double-spend", count == beforeCount - 1
  and commits == 1)
finishSession()

-- Empty inventory ----------------------------------------------------------
count = 0
beforePress = originalPresses
press("righttrigger")
check("empty bag does not create aim", shared.state.overworld == nil)
check("configured R2 empty-bag press remains claimed", originalPresses == beforePress)
check("empty bag cannot spend", commits == 1 and count == 0)
count = 4

-- Press/press and quick modes ---------------------------------------------
values.throw_mode = "press_press"
press("righttrigger")
release("righttrigger")
check("press/press first release does not launch", shared.state.overworld
  and shared.state.overworld.phase == "aim" and count == 4)
press("righttrigger")
check("press/press second press launches", shared.state.overworld
  and shared.state.overworld.phase == "flight" and count == 3)
finishSession()

actions.quick_throw = "x"
values.throw_mode = "hold_release"
press("x")
check("quick action begins and launches in one press", shared.state.overworld
  and shared.state.overworld.phase == "flight" and count == 2)
finishSession()

-- QUICK is also a documented Throw Mode, not only a separate action.
values.throw_mode = "quick"
press("righttrigger")
check("QUICK throw mode launches on aim press", shared.state.overworld
  and shared.state.overworld.phase == "flight" and count == 1)
finishSession()
values.throw_mode = "hold_release"
actions.quick_throw = "off"

-- Ownership gates ----------------------------------------------------------
selectHeld = true
beforePress = originalPresses
press("righttrigger")
check("Select display chord is never stolen", originalPresses == beforePress + 1
  and shared.state.overworld == nil)
selectHeld = false

topState = { menu = true }
beforePress = originalPresses
press("righttrigger")
check("menu input is delegated", originalPresses == beforePress + 1
  and shared.state.overworld == nil)
topState = ow

runnerBusy = true
beforePress = originalPresses
press("righttrigger")
check("cutscene input is delegated", originalPresses == beforePress + 1
  and shared.state.overworld == nil)
runnerBusy = false

skyRideFlying = true
beforePress = originalPresses
press("righttrigger")
check("Sky Ride input is delegated", originalPresses == beforePress + 1
  and shared.state.overworld == nil)
skyRideFlying = false

shared.state.battle = { active = true }
beforePress = originalPresses
press("righttrigger")
check("battle input is delegated", originalPresses == beforePress + 1
  and shared.state.overworld == nil)
shared.state.battle = nil

-- Scoped ownership and the Select ball wheel ------------------------------
-- Buttons unrelated to throwing continue to the host even during aim.  In
-- particular, the user's R1/L1 emulator-speed controls stay untouched.
count = 4
press("righttrigger")
beforePress = originalPresses
local beforeRelease = originalReleases
press("y")
release("y")
press("rightshoulder")
release("rightshoulder")
press("leftshoulder")
release("leftshoulder")
check("active aim delegates unrelated buttons",
  originalPresses == beforePress + 3 and originalReleases == beforeRelease + 3)

values.ball_wheel = true
selectHeld = true
beforePress = originalPresses
press("back")
check("Select opens the ball wheel while aiming",
  shared.state.overworld and shared.state.overworld.wheel ~= nil
    and originalPresses == beforePress)
selectHeld = false
release("back")
beforePress = originalPresses
press("rightshoulder")
press("leftshoulder")
check("R1 and L1 still delegate while the wheel is open",
  originalPresses == beforePress + 2)
selectHeld = true
beforePress = originalPresses
press("back")
check("Select closes the ball wheel without leaking to the host",
  shared.state.overworld and shared.state.overworld.wheel == nil
    and originalPresses == beforePress)
selectHeld = false
release("back")
press("lefttrigger")
values.ball_wheel = false

-- AYN Thor analog-trigger bridge ------------------------------------------
-- LÖVE reports R2/L2 as triggerright/triggerleft axes on Android.  The mod
-- converts threshold crossings into the same logical actions as its fallback
-- trigger-button path while delegating every axis it does not own.
beforePress = originalPresses
local beforeAxes = originalAxes
axis("rightx", 0.8)
check("non-trigger axes always delegate", originalAxes == beforeAxes + 1)

topState = { menu = true }
beforeAxes = originalAxes
axis("triggerright", 0.8)
axis("triggerright", 0.1)
check("ineligible trigger axes delegate both edges",
  originalAxes == beforeAxes + 2 and shared.state.overworld == nil)
topState = ow

selectHeld = true
beforeAxes = originalAxes
axis("triggerright", 0.8)
axis("triggerright", 0.1)
check("Select-held trigger pull remains delegated",
  originalAxes == beforeAxes + 2 and shared.state.overworld == nil)
selectHeld = false

local axisCount, axisCommits = count, commits
beforeAxes = originalAxes
axis("triggerright", 0.8)
check("R2 axis begins overworld aim",
  shared.state.overworld and shared.state.overworld.phase == "aim"
    and originalAxes == beforeAxes)
axis("rightx", 0.7)
check("non-trigger axis delegates during owned R2 aim",
  originalAxes == beforeAxes + 1)
axis("triggerright", 0.9)
axis("triggerright", 0.4)
check("R2 hysteresis holds one owned pull",
  shared.state.overworld and shared.state.overworld.phase == "aim"
    and commits == axisCommits and originalAxes == beforeAxes + 1)
axis("triggerright", 0.2)
check("R2 axis release throws exactly once",
  shared.state.overworld and shared.state.overworld.phase == "flight"
    and count == axisCount - 1 and commits == axisCommits + 1
    and originalAxes == beforeAxes + 1)
axis("triggerright", 0.1)
check("resting R2 axis cannot double throw",
  count == axisCount - 1 and commits == axisCommits + 1)
finishSession()

axisCount, axisCommits = count, commits
beforeAxes = originalAxes
axis("triggerright", 0.8)
axis("triggerleft", 0.8)
check("L2 axis cancels an R2 aim without spending",
  shared.state.overworld == nil and count == axisCount and commits == axisCommits)
axis("triggerleft", 0.1)
axis("triggerright", 0.1)
check("owned trigger releases remain swallowed after cancel",
  originalAxes == beforeAxes)

-- Platforms which happen to send both a trigger button and its analog axis
-- must still spend only one ball.
axisCount, axisCommits = count, commits
press("righttrigger")
axis("triggerright", 0.8)
release("righttrigger")
axis("triggerright", 0.1)
check("button plus axis duplicate commits only once",
  count == axisCount - 1 and commits == axisCommits + 1)
finishSession()

-- Losing controller ownership cancels a free aim and clears the remembered
-- pull, so the later physical release delegates instead of staying stuck.
axis("triggerright", 0.8)
check("focus-loss scenario starts an axis aim", shared.state.overworld ~= nil)
Game.focus(game, false)
beforeAxes = originalAxes
axis("triggerright", 0.1)
check("focus loss clears trigger ownership",
  shared.state.overworld == nil and originalAxes == beforeAxes + 1)

axis("triggerright", 0.8)
check("controller-removal scenario starts an axis aim", shared.state.overworld ~= nil)
Game.joystickremoved(game, joystick)
beforeAxes = originalAxes
axis("triggerright", 0.1)
check("controller removal clears trigger ownership",
  shared.state.overworld == nil and originalAxes == beforeAxes + 1)

-- Only the active overworld's ordinary movement handler is frozen.
count = 3
press("righttrigger")
local worldBefore = originalWorldInputs
OverworldController.handleInput(ow, 0.016)
check("active aim freezes its world handleInput",
  originalWorldInputs == worldBefore)
OverworldController.handleInput({ other = true }, 0.016)
check("other world instance remains composable",
  originalWorldInputs == worldBefore + 1)
press("lefttrigger")
OverworldController.handleInput(ow, 0.016)
check("cancel restores ordinary world input behavior",
  originalWorldInputs == worldBefore + 2)

-- Flight collision/miss ----------------------------------------------------
mapWalkable = false
press("righttrigger")
release("righttrigger")
feature:update(game, 0.25)
check("flight collides with blocked landing terrain",
  shared.state.overworld and shared.state.overworld.phase == "impact"
    and shared.state.overworld.collisionState == "terrain")
check("terrain miss has no pending capture", shared.state.pendingCapture == nil)
finishSession()
mapWalkable = true

-- Wilds hit: exact target identity is handed to the version-gated bridge,
-- and the already-spent ball becomes a one-shot pending battle capture.
local exactTarget = {
  id = "wilds_1", species = "PIDGEY", level = 3,
  position = { x = 0, y = 12, z = 8 }, radius = 1,
}
targetList = { exactTarget }
battleTarget = nil
shared.state.pendingCapture = nil
press("righttrigger")
release("righttrigger")
for _ = 1, 20 do
  feature:update(game, 0.015)
  if battleTarget then break end
end
check("Wilds trajectory hit starts exact target", battleTarget == exactTarget)
check("Wilds hit queues exact pending capture",
  shared.state.pendingCapture
    and shared.state.pendingCapture.target == exactTarget
    and shared.state.pendingCapture.ballId == "POKE_BALL"
    and shared.state.pendingCapture.consumed == true)
check("impact rumble uses engine haptics seam", #buzzes > 0
  and buzzes[#buzzes] == "light")
finishSession()
targetList = {}

-- Cleanup must be safe both while aiming and after a ball has committed.
count = 2
press("righttrigger")
release("righttrigger")
check("cleanup scenario has committed flight",
  shared.state.overworld and shared.state.overworld.committed == true)
feature.cleanup()
check("cleanup clears active visual/input session", shared.state.overworld == nil)
check("cleanup restores press patch", Game.gamepadpressed == originalGamePressed)
check("cleanup restores release patch", Game.gamepadreleased == originalGameReleased)
check("cleanup restores axis patch", Game.gamepadaxis == originalGameAxis)
check("cleanup restores focus patch", Game.focus == originalGameFocus)
check("cleanup restores visible patch", Game.visible == originalGameVisible)
check("cleanup restores joystick patch", Game.joystickremoved == originalGameRemoved)
check("cleanup restores world patch",
  OverworldController.handleInput == originalWorldHandle)
check("cleanup unregisters input hook", hookStops == 1)
check("cleanup releases shared API", shared.overworld == nil)

-- A world-patch conflict must be rejected atomically. It must not leave a
-- new Game wrapper behind after throwing during installation.
rawset(OverworldController, "_letsGoCatchThrowWorldInputV1", { active = true })
local pressBeforeConflict = Game.gamepadpressed
local axisBeforeConflict = Game.gamepadaxis
local conflictShared = {
  state = {}, settings = settings, inventory = inventory,
  camera = camera, trajectory = shared.trajectory, wilds = wilds,
}
local conflictOK = pcall(factory, mod, conflictShared)
check("duplicate world adapter is rejected", conflictOK == false)
check("failed install is atomic", Game.gamepadpressed == pressBeforeConflict
  and Game.gamepadaxis == axisBeforeConflict
  and rawget(Game, "_letsGoCatchThrowGamepadV1") == nil)
rawset(OverworldController, "_letsGoCatchThrowWorldInputV1", nil)

io.stdout:write(("overworld_test: %d passed, %d failed\n"):format(passed, failed))
if failed > 0 then os.exit(1) end
