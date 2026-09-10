local M = {}

M.defaults = {
  autostart = false,
  fps = 15,
  stars = 24,
  margin = 3,
  cursor_row = true,
  blank_lines = false,
  below_eof = true,
  pause_on_focus_lost = true,
  max_lines = 50000,
  max_bytes = 2 * 1024 * 1024,
  -- Used only to shade foreground colors when Normal has no background.
  background = '#121418',
  palette = {}, -- Empty means derive colors from the active colorscheme.
  excluded_filetypes = { 'alpha', 'dashboard', 'snacks_dashboard', 'neo-tree', 'NvimTree', 'oil' },
  twinkle = { '·', '∘', '✧', '✦' },
  meteor = { enabled = true, interval = { 25, 60 }, speed = 18, trail = 6 },
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

function M.resolve(opts)
  if opts ~= nil and type(opts) ~= 'table' then
    fail('options', 'a table')
  end
  opts = opts or {}
  for key in pairs(opts) do
    if M.defaults[key] == nil then
      fail(key, 'a recognized option')
    end
  end
  if opts.meteor ~= nil then
    if type(opts.meteor) ~= 'table' then
      fail('meteor', 'a table')
    end
    for key in pairs(opts.meteor) do
      if M.defaults.meteor[key] == nil then
        fail('meteor.' .. key, 'a recognized option')
      end
    end
  end
  local cfg = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), vim.deepcopy(opts))
  for _, key in ipairs({
    'autostart',
    'cursor_row',
    'blank_lines',
    'below_eof',
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
  list('palette', cfg.palette, 0, 8, color)
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
  if type(cfg.meteor.enabled) ~= 'boolean' then
    fail('meteor.enabled', 'a boolean')
  end
  number('meteor.speed', cfg.meteor.speed, 1, 60, false)
  number('meteor.trail', cfg.meteor.trail, 1, 12, true)
  list('meteor.interval', cfg.meteor.interval, 2, 2, function(key, value)
    number(key, value, 1, 3600, false)
  end)
  if cfg.meteor.interval[1] > cfg.meteor.interval[2] then
    fail('meteor.interval', 'in ascending order')
  end
  return cfg
end

return M
