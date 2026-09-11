local M = {}

M.defaults = {
  autostart = false,
  fps = 30,
  stars = 24,
  enabled = {
    stars = true,
    meteors = true,
    ships = true,
    moons = true,
    planets = true,
    comets = true,
  },
  margin = 3,
  cursor_row = true,
  blank_lines = false,
  below_eof = true,
  terminals = true,
  pause_on_focus_lost = true,
  max_lines = 50000,
  max_bytes = 2 * 1024 * 1024,
  -- Used only to shade foreground colors when Normal has no background.
  background = '#121418',
  colors = {
    stars = { '#f4f1de', '#ffe6a3' },
    meteors = '#e9c889',
    ships = '#c5d6ed',
    moons = '#f4f1de',
    planets = '#ffe6a3',
    comets = '#e9c889',
  },
  excluded_filetypes = { 'alpha', 'dashboard', 'snacks_dashboard', 'neo-tree', 'NvimTree', 'oil' },
  twinkle = { '·', '∘', '✧', '✦' },
  meteor = { enabled = true, interval = { 25, 60 }, speed = 24, trail = 6 },
  objects = {
    enabled = true,
    interval = { 15, 35 },
    speed = 3,
    types = { 'moon', 'planet', 'comet', 'ship' },
    ships = {
      { right = '╞═◉═╡', left = '╞═◉═╡' },
      { right = { '  ▄  ', '╰─○─╯' }, left = { '  ▄  ', '╰─○─╯' } },
    },
  },
}

local function fail(key, expected)
  error('stardust: ' .. key .. ' must be ' .. expected, 3)
end

local function number(key, value, low, high, integer)
  if
    type(value) ~= 'number'
    or value ~= value
    or value < low
    or value > high
    or (integer and value % 1 ~= 0)
  then
    fail(key, ('%s between %s and %s'):format(integer and 'an integer' or 'a number', low, high))
  end
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
  if opts ~= nil and type(opts) ~= 'table' then
    fail('options', 'a table')
  end
  opts = opts or {}
  if opts.palette ~= nil then
    error('stardust: palette was replaced by colors.stars (a list of #RRGGBB colors)', 2)
  end
  for key in pairs(opts) do
    if M.defaults[key] == nil then
      fail(key, 'a recognized option')
    end
  end
  for _, section in ipairs({ 'meteor', 'objects', 'enabled', 'colors' }) do
    if opts[section] ~= nil then
      if type(opts[section]) ~= 'table' then
        fail(section, 'a table')
      end
      for key in pairs(opts[section]) do
        if M.defaults[section][key] == nil then
          fail(section .. '.' .. key, 'a recognized option')
        end
      end
    end
  end
  local cfg = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), vim.deepcopy(opts))
  for _, key in ipairs({
    'autostart',
    'cursor_row',
    'blank_lines',
    'below_eof',
    'terminals',
    'pause_on_focus_lost',
  }) do
    if type(cfg[key]) ~= 'boolean' then
      fail(key, 'a boolean')
    end
  end
  number('fps', cfg.fps, 1, 30, true)
  number('stars', cfg.stars, 0, 100, true)
  number('margin', cfg.margin, 1, 12, true)
  number('max_lines', cfg.max_lines, 1, 1000000, true)
  number('max_bytes', cfg.max_bytes, 1, 100 * 1024 * 1024, true)
  color('background', cfg.background)
  list('colors.stars', cfg.colors.stars, 1, 8, color)
  for _, kind in ipairs({ 'stars', 'meteors', 'ships', 'moons', 'planets', 'comets' }) do
    if type(cfg.enabled[kind]) ~= 'boolean' then
      fail('enabled.' .. kind, 'a boolean')
    end
    if kind ~= 'stars' then
      color('colors.' .. kind, cfg.colors[kind])
    end
  end
  list('excluded_filetypes', cfg.excluded_filetypes, 0, 100, function(key, value)
    if type(value) ~= 'string' then
      fail(key, 'a string')
    end
  end)
  list('twinkle', cfg.twinkle, 2, 8, function(key, value)
    if
      type(value) ~= 'string'
      or value:find('%c')
      or value:find('%s')
      or vim.fn.strdisplaywidth(value) ~= 1
    then
      fail(key, 'one printable, single-cell glyph')
    end
  end)
  number('meteor.speed', cfg.meteor.speed, 1, 60, false)
  number('meteor.trail', cfg.meteor.trail, 1, 12, true)
  number('objects.speed', cfg.objects.speed, 1, 20, false)
  list('objects.types', cfg.objects.types, 1, 4, function(key, value)
    if value ~= 'moon' and value ~= 'planet' and value ~= 'comet' and value ~= 'ship' then
      fail(key, 'moon, planet, comet, or ship')
    end
  end)
  cfg.objects._ships = {}
  list('objects.ships', cfg.objects.ships, 1, 16, function(key, value)
    if type(value) ~= 'table' then
      fail(key, 'a ship definition with right and left artwork')
    end
    for field in pairs(value) do
      if field ~= 'right' and field ~= 'left' and field ~= 'color' then
        fail(key .. '.' .. field, 'right, left, or color')
      end
    end
    if value.color ~= nil then
      color(key .. '.color', value.color)
    end
    cfg.objects._ships[#cfg.objects._ships + 1] = {
      right = sprite(key .. '.right', value.right, 'right'),
      left = sprite(key .. '.left', value.left, 'left'),
    }
  end)
  for _, section in ipairs({ 'meteor', 'objects' }) do
    if type(cfg[section].enabled) ~= 'boolean' then
      fail(section .. '.enabled', 'a boolean')
    end
    list(section .. '.interval', cfg[section].interval, 2, 2, function(key, value)
      number(key, value, 1, 3600, false)
    end)
    if cfg[section].interval[1] > cfg[section].interval[2] then
      fail(section .. '.interval', 'in ascending order')
    end
  end
  return cfg
end

return M
