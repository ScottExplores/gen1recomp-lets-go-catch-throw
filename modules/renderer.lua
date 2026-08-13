-- Procedural battle/world ball, trajectory, target, status and debug HUD.
--
-- This module draws only through the public render.hud hook. Dramaless's
-- exported camera projection is used read-only when present, so Kanto First
-- Person keeps ownership of terrain, ceilings, canopy, weather and camera.
-- The HUD path is deliberately a compatibility fallback: Dramaless 1.6.4
-- exposes projection but no supported companion-depth draw callback, so the
-- mod does not monkey-patch or replace its renderer.

local unpack = table.unpack or unpack

local BALL_COLORS = {
  POKE_BALL = { 0.96, 0.20, 0.20 },
  GREAT_BALL = { 0.18, 0.45, 0.95 },
  ULTRA_BALL = { 0.12, 0.12, 0.15 },
  MASTER_BALL = { 0.67, 0.28, 0.78 },
  SAFARI_BALL = { 0.24, 0.55, 0.22 },
}

local function pack(...)
  return { n = select("#", ...), ... }
end

local function clamp(value, low, high)
  value = tonumber(value) or low
  if value < low then return low end
  if value > high then return high end
  return value
end

return function(mod, shared)
  local feature = { installed = true }
  shared.renderer = feature
  local unsubscribers = {}

  local function setting(key, fallback)
    local settings = shared.settings
    if not (settings and type(settings.get) == "function") then return fallback end
    local ok, value = pcall(settings.get, settings, key)
    if ok and value ~= nil then return value end
    return fallback
  end

  local function fontDraw(text, x, y)
    local ok, Font = pcall(require, "src.render.Font")
    if ok and Font and type(Font.draw) == "function" then
      pcall(Font.draw, tostring(text), math.floor(x), math.floor(y))
    elseif love.graphics.print then
      love.graphics.print(tostring(text), math.floor(x), math.floor(y))
    end
  end

  local function metrics(viewport)
    local width = tonumber(viewport and viewport.width)
    local height = tonumber(viewport and viewport.height)
    if not width and love.graphics.getDimensions then
      width, height = love.graphics.getDimensions()
    end
    width, height = width or 160, height or 144
    local gx = tonumber(viewport and viewport.gameX) or 0
    local gy = tonumber(viewport and viewport.gameY) or 0
    local gw = tonumber(viewport and viewport.gameWidth) or width
    local gh = tonumber(viewport and viewport.gameHeight) or height
    return width, height, gx, gy, gw, gh
  end

  local function mapNormalized(p, gx, gy, gw, gh)
    if type(p) ~= "table" then return nil end
    return gx + clamp(p.x, 0, 1) * gw, gy + clamp(p.y, 0, 1) * gh
  end

  local function projectWorld(game, point, gx, gy, gw, gh)
    local camera = shared.camera
    if camera and type(camera.project) == "function" then
      local ok, x, y, projectScale = pcall(camera.project, camera, point, game,
                                           game and game.overworld)
      if ok and type(x) == "number" and type(y) == "number" then
        -- Dramaless projection is already in its window-sized scene canvas.
        local status = camera.status and camera:status(game, game.overworld)
        if status and status.dramaless and status.dramaless.compatible then
          local scale = tonumber(projectScale) or 1
          if status.mode == "1ST"
             and tostring(setting("first_person_fov_compensation", "auto"))
                 == "off" then
            scale = 1
          end
          return x, y, clamp(scale, 0.45, 2.25)
        end
        -- Core fallback answers world-canvas pixels; map around the centred
        -- viewport using the renderer's reported scale.
        local renderer = game and game.renderer
        local canvas = renderer and renderer.worldCanvas
        local cw = canvas and canvas.getWidth and canvas:getWidth() or 160
        local ch = canvas and canvas.getHeight and canvas:getHeight() or 144
        return gx + x / cw * gw, gy + y / ch * gh, 1
      end
    end
    return nil
  end

  local function ballRadius(session, scale)
    local option = tostring(setting("ball_scale", "normal"))
    local factor = option == "small" and 0.78 or option == "large" and 1.34 or 1
    if session.context == "battle" then factor = 1.2 end
    return math.max(4, 5.5 * factor * math.max(0.65, scale or 1))
  end

  local function drawBall(x, y, radius, id, alpha)
    local lg = love.graphics
    local color = BALL_COLORS[id] or BALL_COLORS.POKE_BALL
    alpha = alpha or 1
    lg.setColor(0, 0, 0, 0.75 * alpha)
    lg.circle("fill", x + 1.5, y + 2, radius + 1)
    lg.setColor(1, 1, 1, alpha)
    lg.circle("fill", x, y, radius)
    lg.setColor(color[1], color[2], color[3], alpha)
    lg.arc("fill", x, y, radius, math.pi, math.pi * 2)
    lg.setColor(0.08, 0.08, 0.09, alpha)
    lg.rectangle("fill", x - radius, y - 1, radius * 2, 2)
    lg.circle("fill", x, y, radius * 0.30)
    lg.setColor(0.92, 0.92, 0.92, alpha)
    lg.circle("fill", x, y, radius * 0.17)
    lg.setColor(1, 1, 1, 1)
  end

  local function drawPolyline(points, width, color, style)
    local lg = love.graphics
    if #points < 2 then return end
    style = style or "solid"
    lg.setColor(color[1], color[2], color[3], color[4] or 1)
    lg.setLineWidth(width)
    if style == "dots" then
      for index = 1, #points, 2 do
        local point = points[index]
        lg.circle("fill", point[1], point[2], math.max(1.2, width * 0.8))
      end
    elseif style == "segments" then
      for index = 1, #points - 1, 2 do
        local first, second = points[index], points[index + 1]
        lg.line(first[1], first[2], second[1], second[2])
      end
    else
      local coords = {}
      for _, point in ipairs(points) do
        coords[#coords + 1] = point[1]
        coords[#coords + 1] = point[2]
      end
      if #coords >= 4 then lg.line(coords) end
    end
    lg.setLineWidth(1)
    lg.setColor(1, 1, 1, 1)
  end

  local function battlePoint(point, gx, gy, gw, gh)
    return mapNormalized(point, gx, gy, gw, gh)
  end

  local function worldPoint(game, point, gx, gy, gw, gh)
    return projectWorld(game, point, gx, gy, gw, gh)
  end

  local function projectedList(game, session, source, gx, gy, gw, gh)
    local list = {}
    for _, point in ipairs(source or {}) do
      local x, y
      if session.context == "battle" then
        x, y = battlePoint(point, gx, gy, gw, gh)
      else
        x, y = worldPoint(game, point, gx, gy, gw, gh)
      end
      if x and y then list[#list + 1] = { x, y } end
    end
    return list
  end

  local function drawTrajectory(game, session, gx, gy, gw, gh)
    if session.context == "battle" and setting("battle_throw_arc", true) ~= true then
      return
    end
    local style = session.context == "battle" and "segments"
      or tostring(setting("trajectory_line", "dots"))
    if style == "off" then return end
    local source = session.fullTrajectoryPoints or session.trajectoryPoints
      or session.trajectory
    local points = projectedList(game, session, source, gx, gy, gw, gh)
    local thicknessName = tostring(setting("trajectory_thickness", "normal"))
    local width = thicknessName == "thin" and 1.5
      or thicknessName == "thick" and 4 or 2.5
    local color = session.target and { 0.35, 1, 0.55, 0.86 }
      or { 1, 0.86, 0.25, 0.84 }
    drawPolyline(points, width, color, style)
  end

  local function drawTrail(game, session, gx, gy, gw, gh)
    if not session.trail or #session.trail == 0 then return end
    local points = projectedList(game, session, session.trail, gx, gy, gw, gh)
    drawPolyline(points, 2, { 0.6, 0.88, 1, 0.58 }, "solid")
  end

  local function drawTarget(game, session, gx, gy, gw, gh)
    local target = session.target
    if not target then return end
    local style = tostring(setting("target_highlight", "both"))
    if style == "off" then return end
    local x, y = worldPoint(game, target.position, gx, gy, gw, gh)
    if not x then return end
    local pulse = 1 + 0.12 * math.sin((session.age or 0) * 8)
    if style == "outline" or style == "both" then
      love.graphics.setColor(0.25, 1, 0.48, 0.95)
      love.graphics.setLineWidth(2)
      love.graphics.circle("line", x, y, 10 * pulse)
      love.graphics.setLineWidth(1)
    end
    if style == "icon" or style == "both" then
      love.graphics.setColor(1, 0.9, 0.2, 1)
      love.graphics.polygon("fill", x, y - 14, x - 4, y - 20, x + 4, y - 20)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function drawRing(session, gx, gy, gw, gh)
    if session.context ~= "battle" or not session.ringRadius then return end
    local x = gx + 0.5 * gw
    local y = gy + 0.36 * gh
    local radius = session.ringRadius * math.min(gw, gh) * 0.18
    local color = session.ringRadius <= 0.40 and { 0.2, 1, 0.35 }
      or session.ringRadius <= 0.70 and { 1, 0.78, 0.15 }
      or { 1, 0.35, 0.20 }
    love.graphics.setColor(color[1], color[2], color[3], 0.92)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", x, y, radius)
    if session.catchRing == "full" then
      love.graphics.setColor(1, 1, 1, 0.48)
      love.graphics.setLineWidth(1.5)
      love.graphics.circle("line", x, y, math.min(gw, gh) * 0.18)
      love.graphics.line(x - 4, y, x + 4, y)
      love.graphics.line(x, y - 4, x, y + 4)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function drawImpact(game, session, gx, gy, gw, gh)
    local show
    if session.context == "battle" then
      show = session.impact and session.impactEffect ~= false
    elseif session.phase == "impact" then
      show = session.hit and setting("overworld_impact_effect", true) == true
        or (not session.hit and setting("miss_effect", true) == true)
    end
    if not show then return end

    local x, y
    if session.context == "battle" then
      x, y = battlePoint(session.position or session.targetPoint,
                         gx, gy, gw, gh)
    else
      x, y = worldPoint(game, session.position, gx, gy, gw, gh)
    end
    if not x or not y then return end

    local elapsed = session.context == "battle"
      and (tonumber(session.timer) or 0)
      or (tonumber(session.impactTimer) or 0)
    local progress = clamp(elapsed / 0.42, 0, 1)
    local radius = 5 + progress * 18
    local alpha = 0.90 * (1 - progress)
    local color = session.hit == false and { 0.72, 0.82, 1 }
      or { 1, 0.86, 0.25 }
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    love.graphics.setLineWidth(2.5)
    love.graphics.circle("line", x, y, radius)
    love.graphics.circle("line", x, y, radius * 0.55)
    for index = 0, 5 do
      local angle = index * math.pi / 3
      local inner = radius * 0.65
      local outer = radius * 1.15
      love.graphics.line(x + math.cos(angle) * inner,
        y + math.sin(angle) * inner, x + math.cos(angle) * outer,
        y + math.sin(angle) * outer)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function drawWheel(session, width, height, gx, gy, gw, gh)
    local wheel = session.wheel
    if not (wheel and type(wheel.items) == "table" and #wheel.items > 0) then
      return
    end
    local items = wheel.items
    local style = tostring(wheel.style or setting("ball_wheel_style", "horizontal"))

    if style == "list" then
      local rowH = 18
      local boxW = math.min(width - 16, 148)
      local boxH = #items * rowH + 8
      local bx = math.max(8, gx + gw - boxW - 8)
      local by = math.max(8, math.min(height - boxH - 8, gy + (gh - boxH) / 2))
      love.graphics.setColor(0, 0, 0, 0.84)
      love.graphics.rectangle("fill", bx, by, boxW, boxH)
      for index, item in ipairs(items) do
        local cy = by + 4 + (index - 0.5) * rowH
        if index == wheel.index then
          love.graphics.setColor(1, 0.88, 0.2, 0.45)
          love.graphics.rectangle("fill", bx + 2, cy - rowH / 2,
                                  boxW - 4, rowH)
        end
        drawBall(bx + 11, cy, 5, item.id)
        fontDraw((tostring(item.id):gsub("_", " ")) .. " x" ..
          tostring(item.count), bx + 21, cy - 5)
      end
      return
    end

    if style == "radial" then
      local cx, cy = gx + gw * 0.5, gy + gh * 0.58
      local radius = math.min(gw, gh) * 0.20
      love.graphics.setColor(0, 0, 0, 0.72)
      love.graphics.circle("fill", cx, cy, radius + 16)
      for index, item in ipairs(items) do
        local angle = -math.pi / 2 + (index - 1) * math.pi * 2 / #items
        local x, y = cx + math.cos(angle) * radius,
                     cy + math.sin(angle) * radius
        if index == wheel.index then
          love.graphics.setColor(1, 0.88, 0.2, 0.55)
          love.graphics.circle("fill", x, y, 12)
        end
        drawBall(x, y, 6, item.id)
        fontDraw("x" .. tostring(item.count), x + 7, y - 5)
      end
      return
    end

    local cy = math.min(height - 26, gy + gh - 24)
    local boxW = math.min(width - 16, #items * 54)
    local bx = (width - boxW) / 2
    love.graphics.setColor(0, 0, 0, 0.82)
    love.graphics.rectangle("fill", bx, cy - 8, boxW, 24)
    local slot = boxW / #items
    for index, item in ipairs(items) do
      local cx = bx + (index - 0.5) * slot
      if index == wheel.index then
        love.graphics.setColor(1, 0.88, 0.2, 0.55)
        love.graphics.rectangle("fill", bx + (index - 1) * slot, cy - 7,
                                slot, 22)
      end
      drawBall(cx, cy - 1, 5, item.id)
      fontDraw("x" .. tostring(item.count), cx + 7, cy - 5)
    end
  end

  local function drawStatus(game, session, width, height, gx, gy, gw, gh)
    local x, y = gx + 7, gy + 7
    local count = session.inventoryCount or 0
    if session.statusText then
      love.graphics.setColor(0, 0, 0, 0.76)
      love.graphics.rectangle("fill", x - 4, y - 3,
                              math.min(width - x - 3, 180), 17)
      love.graphics.setColor(1, 1, 1, 1)
      fontDraw(session.statusText, x, y)
      y = y + 14
    elseif setting("show_ball_count", true) == true
       or session.context == "battle" then
      love.graphics.setColor(0, 0, 0, 0.70)
      love.graphics.rectangle("fill", x - 4, y - 3, 99, 17)
      love.graphics.setColor(1, 1, 1, 1)
      fontDraw((tostring(session.ballId or "NO BALL"):gsub("_", " ")) ..
        " x" .. count, x, y)
      y = y + 14
    end
    if session.context == "overworld" and setting("show_range_number", true) == true then
      fontDraw("RANGE " .. tostring(session.stage) .. " BLOCK" ..
        (session.stage == 1 and "" or "S"), x, y)
      y = y + 11
    end
    if session.target then
      if setting("show_target_name", true) == true then
        local def = game and game.data and game.data.pokemon
          and game.data.pokemon[session.target.species]
        fontDraw("TARGET " .. tostring(def and def.name or session.target.species), x, y)
        y = y + 11
      end
      if setting("show_target_level", true) == true then
        fontDraw("LEVEL " .. tostring(session.target.level or "?"), x, y)
        y = y + 11
      end
      local chance = tostring(setting("show_catch_chance", "simple"))
      if chance == "percent" and session.catchChance then
        fontDraw("CATCH ~" .. tostring(session.catchChance) .. "%", x, y)
      elseif chance == "simple" and session.catchChance then
        local word = session.catchChance >= 65 and "HIGH"
          or session.catchChance >= 30 and "MED" or "LOW"
        fontDraw("CATCH " .. word, x, y)
      end
    end

    drawWheel(session, width, height, gx, gy, gw, gh)
  end

  local function debugLines(game, session)
    local cameraStatus = shared.camera and shared.camera.status
      and shared.camera:status(game, game.overworld) or {}
    local wildStatus = shared.wilds and shared.wilds.status
      and shared.wilds:status() or {}
    local conflicts = shared.settings and shared.settings.inputConflicts
      and shared.settings:inputConflicts(game) or {}
    local o, d = session.origin or {}, session.direction or session.aim or {}
    return {
      "STATE " .. tostring(session.phase) .. " / " .. tostring(session.context),
      "BALL " .. tostring(session.ballId) .. " x" .. tostring(session.inventoryCount or 0),
      ("CHARGE %.2f  RANGE %s"):format(session.chargeTimer or 0,
        tostring(session.stage or "-")),
      ("DIST %.2f  POINTS %d"):format(session.actualDistance or 0,
        #(session.trajectoryPoints or {})),
      ("ORIGIN %.1f %.1f %.1f"):format(o.x or 0, o.y or 0, o.z or 0),
      ("DIRECTION %.2f %.2f %.2f"):format(d.x or 0, d.y or 0, d.z or 0),
      "CAMERA " .. tostring(session.cameraMode or cameraStatus.mode or "BATTLE"),
      "COLLISION " .. tostring(session.collisionState or "none"),
      "TARGET " .. tostring(session.target and session.target.id or "none"),
      "SPECIES " .. tostring(session.target and session.target.species or session.species or "-"),
      "LEVEL " .. tostring(session.target and session.target.level or session.level or "-"),
      "WILDS " .. tostring(wildStatus.available or wildStatus.installed or false),
      "DRAMALESS " .. tostring(cameraStatus.dramaless and cameraStatus.dramaless.compatible or false),
      "KANTO FP " .. tostring(cameraStatus.kantoFirstPerson and cameraStatus.kantoFirstPerson.compatible or false),
      "INPUT " .. tostring(session.lastInput or "-") .. " " ..
        tostring(session.inputActions and session.inputActions.aim or ""),
      "CONFLICTS " .. tostring(#conflicts),
      "ERROR " .. tostring(session.integrationError or session.wildsError or session.error or "none"),
    }
  end

  function feature:draw(game, viewport)
    local session = shared.state.battle or shared.state.overworld
    if not session or session.visible == false then return end
    if not (love and love.graphics and type(love.graphics.circle) == "function") then return end
    local width, height, gx, gy, gw, gh = metrics(viewport)
    local lg = love.graphics
    lg.push("all")
    local ok, err = xpcall(function()
      if session.context == "battle" and session.impact then
        local strength = tostring(setting("camera_shake", "low"))
        local amplitude = strength == "normal" and 3
          or strength == "low" and 1.5 or 0
        if amplitude > 0 then
          local clock = tonumber(session.timer) or tonumber(session.age) or 0
          lg.translate(math.sin(clock * 57) * amplitude,
                       math.cos(clock * 43) * amplitude * 0.7)
        end
      end
      drawTarget(game, session, gx, gy, gw, gh)
      if session.phase == "aim" then drawTrajectory(game, session, gx, gy, gw, gh) end
      drawTrail(game, session, gx, gy, gw, gh)
      drawRing(session, gx, gy, gw, gh)

      local x, y, scale
      if session.context == "battle" then
        x, y = battlePoint(session.position or session.origin, gx, gy, gw, gh)
        scale = 1
      else
        x, y, scale = worldPoint(game, session.position or session.origin,
                                 gx, gy, gw, gh)
      end
      if x and y and session.ballVisible ~= false then
        drawBall(x, y, ballRadius(session, scale), session.ballId)
      end
      drawImpact(game, session, gx, gy, gw, gh)

      drawStatus(game, session, width, height, gx, gy, gw, gh)
      if session.debug or setting(session.context == "battle"
          and "debug_battle_throw" or "debug_throw", false) == true then
        local lines = debugLines(game, session)
        local boxW, boxH = math.min(width - 8, 238), #lines * 10 + 8
        local bx, by = width - boxW - 4, 4
        lg.setColor(0, 0, 0, 0.80)
        lg.rectangle("fill", bx, by, boxW, boxH)
        lg.setColor(1, 1, 1, 1)
        for i, line in ipairs(lines) do fontDraw(line, bx + 4, by + 3 + (i - 1) * 10) end
      end
    end, function(message)
      return debug and debug.traceback and debug.traceback(tostring(message), 2)
        or tostring(message)
    end)
    lg.pop()
    if not ok and mod.log and type(mod.log.warn) == "function" then
      pcall(mod.log.warn, mod.log, "throw HUD disabled for frame: %s", tostring(err))
    end
  end

  if mod.hooks and type(mod.hooks.wrap) == "function" then
    unsubscribers[#unsubscribers + 1] = mod.hooks:wrap(
      "render.hud", function(nextFn, game, viewport)
        local result = pack(nextFn(game, viewport))
        feature:draw(game, viewport)
        return unpack(result, 1, result.n)
      end, 200)
  end

  function feature.cleanup()
    if not feature.installed then return end
    feature.installed = false
    for _, stop in ipairs(unsubscribers) do
      if type(stop) == "function" then pcall(stop) end
    end
    if shared.renderer == feature then shared.renderer = nil end
  end

  return feature
end
