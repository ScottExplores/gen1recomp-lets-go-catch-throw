-- ROM-free procedural HUD tests. Run from the mod root with Fengari/Lua:
--   fengari tests/renderer_test.lua

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

local calls = {}
local graphics = {
  color = { 0.11, 0.22, 0.33, 0.44 },
  lineWidth = 7,
  translateX = 4,
  translateY = -3,
  stack = {},
  fail = nil,
}
local function record(name, ...)
  calls[#calls + 1] = { name, ... }
  if graphics.fail == name then
    graphics.fail = nil
    error("synthetic " .. name .. " failure")
  end
end
function graphics.push(mode)
  record("push", mode)
  graphics.stack[#graphics.stack + 1] = {
    color = { graphics.color[1], graphics.color[2],
              graphics.color[3], graphics.color[4] },
    lineWidth = graphics.lineWidth,
    translateX = graphics.translateX,
    translateY = graphics.translateY,
  }
end
function graphics.pop()
  record("pop")
  local state = table.remove(graphics.stack)
  if not state then error("unbalanced graphics pop") end
  graphics.color, graphics.lineWidth = state.color, state.lineWidth
  graphics.translateX, graphics.translateY = state.translateX, state.translateY
end
function graphics.setColor(r, g, b, a)
  record("setColor", r, g, b, a)
  graphics.color = { r, g, b, a }
end
function graphics.setLineWidth(width)
  record("setLineWidth", width)
  graphics.lineWidth = width
end
function graphics.circle(...) record("circle", ...) end
function graphics.arc(...) record("arc", ...) end
function graphics.rectangle(...) record("rectangle", ...) end
function graphics.line(...) record("line", ...) end
function graphics.polygon(...) record("polygon", ...) end
function graphics.print(...) record("print", ...) end
function graphics.translate(x, y)
  record("translate", x, y)
  graphics.translateX = graphics.translateX + x
  graphics.translateY = graphics.translateY + y
end
function graphics.getDimensions() return 320, 180 end

love = { graphics = graphics }

local values = {
  battle_throw_arc = true,
  trajectory_line = "dots",
  trajectory_thickness = "normal",
  ball_scale = "normal",
  target_highlight = "both",
  show_ball_count = true,
  show_range_number = true,
  show_target_name = true,
  show_target_level = true,
  show_catch_chance = "percent",
  debug_throw = false,
  debug_battle_throw = false,
  camera_shake = "off",
  overworld_impact_effect = true,
  miss_effect = true,
}
local settings = {}
function settings:get(key) return values[key] end
function settings:inputConflicts() return {} end

local camera = {}
function camera:project(point)
  return 30 + point.x * 2, 18 + point.z * 1.5,
    1 + math.max(0, point.y or 0) / 20
end
function camera:status()
  return {
    mode = "1ST",
    dramaless = { compatible = true },
    kantoFirstPerson = { compatible = true },
  }
end
local wilds = {}
function wilds:status() return { available = true } end

local hookWrapper, hookStops = nil, 0
local warnings = 0
local mod = {
  hooks = {
    wrap = function(_, name, wrapper, priority)
      if name == "render.hud" then hookWrapper = wrapper end
      check("HUD hook uses late overlay priority", priority == 200)
      return function() hookStops = hookStops + 1 end
    end,
  },
  log = { warn = function() warnings = warnings + 1 end },
}
local shared = {
  state = {}, settings = settings, camera = camera, wilds = wilds,
}
local feature = installer("renderer")(mod, shared)
check("renderer installs shared API", feature == shared.renderer)
check("render.hud hook installed", type(hookWrapper) == "function")

local game = {
  data = { pokemon = { PIDGEY = { name = "PIDGEY" } } },
  overworld = { map = { id = "ROUTE_1" } },
}
local viewport = {
  width = 320, height = 180,
  gameX = 20, gameY = 10, gameWidth = 280, gameHeight = 160,
}

local function countCalls(name, from)
  local result = 0
  for index = from or 1, #calls do
    if calls[index][1] == name then result = result + 1 end
  end
  return result
end

local function callsOf(name, from)
  local result = {}
  for index = from or 1, #calls do
    if calls[index][1] == name then result[#result + 1] = calls[index] end
  end
  return result
end

local function countCircleMode(mode, from)
  local result = 0
  for _, call in ipairs(callsOf("circle", from)) do
    if call[2] == mode then result = result + 1 end
  end
  return result
end

local function callNames(from)
  local names = {}
  for index = from or 1, #calls do names[#names + 1] = calls[index][1] end
  return table.concat(names, ",")
end

local initialColor = { graphics.color[1], graphics.color[2],
                       graphics.color[3], graphics.color[4] }
local initialWidth = graphics.lineWidth
local initialTranslateX, initialTranslateY = graphics.translateX, graphics.translateY

-- Battle context uses normalized screen geometry and draws arc, trail,
-- shrinking ring, ball and status without mutating caller graphics state.
shared.state.battle = {
  context = "battle",
  phase = "aim",
  ballId = "GREAT_BALL",
  inventoryCount = 3,
  origin = { x = 0.20, y = 0.82 },
  position = { x = 0.34, y = 0.64 },
  trajectoryPoints = {
    { x = 0.20, y = 0.82 }, { x = 0.36, y = 0.52 },
    { x = 0.50, y = 0.36 },
  },
  trail = { { x = 0.20, y = 0.82 }, { x = 0.28, y = 0.70 } },
  ringRadius = 0.55,
  age = 1,
}
local from = #calls + 1
feature:draw(game, viewport)
check("battle HUD draws procedural ball", countCalls("arc", from) >= 1
  and countCalls("circle", from) >= 3)
check("battle HUD draws trajectory and trail", countCalls("line", from) >= 2,
  tostring(countCalls("line", from)) .. ":" .. callNames(from))
check("battle HUD draws ring/status", countCalls("rectangle", from) >= 1
  and countCalls("print", from) >= 1)
check("battle HUD balances graphics stack", #graphics.stack == 0
  and countCalls("push", from) == 1 and countCalls("pop", from) == 1)
check("battle HUD restores caller color",
  graphics.color[1] == initialColor[1]
    and graphics.color[2] == initialColor[2]
    and graphics.color[3] == initialColor[3]
    and graphics.color[4] == initialColor[4])
check("battle HUD restores caller line width", graphics.lineWidth == initialWidth)

-- Overworld uses the read-only camera projection for trajectory, target and
-- ball and shows target metadata.
shared.state.battle = nil
shared.state.overworld = {
  context = "overworld",
  phase = "aim",
  ballId = "ULTRA_BALL",
  inventoryCount = 2,
  stage = 3,
  age = 0.5,
  origin = { x = 1, y = 7, z = 2 },
  position = { x = 3, y = 8, z = 5 },
  trajectoryPoints = {
    { x = 1, y = 7, z = 2 }, { x = 3, y = 10, z = 5 },
    { x = 5, y = 2, z = 8 },
  },
  trail = { { x = 2, y = 8, z = 3 }, { x = 3, y = 8, z = 5 } },
  target = {
    id = "wilds_1", species = "PIDGEY", level = 4,
    position = { x = 5, y = 8, z = 7 },
  },
  catchChance = 72,
}
from = #calls + 1
feature:draw(game, viewport)
check("overworld HUD projects and draws ball/target",
  countCalls("arc", from) >= 1 and countCalls("polygon", from) >= 1
    and countCalls("circle", from) >= 3)
check("overworld dotted trajectory draws points", countCalls("circle", from) >= 5)
check("overworld HUD draws status metadata", countCalls("print", from) >= 4)
check("overworld HUD restores graphics", #graphics.stack == 0
  and graphics.lineWidth == initialWidth
  and graphics.color[1] == initialColor[1])

-- Trajectory styles are intentionally distinct: DOTS emit alternating
-- points, SEGMENTS emit alternating two-point strokes, and SOLID emits one
-- continuous coordinate array. This also guards the Lua multi-assignment
-- regression that once overwrote every x coordinate with its y coordinate.
values.show_ball_count = false
values.show_range_number = false
local trajectorySession = {
  context = "overworld", phase = "aim", ballId = "POKE_BALL",
  trajectoryPoints = {
    { x = 1, y = 4, z = 1 }, { x = 2, y = 6, z = 2 },
    { x = 3, y = 7, z = 3 }, { x = 4, y = 6, z = 4 },
    { x = 5, y = 2, z = 5 },
  },
}
shared.state.overworld = trajectorySession

values.trajectory_line = "dots"
from = #calls + 1
feature:draw(game, viewport)
check("DOTS trajectory draws alternating points",
  countCalls("line", from) == 0 and countCalls("circle", from) == 3)

values.trajectory_line = "segments"
from = #calls + 1
feature:draw(game, viewport)
local segmentLines = callsOf("line", from)
check("SEGMENTS trajectory draws alternating strokes",
  #segmentLines == 2 and type(segmentLines[1][2]) == "number"
    and #segmentLines[1] == 5)

values.trajectory_line = "solid"
from = #calls + 1
feature:draw(game, viewport)
local solidLines = callsOf("line", from)
check("SOLID trajectory draws one continuous path",
  #solidLines == 1 and type(solidLines[1][2]) == "table"
    and #solidLines[1][2] == 10)

values.trajectory_line = "off"
from = #calls + 1
feature:draw(game, viewport)
check("OFF trajectory draws no path primitives",
  countCalls("line", from) == 0 and countCalls("circle", from) == 0)

-- Battle throws always use readable segmented arcs regardless of the
-- overworld trajectory setting.
shared.state.overworld = nil
shared.state.battle = {
  context = "battle", phase = "aim", ballId = "POKE_BALL",
  trajectoryPoints = {
    { x = 0.1, y = 0.8 }, { x = 0.2, y = 0.6 },
    { x = 0.3, y = 0.4 }, { x = 0.4, y = 0.3 },
    { x = 0.5, y = 0.2 },
  },
}
from = #calls + 1
feature:draw(game, viewport)
segmentLines = callsOf("line", from)
check("battle arc remains SEGMENTS when world trajectory is OFF",
  #segmentLines == 2 and type(segmentLines[1][2]) == "number")

-- Wheel layouts use materially different geometry: horizontal shares y,
-- radial varies both axes, and list shares x while spelling out ball names.
local wheelItems = {
  { id = "POKE_BALL", count = 4 },
  { id = "GREAT_BALL", count = 3 },
  { id = "ULTRA_BALL", count = 2 },
}
local wheelSession = {
  context = "overworld", phase = "wheel", ballId = "POKE_BALL",
  wheel = { items = wheelItems, index = 2, style = "horizontal" },
}
shared.state.battle = nil
shared.state.overworld = wheelSession

from = #calls + 1
feature:draw(game, viewport)
local ballArcs = callsOf("arc", from)
check("HORIZONTAL wheel lays balls on one row", #ballArcs == 3
  and ballArcs[1][4] == ballArcs[2][4]
  and ballArcs[2][4] == ballArcs[3][4]
  and ballArcs[1][3] ~= ballArcs[2][3])

wheelSession.wheel.style = "radial"
from = #calls + 1
feature:draw(game, viewport)
ballArcs = callsOf("arc", from)
check("RADIAL wheel varies both ball axes", #ballArcs == 3
  and ballArcs[1][3] ~= ballArcs[2][3]
  and ballArcs[1][4] ~= ballArcs[2][4])

wheelSession.wheel.style = "list"
from = #calls + 1
feature:draw(game, viewport)
ballArcs = callsOf("arc", from)
local listPrints = callsOf("print", from)
check("LIST wheel lays balls in one column", #ballArcs == 3
  and ballArcs[1][3] == ballArcs[2][3]
  and ballArcs[2][3] == ballArcs[3][3]
  and ballArcs[1][4] ~= ballArcs[2][4])
check("LIST wheel includes readable ball names", #listPrints == 3
  and tostring(listPrints[1][2]):find("POKE BALL", 1, true) ~= nil)

-- Impact effects honor independent battle, overworld-hit and miss gates.
local battleImpact = {
  context = "battle", phase = "breakout", ballId = "POKE_BALL",
  position = { x = 0.5, y = 0.36 }, impact = true,
  impactEffect = true, hit = true, timer = 0.08,
}
shared.state.overworld = nil
shared.state.battle = battleImpact
from = #calls + 1
feature:draw(game, viewport)
check("battle impact enabled draws burst",
  countCircleMode("line", from) == 2 and countCalls("line", from) == 6)
battleImpact.impactEffect = false
from = #calls + 1
feature:draw(game, viewport)
check("battle impact disabled draws no burst",
  countCircleMode("line", from) == 0 and countCalls("line", from) == 0)

local worldImpact = {
  context = "overworld", phase = "impact", ballId = "POKE_BALL",
  position = { x = 3, y = 2, z = 5 }, hit = true, impactTimer = 0.08,
}
shared.state.battle = nil
shared.state.overworld = worldImpact
values.overworld_impact_effect = true
from = #calls + 1
feature:draw(game, viewport)
check("overworld hit effect enabled draws burst", countCircleMode("line", from) == 2)
values.overworld_impact_effect = false
from = #calls + 1
feature:draw(game, viewport)
check("overworld hit effect gate suppresses burst", countCircleMode("line", from) == 0)

worldImpact.hit = false
values.miss_effect = true
from = #calls + 1
feature:draw(game, viewport)
check("miss effect enabled draws burst", countCircleMode("line", from) == 2)
values.miss_effect = false
from = #calls + 1
feature:draw(game, viewport)
check("miss effect gate suppresses burst", countCircleMode("line", from) == 0)

-- Battle shake translates inside push('all'), then pop restores the caller's
-- transform. OFF must issue no translate at all.
shared.state.overworld = nil
shared.state.battle = battleImpact
battleImpact.impactEffect = false
values.camera_shake = "low"
from = #calls + 1
feature:draw(game, viewport)
check("battle shake uses a scoped translate", countCalls("translate", from) == 1)
check("battle shake restores caller transform", #graphics.stack == 0
  and graphics.translateX == initialTranslateX
  and graphics.translateY == initialTranslateY)
values.camera_shake = "off"
from = #calls + 1
feature:draw(game, viewport)
check("camera shake OFF never translates", countCalls("translate", from) == 0)

-- Restore a known ball-bearing world session for hook/error assertions below.
shared.state.battle = nil
shared.state.overworld = {
  context = "overworld", phase = "impact", ballId = "ULTRA_BALL",
  position = { x = 3, y = 8, z = 5 }, hit = true, impactTimer = 0.1,
}
values.overworld_impact_effect = true
values.miss_effect = true
values.show_ball_count = true
values.show_range_number = true

-- The runtime hook preserves nextFn's multiple returns and draws afterward.
local order = {}
local oldArc = graphics.arc
graphics.arc = function(...)
  order[#order + 1] = "draw"
  return oldArc(...)
end
local a, b, c = hookWrapper(function()
  order[#order + 1] = "next"
  return "a", nil, "c"
end, game, viewport)
check("render hook delegates before overlay", order[1] == "next"
  and order[2] == "draw")
check("render hook preserves multiple returns", a == "a" and b == nil and c == "c")
graphics.arc = oldArc

-- Any one drawing primitive may fail. The frame is skipped, the exception
-- stays contained, and push('all') state is still popped/restored.
from = #calls + 1
graphics.fail = "arc"
local errorEscaped, errorValue = pcall(feature.draw, feature, game, viewport)
check("HUD draw failure is contained", errorEscaped == true, errorValue)
check("HUD draw failure is logged once", warnings == 1, warnings)
check("HUD draw failure restores graphics", #graphics.stack == 0
  and graphics.lineWidth == initialWidth
  and graphics.color[1] == initialColor[1]
  and countCalls("pop", from) == 1)

from = #calls + 1
feature:draw(game, viewport)
check("renderer survives next frame after draw error", countCalls("arc", from) >= 1
  and #graphics.stack == 0)

-- A failing translate is contained by the same frame guard, and push/pop
-- still restores the incoming transform.
shared.state.overworld = nil
shared.state.battle = battleImpact
values.camera_shake = "normal"
graphics.fail = "translate"
from = #calls + 1
local shakeEscaped, shakeValue = pcall(feature.draw, feature, game, viewport)
check("shake translate failure is contained", shakeEscaped == true, shakeValue)
check("shake translate failure is logged", warnings == 2, warnings)
check("shake translate failure restores transform", #graphics.stack == 0
  and graphics.translateX == initialTranslateX
  and graphics.translateY == initialTranslateY
  and countCalls("pop", from) == 1)
values.camera_shake = "off"

-- No active throw means no graphics ownership at all.
shared.state.battle = nil
shared.state.overworld = nil
from = #calls + 1
feature:draw(game, viewport)
check("inactive renderer is a no-op", #calls == from - 1)

feature.cleanup()
check("renderer cleanup unregisters hook", hookStops == 1)
check("renderer cleanup releases shared API", shared.renderer == nil)

io.stdout:write(("renderer_test: %d passed, %d failed\n"):format(passed, failed))
if failed > 0 then os.exit(1) end
