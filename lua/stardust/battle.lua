-- A short encounter: two ships enter together, three shots, then an explosion.
-- Positions derive from elapsed time, so low FPS cannot skip a hit or stall it.
local M = {}
local SPEED, LASER_SPEED = 7, 45
local DEBRIS =
  { { -2, -1 }, { 0, -1 }, { 2, -1 }, { -2, 0 }, { 2, 0 }, { -2, 1 }, { 0, 1 }, { 2, 1 } }

function M.start(scene, view, cfg, ship)
  if not cfg.enabled.ship_enemies or view.width < 50 then
    return false
  end
  local direction = ship.dx == 1 and 'right' or 'left'
  local variant = math.floor(scene.random() * #cfg.art) + 1
  local enemy = cfg.art[variant][direction]
  local height = cfg.art[ship.variant][direction].height
  local row = ship.y + math.floor((height - 1) / 2)
  local enemy_y = row - math.floor((enemy.height - 1) / 2)
  if enemy_y < 2 or enemy_y + enemy.height > view.height then
    return false
  end
  local rear = 0
  for _, cell in ipairs(enemy.cells) do
    rear = math.min(rear, cell[1])
  end
  local gap = math.max(14, -rear + 8, math.min(22, math.floor(view.width * 0.2)))
  local first = gap / SPEED + 0.4
  local impact = first + 1.6 + (gap + rear - 1) / (LASER_SPEED - SPEED)
  ship.battle = {
    age = 0,
    gap = gap,
    first = first,
    impact = impact,
    row = row,
    enemy_y = enemy_y,
    sprite = enemy.cells,
  }
  return true
end

function M.step(ship, view, dt)
  local battle = ship.battle
  battle.age = battle.age + dt
  ship.x = ship.origin_x + math.floor(battle.age * SPEED - battle.gap) * ship.dx
  -- The pursuer continues across the whole view after the enemy is destroyed.
  local rear = 0
  for _, cell in ipairs(ship.sprite) do
    rear = math.min(rear, cell[1])
  end
  local tail = ship.x + rear * ship.dx
  local exited = ship.dx == 1 and tail >= view.width or ship.dx == -1 and tail < 0
  return not exited or battle.age < battle.impact + 1
end

function M.draw(ship, palette, add)
  local battle = ship.battle
  local age, dx = battle.age, ship.dx
  local enemy_x = ship.origin_x + math.floor(age * SPEED) * dx
  if age < battle.impact then
    -- The first two volleys miss while the enemy banks above the firing lane.
    local dodge = age < battle.first + 1.6 and -1 or 0
    for _, part in ipairs(battle.sprite) do
      add(enemy_x + part[1] * dx, battle.enemy_y + part[2] + dodge, part[3], palette.enemy[7])
    end
  else
    local elapsed = age - battle.impact
    if elapsed < 1 then
      local x = ship.origin_x + math.floor(battle.impact * SPEED) * dx
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
  for shot = 0, 2 do
    local fired = battle.first + shot * 0.8
    local elapsed = age - fired
    if elapsed >= 0 and (shot < 2 or age < battle.impact) then
      local distance = fired * SPEED - battle.gap + 1 + elapsed * LASER_SPEED
      local x = ship.origin_x + math.floor(distance) * dx
      add(x, battle.row, '━', palette.laser[8])
      add(x - dx, battle.row, '─', palette.laser[4])
    end
  end
end

return M
