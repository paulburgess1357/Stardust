-- Every celestial object kind in one place. Adding an entry here adds its
-- 0-10 option, its color, its preview command, and its spawn timer.
--
--   name     singular name used by object(kind) and :Stardust <kind>
--   plural   option and color key
--   level    default frequency, 0-10
--   color    default foreground color
--   motion   'stationary' fades in place; 'straight' and 'diagonal' cross the view
--   speed    multiplier for moving kinds (3 cells per second at 1)
--   sprite   cells { dx, dy, glyph, level = 1-8, phase = 0-1 } around the anchor;
--            for 'diagonal' dx counts flight steps behind the head
--   frames   list of sprites shown in turn: every `period` seconds when set,
--            otherwise spread across the object's life
--   spin     seconds per brightness cycle; cells with a phase pulse in turn
--   bob      seconds per vertical wobble of one row (moving kinds)
--   life     { shortest, longest } seconds on screen (stationary kinds)
--   fade     seconds to fade in and out (stationary kinds)
--   fleet    true when artwork comes from the fleet option instead of sprite
local M = {}

local function ring(glyphs)
  -- A one-row ring seen edge on: brightness sweeps across the front.
  local cells, count = {}, #glyphs
  for index, glyph in ipairs(glyphs) do
    local dx = index - math.ceil(count / 2)
    if dx == 0 then
      cells[#cells + 1] = { 0, 0, glyph, level = 8 }
    else
      cells[#cells + 1] = { dx, 0, glyph, level = 6, phase = (index - 1) / (count - 1) }
    end
  end
  return cells
end

local function orbit_frames()
  -- A small moon on a 5x3 track, brighter in front of the planet than behind.
  local track = {
    { -2, 0, '·', level = 5 },
    { -1, -1, '·', level = 4 },
    { 0, -1, '·', level = 3 },
    { 1, -1, '·', level = 4 },
    { 2, 0, '·', level = 5 },
    { 1, 1, '∘', level = 7 },
    { 0, 1, '∘', level = 8 },
    { -1, 1, '∘', level = 7 },
  }
  local frames = {}
  for _, moon in ipairs(track) do
    frames[#frames + 1] = { { 0, 0, '◉', level = 8 }, moon }
  end
  return frames
end

local function nebula_frames()
  local function cloud(inner, outer)
    return {
      { 0, 0, '◦', level = 4 },
      { -1, -1, inner, level = 3 },
      { 0, -1, outer, level = 2 },
      { 1, -1, inner, level = 3 },
      { -2, 0, outer, level = 2 },
      { -1, 0, inner, level = 3 },
      { 1, 0, inner, level = 3 },
      { 2, 0, outer, level = 2 },
      { -1, 1, inner, level = 3 },
      { 0, 1, outer, level = 2 },
      { 1, 1, inner, level = 3 },
    }
  end
  return { cloud('·', '∘'), cloud('∘', '·') }
end

local function supernova_frames()
  local function shell(radius, glyph, level)
    local cells = {}
    for _, dx in ipairs({ -radius, radius }) do
      cells[#cells + 1] = { dx, 0, glyph, level = level }
    end
    for _, dx in ipairs({ -math.ceil(radius / 2), math.ceil(radius / 2) }) do
      cells[#cells + 1] = { dx, -1, glyph, level = level }
      cells[#cells + 1] = { dx, 1, glyph, level = level }
    end
    return cells
  end
  local function with_core(cells, glyph, level)
    table.insert(cells, 1, { 0, 0, glyph, level = level })
    return cells
  end
  return {
    { { 0, 0, '✦', level = 6 } },
    { { 0, 0, '✹', level = 8 } },
    with_core(shell(2, '✧', 7), '✹', 8),
    with_core(shell(3, '∘', 5), '✦', 6),
    with_core(shell(4, '·', 3), '·', 3),
  }
end

M.kinds = {
  {
    name = 'moon',
    plural = 'moons',
    level = 5,
    color = '#f4f1de',
    motion = 'stationary',
    frames = { { { 0, 0, '☾' } }, { { 0, 0, '○' } }, { { 0, 0, '☽' } } },
  },
  {
    name = 'planet',
    plural = 'planets',
    level = 5,
    color = '#ffe6a3',
    motion = 'stationary',
    sprite = ring({ '─', '─', '◉', '─', '─' }),
    spin = 3,
  },
  {
    name = 'orbit',
    plural = 'orbits',
    level = 4,
    color = '#9fd8cf',
    motion = 'stationary',
    frames = orbit_frames(),
    period = 4,
  },
  {
    name = 'pulsar',
    plural = 'pulsars',
    level = 4,
    color = '#bfe3ff',
    motion = 'stationary',
    frames = {
      { { 0, 0, '·', level = 3 } },
      { { 0, 0, '✧', level = 5 } },
      { { 0, 0, '✦', level = 7 } },
      { { 0, 0, '✹', level = 8 } },
      { { 0, 0, '✦', level = 7 } },
      { { 0, 0, '✧', level = 5 } },
    },
    period = 1.5,
    life = { 10, 18 },
  },
  {
    name = 'nebula',
    plural = 'nebulas',
    level = 3,
    color = '#c9a7e8',
    motion = 'stationary',
    frames = nebula_frames(),
    period = 3,
    life = { 24, 40 },
    fade = 4,
  },
  {
    name = 'supernova',
    plural = 'supernovas',
    level = 2,
    color = '#ffd2a8',
    motion = 'stationary',
    frames = supernova_frames(),
    life = { 3.5, 5 },
    fade = 0.25,
  },
  {
    name = 'comet',
    plural = 'comets',
    level = 6,
    color = '#e9c889',
    motion = 'diagonal',
    speed = 2,
    sprite = { { 0, 0, '✧' }, { -1, 0, '•' }, { -2, 0, '·' }, { -3, 0, '·' } },
  },
  {
    name = 'satellite',
    plural = 'satellites',
    level = 4,
    color = '#b8c4d0',
    motion = 'straight',
    speed = 0.7,
    sprite = {
      { -1, 0, '╺', level = 5 },
      { 0, 0, '╋', level = 8, phase = 0 },
      { 1, 0, '╸', level = 5 },
    },
    spin = 1.2,
  },
  {
    name = 'ufo',
    plural = 'ufos',
    level = 3,
    color = '#9be07a',
    motion = 'straight',
    speed = 1.4,
    sprite = {
      { -2, 0, '◢', level = 8, phase = 0 },
      { -1, 0, '▀', level = 6 },
      { 0, 0, '◉', level = 7 },
      { 1, 0, '▀', level = 6 },
      { 2, 0, '◣', level = 8, phase = 0.5 },
    },
    spin = 0.8,
    bob = 1.6,
  },
  {
    name = 'ship',
    plural = 'ships',
    level = 6,
    color = '#c5d6ed',
    motion = 'straight',
    speed = 1,
    fleet = true,
  },
}

M.by_name = {}
for _, kind in ipairs(M.kinds) do
  M.by_name[kind.name] = kind
end

-- The configured level of an object kind by singular name.
function M.level(cfg, name)
  return cfg[M.by_name[name].plural]
end

-- The sprite to draw at this moment of an object's life.
function M.sprite(kind, object)
  if not kind.frames then
    return object.sprite
  end
  local count = #kind.frames
  local index
  if kind.period then
    index = math.floor(object.age / kind.period * count) % count + 1
  else
    index = math.min(count, math.floor(object.age / object.life * count) + 1)
  end
  return kind.frames[index]
end

-- Every cell any frame can touch, for finding a clear spot.
function M.footprint(kind)
  if not kind.footprint then
    local cells, seen = {}, {}
    for _, frame in ipairs(kind.frames or { kind.sprite }) do
      for _, cell in ipairs(frame) do
        local key = cell[1] .. ',' .. cell[2]
        if not seen[key] then
          seen[key] = true
          cells[#cells + 1] = cell
        end
      end
    end
    kind.footprint = cells
  end
  return kind.footprint
end

-- Rows a moving kind needs, including room to bob.
function M.height(kind, art)
  local top, bottom = 0, 0
  for _, cell in ipairs(art or kind.sprite) do
    top, bottom = math.min(top, cell[2]), math.max(bottom, cell[2])
  end
  return bottom - top + 1 + (kind.bob and 2 or 0)
end

return M
