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

function M.setup(cfg)
  local function get(name, key, fallback)
    local hl = vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
    return hl[key] and ('#%06x'):format(hl[key]) or fallback
  end
  local background = get('Normal', 'bg', cfg.background)
  local function ramp(prefix, fg)
    local groups = {}
    for level = 1, M.levels do
      local name = prefix .. level
      -- Deliberately foreground-only: retain terminal transparency and selections.
      vim.api.nvim_set_hl(0, name, { fg = shade(fg, background, 0.15 + level * 0.1) })
      groups[level] = name
    end
    return groups
  end
  local result = { stars = {}, ships = {} }
  for index, fg in ipairs(cfg.colors.stars) do
    result.stars[index] = ramp(('StardustStar%d_'):format(index), fg)
  end
  for _, kind in ipairs({ 'meteor', 'moon', 'planet', 'comet', 'ship' }) do
    result[kind] = ramp('Stardust' .. kind:gsub('^%l', string.upper), cfg.colors[kind .. 's'])
  end
  for index, ship in ipairs(cfg.objects.ships) do
    result.ships[index] = ship.color and ramp(('StardustShip%d_'):format(index), ship.color)
      or result.ship
  end
  return result
end

return M
