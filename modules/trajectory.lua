-- Pure throw-path geometry.  World points are { x, y, z }, with y up and
-- one Gen1Recomp map cell (one "block" in the throw UI) equal to 16 pixels.

return function(_, shared)
  local api = {}

  api.BLOCK_SIZE = 16
  api.RANGE_STAGES = { 1, 2, 3, 4, 5 }
  api.MIN_STAGE = 1
  api.MAX_STAGE = 5

  local function number(v, fallback)
    v = tonumber(v)
    if v == nil or v ~= v then return fallback end
    return v
  end

  local function point(p)
    if type(p) ~= "table" then return nil end
    local x = number(p.x, number(p[1]))
    local y = number(p.y, number(p[2]))
    local z = number(p.z, number(p[3]))
    if x == nil or y == nil or z == nil then return nil end
    return { x = x, y = y, z = z }
  end

  local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
  end

  local function distance(a, b)
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  local function normalize(v)
    local p = point(v)
    if not p then return nil end
    local len = math.sqrt(p.x * p.x + p.y * p.y + p.z * p.z)
    if len <= 1e-9 then return nil end
    return { x = p.x / len, y = p.y / len, z = p.z / len }, len
  end

  function api.stage(a, b)
    local value = a == api and b or a
    value = math.floor(number(value, api.MIN_STAGE) + 0.5)
    return clamp(value, api.MIN_STAGE, api.MAX_STAGE)
  end

  function api.nextStage(a, b, c)
    local value, delta
    if a == api then value, delta = b, c else value, delta = a, b end
    value = api.stage(value)
    delta = math.floor(number(delta, 1))
    return ((value - api.MIN_STAGE + delta)
      % (api.MAX_STAGE - api.MIN_STAGE + 1)) + api.MIN_STAGE
  end

  function api.rangePixels(a, b, c)
    local stage, opts
    if a == api then stage, opts = b, c else stage, opts = a, b end
    opts = opts or {}
    return api.stage(stage) * number(opts.blockSize, api.BLOCK_SIZE)
  end

  -- Endpoint for a staged throw. Direction may include pitch; its full 3D
  -- magnitude is normalized so every stage still has a deterministic range.
  function api.finish(a, b, c, d, e)
    local origin, direction, stage, opts
    if a == api then origin, direction, stage, opts = b, c, d, e
    else origin, direction, stage, opts = a, b, c, d end
    origin, direction = point(origin), normalize(direction)
    if not origin then return nil, "invalid origin" end
    if not direction then return nil, "invalid direction" end
    local range = api.rangePixels(stage, opts)
    return {
      x = origin.x + direction.x * range,
      y = origin.y + direction.y * range,
      z = origin.z + direction.z * range,
    }
  end

  -- Construct a parabola between two explicit world points.  The path is a
  -- linear flight plus 4*h*t*(1-t), so it reaches both endpoints exactly.
  function api.arc(a, b, c, d)
    local startPoint, finishPoint, opts
    if a == api then startPoint, finishPoint, opts = b, c, d
    else startPoint, finishPoint, opts = a, b, c end
    opts = opts or {}
    startPoint, finishPoint = point(startPoint), point(finishPoint)
    if not startPoint then return nil, "invalid start point" end
    if not finishPoint then return nil, "invalid finish point" end

    local length = distance(startPoint, finishPoint)
    local height = number(opts.arcHeight)
    if height == nil then height = clamp(length * 0.22, 8, 32) end
    height = math.max(0, height)
    local speed = math.max(1, number(opts.speed, 96))
    local duration = math.max(1 / 120, number(opts.duration, length / speed))

    return {
      start = startPoint,
      finish = finishPoint,
      arcHeight = height,
      duration = duration,
      distance = length,
      blockSize = number(opts.blockSize, api.BLOCK_SIZE),
    }
  end

  function api.fromDirection(a, b, c, d, e)
    local origin, direction, stage, opts
    if a == api then origin, direction, stage, opts = b, c, d, e
    else origin, direction, stage, opts = a, b, c, d end
    local finishPoint, err = api.finish(origin, direction, stage, opts)
    if not finishPoint then return nil, err end
    local arc, arcErr = api.arc(origin, finishPoint, opts)
    if not arc then return nil, arcErr end
    arc.stage = api.stage(stage)
    return arc
  end

  -- "start" is the staged-flight constructor used by the input adapters.
  api.start = api.fromDirection

  function api.positionAt(a, b, c)
    local arc, t
    if a == api then arc, t = b, c else arc, t = a, b end
    if type(arc) ~= "table" then return nil, "invalid arc" end
    local p0, p1 = point(arc.start), point(arc.finish)
    if not p0 or not p1 then return nil, "arc has invalid endpoints" end
    t = clamp(number(t, 0), 0, 1)
    local u = 1 - t
    return {
      x = p0.x * u + p1.x * t,
      y = p0.y * u + p1.y * t
        + 4 * math.max(0, number(arc.arcHeight, 0)) * t * u,
      z = p0.z * u + p1.z * t,
    }
  end

  function api.velocityAt(a, b, c)
    local arc, t
    if a == api then arc, t = b, c else arc, t = a, b end
    if type(arc) ~= "table" then return nil, "invalid arc" end
    local p0, p1 = point(arc.start), point(arc.finish)
    if not p0 or not p1 then return nil, "arc has invalid endpoints" end
    t = clamp(number(t, 0), 0, 1)
    local duration = math.max(1 / 120, number(arc.duration, 1))
    local h = math.max(0, number(arc.arcHeight, 0))
    return {
      x = (p1.x - p0.x) / duration,
      y = ((p1.y - p0.y) + 4 * h * (1 - 2 * t)) / duration,
      z = (p1.z - p0.z) / duration,
    }
  end

  function api.flight(a, b, c)
    local arc, elapsed
    if a == api then arc, elapsed = b, c else arc, elapsed = a, b end
    if type(arc) ~= "table" then return nil, false, 0 end
    local duration = math.max(1 / 120, number(arc.duration, 1))
    local progress = clamp(number(elapsed, 0) / duration, 0, 1)
    return api.positionAt(arc, progress), progress >= 1, progress
  end
  api.flightAt = api.flight

  function api.sample(a, b, c)
    local arc, samples
    if a == api then arc, samples = b, c else arc, samples = a, b end
    samples = math.max(1, math.floor(number(samples, 20)))
    local points = {}
    for i = 0, samples do
      points[#points + 1] = api.positionAt(arc, i / samples)
    end
    return points
  end
  api.points = api.sample

  -- Swept sphere against a spherical target.  This catches fast throws that
  -- cross a target between rendered frames instead of testing endpoints only.
  function api.sweep(a, b, c, d, e, f)
    local from, to, target, ballRadius, targetRadius
    if a == api then from, to, target, ballRadius, targetRadius = b, c, d, e, f
    else from, to, target, ballRadius, targetRadius = a, b, c, d, e end
    local inferredTargetRadius = type(target) == "table" and target.radius or nil
    from, to = point(from), point(to)
    target = point(type(target) == "table" and (target.position or target) or nil)
    if not from or not to or not target then return false, nil, nil end

    local vx, vy, vz = to.x - from.x, to.y - from.y, to.z - from.z
    local wx, wy, wz = target.x - from.x, target.y - from.y, target.z - from.z
    local vv = vx * vx + vy * vy + vz * vz
    local t = vv <= 1e-12 and 0 or clamp((wx * vx + wy * vy + wz * vz) / vv, 0, 1)
    local hitPoint = {
      x = from.x + vx * t,
      y = from.y + vy * t,
      z = from.z + vz * t,
    }
    local dx, dy, dz = target.x - hitPoint.x,
                             target.y - hitPoint.y,
                             target.z - hitPoint.z
    local separation = math.sqrt(dx * dx + dy * dy + dz * dz)
    local radius = math.max(0, number(ballRadius, 0))
      + math.max(0, number(targetRadius, number(inferredTargetRadius, 0)))
    return separation <= radius, t, hitPoint, separation
  end
  api.hit = api.sweep

  function api.firstHit(a, b, c, d, e)
    local points, targets, ballRadius, defaultTargetRadius
    if a == api then points, targets, ballRadius, defaultTargetRadius = b, c, d, e
    else points, targets, ballRadius, defaultTargetRadius = a, b, c, d end
    if type(points) ~= "table" or type(targets) ~= "table" then return nil end
    for segment = 1, #points - 1 do
      local best
      for index, target in ipairs(targets) do
        local hit, t, hitPoint, separation = api.sweep(
          points[segment], points[segment + 1], target,
          ballRadius, target.radius or defaultTargetRadius)
        if hit and (not best or t < best.t) then
          best = {
            target = target,
            targetIndex = index,
            segment = segment,
            t = t,
            point = hitPoint,
            separation = separation,
          }
        end
      end
      if best then return best end
    end
    return nil
  end

  shared.trajectory = api
  return api
end
