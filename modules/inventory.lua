-- Live Bag adapter for throw selection and transactional spending.
-- SAFARI_BALL is deliberately virtual: Safari uses save.safari.balls and
-- must never create, remove, or refund an ordinary Bag stack.

return function(mod, shared)
  local api = {}
  local LAST_USED_KEY = "last_used_ball"
  local bagModule, bagChecked
  local catchingModule, catchingChecked

  local function positiveInteger(value, fallback)
    value = math.floor(tonumber(value) or fallback or 1)
    if value < 1 then return nil end
    return value
  end

  local function gameOf(game)
    if type(game) == "table" and game.save then return game end
    if type(shared.game) == "table" and shared.game.save then return shared.game end
    if type(shared.game) == "function" then
      local ok, current = pcall(shared.game)
      if ok and type(current) == "table" and current.save then return current end
    end
    local ok, world = pcall(function() return mod.world end)
    return ok and world and world.game or nil
  end

  local function bag()
    if not bagChecked then
      bagChecked = true
      local ok, value = pcall(require, "src.inventory.Bag")
      if ok and type(value) == "table" then bagModule = value end
    end
    return bagModule
  end

  local function stockBalls()
    if not catchingChecked then
      catchingChecked = true
      local ok, value = pcall(require, "src.battle.Catching")
      if ok and type(value) == "table" then catchingModule = value end
    end
    return catchingModule and catchingModule.BALLS or nil
  end

  local function saveOf(game)
    game = gameOf(game)
    local save = game and game.save
    if save and type(save.inventory) ~= "table" then save.inventory = {} end
    return save, game
  end

  local function safariState(game, battle)
    if type(battle) == "table" and type(battle.safari) == "table" then
      return battle.safari
    end
    game = gameOf(game)
    local state = game and game.save and game.save.safari
    if type(state) == "table" and type(state.balls) == "number" then return state end
    return nil
  end

  local function ballMap(game)
    game = gameOf(game)
    local merged = game and game.data and game.data.balls
    if type(merged) == "table" then return merged end
    return stockBalls() or {}
  end

  local function ballDef(game, id)
    return ballMap(game)[id]
  end

  local function fallbackRemove(save, id, qty)
    local current = (save.inventory and save.inventory[id]) or 0
    if current < qty then return false end
    local left = current - qty
    save.inventory[id] = left > 0 and left or nil
    if left <= 0 and type(save.bagOrder) == "table" then
      for i = #save.bagOrder, 1, -1 do
        if save.bagOrder[i] == id then table.remove(save.bagOrder, i) end
      end
    end
    return true
  end

  local function fallbackAdd(save, id, qty)
    local current = (save.inventory and save.inventory[id]) or 0
    if current + qty > 99 then return false end
    save.inventory[id] = current + qty
    if current == 0 then
      save.bagOrder = save.bagOrder or {}
      save.bagOrder[#save.bagOrder + 1] = id
    end
    return true
  end

  local function removeBag(game, id, qty)
    local save = game and game.save
    if not save or type(save.inventory) ~= "table" then return false, "no save" end
    if (save.inventory[id] or 0) < qty then return false, "not enough balls" end
    local impl = bag()
    if impl and type(impl.remove) == "function" then
      local ok, result = pcall(impl.remove, save, id, qty)
      if not ok then return false, tostring(result) end
      -- Gen1Recomp 0.1.75 Bag.remove has no success return.
      return result ~= false
    end
    return fallbackRemove(save, id, qty)
  end

  local function addBag(game, id, qty)
    local save = game and game.save
    if not save or type(save.inventory) ~= "table" then return false, "no save" end
    local impl = bag()
    if impl and type(impl.add) == "function" then
      local ok, result = pcall(impl.add, save, id, qty, game.data)
      if not ok then return false, tostring(result) end
      return result ~= false, result == false and "bag full" or nil
    end
    local ok = fallbackAdd(save, id, qty)
    return ok, ok and nil or "bag full"
  end

  function api.isBall(a, b, c)
    local game, id
    if a == api then game, id = b, c else game, id = a, b end
    return type(id) == "string" and ballDef(game, id) ~= nil
  end

  function api.count(a, b, c, d)
    local game, id, battle
    if a == api then game, id, battle = b, c, d else game, id, battle = a, b, c end
    if id == "SAFARI_BALL" then
      local state = safariState(game, battle)
      return state and math.max(0, math.floor(state.balls or 0)) or 0
    end
    local save = saveOf(game)
    return save and math.max(0, math.floor(save.inventory[id] or 0)) or 0
  end

  local function orderIndex(save)
    local result = {}
    local order
    local impl = bag()
    if impl and type(impl.order) == "function" then
      local ok, value = pcall(impl.order, save)
      if ok and type(value) == "table" then order = value end
    end
    order = order or save.bagOrder or {}
    for i, id in ipairs(order) do result[id] = i end
    return result
  end

  function api.definitions(a, b, c)
    local game, battle
    if a == api then game, battle = b, c else game, battle = a, b end
    game = gameOf(game)
    local save = game and game.save
    if not save then return {} end
    local balls = ballMap(game)
    local items = game.data and game.data.items or {}
    local positions = orderIndex(save)
    local list = {}
    for id, def in pairs(balls) do
      local count = api.count(game, id, battle)
      list[#list + 1] = {
        id = id,
        def = def,
        name = (items[id] and items[id].name) or id,
        count = count,
        safari = id == "SAFARI_BALL",
        order = positions[id],
      }
    end
    table.sort(list, function(left, right)
      if left.order and right.order then return left.order < right.order end
      if left.order then return true end
      if right.order then return false end
      return tostring(left.id) < tostring(right.id)
    end)
    return list
  end

  function api.available(a, b, c)
    local game, battle
    if a == api then game, battle = b, c else game, battle = a, b end
    local safari = safariState(game, battle)
    local list = {}
    for _, entry in ipairs(api.definitions(game, battle)) do
      -- A live Safari session exposes only its virtual ball counter; outside
      -- Safari, SAFARI_BALL is never treated as a Bag item.
      local eligible = safari and entry.id == "SAFARI_BALL"
        or (not safari and entry.id ~= "SAFARI_BALL")
      if eligible and entry.count > 0 then list[#list + 1] = entry end
    end
    return list
  end

  function api.lastUsed(a)
    local _ = a -- supports both dot and colon calls
    if not (mod.save and type(mod.save.get) == "function") then return nil end
    local ok, value = pcall(mod.save.get, mod.save, LAST_USED_KEY, nil)
    return ok and type(value) == "string" and value or nil
  end

  function api.remember(a, b)
    local id = a == api and b or a
    if type(id) ~= "string" or id == "" then return false, "invalid ball id" end
    if not (mod.save and type(mod.save.set) == "function") then
      return false, "save API unavailable"
    end
    local ok, err = pcall(mod.save.set, mod.save, LAST_USED_KEY, id)
    if not ok then return false, tostring(err) end
    return true
  end

  function api.select(a, b, c, d)
    local game, opts, battle
    if a == api then game, opts, battle = b, c, d else game, opts, battle = a, b, c end
    if type(opts) == "string" then opts = { strategy = opts } end
    opts = opts or {}
    battle = battle or opts.battle
    local list = api.available(game, battle)
    if #list == 0 then return nil, "no balls" end

    local byId = {}
    for _, entry in ipairs(list) do byId[entry.id] = entry end
    if opts.preferred and byId[opts.preferred] then
      return opts.preferred, byId[opts.preferred]
    end

    local strategy = string.upper(opts.strategy or "LAST_USED")
    if strategy == "LAST_USED" or strategy == "AUTO" then
      local last = api.lastUsed()
      if last and byId[last] then return last, byId[last] end
    end
    if strategy == "BEST" or strategy == "BEST_AVAILABLE" then
      local best = list[1]
      local function score(entry)
        if entry.def and entry.def.autoCatch then return -math.huge end
        return tonumber(entry.def and entry.def.randMax) or math.huge
      end
      for i = 2, #list do
        if score(list[i]) < score(best) then best = list[i] end
      end
      return best.id, best
    end
    return list[1].id, list[1]
  end

  -- Settings-facing selector.  This remains a plain-function-compatible
  -- alias because the battle/overworld adapters intentionally call it as
  -- choose(game, preference), not as a method.
  function api.choose(a, b, c, d)
    local game, preference, battle
    if a == api then game, preference, battle = b, c, d
    else game, preference, battle = a, b, c end
    preference = string.lower(tostring(preference or "last_used"))

    if preference == "preferred" then
      local preferred = "auto"
      local settings = shared.settings
      if type(settings) == "table" and type(settings.get) == "function" then
        local ok, value = pcall(settings.get, settings, "default_ball", "auto")
        if ok and type(value) == "string" then preferred = value end
      end
      preference = string.lower(preferred)
    end

    if preference == "best_available" or preference == "best" then
      return api.select(game, { strategy = "BEST_AVAILABLE" }, battle)
    end
    if preference == "last_used" or preference == "last"
       or preference == "auto" or preference == "manual" then
      return api.select(game, { strategy = preference == "last_used"
        and "LAST_USED" or "AUTO" }, battle)
    end

    local explicit = string.upper(preference)
    local selected = api.select(game, { preferred = explicit, strategy = "AUTO" }, battle)
    return selected
  end

  local function commitDirect(game, id, qty, battle)
    game = gameOf(game)
    qty = positiveInteger(qty, 1)
    if not qty then return false, "invalid quantity" end
    if not ballDef(game, id) then return false, "unknown ball" end
    if id == "SAFARI_BALL" then
      local state = safariState(game, battle)
      if not state then return false, "no Safari session" end
      if (state.balls or 0) < qty then return false, "not enough Safari Balls" end
      state.balls = state.balls - qty
      api.remember(id)
      return true
    end
    local ok, err = removeBag(game, id, qty)
    if ok then api.remember(id) end
    return ok, err
  end

  function api.commit(a, b, c, d, e)
    -- Token form: inventory:commit(token)
    local token = a == api and b or a
    if type(token) == "table" and token._inventoryToken then
      if token.cancelled then return false, "reservation cancelled" end
      if token.committed then return true end
      if token.preconsumed then
        token.committed = true
        api.remember(token.id)
        return true
      end
      local ok, err = commitDirect(token.game, token.id, token.qty, token.battle)
      if ok then token.committed = true end
      return ok, err
    end

    local game, id, qty, battle
    if a == api then game, id, qty, battle = b, c, d, e
    else game, id, qty, battle = a, b, c, d end
    return commitDirect(game, id, qty, battle)
  end

  local function refundDirect(game, id, qty, battle)
    game = gameOf(game)
    qty = positiveInteger(qty, 1)
    if not qty then return false, "invalid quantity" end
    if not ballDef(game, id) then return false, "unknown ball" end
    if id == "SAFARI_BALL" then
      local state = safariState(game, battle)
      if not state then return false, "no Safari session" end
      state.balls = math.min(255, math.max(0, state.balls or 0) + qty)
      return true
    end
    return addBag(game, id, qty)
  end

  function api.refund(a, b, c, d, e)
    local token = a == api and b or a
    if type(token) == "table" and token._inventoryToken then
      if token.refunded then return true end
      -- An uncommitted reservation never removed anything unless the native
      -- BagMenu consumed it before our interceptor (preconsumed=true).
      if token.committed or token.preconsumed then
        local ok, err = refundDirect(token.game, token.id, token.qty, token.battle)
        if not ok then return false, err end
      end
      token.refunded, token.cancelled = true, true
      return true
    end
    local game, id, qty, battle
    if a == api then game, id, qty, battle = b, c, d, e
    else game, id, qty, battle = a, b, c, d end
    return refundDirect(game, id, qty, battle)
  end

  function api.reserve(a, b, c, d, e, f)
    local game, id, qty, battle, opts
    if a == api then game, id, qty, battle, opts = b, c, d, e, f
    else game, id, qty, battle, opts = a, b, c, d, e end
    opts = opts or {}
    game = gameOf(game)
    qty = positiveInteger(qty, 1)
    if not qty then return nil, "invalid quantity" end
    if not ballDef(game, id) then return nil, "unknown ball" end
    if not opts.preconsumed and api.count(game, id, battle) < qty then
      return nil, "not enough balls"
    end
    return {
      _inventoryToken = true,
      game = game,
      id = id,
      qty = qty,
      battle = battle,
      preconsumed = opts.preconsumed == true,
      committed = false,
      refunded = false,
      cancelled = false,
    }
  end

  function api.cancel(a, b)
    local token = a == api and b or a
    if type(token) ~= "table" or not token._inventoryToken then
      return false, "invalid reservation"
    end
    return api.refund(token)
  end
  api.refundPreconsumed = api.refund

  shared.inventory = api
  return api
end
