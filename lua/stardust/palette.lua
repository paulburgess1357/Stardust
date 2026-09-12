local objects = require('stardust.objects')
local M = { levels = 8 }

local function rgb(value)
  return tonumber(value:sub(2, 3), 16), tonumber(value:sub(4, 5), 16), tonumber(value:sub(6, 7), 16)
end

local function shade(fg, bg, strength)
  local r, g, b = rgb(fg)
  local br, bgc, bb = rgb(bg)
  local function mix(a, base)
    return math.floor(base + (a - base) * strength + 0.5)
  end
  return ('#%02x%02x%02x'):format(mix(r, br), mix(g, bgc), mix(b, bb))
end

local function brightness(color)
  local r, g, b = rgb(color)
  return (r * 0.2126 + g * 0.7152 + b * 0.0722) / 255
end

function M.setup(cfg)
  local function get(name, key, fallback)
    local hl = vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
    return hl[key] and ('#%06x'):format(hl[key]) or fallback
  end
  -- A transparent terminal does not expose its background through Normal.
  local fallback = vim.o.background == 'light' and '#f5f5f0' or '#121418'
  local background = get('Normal', 'bg', fallback)
  local function ramp(prefix, fg)
    local groups = {}
    if math.abs(brightness(fg) - brightness(background)) < 0.4 then
      local contrast = brightness(background) > 0.5 and '#161820' or '#f4f1ed'
      fg = shade(fg, contrast, 0.4)
    end
    for level = 1, M.levels do
      local name = prefix .. level
      -- Deliberately foreground-only: retain terminal transparency and selections.
      vim.api.nvim_set_hl(0, name, { fg = shade(fg, background, 0.15 + level * 0.1) })
      groups[level] = name
    end
    return groups
  end
  local function group(name)
    return 'Stardust' .. name:gsub('^%l', string.upper)
  end
  local result = { stars = {}, fleet = {} }
  for index, fg in ipairs(cfg.colors.stars) do
    result.stars[index] = ramp(('StardustStar%d_'):format(index), fg)
  end
  result.meteor = ramp(group('meteor'), cfg.colors.meteors)
  for _, kind in ipairs(objects.kinds) do
    result[kind.name] = ramp(group(kind.name), cfg.colors[kind.plural])
  end
  for index, ship in ipairs(cfg.fleet) do
    result.fleet[index] = ship.color and ramp(('StardustShip%d_'):format(index), ship.color)
      or result.ship
  end
  result.enemy = ramp('StardustEnemy', '#e58d91')
  result.laser = ramp('StardustLaser', '#f6c765')
  return result
end

return M
