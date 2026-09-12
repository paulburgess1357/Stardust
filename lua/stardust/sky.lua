-- Animation is independent of Neovim. Positions are screen cells, time is seconds.
local M = {}
local meteors = require('stardust.meteors')
local battle = require('stardust.battle')
local objects = require('stardust.objects')
local MARGIN, OBJECT_SPEED, MAX_STARS = 2, 3, 200
local TWINKLE = { '·', '∘', '✧', '✦' }

local function random_source(seed)
  local value = math.floor(seed) % 2147483646 + 1
  return function()
    value = (value * 16807) % 2147483647
    return (value - 1) / 2147483646
  end
end

-- Level 1 averages about once an hour and each level doubles that, so 10 is
-- roughly every seven seconds. Waits vary between half and one and a half
-- times the average.
function M.mean_interval(level)
  return 3600 / 2 ^ (level - 1)
end

local function next_time(sky, level)
  return sky.age + M.mean_interval(level) * (0.5 + sky.random())
end

-- Stars per empty cell at a given density level, capped per scene.
function M.star_target(level, area)
  return math.min(MAX_STARS, math.ceil(area * level / 300))
end

function M.new(seed)
  return { random = random_source(seed), stars = {}, objects = {}, age = 0, due = {} }
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
        age = 0,
      }
    end
  end
end

local function flight_point(body, step)
  return body.origin_x + step * body.dx * body.stride,
    body.origin_y + step * body.stride * body.slope
end

function M.meteor(sky, layout, cfg)
  if sky.meteor or cfg.meteors <= 0 then
    return false
  end
  local meteor = flight(sky, layout, true)
  if meteor then
    sky.meteor = meteors.new(meteor.x, meteor.y, meteor.dx)
    sky.due.meteor = next_time(sky, cfg.meteors)
    return true
  end
  return false
end

function M.shower(sky, layout, cfg)
  if not meteors.shower(sky, layout, cfg) then
    return false
  end
  sky.due.shower = next_time(sky, cfg.showers)
  return true
end

-- Cells the stationary objects already on screen can touch, so a new one
-- prefers a spot of its own. Overlaps are still allowed when space is short.
local function taken(sky)
  local cells = {}
  for _, object in ipairs(sky.objects) do
    if object.life then
      for _, part in ipairs(objects.footprint(objects.by_name[object.kind])) do
        cells[(object.y + part[2]) * 65536 + object.x + part[1]] = true
      end
    end
  end
  return cells
end

local function stationary(sky, layout, kind)
  local life = kind.life or { 16, 28 }
  local used, fallback = taken(sky), nil
  for _ = 1, 48 do
    local x, y = point(sky, layout)
    if not x then
      break
    end
    local clear, alone = true, true
    for _, part in ipairs(objects.footprint(kind)) do
      local px, py = x + part[1], y + part[2]
      if not M.safe(layout, px, py) then
        clear = false
        break
      end
      alone = alone and not used[py * 65536 + px]
    end
    if clear and alone then
      fallback = { x = x, y = y }
      break
    elseif clear and not fallback then
      fallback = { x = x, y = y }
    end
  end
  if fallback then
    return {
      x = fallback.x,
      y = fallback.y,
      dx = 1,
      age = 0,
      life = life[1] + sky.random() * (life[2] - life[1]),
    }
  end
end

-- One row up or down on a slow wave, for kinds that bob.
local function bob(kind, object)
  if not kind.bob then
    return 0
  end
  return math.floor(math.sin(object.age / kind.bob * math.pi * 2) + 0.5)
end

