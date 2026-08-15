-- Let's Go Catch & Throw
--
-- Independently authored Gen1Recomp mod. Dramatic Shape 1.8.0 was studied
-- only as a behavioral reference; no Dramatic Shape source or assets are
-- included here.

local MODULES = {
  { "modules/settings.lua", true },
  { "modules/trajectory.lua", true },
  { "modules/inventory.lua", true },
  { "modules/camera.lua", true },
  { "modules/wilds.lua", false },
  { "modules/battle.lua", true },
  { "modules/overworld.lua", true },
  { "modules/renderer.lua", true },
  { "modules/settings_menu.lua", false },
}

local function traceback(err)
  if debug and debug.traceback then return debug.traceback(tostring(err), 2) end
  return tostring(err)
end

local function compileModule(mod, relative)
  local source, readErr = mod:read(relative)
  if type(source) ~= "string" then
    return nil, readErr or ("could not read " .. relative)
  end
  local compile = loadstring or load
  local chunk, loadErr = compile(source, "@" .. mod.path .. "/" .. relative)
  if not chunk then return nil, loadErr end
  if setfenv and getfenv then setfenv(chunk, getfenv(1)) end
  local ok, result = xpcall(chunk, traceback)
  if not ok then return nil, result end
  if type(result) ~= "function" then
    return nil, relative .. " did not return an installer"
  end
  return result
end

local function unwind(mod, shared)
  for i = #shared.cleanups, 1, -1 do
    local ok, err = pcall(shared.cleanups[i])
    if not ok then mod.log:warn("rollback cleanup failed: %s", tostring(err)) end
  end
  shared.cleanups = {}
  shared.state.battle = nil
  shared.state.overworld = nil
end

return function(mod)
  local already = mod.exports.status
  if type(already) == "table" and already.installed then return already end

  local shared = {
    mod = mod,
    state = {
      battle = nil,
      overworld = nil,
      conflicts = {},
      notices = {},
    },
    cleanups = {},
    VERSION = "0.2.2",
  }

  local status = {
    installed = true,
    version = shared.VERSION,
    state = shared.state,
  }
  mod.exports.status = status
  mod.exports.api = {
    version = 1,
    isAiming = function()
      return shared.state.battle ~= nil or shared.state.overworld ~= nil
    end,
  }

  for _, spec in ipairs(MODULES) do
    local relative, required = spec[1], spec[2]
    local install, loadErr = compileModule(mod, relative)
    if not install then
      if required then
        unwind(mod, shared)
        status.installed = false
        error(relative .. ": " .. tostring(loadErr), 0)
      end
      mod.log:warn("%s disabled: %s", relative, tostring(loadErr))
    else
      local ok, result = xpcall(function() return install(mod, shared) end,
                                traceback)
      if not ok then
        if required then
          unwind(mod, shared)
          status.installed = false
          error(relative .. ": " .. tostring(result), 0)
        end
        mod.log:warn("%s disabled: %s", relative, tostring(result))
      elseif type(result) == "function" then
        shared.cleanups[#shared.cleanups + 1] = result
      elseif type(result) == "table" and type(result.cleanup) == "function" then
        shared.cleanups[#shared.cleanups + 1] = result.cleanup
      end
    end
  end

  function status.cleanup()
    if not status.installed then return end
    status.installed = false
    unwind(mod, shared)
  end

  return status
end
