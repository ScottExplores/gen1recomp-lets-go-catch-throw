-- Whole-package ROM-free API-2 loader smoke.
-- Run from a Gen1Recomp checkout:
--   lua <mod>/tests/full_load.lua <directory-containing-mod> [fixture-root]

local argv = rawget(_G, "arg") or {}
local fixtureRoot = argv[2] or os.getenv("LETSGO_FIXTURE_ROOT") or "."
local engineRoot = os.getenv("LETSGO_ENGINE_ROOT") or fixtureRoot
package.path = engineRoot .. "/?.lua;" .. engineRoot .. "/?/init.lua;"
  .. fixtureRoot .. "/?.lua;" .. fixtureRoot .. "/?/init.lua;"
  .. "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local parent = argv[1] or os.getenv("LETSGO_MOD_PARENT")
assert(parent, "pass the directory containing lets_go_catch_throw")
local T = require("tests.modkit")
local Game = require("src.core.Game")
local Overworld = require("src.world.OverworldController")
local Battle = require("src.battle.BattleState")
local before = {
  pressed = Game.gamepadpressed,
  released = Game.gamepadreleased,
  axis = Game.gamepadaxis,
  worldInput = Overworld.handleInput,
  throwBall = Battle.throwBall,
}

local function read(path)
  local handle = assert(io.open(path, "rb"))
  local body = handle:read("*a")
  handle:close()
  return body
end

-- A deterministic memfs avoids depending on io.popen/dir in self-contained
-- Lua runners while still exercising the production Loader and schemas.
local prefix = "mods/lets_go_catch_throw/"
local sourceRoot = parent .. "/lets_go_catch_throw/"
local files = {}
for _, relative in ipairs({
  "manifest.json", "main.lua",
  "modules/settings.lua", "modules/trajectory.lua",
  "modules/inventory.lua", "modules/camera.lua", "modules/wilds.lua",
  "modules/battle.lua", "modules/overworld.lua", "modules/renderer.lua",
  "modules/settings_menu.lua",
}) do
  files[prefix .. relative] = read(sourceRoot .. relative)
end

local run = T.sdk.loadMod("mods/lets_go_catch_throw", {
  data = require("tests.modkit.fixtures").fresh(),
  fs = T.sdk.memfs(files),
  generation = 1,
})

for key, err in pairs(run.errors or {}) do
  io.stderr:write("loader error " .. tostring(key) .. ": " .. tostring(err) .. "\n")
end
if run.mod == nil then
  for key, value in pairs(run.loader.mods or {}) do
    io.stderr:write("loaded mod " .. tostring(key) .. " at "
      .. tostring(value and value.path) .. "\n")
  end
end

T.eq(#run.errors, 0, "mod loads through the production API-2 loader")
T.check(run.mod ~= nil, "loader selected the mod")
T.check(run.loader.optionSchemas.LETS_GO_CATCH_THROW ~= nil,
  "complete settings schema registered")
local modeDefault
for _, row in ipairs(run.loader.optionSchemas.LETS_GO_CATCH_THROW or {}) do
  if row.key == "lets_go_mode" then modeDefault = row.default break end
end
T.eq(modeDefault, "catch_only", "Catch Only is enabled by default")
local exported = run.loader.exports.LETS_GO_CATCH_THROW
T.check(type(exported) == "table" and type(exported.status) == "table",
  "status export published")
T.check(exported and exported.status and exported.status.installed == true,
  "package reports installed")
T.check(Game.gamepadpressed ~= before.pressed, "controller adapter installed")
T.check(Game.gamepadaxis ~= before.axis, "analog trigger adapter installed")
T.check(Overworld.handleInput ~= before.worldInput, "world input gate installed")
T.check(Battle.throwBall ~= before.throwBall, "battle throw adapter installed")

if exported and exported.status and exported.status.cleanup then
  exported.status.cleanup()
end
T.eq(Game.gamepadpressed, before.pressed, "controller adapter restored")
T.eq(Game.gamepadreleased, before.released, "controller release restored")
T.eq(Game.gamepadaxis, before.axis, "analog trigger adapter restored")
T.eq(Overworld.handleInput, before.worldInput, "world input restored")
T.eq(Battle.throwBall, before.throwBall, "battle adapter restored")

run.release()
T.finish("lets_go_catch_throw full load")