-- Objects never wait for one another: each kind follows its own timer and
-- previews always add one more. Only automatic ship flights can turn into a
-- chase by chance; an explicit battle preview always tries to start one.
local function spawn_object(sky, layout, cfg, name, automatic, encounter)
  local kind = objects.by_name[name]
  if not kind or cfg[kind.plural] <= 0 then
    return false
  end
  local sprite, variant, ship = kind.sprite or (kind.frames and kind.frames[1]), nil, nil
  if kind.fleet then
    variant = math.floor(sky.random() * #cfg.art) + 1
    ship = cfg.art[variant]
  end
  local object
  if kind.motion == 'stationary' then
    object = stationary(sky, layout, kind)
  else
    local height = ship and math.max(ship.right.height, ship.left.height) or objects.height(kind)
    object = flight(sky, layout, kind.motion == 'diagonal', height)
    if object and kind.bob then
      -- Leave a row above and below for the wobble.
      object.y, object.origin_y = object.y + 1, object.origin_y + 1
    end
  end
  if not object then
    return false
  end
  if ship then
    sprite = ship[object.dx == 1 and 'right' or 'left'].cells
  end
  object.kind, object.sprite, object.variant = name, sprite, variant
  if
    ship
    and cfg.battles > 0
    and (encounter or (automatic and sky.random() < cfg.battles / 10))
  then
    local started = battle.start(sky, layout, cfg, object)
    if encounter and not started then
      return false
    end
  end
  sky.objects[#sky.objects + 1] = object
  sky.due[name] = next_time(sky, cfg[kind.plural])
  return true
end

-- Without a kind, pick any enabled kind as an automatic appearance would.
function M.object(sky, layout, cfg, name)
  local automatic = name == nil
  if automatic then
    if #cfg.objects == 0 then
      return false
    end
    name = cfg.objects[math.floor(sky.random() * #cfg.objects) + 1]
  end
  return spawn_object(sky, layout, cfg, name, automatic, false)
end

function M.battle(sky, layout, cfg)
  if objects.level(cfg, 'ship') <= 0 or cfg.battles <= 0 then
    return false
  end
  for _ = 1, 48 do
    if spawn_object(sky, layout, cfg, 'ship', false, true) then
      return true
    end
  end
  return false
end

-- Move one object through dt seconds; false once it has left or expired.
local function advance_object(sky, layout, cfg, object, dt)
  local kind = objects.by_name[object.kind]
  if cfg[kind.plural] <= 0 then
    return false
  end
  object.age = object.age + dt
  if object.battle then
    if cfg.battles <= 0 then
      -- Resume an ordinary flight from the pursuer's current position.
      object.origin_x, object.origin_y = object.x, object.y
      object.step, object.travel = 0, 0
      object.battle = nil
      return true
    end
    return battle.step(object, layout, dt)
  end
  if object.life then
    return object.age < object.life
  end
  object.travel = object.travel + dt * OBJECT_SPEED * (kind.speed or 1) / object.stride
  local steps = math.floor(object.travel + 1e-9)
  object.travel = math.max(0, object.travel - steps)
  object.step = object.step + steps
  object.x, object.y = flight_point(object, object.step)
  object.y = object.y + bob(kind, object)
  -- Keep moving until every sprite cell (including the diagonal tail) exits.
  for _, part in ipairs(object.sprite) do
    local x, y = flight_point(object, object.step + part[1])
    y = y + part[2]
    if x >= 0 and x < layout.width and y >= 1 and y <= layout.height then
      return true
    end
  end
  return false
end

-- True once a timer at this level is due; timers for disabled levels vanish.
local function due(sky, name, level)
  if level <= 0 then
    sky.due[name] = nil
    return false
  end
  sky.due[name] = sky.due[name] or next_time(sky, level)
  return sky.age >= sky.due[name]
end

function M.step(sky, layout, cfg, dt, color_count)
  dt = math.max(0, dt)
  sky.age = sky.age + dt
  if cfg.meteors <= 0 then
    sky.meteor = nil
  end
  if cfg.showers <= 0 then
    sky.shower = nil
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
  if keep < M.star_target(cfg.stars, layout.area) then
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
  if due(sky, 'meteor', cfg.meteors) then
    M.meteor(sky, layout, cfg)
    sky.due.meteor = next_time(sky, cfg.meteors)
  end
  if sky.meteor and not meteors.step(sky.meteor, layout, dt) then
    sky.meteor = nil
  end
  local shower_dt = dt
  if due(sky, 'shower', cfg.showers) then
    local started = sky.due.shower
    if not sky.shower and meteors.shower(sky, layout, cfg) then
      -- The burst begins at its scheduled moment, not at this frame.
      shower_dt = sky.age - started
    end
    sky.due.shower = next_time(sky, cfg.showers)
  end
  if sky.shower and not meteors.step_shower(sky.shower, layout, shower_dt) then
    sky.shower = nil
  end
  -- Every kind keeps its own timer, so several objects can share the view.
  -- A kind that finds no room simply tries again at its next due time.
  for _, kind in ipairs(objects.kinds) do
    if due(sky, kind.name, cfg[kind.plural]) then
      spawn_object(sky, layout, cfg, kind.name, true, false)
      sky.due[kind.name] = next_time(sky, cfg[kind.plural])
    end
  end
  local kept = 0
  for _, object in ipairs(sky.objects) do
    if advance_object(sky, layout, cfg, object, dt) then
      kept = kept + 1
      sky.objects[kept] = object
    end
  end
  for i = #sky.objects, kept + 1, -1 do
    sky.objects[i] = nil
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
  if sky.meteor and cfg.meteors > 0 then
    meteors.draw(sky.meteor, palette.meteor, add)
  end
  if sky.shower and cfg.showers > 0 then
    meteors.draw_shower(sky.shower, palette.meteor, add)
  end
  for _, object in ipairs(sky.objects) do
    local kind = objects.by_name[object.kind]
    local diagonal = kind.motion == 'diagonal'
    local ease = kind.fade or 2
    local fade = object.life
        and math.max(0, math.min(1, object.age / ease, (object.life - object.age) / ease))
      or 1
    if object.battle and cfg.battles > 0 then
      battle.draw(object, palette, add)
    end
    if diagonal and object.travel > 0.05 then
      local x, y = flight_point(object, object.step + 1)
      add(x, y, '✧', palette[object.kind][math.ceil(object.travel * 7)])
    end
    local colors = kind.fleet and palette.fleet[object.variant] or palette[object.kind]
    local sprite = objects.sprite(kind, object)
    for index, part in ipairs(sprite) do
      local x, y = object.x + part[1] * object.dx, object.y + part[2]
      local level = part.level or (kind.fleet and 7 or math.max(2, 8 - index))
      if kind.spin and part.phase then
        -- Brightness travels from cell to cell in phase order.
        local wave = 0.5 + 0.5 * math.cos((object.age / kind.spin - part.phase) * math.pi * 2)
        level = level * (0.3 + 0.7 * wave)
      end
      level = level * fade
      if diagonal then
        x, y = flight_point(object, object.step + part[1])
        y = y + part[2]
        level = index == #sprite and level * (1 - object.travel) or level - object.travel
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
