-- Shared flight and trail rendering for lone meteors and staggered showers.
local M = {}

function M.new(x, y, dx, speed, length)
  return {
    x = x,
    y = y,
    origin_x = x,
    origin_y = y,
    dx = dx,
    stride = 2,
    slope = 0.5,
    travel = 0,
    step = 0,
    head = true,
    trail = {},
    speed = speed or 24,
    length = length or 6,
  }
end

function M.step(body, view, dt)
  local speed, length = body.speed, body.length
  for _, tail in ipairs(body.trail) do
    tail.age = tail.age + dt
  end
  body.travel = body.travel + dt * speed / body.stride
  while body.head and body.travel >= 1 - 1e-9 do
    body.travel = math.max(0, body.travel - 1)
    local step = body.step + 1
    local x, y = body.origin_x + step * body.dx * 2, body.origin_y + step
    body.trail[#body.trail + 1] = { x = body.x, y = body.y, age = body.travel * 2 / speed }
    if #body.trail > length then
      table.remove(body.trail, 1)
    end
    if x < 0 or x >= view.width or y < 1 or y > view.height then
      body.head = false
    else
      body.x, body.y, body.step = x, y, step
    end
  end
  while body.trail[1] and body.trail[1].age > length * 2 / speed do
    table.remove(body.trail, 1)
  end
  return body.head or #body.trail > 0
end

function M.draw(body, colors, add)
  if body.head then
    if body.travel > 0.05 then
      add(body.x + body.dx * 2, body.y + 1, '✦', colors[math.ceil(body.travel * 8)])
    end
    add(body.x, body.y, '✦', colors[math.ceil(8 - body.travel * 2)])
  end
  for i = #body.trail, 1, -1 do
    local tail = body.trail[i]
    local strength = math.max(0, 1 - tail.age * body.speed / (body.length * 2))
    local level = math.max(1, math.ceil(strength * 6))
    if strength > 0.05 then
      add(tail.x, tail.y, level > 4 and '•' or '·', colors[level])
    end
  end
end

function M.shower(scene, view, cfg)
  if scene.shower or not cfg.meteors or view.area == 0 or view.width < 20 or view.height < 6 then
    return false
  end
  local dx = scene.random() < 0.5 and -1 or 1
  local band = math.floor(view.width * 0.42)
  local runway = math.min(view.height * 2, view.width * 0.25)
  local start = 2 + math.floor(scene.random() * math.max(1, view.width - band - runway - 4))
  local count = math.max(24, math.min(48, math.floor(view.width * view.height / 80)))
  local shower = { age = 0, meteors = {} }
  for i = 1, count do
    -- Stratified lanes give a broad band even when the random offsets cluster.
    local x = start + math.floor(((i - 1 + scene.random()) / count) * band)
    if dx == -1 then
      x = view.width - 1 - x
    end
    local body = M.new(x, 1, dx, 16 + scene.random() * 16, 6 + math.floor(scene.random() * 5))
    shower.meteors[#shower.meteors + 1] = body
  end
  -- Shuffle the lanes, then spread launches across the burst without long gaps.
  for i = count, 2, -1 do
    local j = math.floor(scene.random() * i) + 1
    shower.meteors[i], shower.meteors[j] = shower.meteors[j], shower.meteors[i]
  end
  for i, body in ipairs(shower.meteors) do
    body.delay = i == 1 and 0 or (i - 1 + scene.random()) * 3.5 / count
  end
  scene.shower = shower
  return true
end

function M.step_shower(shower, view, dt)
  local before = shower.age
  shower.age = before + dt
  for i = #shower.meteors, 1, -1 do
    local body = shower.meteors[i]
    if shower.age >= body.delay then
      local elapsed = shower.age - math.max(before, body.delay)
      if not M.step(body, view, elapsed) then
        table.remove(shower.meteors, i)
      end
    end
  end
  return #shower.meteors > 0
end

function M.draw_shower(shower, colors, add)
  for _, body in ipairs(shower.meteors) do
    if shower.age >= body.delay then
      M.draw(body, colors, add)
    end
  end
end

return M
