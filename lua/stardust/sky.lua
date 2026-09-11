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

local function interval(sky, range)
  return range[1] + sky.random() * (range[2] - range[1])
end

-- Sample one fixed diagonal: two columns across and one row down per point.
-- Alternating horizontal/diagonal moves would trace two interleaved tracks.
-- Enter from the top or a side; a short split naturally ends at the bottom.
-- Occupied cells hide the flight, but never end its motion.
local function flight(sky, layout, cfg, diagonal, sprite_height)
  sprite_height = sprite_height or 1
  local span = layout.width - cfg.margin * 2 - 1
  if layout.area == 0 or span < 5 or sprite_height > layout.height then
    return
  end
  local slope = diagonal and 0.5 or 0
  local stride = diagonal and 2 or 1
  local runway = math.min(span, 12)
  local max_y = math.max(1, layout.height - math.floor(runway * slope) - sprite_height + 1)
  for _ = 1, 48 do
    local dx = sky.random() < 0.5 and -1 or 1
    local x = dx == 1 and cfg.margin or layout.width - cfg.margin - 1
    local y = math.floor(sky.random() * max_y) + 1
    if diagonal and sky.random() < 0.5 then
      -- Reserve some horizontal room so top entries do not immediately exit.
      x = x + dx * math.floor(sky.random() * (span - runway + 1))
      y = 1
    end
    local clear = true
    local initial_steps = diagonal and math.min(5, layout.height - 1, math.floor(span / 2)) or 5
    for step = 0, initial_steps do
      if not M.safe(layout, x + step * dx * stride, y + step * stride * slope) then
        clear = false
        break
      end
    end
    if clear then
      return {
        x = x,
        y = y,
        origin_x = x,
        origin_y = y,
        dx = dx,
        stride = stride,
        slope = slope,
        travel = 0,
        step = 0,
      }
    end
  end
end

local function flight_point(body, step)
  return body.origin_x + step * body.dx * body.stride,
    body.origin_y + step * body.stride * body.slope
end

function M.meteor(sky, layout, cfg)
  if sky.meteor or not cfg.enabled.meteors then
    return false
  end
  local meteor = flight(sky, layout, cfg, true)
  if meteor then
    meteor.head, meteor.trail = true, {}
    sky.meteor = meteor
    sky.next_meteor = sky.age + interval(sky, cfg.meteor.interval)
    return true
  end
  return false
end

M.objects = {
  moon = { { 0, 0, '☾' } },
  planet = { { 0, 0, '◉' }, { -1, 0, '─' }, { 1, 0, '─' } },
  comet = { { 0, 0, '✧' }, { -1, 0, '•' }, { -2, 0, '·' }, { -3, 0, '·' } },
  ship = {}, -- Artwork comes from objects.ships in the user's configuration.
}

local function stationary(sky, layout, sprite)
  for _ = 1, 48 do
    local x, y = point(sky, layout)
    if not x then
      return
    end
    local clear = true
    for _, part in ipairs(sprite) do
      if not M.safe(layout, x + part[1], y + part[2]) then
        clear = false
        break
      end
    end
    if clear then
      return { x = x, y = y, dx = 1, age = 0, life = 16 + sky.random() * 12 }
    end
  end
end

