-- Every celestial object kind in one place. Adding an entry here adds its
-- 0-10 option, its color, its preview command, and its spawn timer.
--
--   name    singular name used by object(kind) and :Stardust <kind>
--   plural  option and color key
--   level   default frequency, 0-10
--   color   default foreground color
--   motion  'stationary' fades in place; 'straight' and 'diagonal' cross the view
--   speed   cells per second multiplier for moving kinds
--   sprite  { { dx, dy, glyph }, ... } around the anchor; for 'diagonal' dx is
--           measured in flight steps behind the head
--   fleet   true when artwork comes from the fleet option instead of sprite
local M = {}

M.kinds = {
  {
    name = 'moon',
    plural = 'moons',
    level = 6,
    color = '#f4f1de',
    motion = 'stationary',
    sprite = { { 0, 0, '☾' } },
  },
  {
    name = 'planet',
    plural = 'planets',
    level = 6,
    color = '#ffe6a3',
    motion = 'stationary',
    sprite = { { 0, 0, '◉' }, { -1, 0, '─' }, { 1, 0, '─' } },
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

return M
