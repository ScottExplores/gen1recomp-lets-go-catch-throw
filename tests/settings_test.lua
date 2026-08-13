-- ROM-free unit coverage for settings.lua and settings_menu.lua.
-- Run from the mod root with a Lua 5.1+ interpreter:
--   lua tests/settings_test.lua

local script = debug.getinfo(1, "S").source
if script:sub(1, 1) == "@" then script = script:sub(2) end
local root = script:gsub("[/\\]tests[/\\]settings_test%.lua$", "")
if root == script then root = "." end

local function loadInstaller(rel)
  local chunk, err = loadfile(root .. "/" .. rel)
  assert(chunk, err)
  local ok, installer = pcall(chunk)
  assert(ok, installer)
  assert(type(installer) == "function", rel .. " must return an installer")
  return installer
end

local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, ("check %d failed: %s"):format(checks, message))
end

local listeners, emitted = {}, {}
local eventBus = {}
function eventBus:on(name, fn)
  listeners[name] = listeners[name] or {}
  listeners[name][#listeners[name] + 1] = fn
  return fn
end
function eventBus:emit(name, payload)
  emitted[#emitted + 1] = { name = name, payload = payload }
  for _, fn in ipairs(listeners[name] or {}) do fn(payload) end
end

local optionSchema
local screens = {}
local wrapped = {}
local stored = {}
local modSaved = {}
local stack = { states = {} }
function stack:push(state)
  self.states[#self.states + 1] = state
  return state
end
function stack:pop()
  return table.remove(self.states)
end
function stack:top()
  return self.states[#self.states]
end

local game = {
  save = { options = { modOptions = {
    LETS_GO_CATCH_THROW = { lets_go_mode = "off" },
  } } },
  mods = { modOptions = {
    LETS_GO_CATCH_THROW = { lets_go_mode = "off" },
  }, events = eventBus },
  stack = stack,
  writes = 0,
}
function game:writeOptions() self.writes = self.writes + 1 end

local installed = {
  DRAMALESS_SHAPE = { id = "DRAMALESS_SHAPE", version = "1.6.4", exports = {} },
  ds_fp_ceiling = { id = "ds_fp_ceiling", version = "1.60.0", exports = {} },
  overworld_wild_spawns = {
    id = "overworld_wild_spawns", version = "1.11.1", exports = {},
  },
}

local mod = {
  id = "LETS_GO_CATCH_THROW",
  options = {},
  events = eventBus,
  hooks = {},
  content = { screens = {} },
  ui = {},
  log = {},
  world = { game = game },
  save = {},
}
function mod.options:define(schema)
  optionSchema = schema
  return schema
end
function mod.options:get(key)
  local bucket = game.mods.modOptions[mod.id]
  if bucket and bucket[key] ~= nil then return bucket[key] end
  if stored[key] ~= nil then return stored[key] end
  for _, row in ipairs(optionSchema or {}) do
    if row.key == key then return row.default end
  end
end
function mod.save:get(key, fallback)
  local value = modSaved[key]
  if value == nil then return fallback end
  return value
end
function mod.save:set(key, value) modSaved[key] = value end
function mod.find(id) return installed[id] end
function mod.hooks:wrap(name, fn)
  wrapped[name] = fn
  return fn
end
function mod.content.screens:register(id, record)
  screens[id] = record
end
function mod.log:warn() end

local function makeList(gameArg, title, items, opts)
  local list = {
    game = gameArg, title = title, items = items, opts = opts or {}, closed = false,
  }
  list.onChoose = list.opts.onChoose
  function list:close()
    self.closed = true
    if self.game.stack:top() == self then self.game.stack:pop() end
  end
  return list
end
mod.ui.ListMenu = { new = makeList }
mod.ui.TextBox = { new = function(_, text) return { text = text } end }
function mod.ui.push(gameArg, id)
  local record = assert(screens[id], "unknown screen " .. tostring(id))
  local state = record.new(gameArg)
  gameArg.stack:push(state)
  return state
end

local shared = {}
local Settings = loadInstaller("modules/settings.lua")(mod, shared)
eventBus:emit("game.ready", { game = game })

check(shared.settings == Settings, "settings exported through shared state")
check(type(optionSchema) == "table" and #optionSchema >= 70,
  "full schema registered")
check(Settings:get("manual_throw") == true,
  "manual throw defaults on for the AYN Thor")
check(Settings:get("lets_go_mode") == "catch_only", "battle mode defaults to Catch Only")
check(modSaved.catch_only_default_v020 == true,
  "legacy OFF option is migrated to Catch Only exactly once")
Settings:set("lets_go_mode", "off", game, "post_migration_choice")
eventBus:emit("game.ready", { game = game })
check(Settings:get("lets_go_mode") == "off",
  "an intentional OFF choice after migration remains respected")
Settings:set("lets_go_mode", "catch_only", game, "restore_test_default")
check(Settings:get("wilds_integration") == "auto", "Wilds defaults auto")
check(Settings:get("overworld_capture") == true,
  "overworld capture is ready by default")

local required = {
  -- battle
  "lets_go_mode", "battle_catch_throw", "throw_input", "throw_sensitivity",
  "battle_throw_speed", "battle_aim_assist", "battle_throw_arc",
  "battle_ball_trail", "catch_ring", "catch_ring_speed", "camera_shake",
  "battle_throw_sound", "battle_impact_effect", "capture_animation",
  "debug_battle_throw",
  -- overworld and targeting
  "manual_throw", "aim_button", "cancel_button", "throw_mode", "max_range",
  "min_range", "charge_speed", "range_loop", "trajectory_line",
  "trajectory_thickness", "trajectory_length", "arc_height",
  "overworld_throw_speed", "ball_scale", "overworld_ball_trail",
  "throw_camera", "overworld_aim_assist", "target_snap", "target_highlight",
  "target_range", "auto_face_target", "default_ball", "ball_select_mode",
  "show_ball_count", "show_range_number", "show_target_name",
  "show_target_level", "show_catch_chance", "overworld_throw_sound",
  "overworld_impact_sound", "overworld_impact_effect", "miss_effect",
  "rumble", "debug_throw",
  -- wheel / Wilds / camera / controls / preset
  "ball_wheel", "ball_wheel_button", "ball_wheel_style",
  "remember_last_ball", "wilds_integration", "overworld_capture",
  "miss_starts_battle", "hit_starts_capture", "failed_catch_starts_battle",
  "aggro_on_miss", "first_person_throw_origin", "third_person_throw_origin",
  "diorama_throw_origin", "camera_aim_mode", "camera_pitch_affects_throw",
  "camera_yaw_affects_throw", "first_person_fov_compensation",
  "custom_aim_button", "custom_cancel_button", "ball_select_button",
  "quick_throw_button", "range_up_button", "range_down_button",
  "toggle_aim_assist_button", "throw_preset",
}
for _, key in ipairs(required) do
  check(Settings.byKey[key] ~= nil, "schema contains " .. key)
end

local ok = Settings:set("max_range", 99, game, "test")
check(ok and Settings:raw("max_range") == 5, "number writes clamp to schema")
check(game.save.options.modOptions[mod.id].max_range == 5,
  "save option bucket updated")
check(game.mods.modOptions[mod.id].max_range == 5,
  "live loader option bucket updated")
check(game.writes > 0, "option writes are persisted")
local sawNamespaced, sawEngine = false, false
for _, event in ipairs(emitted) do
  if event.name == "mod.LETS_GO_CATCH_THROW.options_changed" then
    sawNamespaced = true
  elseif event.name == "mod.options_changed" then
    sawEngine = true
  end
end
check(sawNamespaced and sawEngine, "both available change channels emitted")

check(Settings:get("arc_height") == "normal", "Let's Go preset is resolved")
Settings:set("arc_height", "high", game, "test")
check(Settings:raw("throw_preset") == "custom",
  "manual preset-controlled edit selects CUSTOM")
check(Settings:get("arc_height") == "high", "manual value becomes active")
Settings:applyPreset("arcade", game, "test_preset")
check(Settings:get("arc_height") == "low", "Arcade preset overrides at read time")
check(Settings:raw("arc_height") == "high", "preset preserves manual raw value")
Settings:applyPreset("custom", game, "test_preset")
check(Settings:get("arc_height") == "high", "CUSTOM restores manual value")
local bad = Settings:set("arc_height", "impossible", game, "test")
check(bad == false, "unsupported choices are rejected")

Settings:set("lets_go_mode", "full", game, "test")
Settings:set("debug_battle_throw", true, game, "test")
Settings:set("manual_throw", false, game, "test")
Settings:resetBattle(game)
check(Settings:raw("lets_go_mode") == "catch_only", "battle reset restores Catch Only")
check(Settings:raw("debug_battle_throw") == false,
  "battle reset includes its debug switch")
check(Settings:raw("manual_throw") == false,
  "battle reset does not touch overworld settings")
check(Settings:raw("throw_preset") == "custom",
  "targeted reset exposes raw defaults instead of preset overrides")
Settings:resetOverworld(game)
check(Settings:raw("manual_throw") == true, "overworld reset restores Thor default")
Settings:set("aim_button", "x", game, "test")
Settings:resetControls(game)
check(Settings:raw("aim_button") == "r2", "controls reset is scoped")
Settings:resetAll(game)
check(Settings:raw("throw_preset") == "lets_go", "restore all restores preset default")

local conflicts = Settings:inputConflicts(game)
local hasCoreSpeedConflict = false
for _, conflict in ipairs(conflicts) do
  if tostring(conflict.code):match("^core:") then hasCoreSpeedConflict = true end
end
check(not hasCoreSpeedConflict,
  "default R2/L2 bindings do not claim R1/L1 speed controls")
check(Settings:actionBinding("aim") == "righttrigger",
  "R2 resolves to the physical right trigger")
check(Settings:actionBinding("cancel") == "lefttrigger",
  "L2 resolves to the physical left trigger")

local Menu = loadInstaller("modules/settings_menu.lua")(mod, shared)
check(shared.settings_menu == Menu, "menu exported through shared state")
check(Menu.available == true, "organized menu registered when UI API exists")
check(type(wrapped["ui.options.rows"]) == "function", "Options rows hook installed")
check(screens[Menu.ROOT_ID] ~= nil and screens[Menu.STATUS_ID] ~= nil,
  "root and status screens registered")
for _, page in ipairs(Menu.PAGE_DEFS) do
  check(screens[Menu.PAGE_IDS[page.id]] ~= nil, "page registered: " .. page.id)
end

local hookedRows = wrapped["ui.options.rows"](
  function(_, engineRows) return engineRows end,
  game, { { id = "engine", label = "ENGINE" } })
check(hookedRows[1].id == "LETS_GO_CATCH_THROW:settings.open",
  "single mod menu row leads OPTIONS")
check(hookedRows[1].value() == "WARN", "known binding conflict is visible at top level")

local rootMenu = screens[Menu.ROOT_ID].new(game)
check(rootMenu.title == "CATCH & THROW", "root title is readable")
local pageCount, resetBattle, resetWorld, resetControls, resetAll = 0
for _, item in ipairs(rootMenu.items) do
  check(#item.label <= 14, "root label fits ListMenu: " .. item.label)
  if item.page then pageCount = pageCount + 1 end
  if item.label == "RESET BATTLE" then resetBattle = true end
  if item.label == "RESET WORLD" then resetWorld = true end
  if item.label == "RESET CONTROLS" then resetControls = true end
  if item.label == "RESTORE ALL" then resetAll = true end
end
check(pageCount == #Menu.PAGE_DEFS, "all setting categories appear at root")
check(resetBattle and resetWorld and resetControls and resetAll,
  "all requested scoped reset actions appear")

for _, page in ipairs(Menu.PAGE_DEFS) do
  local pageMenu = screens[Menu.PAGE_IDS[page.id]].new(game)
  local restore = false
  for _, item in ipairs(pageMenu.items) do
    check(#item.label <= 14, "page label fits ListMenu: " .. item.label)
    if item.label == "RESTORE PAGE" then restore = true end
  end
  check(restore, "every settings page has restore defaults: " .. page.id)
end

-- The AYN Thor defaults work immediately. Potential engine-build / mod
-- conflicts remain visible in DEBUG/STATUS without blocking normal use.
Settings:resetAll(game)
local worldMenu = screens[Menu.PAGE_IDS.overworld].new(game)
local manual
for _, item in ipairs(worldMenu.items) do
  if item.key == "manual_throw" then manual = item break end
end
check(manual ~= nil and Settings:get("manual_throw") == true,
  "manual throw row starts enabled for AYN Thor")
worldMenu.onChoose(manual, worldMenu)
check(Settings:get("manual_throw") == false,
  "manual throw can be disabled directly")
worldMenu.onChoose(manual, worldMenu)
check(Settings:get("manual_throw") == true,
  "manual throw can be re-enabled directly")

print(("settings_test: %d checks passed"):format(checks))