function M.object(sky, layout, cfg, kind)
  if sky.object then
    return false
  end
  if not kind then
    local enabled = {}
    for _, candidate in ipairs(cfg.objects.types) do
      if cfg.enabled[candidate .. 's'] then
        enabled[#enabled + 1] = candidate
      end
    end
    if #enabled == 0 then
      return false
    end
    kind = enabled[math.floor(sky.random() * #enabled) + 1]
  end
  if not M.objects[kind] or not cfg.enabled[kind .. 's'] then
    return false
  end
  local sprite, variant, ship = M.objects[kind], nil, nil
  if kind == 'ship' then
    variant = math.floor(sky.random() * #cfg.objects.ships) + 1
    ship = cfg.objects._ships[variant]
  end
  local object
  if kind == 'moon' or kind == 'planet' then
    object = stationary(sky, layout, sprite)
  else
    object = flight(
      sky,
      layout,
      cfg,
      kind == 'comet',
      ship and math.max(ship.right.height, ship.left.height)
    )
  end
  if not object then
    return false
  end
  if ship then
    sprite = ship[object.dx == 1 and 'right' or 'left'].cells
  end
  object.kind, object.sprite, object.variant = kind, sprite, variant
  sky.object = object
  sky.next_object = sky.age + interval(sky, cfg.objects.interval)
  return true
end

function M.step(sky, layout, cfg, dt, color_count)
  dt = math.max(0, math.min(dt, 0.25))
  sky.age = sky.age + dt
  if not cfg.enabled.meteors then
    sky.meteor = nil
  end
  if sky.object and not cfg.enabled[sky.object.kind .. 's'] then
    sky.object = nil
  end
  local keep = 0
  for _, star in ipairs(sky.stars) do
    star.age = star.age + dt
    if cfg.enabled.stars and star.age < star.life and M.safe(layout, star.x, star.y) then
      keep = keep + 1
      sky.stars[keep] = star
    end
  end
  for i = #sky.stars, keep + 1, -1 do
    sky.stars[i] = nil
  end
  local target = cfg.enabled.stars and math.min(cfg.stars, math.ceil(layout.area / 100)) or 0
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
  sky.next_meteor = sky.next_meteor or (sky.age + interval(sky, cfg.meteor.interval))
  if cfg.meteor.enabled and sky.age >= sky.next_meteor then
    M.meteor(sky, layout, cfg)
    sky.next_meteor = sky.age + interval(sky, cfg.meteor.interval)
  end
  local meteor = sky.meteor
  if meteor and cfg.enabled.meteors then
    for _, tail in ipairs(meteor.trail) do
      tail.age = tail.age + dt
    end
    while
      meteor.trail[1]
      and meteor.trail[1].age > cfg.meteor.trail * meteor.stride / cfg.meteor.speed
    do
      table.remove(meteor.trail, 1)
    end
    meteor.travel = meteor.travel + dt * cfg.meteor.speed / meteor.stride
    while meteor.head and meteor.travel >= 1 - 1e-9 do
      meteor.travel = math.max(0, meteor.travel - 1)
      local step = meteor.step + 1
      local x, y = flight_point(meteor, step)
      meteor.trail[#meteor.trail + 1] =
        { x = meteor.x, y = meteor.y, age = meteor.travel * meteor.stride / cfg.meteor.speed }
      if #meteor.trail > cfg.meteor.trail then
        table.remove(meteor.trail, 1)
      end
      if x < 0 or x >= layout.width or y < 1 or y > layout.height then
        meteor.head = false
      else
        meteor.x, meteor.y, meteor.step = x, y, step
      end
    end
    if not meteor.head and #meteor.trail == 0 then
      sky.meteor = nil
    end
  end
  sky.next_object = sky.next_object or (sky.age + interval(sky, cfg.objects.interval))
  if cfg.objects.enabled and sky.age >= sky.next_object then
    M.object(sky, layout, cfg)
    sky.next_object = sky.age + interval(sky, cfg.objects.interval)
  end
  local object = sky.object
  if object and object.life then
    object.age = object.age + dt
    if object.age >= object.life then
      sky.object = nil
    end
  elseif object then
    object.travel = object.travel
      + dt * cfg.objects.speed * (object.kind == 'comet' and 2 or 1) / object.stride
    while object.travel >= 1 - 1e-9 do
      object.travel = math.max(0, object.travel - 1)
      object.step = object.step + 1
      object.x, object.y = flight_point(object, object.step)
    end
    -- Keep moving until every sprite cell (including the diagonal tail) exits.
    local visible = false
    for _, part in ipairs(object.sprite) do
      local x, y = flight_point(object, object.step + part[1])
      y = y + part[2]
      visible = visible or (x >= 0 and x < layout.width and y >= 1 and y <= layout.height)
    end
    if not visible then
      sky.object = nil
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
  if meteor and cfg.enabled.meteors then
    if meteor.head then
      -- Ease into the next point on the same line; retain the current point
      -- as the start of the trail. No sideways phase or alternate row track.
      if meteor.travel > 0.05 then
        local x, y = flight_point(meteor, meteor.step + 1)
        add(x, y, '✦', palette.meteor[math.ceil(meteor.travel * 8)])
      end
      add(meteor.x, meteor.y, '✦', palette.meteor[math.ceil(8 - meteor.travel * 2)])
    end
    for i = #meteor.trail, 1, -1 do
      local tail = meteor.trail[i]
      local strength =
        math.max(0, 1 - tail.age * cfg.meteor.speed / (cfg.meteor.trail * meteor.stride))
      local level = math.max(1, math.ceil(strength * 6))
      if strength > 0.05 then
        add(tail.x, tail.y, level > 4 and '•' or '·', palette.meteor[level])
      end
    end
  end
  local object = sky.object
  if object and cfg.enabled[object.kind .. 's'] then
    local fade = object.life
        and math.max(0, math.min(1, object.age / 2, (object.life - object.age) / 2))
      or 1
    if object.kind == 'comet' and object.travel > 0.05 then
      local x, y = flight_point(object, object.step + 1)
      add(x, y, '✧', palette.comet[math.ceil(object.travel * 7)])
    end
    for index, part in ipairs(object.sprite) do
      local colors = object.kind == 'ship' and palette.ships[object.variant] or palette[object.kind]
      local x, y = object.x + part[1] * object.dx, object.y + part[2]
      local level = (object.kind == 'ship' and 7 or math.max(2, 8 - index)) * fade
      if object.kind == 'comet' then
        x, y = flight_point(object, object.step + part[1])
        y = y + part[2]
        level = index == #object.sprite and level * (1 - object.travel) or level - object.travel
      end
      if fade > 0.05 and level > 0.2 then
        add(x, y, part[3], colors[math.max(1, math.ceil(level))])
      end
    end
  end
  for _, star in ipairs(cfg.enabled.stars and sky.stars or {}) do
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
