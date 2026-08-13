-- Organized START -> OPTIONS menu for LETS_GO_CATCH_THROW.
--
-- The engine's option schema remains the fallback and is always complete.
-- When the 0.1.75 screen registry and ui.options.rows hook are available,
-- this adds one discoverable row that opens compact category screens.

return function(mod, shared)
  shared = shared or {}
  local Settings = assert(shared.settings,
    "LETS_GO_CATCH_THROW settings_menu requires settings first")

  local Menu = {}
  Menu.ROOT_ID = "LETS_GO_CATCH_THROW:settings"
  Menu.STATUS_ID = "LETS_GO_CATCH_THROW:status"
  Menu.WARNINGS_ID = "LETS_GO_CATCH_THROW:warnings"

  local PAGE_DEFS = {
    { id = "battle", label = "BATTLE CATCH" },
    { id = "overworld", label = "OVERWORLD" },
    { id = "target_hud", label = "TARGET & HUD" },
    { id = "wheel", label = "BALL WHEEL" },
    { id = "wilds", label = "WILDS LINK" },
    { id = "camera", label = "CAMERA THROW" },
    { id = "controls", label = "CONTROLS" },
    { id = "preset", label = "PRESETS" },
    { id = "debug", label = "DEBUG/STATUS" },
  }
  Menu.PAGE_DEFS = PAGE_DEFS
  Menu.PAGE_IDS = {}
  for _, page in ipairs(PAGE_DEFS) do
    Menu.PAGE_IDS[page.id] = "LETS_GO_CATCH_THROW:settings:" .. page.id
  end

  local function clip(text, n)
    text = tostring(text or "")
    n = n or 14
    if #text <= n then return text end
    return text:sub(1, n)
  end

  local function close(menu)
    if menu and type(menu.close) == "function" then menu:close() end
  end

  local function listMenu(game, title, items, opts)
    if not (mod and mod.ui and mod.ui.ListMenu
        and type(mod.ui.ListMenu.new) == "function") then
      return nil
    end
    opts = opts or {}
    opts.wrap = opts.wrap ~= false
    opts.pageJump = opts.pageJump ~= false
    opts.keyRepeat = opts.keyRepeat ~= false
    return mod.ui.ListMenu.new(game, clip(title), items, opts)
  end

  local factories = {}

  function Menu:push(game, id)
    Settings:bindGame(game)
    if mod and mod.ui and type(mod.ui.push) == "function" then
      local ok, result = pcall(mod.ui.push, game, id)
      if ok then return result end
    end
    local factory = factories[id]
    local state = factory and factory(game)
    if state and game and game.stack and type(game.stack.push) == "function" then
      game.stack:push(state)
    end
    return state
  end

  local function pushState(game, state)
    if state and game and game.stack and type(game.stack.push) == "function" then
      game.stack:push(state)
      return state
    end
    return nil
  end

  local function showMessage(game, message)
    if mod and mod.ui and mod.ui.TextBox and type(mod.ui.TextBox.new) == "function"
        and game and game.stack and type(game.stack.push) == "function" then
      local ok, box = pcall(mod.ui.TextBox.new, game, message)
      if ok and box then game.stack:push(box) return true end
    end
    if mod and mod.log and type(mod.log.warn) == "function" then
      pcall(mod.log.warn, mod.log, "%s", tostring(message))
    end
    return false
  end

  local function refreshItems(items)
    for _, item in ipairs(items or {}) do
      if item._row then
        item.right = clip(Settings:valueLabel(item._row, nil, true), 9)
      end
    end
  end

  local function marked(label, current)
    label = clip(label, current and 12 or 14)
    return current and ("> " .. label) or label
  end

  local function openConfirm(game, title, footer, action)
    local state
    local items = {
      { label = "NO", value = false },
      { label = "YES", value = true },
    }
    state = listMenu(game, title, items, {
      footer = footer,
      onChoose = function(item, menu)
        if item and item.value == true and action then action() end
        close(menu)
      end,
    })
    return pushState(game, state)
  end

  local function openChoice(game, row, parentItem)
    local current = Settings:get(row.key)
    local items = {}
    if row.type == "number" then
      local first = row.min or 0
      local last = row.max or 10
      local step = row.step or 1
      local value = first
      while value <= last do
        items[#items + 1] = {
          label = marked(tostring(value), value == current), value = value,
        }
        value = value + step
      end
    else
      for _, option in ipairs(row.choices or {}) do
        items[#items + 1] = {
          label = marked(option[3] or option[1], option[2] == current),
          value = option[2],
        }
      end
    end
    items[#items + 1] = { label = "BACK", _back = true }
    local state
    state = listMenu(game, row.menu_label or row.label, items, {
      onChoose = function(item, menu)
        if not item then return end
        if not item._back then
          if row.key == "throw_preset" then
            Settings:applyPreset(item.value, game, "options_menu")
          else
            Settings:set(row.key, item.value, game, "options_menu")
          end
          if parentItem then
            parentItem.right = clip(Settings:valueLabel(row, nil, true), 9)
          end
        end
        close(menu)
      end,
    })
    return pushState(game, state)
  end

  local function optionItem(game, row)
    local item = {
      key = row.key,
      _row = row,
      label = clip(row.menu_label or row.label),
      right = clip(Settings:valueLabel(row, nil, true), 9),
    }
    item._activate = function()
      if row.type == "toggle" then
        local nextValue = not (Settings:get(row.key) == true)
        Settings:set(row.key, nextValue, game, "options_menu")
        item.right = nextValue and "ON" or "OFF"
      else
        openChoice(game, row, item)
      end
    end
    return item
  end

  local function integrationItems(game)
    local status = Settings:integrationStatus()
    local conflicts = Settings:inputConflicts(game)
    return {
      { label = "INPUT WARNINGS", right = tostring(#conflicts), _warnings = true },
      { label = "DRAMALESS", right = status.dramaless and "FOUND" or "NOT FOUND" },
      { label = "KANTO 1ST", right = status.kanto_first_person and "FOUND" or "NOT FOUND" },
      { label = "WILDS", right = status.wilds and "FOUND" or "NOT FOUND" },
      { label = "SKY RIDE", right = status.sky_ride and "FOUND" or "NOT FOUND" },
      { label = "CONTROL NOTE", _note = true },
      { label = "BACK", _back = true },
    }
  end

  factories[Menu.WARNINGS_ID] = function(game)
    local conflicts = Settings:inputConflicts(game)
    local items = {}
    if #conflicts == 0 then
      items[1] = { label = "NO CONFLICTS", message = "No known input conflicts detected." }
    else
      for _, conflict in ipairs(conflicts) do
        items[#items + 1] = {
          label = clip(conflict.label), right = "!", message = conflict.message,
        }
      end
    end
    items[#items + 1] = { label = "BACK", _back = true }
    return listMenu(game, "INPUT WARNINGS", items, {
      footer = "A: DETAILS  B: BACK",
      onChoose = function(item, menu)
        if item and item._back then close(menu)
        elseif item and item.message then showMessage(game, item.message) end
      end,
    })
  end

  factories[Menu.STATUS_ID] = function(game)
    local items = integrationItems(game)
    return listMenu(game, "MOD STATUS", items, {
      footer = "THOR DEFAULT: R2/L2",
      onChoose = function(item, menu)
        if not item then return end
        if item._back then close(menu)
        elseif item._warnings then Menu:push(game, Menu.WARNINGS_ID)
        elseif item._note then
          showMessage(game,
            "AYN Thor defaults are R2 aim and L2 cancel, with Catch Only and "
            .. "manual throwing enabled. R1/L1 remain emulator-speed buttons. "
            .. "The adapter reads the Thor trigger axes and claims R2/L2 only "
            .. "for eligible free-roam throwing; SELECT chords still pass to "
            .. "the engine.")
        end
      end,
    })
  end

  local function buildPage(game, pageId)
    local pageRows = Settings.pages[pageId] or {}
    local items = {}
    if pageId == "debug" then
      local conflicts = Settings:inputConflicts(game)
      items[#items + 1] = {
        label = "INPUT STATUS", right = #conflicts > 0 and "WARN" or "OK",
        _status = true,
      }
    end
    for _, row in ipairs(pageRows) do items[#items + 1] = optionItem(game, row) end
    items[#items + 1] = { label = "RESTORE PAGE", _reset = true }
    items[#items + 1] = { label = "BACK", _back = true }
    local pageLabel = pageId
    for _, page in ipairs(PAGE_DEFS) do
      if page.id == pageId then pageLabel = page.label break end
    end
    return listMenu(game, pageLabel, items, {
      footer = "A: CHANGE  B: BACK",
      onChoose = function(item, menu)
        if not item then return end
        if item._back then
          close(menu)
        elseif item._status then
          Menu:push(game, Menu.STATUS_ID)
        elseif item._reset then
          openConfirm(game, "RESTORE PAGE", "ONLY THIS PAGE", function()
            Settings:resetPage(pageId, game)
            refreshItems(items)
          end)
        elseif item._activate then
          item._activate()
        end
      end,
    })
  end

  local function pageSummary(pageId, game)
    if pageId == "battle" then
      return Settings:valueLabel("lets_go_mode", nil, true)
    elseif pageId == "overworld" then
      return Settings:get("manual_throw") and "ON" or "OFF"
    elseif pageId == "target_hud" then
      return Settings:valueLabel("overworld_aim_assist", nil, true)
    elseif pageId == "wheel" then
      return Settings:get("ball_wheel") and "ON" or "OFF"
    elseif pageId == "wilds" then
      return Settings:valueLabel("wilds_integration", nil, true)
    elseif pageId == "camera" then
      return Settings:valueLabel("camera_aim_mode", nil, true)
    elseif pageId == "controls" then
      local n = #Settings:inputConflicts(game)
      return n > 0 and "WARN" or "OK"
    elseif pageId == "preset" then
      return Settings:valueLabel("throw_preset", nil, true)
    elseif pageId == "debug" then
      return (Settings:get("debug_throw") or Settings:get("debug_battle_throw"))
        and "ON" or "OFF"
    end
    return "OPEN"
  end

  factories[Menu.ROOT_ID] = function(game)
    Settings:bindGame(game)
    local items = {}
    for _, page in ipairs(PAGE_DEFS) do
      local thisPage = page
      items[#items + 1] = {
        label = clip(thisPage.label),
        right = clip(pageSummary(thisPage.id, game), 9),
        page = thisPage.id,
      }
    end
    items[#items + 1] = { label = "RESET BATTLE", _action = "battle" }
    items[#items + 1] = { label = "RESET WORLD", _action = "overworld" }
    items[#items + 1] = { label = "RESET CONTROLS", _action = "controls" }
    items[#items + 1] = { label = "RESTORE ALL", _action = "all" }
    items[#items + 1] = { label = "BACK", _back = true }
    return listMenu(game, "CATCH & THROW", items, {
      footer = "A: OPEN  B: BACK",
      onChoose = function(item, menu)
        if not item then return end
        if item.page then
          Menu:push(game, Menu.PAGE_IDS[item.page])
        elseif item._back then
          close(menu)
        elseif item._action then
          local label = item.label
          openConfirm(game, label, "THIS MOD ONLY", function()
            if item._action == "battle" then Settings:resetBattle(game)
            elseif item._action == "overworld" then Settings:resetOverworld(game)
            elseif item._action == "controls" then Settings:resetControls(game)
            elseif item._action == "all" then Settings:resetAll(game) end
            for _, rootItem in ipairs(items) do
              if rootItem.page then
                rootItem.right = clip(pageSummary(rootItem.page, game), 9)
              end
            end
          end)
        end
      end,
    })
  end

  for _, page in ipairs(PAGE_DEFS) do
    local pageId = page.id
    factories[Menu.PAGE_IDS[pageId]] = function(game)
      return buildPage(game, pageId)
    end
  end

  local registry = mod and mod.content and mod.content.screens
  local uiReady = mod and mod.ui and mod.ui.ListMenu
  if registry and type(registry.register) == "function" and uiReady then
    for id, factory in pairs(factories) do
      registry:register(id, { new = factory })
    end
    Menu.available = true
  else
    Menu.available = false
    if mod and mod.log and type(mod.log.warn) == "function" then
      pcall(mod.log.warn, mod.log,
        "organized settings menu unavailable; use Mod Manager settings")
    end
  end

  if Menu.available and mod and mod.hooks and type(mod.hooks.wrap) == "function" then
    mod.hooks:wrap("ui.options.rows", function(next, game, rows)
      Settings:bindGame(game)
      local out = next(game, rows)
      if type(out) ~= "table" then return out end
      for i = #out, 1, -1 do
        if out[i].id == "LETS_GO_CATCH_THROW:settings.open" then
          table.remove(out, i)
        end
      end
      local entry = {
        id = "LETS_GO_CATCH_THROW:settings.open",
        label = "CATCH & THROW",
        value = function()
          return Settings:hasInputConflicts(game) and "WARN" or "OPEN"
        end,
        activate = function(g) Menu:push(g, Menu.ROOT_ID) end,
      }
      -- Put the mod's only top-level row first so the warning and menu remain
      -- visible without scrolling through the engine's long options list.
      table.insert(out, 1, entry)
      return out
    end, 40)
  end

  shared.settings_menu = Menu
  return Menu
end
