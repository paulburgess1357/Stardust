-- Animation is independent of Neovim. Positions are screen cells, time is seconds.
local M = {}

local function random_source(seed)
  local value = math.floor(seed) % 2147483646 + 1
  return function()
    value = (value * 16807) % 2147483647
    return (value - 1) / 2147483646
  end
end

function M.new(seed)
  return { random = random_source(seed), stars = {}, meteor = nil, next_meteor = nil, age = 0 }
end

function M.safe(layout, x, y)
  local row = layout.rows[y]
  return row ~= nil and x >= row.first and x < row.last
end

local function point(sky, layout)
  if layout.area == 0 then
    return
  end
  local cell = math.floor(sky.random() * layout.area)
  for y, row in ipairs(layout.rows) do
    local width = row.last - row.first
    if cell < width then
      return row.first + cell, y
    end
    cell = cell - width
  end
end

local function interval(sky, cfg)
  local range = cfg.meteor.interval
  return range[1] + sky.random() * (range[2] - range[1])
end

function M.meteor(sky, layout, cfg)
  if sky.meteor or layout.area == 0 then
    return false
  end
  for _ = 1, 24 do
    local x, y = point(sky, layout)
    local dx = sky.random() < 0.5 and -1 or 1
    -- Reserve a useful initial path; a meteor is allowed to end early after edits.
    local clear = true
    for step = 0, 5 do
      if not M.safe(layout, x + step * dx, y + math.floor(step / 2)) then
        clear = false
        break
      end
    end
    if clear then
      sky.meteor = { x = x, y = y, dx = dx, travel = 0, head = true, trail = {} }
      sky.next_meteor = sky.age + interval(sky, cfg)
      return true
    end
  end
  return false
end

function M.step(sky, layout, cfg, dt, color_count)
  sky.age = sky.age + math.min(dt, 0.25)
  local keep = 0
  for _, star in ipairs(sky.stars) do
    star.age = star.age + dt
    if star.age < star.life and M.safe(layout, star.x, star.y) then
      keep = keep + 1
      sky.stars[keep] = star
    end
  end
  for i = #sky.stars, keep + 1, -1 do
    sky.stars[i] = nil
  end
  local target = math.min(cfg.stars, math.ceil(layout.area / 100))
  if keep < target then
    local x, y = point(sky, layout)
    if x then
      sky.stars[#sky.stars + 1] = {
        x = x,
        y = y,
        age = 0,
        life = 4 + sky.random() * 7,
        period = 1.8 + sky.random() * 3,
        phase = sky.random() * math.pi * 2,
        color = math.floor(sky.random() * color_count) + 1,
      }
    end
  end
  sky.next_meteor = sky.next_meteor or (sky.age + interval(sky, cfg))
  if cfg.meteor.enabled and sky.age >= sky.next_meteor then
    M.meteor(sky, layout, cfg)
    sky.next_meteor = sky.age + interval(sky, cfg)
  end
  local meteor = sky.meteor
  if meteor then
    for _, tail in ipairs(meteor.trail) do
      tail.age = tail.age + dt
    end
    while meteor.trail[1] and meteor.trail[1].age > cfg.meteor.trail / cfg.meteor.speed do
      table.remove(meteor.trail, 1)
    end
    meteor.travel = meteor.travel + dt * cfg.meteor.speed
    while meteor.head and meteor.travel >= 1 do
      meteor.travel = meteor.travel - 1
      local step = (meteor.step or 0) + 1
      local x, y = meteor.x + meteor.dx, meteor.y + (step % 2 == 0 and 1 or 0)
      if not M.safe(layout, meteor.x, meteor.y) or not M.safe(layout, x, y) then
        meteor.head = false
      else
        meteor.trail[#meteor.trail + 1] = { x = meteor.x, y = meteor.y, age = 0 }
        if #meteor.trail > cfg.meteor.trail then
          table.remove(meteor.trail, 1)
        end
        meteor.x, meteor.y, meteor.step = x, y, step
      end
    end
    if not meteor.head and #meteor.trail == 0 then
      sky.meteor = nil
    end
  end
end

function M.frame(sky, layout, cfg, palette)
  local cells, occupied = {}, {}
  local function add(x, y, glyph, hl)
    if not M.safe(layout, x, y) then
      return
    end
    local key = y * layout.width + x
    if occupied[key] then
      return
    end
    occupied[key] = true
    cells[#cells + 1] = { x = x, y = y, glyph = glyph, hl = hl }
  end
  local meteor = sky.meteor
  if meteor then
    if meteor.head then
      add(meteor.x, meteor.y, '✦', palette.meteor[8])
    end
    for i = #meteor.trail, 1, -1 do
      local tail = meteor.trail[i]
      local strength = math.max(0, 1 - tail.age * cfg.meteor.speed / cfg.meteor.trail)
      local level = math.max(1, math.ceil(strength * 6))
      add(tail.x, tail.y, level > 4 and '•' or '·', palette.meteor[level])
    end
  end
  for _, star in ipairs(sky.stars) do
    local envelope = math.min(1, star.age / 1.2, (star.life - star.age) / 1.5)
    local pulse = (0.5 + 0.5 * math.sin(star.age / star.period * math.pi * 2 + star.phase))
    local brightness = envelope * (0.2 + 0.8 * pulse)
    if brightness > 0.08 then
      local glyph = cfg.twinkle[math.min(#cfg.twinkle, math.floor(brightness * #cfg.twinkle) + 1)]
      add(star.x, star.y, glyph, palette.stars[star.color][math.max(1, math.ceil(brightness * 8))])
    end
  end
  return cells
end

return M
