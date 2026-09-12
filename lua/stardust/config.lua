local objects = require('stardust.objects')
local M = {}

-- Levels run from 0 (off) to 10 (constant). See README.md for the scale.
M.defaults = {
  fps = 60,
  floating_windows = false,
  stars = 3,
  meteors = 7,
  showers = 3,
  battles = 3,
  colors = {
    stars = { '#f4f1de', '#ffe6a3' },
    meteors = '#e9c889',
  },
  -- stylua: ignore
  fleet = {
    { right = '╺══◈══►', left = '◄══◈══╸' },
    { right = '·∘○╡═◉═╞▶', left = '◀╡═◉═╞○∘·' },
    { right = '─═◆═▶', left = '◀═◆═─' },
    { right = '╾──◈──╼▶', left = '◀╾──◈──╼' },
    { right = '◖◉▶', left = '◀◉◗' },
    { right = '·─◆▶', left = '◀◆─·' },
    { right = '∘═◉═▶', left = '◀═◉═∘' },
    {
      right = {
        '  ▄▖',
        '╾═◉▐▶',
      },
      left = {
        ' ▗▄',
        '◀▌◉═╼',
      },
    },
    {
      right = {
        '▗▖',
        '▐◉▶',
      },
      left = {
        ' ▗▖',
        '◀◉▌',
      },
    },
    {
      right = {
        ' ▄▄',
        '╾◉◉▶',
      },
      left = {
        ' ▄▄',
        '◀◉◉╼',
      },
    },
  },
}
for _, kind in ipairs(objects.kinds) do
  M.defaults[kind.plural] = kind.level
  M.defaults.colors[kind.plural] = kind.color
end

local option_names = {}
for key in pairs(M.defaults) do
  option_names[#option_names + 1] = key
end
table.sort(option_names)

local function fail(key, expected)
  error('stardust: ' .. key .. ' must be ' .. expected, 3)
end

local function number(key, value, low, high)
  if type(value) ~= 'number' or value ~= value or value < low or value > high or value % 1 ~= 0 then
    fail(key, ('an integer between %s and %s'):format(low, high))
  end
end

local function level(key, value)
  number(key, value, 0, 10)
end

local function color(key, value)
  if type(value) ~= 'string' or not value:match('^#%x%x%x%x%x%x$') then
    fail(key, 'a #RRGGBB color')
  end
end

local function list(key, value, low, high, check)
  if type(value) ~= 'table' or not vim.islist(value) or #value < low or #value > high then
    fail(key, ('a list containing %d to %d items'):format(low, high))
  end
  for i, item in ipairs(value) do
    check(key .. '[' .. i .. ']', item)
  end
end

local function sprite(key, art, direction)
  local rows = type(art) == 'string' and { art } or art
  local parsed, width = {}, 0
  list(key, rows, 1, 4, function(row_key, row)
    if type(row) ~= 'string' or row:find('%c') then
      fail(row_key, 'a printable string without tabs or newlines')
    end
    local chars = vim.fn.split(row, '\\zs')
    if #chars > 16 then
      fail(row_key, 'at most 16 single-cell glyphs wide')
    end
    for _, char in ipairs(chars) do
      if vim.fn.strdisplaywidth(char) ~= 1 then
        fail(row_key, 'made of single-cell glyphs and spaces')
      end
    end
    parsed[#parsed + 1] = chars
    width = math.max(width, #chars)
  end)
  local cells = {}
  for y, chars in ipairs(parsed) do
    for x, char in ipairs(chars) do
      if char ~= ' ' then
        -- Offsets are measured behind the leading edge in either direction.
        cells[#cells + 1] = { direction == 'right' and x - width or 1 - x, y - 1, char }
      end
    end
  end
  if #cells == 0 then
    fail(key, 'artwork containing at least one visible glyph')
  end
  return { cells = cells, height = #rows }
end

function M.resolve(opts)
  if opts == nil then
    opts = {}
  end
  if type(opts) ~= 'table' then
    fail('options', 'a table')
  end
  for key in pairs(opts) do
    if M.defaults[key] == nil then
      fail(key, 'one of: ' .. table.concat(option_names, ', '))
    end
  end
  local cfg = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), vim.deepcopy(opts))
  number('fps', cfg.fps, 1, 120)
  if type(cfg.floating_windows) ~= 'boolean' then
    fail('floating_windows', 'a boolean')
  end
  level('stars', cfg.stars)
  level('meteors', cfg.meteors)
  level('showers', cfg.showers)
  level('battles', cfg.battles)
  -- Object kinds with a level above zero, in registry order.
  cfg.objects = {}
  for _, kind in ipairs(objects.kinds) do
    level(kind.plural, cfg[kind.plural])
    if cfg[kind.plural] > 0 then
      cfg.objects[#cfg.objects + 1] = kind.name
    end
  end
  if type(cfg.colors) ~= 'table' then
    fail('colors', 'a table')
  end
  for key, value in pairs(cfg.colors) do
    if M.defaults.colors[key] == nil then
      fail('colors.' .. key, 'a recognized color category')
    end
    if key == 'stars' then
      list('colors.stars', value, 1, 8, color)
    else
      color('colors.' .. key, value)
    end
  end
  cfg.art = {}
  list('fleet', cfg.fleet, 1, 16, function(key, value)
    if type(value) ~= 'table' then
      fail(key, 'a ship with right and left artwork')
    end
    for field in pairs(value) do
      if field ~= 'right' and field ~= 'left' and field ~= 'color' then
        fail(key .. '.' .. field, 'right, left, or color')
      end
    end
    if value.color ~= nil then
      color(key .. '.color', value.color)
    end
    cfg.art[#cfg.art + 1] = {
      right = sprite(key .. '.right', value.right, 'right'),
      left = sprite(key .. '.left', value.left, 'left'),
    }
  end)
  return cfg
end

return M
