-- A chase ends with a hit along the flight or an enemy accelerating to safety.
-- Positions derive from elapsed time, so low FPS cannot skip a hit or stall it.
local M = {}
local DEBRIS =
  { { -2, -1 }, { 0, -1 }, { 2, -1 }, { -2, 0 }, { 2, 0 }, { -2, 1 }, { 0, 1 }, { 2, 1 } }

local function gun_row(battle, age)
  local progress = math.max(0, math.min(1, (age - battle.align_at) / battle.align_duration))
  local ease = progress * progress * (3 - 2 * progress)
  local offset = battle.row - battle.origin_row
  local moved = math.floor(math.abs(offset) * ease + 0.5)
  return battle.origin_row + (offset < 0 and -moved or moved)
end

local function ship_distance(battle, age)
  return (age - battle.arrival) * battle.speed
end

local function enemy_distance(battle, age)
  local boost = battle.boost_at
      and math.max(0, age - battle.boost_at) * (battle.escape_speed - battle.enemy_speed)
    or 0
  return age * battle.enemy_speed + boost
end

-- Solve the relative flight in each constant-speed segment, including a boost.
-- The result is a collision time, not a scheduled destruction or hit counter.
local function contact_time(battle, shot)
  local segments = { shot.at }
  if battle.boost_at and battle.boost_at > shot.at then
    segments[2] = battle.boost_at
  end
  for i, start in ipairs(segments) do
    local gap = enemy_distance(battle, start)
      + battle.enemy_rear
      - (shot.origin + (start - shot.at) * battle.laser_speed)
    local speed = battle.boost_at and start >= battle.boost_at and battle.escape_speed
      or battle.enemy_speed
    local closing = battle.laser_speed - speed
    if gap >= 0 and closing > 0 then
      local contact = start + gap / closing
      if not segments[i + 1] or contact <= segments[i + 1] then
        return contact
      end
    end
  end
end

