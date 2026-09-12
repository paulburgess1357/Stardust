-- Animation is independent of Neovim. Positions are screen cells, time is seconds.
local M = {}
local meteors = require('stardust.meteors')
local battle = require('stardust.battle')
local MARGIN, OBJECT_SPEED = 2, 3
local METEOR_INTERVAL, OBJECT_INTERVAL = { 25, 60 }, { 15, 35 }
local TWINKLE = { '·', '∘', '✧', '✦' }

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
local function flight(sky, layout, diagonal, sprite_height)
  sprite_height = sprite_height or 1
  local span = layout.width - MARGIN * 2 - 1
  if layout.area == 0 or span < 5 or sprite_height > layout.height then
    return
  end
  local slope = diagonal and 0.5 or 0
  local stride = diagonal and 2 or 1
  local runway = math.min(span, 12)
  local max_y = math.max(1, layout.height - math.floor(runway * slope) - sprite_height + 1)
  for _ = 1, 48 do
    local dx = sky.random() < 0.5 and -1 or 1
    local x = dx == 1 and MARGIN or layout.width - MARGIN - 1
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
  if sky.meteor or not cfg.meteors then
    return false
  end
  local meteor = flight(sky, layout, true)
  if meteor then
    sky.meteor = meteors.new(meteor.x, meteor.y, meteor.dx)
    sky.next_meteor = sky.age + interval(sky, METEOR_INTERVAL)
    return true
  end
  return false
end

local function next_shower(sky, cfg)
  return sky.age + cfg.shower_interval * (0.5 + sky.random())
end

function M.shower(sky, layout, cfg)
  if not meteors.shower(sky, layout, cfg) then
    return false
  end
  sky.next_shower = cfg.shower_interval > 0 and next_shower(sky, cfg) or nil
  return true
end