function M.start(scene, view, cfg, ship)
  if cfg.battles <= 0 or view.width < 50 then
    return false
  end
  local direction = ship.dx == 1 and 'right' or 'left'
  local variant = math.floor(scene.random() * #cfg.art) + 1
  local enemy = cfg.art[variant][direction]
  local height = cfg.art[ship.variant][direction].height
  -- Aim from an actual nose glyph to an actual glyph at the enemy's rear.
  local nose, rear = ship.sprite[1], enemy.cells[1]
  for _, cell in ipairs(ship.sprite) do
    if cell[1] > nose[1] then
      nose = cell
    end
  end
  for _, cell in ipairs(enemy.cells) do
    if cell[1] < rear[1] then
      rear = cell
    end
  end
  local row = ship.y + nose[2]
  local low = math.max(nose[2], rear[2]) + 1
  local high = view.height - math.max(height - nose[2], enemy.height - rear[2]) + 1
  if low > high then
    return false
  end
  local offset = scene.random() < 0.5 and -3 or 3
  local target = math.max(low, math.min(high, row + offset))
  if target == row then
    target = math.max(low, math.min(high, row - offset))
  end
  local enemy_speed = 6 + scene.random() * 5
  local speed = enemy_speed * (0.8 + scene.random() * 0.18)
  local arrival = (-rear[1] + 8) / enemy_speed
    + 0.3
    + scene.random() * math.min(6, view.width * 0.3 / enemy_speed)
  local align_at, align_duration = arrival + 0.5, 1.1 + scene.random() * 0.6
  local first = align_at
    + align_duration
    + 0.2
    + scene.random() * math.min(2, view.width * 0.1 / enemy_speed)
  local laser_speed = 18 + scene.random() * 28
  if scene.random() < 0.2 then
    laser_speed = speed + 0.2 + scene.random() * (enemy_speed * 1.3 - speed)
  end
  local battle = {
    age = 0,
    arrival = arrival,
    speed = speed,
    enemy_speed = enemy_speed,
    laser_speed = laser_speed,
    align_at = align_at,
    align_duration = align_duration,
    boost_at = scene.random() < 0.25 and first + 0.1 + scene.random() * 0.2 or nil,
    escape_speed = math.max(laser_speed, enemy_speed) * (1.2 + scene.random() * 0.4),
    shots = {},
    origin_row = row,
    row = target,
    gun_x = nose[1],
    gun_y = nose[2],
    enemy_y = target - rear[2],
    enemy_rear = rear[1],
    sprite = enemy.cells,
  }
  local spacing = 0.13 + scene.random() * 0.08
  for i = 0, 2 do
    local fired = first + i * spacing
    local shot = {
      at = fired,
      origin = math.floor(ship_distance(battle, fired) + 1e-9) + nose[1] + 1,
    }
    shot.contact = contact_time(battle, shot)
    battle.shots[#battle.shots + 1] = shot
  end
  ship.battle = battle
  ship.x = ship.origin_x + math.floor(ship_distance(battle, 0)) * ship.dx
  return true
end

function M.step(ship, view, dt)
  local battle = ship.battle
  battle.age = battle.age + dt
  ship.x = ship.origin_x + math.floor(ship_distance(battle, battle.age) + 1e-9) * ship.dx
  ship.y = gun_row(battle, battle.age) - battle.gun_y
  if not battle.hit then
    for _, shot in ipairs(battle.shots) do
      local contact = shot.contact
      if contact and battle.age >= contact - 1e-9 then
        local x = ship.origin_x
          + (math.floor(enemy_distance(battle, contact) + 1e-9) + battle.enemy_rear) * ship.dx
        -- A catch beyond the viewport is an escape, not an off-screen explosion.
        if x >= 0 and x < view.width and battle.row >= 1 and battle.row <= view.height then
          battle.hit = { at = contact, shot = shot, x = x }
          break
        end
      end
    end
  end
  -- The pursuer continues across the whole view after either outcome.
  local rear = 0
  for _, cell in ipairs(ship.sprite) do
    rear = math.min(rear, cell[1])
  end
  local tail = ship.x + rear * ship.dx
  local exited = ship.dx == 1 and tail >= view.width or ship.dx == -1 and tail < 0
  return not exited or (battle.hit ~= nil and battle.age < battle.hit.at + 1)
end

function M.draw(ship, palette, add)
  local battle = ship.battle
  local age, dx = battle.age, ship.dx
  local enemy_x = ship.origin_x + math.floor(enemy_distance(battle, age) + 1e-9) * dx
  if not battle.hit then
    for _, part in ipairs(battle.sprite) do
      add(enemy_x + part[1] * dx, battle.enemy_y + part[2], part[3], palette.enemy[7])
    end
  else
    local elapsed = math.max(0, age - battle.hit.at)
    if elapsed < 1 then
      local x = battle.hit.x
      local level = math.max(1, math.ceil((1 - elapsed) * 8))
      add(x, battle.row, elapsed < 0.2 and '✹' or '✧', palette.laser[level])
      local radius = 0.5 + elapsed * 3
      for _, part in ipairs(DEBRIS) do
        add(
          x + math.floor(part[1] * radius),
          battle.row + math.floor(part[2] * radius),
          elapsed < 0.4 and '✧' or '·',
          palette.enemy[level]
        )
      end
    end
  end
  for _, shot in ipairs(battle.shots) do
    local elapsed = age - shot.at
    -- Stop firing on impact. Other bullets already in flight carry on.
    local in_flight = not battle.hit or (shot.at < battle.hit.at and shot ~= battle.hit.shot)
    if elapsed >= -1e-9 and in_flight then
      local x = ship.origin_x + math.floor(shot.origin + elapsed * battle.laser_speed + 1e-9) * dx
      add(x, battle.row, '━', palette.laser[8])
      add(x - dx, battle.row, '─', palette.laser[4])
    end
  end
end

return M