M.objects = {
  moon = { { 0, 0, '☾' } },
  planet = { { 0, 0, '◉' }, { -1, 0, '─' }, { 1, 0, '─' } },
  comet = { { 0, 0, '✧' }, { -1, 0, '•' }, { -2, 0, '·' }, { -3, 0, '·' } },
  ship = {}, -- Artwork comes from ships in the user's configuration.
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

function M.object(sky, layout, cfg, kind, encounter)
  local automatic = kind == nil
  -- An explicit battle preview replaces the current object once a chase fits.
  -- Automatic appearances still wait for the current object to finish.
  if sky.object and not encounter then
    return false
  end
  if not kind then
    if #cfg.objects == 0 then
      return false
    end
    kind = cfg.objects[math.floor(sky.random() * #cfg.objects) + 1]
  end
  if not M.objects[kind] or not cfg.kinds[kind] then
    return false
  end
  local sprite, variant, ship = M.objects[kind], nil, nil
  if kind == 'ship' then
    variant = math.floor(sky.random() * #cfg.ships) + 1
    ship = cfg.art[variant]
  end
  local object
  if kind == 'moon' or kind == 'planet' then
    object = stationary(sky, layout, sprite)
  else
    object =
      flight(sky, layout, kind == 'comet', ship and math.max(ship.right.height, ship.left.height))
  end
  if not object then
    return false
  end
  if ship then
    sprite = ship[object.dx == 1 and 'right' or 'left'].cells
  end
  object.kind, object.sprite, object.variant = kind, sprite, variant
  if ship and cfg.enabled.ship_enemies and (encounter or (automatic and sky.random() < 0.25)) then
    local started = battle.start(sky, layout, cfg, object)
    if encounter and not started then
      return false
    end
  end
  sky.object = object
  sky.next_object = sky.age + interval(sky, OBJECT_INTERVAL)
  return true
end

function M.battle(sky, layout, cfg)
  if not cfg.kinds.ship or not cfg.enabled.ship_enemies then
    return false
  end
  for _ = 1, 48 do
    if M.object(sky, layout, cfg, 'ship', true) then
      return true
    end
  end
  return false
end

function M.step(sky, layout, cfg, dt, color_count)
  dt = math.max(0, dt)
  if cfg.meteors and cfg.shower_interval > 0 then
    sky.next_shower = sky.next_shower or next_shower(sky, cfg)
  else
    sky.next_shower = nil
  end
  sky.age = sky.age + dt
  if not cfg.meteors then
    sky.meteor, sky.shower = nil, nil
  end
  if sky.object and not cfg.kinds[sky.object.kind] then
    sky.object = nil
  end
  local keep = 0
  for _, star in ipairs(sky.stars) do
    star.age = star.age + dt
    -- Occupancy only hides stars in frame(); cursor movement and edits must
    -- never erase them. Retire stars only with age or outside a resized view.
    if
      cfg.stars > 0
      and star.age < star.life
      and star.x >= 0
      and star.x < layout.width
      and star.y >= 1
      and star.y <= layout.height
    then
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
  sky.next_meteor = sky.next_meteor or (sky.age + interval(sky, METEOR_INTERVAL))
  if cfg.meteors and sky.age >= sky.next_meteor then
    M.meteor(sky, layout, cfg)
    sky.next_meteor = sky.age + interval(sky, METEOR_INTERVAL)
  end
  if sky.meteor and not meteors.step(sky.meteor, layout, dt) then
    sky.meteor = nil
  end
  local shower_dt = dt
  if sky.next_shower and sky.age >= sky.next_shower then
    local due = sky.next_shower
    if not sky.shower and meteors.shower(sky, layout, cfg) then
      shower_dt = sky.age - due
    end
    sky.next_shower = next_shower(sky, cfg)
  end
  if sky.shower and not meteors.step_shower(sky.shower, layout, shower_dt) then
    sky.shower = nil
  end
  sky.next_object = sky.next_object or (sky.age + interval(sky, OBJECT_INTERVAL))
  if #cfg.objects > 0 and sky.age >= sky.next_object then
    M.object(sky, layout, cfg)
    sky.next_object = sky.age + interval(sky, OBJECT_INTERVAL)
  end
  local object = sky.object
  if object and object.battle then
    if not cfg.enabled.ship_enemies then
      -- Resume an ordinary flight from the pursuer's current position.
      object.origin_x, object.origin_y = object.x, object.y
      object.step, object.travel = 0, 0
      object.battle = nil
    elseif not battle.step(object, layout, dt) then
      sky.object = nil
    end
  elseif object and object.life then
    object.age = object.age + dt
    if object.age >= object.life then
      sky.object = nil
    end
  elseif object then
    object.travel = object.travel
      + dt * OBJECT_SPEED * (object.kind == 'comet' and 2 or 1) / object.stride
    local steps = math.floor(object.travel + 1e-9)
    object.travel = math.max(0, object.travel - steps)
    object.step = object.step + steps
    object.x, object.y = flight_point(object, object.step)
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
  if sky.meteor and cfg.meteors then
    meteors.draw(sky.meteor, palette.meteor, add)
  end
  if sky.shower and cfg.meteors then
    meteors.draw_shower(sky.shower, palette.meteor, add)
  end
  local object = sky.object
  if object and cfg.kinds[object.kind] then
    local fade = object.life
        and math.max(0, math.min(1, object.age / 2, (object.life - object.age) / 2))
      or 1
    if object.battle and cfg.enabled.ship_enemies then
      battle.draw(object, palette, add)
    end
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
  for _, star in ipairs(cfg.stars > 0 and sky.stars or {}) do
    local envelope = math.min(1, star.age / 1.2, (star.life - star.age) / 1.5)
    local pulse = (0.5 + 0.5 * math.sin(star.age / star.period * math.pi * 2 + star.phase))
    local brightness = envelope * (0.2 + 0.8 * pulse)
    if brightness > 0.08 then
      local glyph = TWINKLE[math.min(#TWINKLE, math.floor(brightness * #TWINKLE) + 1)]
      add(star.x, star.y, glyph, palette.stars[star.color][math.max(1, math.ceil(brightness * 8))])
    end
  end
  return cells
end

return M
