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
  local colors = #cfg.palette > 0 and cfg.palette
    or {
      get('Normal', 'fg', '#c5cad3'),
      get('Identifier', 'fg', '#89b4cf'),
      get('Special', 'fg', '#c9b3d5'),
    }
  local background = get('Normal', 'bg', cfg.background)
  local groups = {}
  for index, fg in ipairs(colors) do
    groups[index] = {}
    for level = 1, M.levels do
      local name = ('StardustStar%d_%d'):format(index, level)
      -- Deliberately foreground-only: retain terminal transparency and selections.
      vim.api.nvim_set_hl(0, name, { fg = shade(fg, background, 0.15 + level * 0.1) })
      groups[index][level] = name
    end
  end
  local meteor = {}
  for level = 1, M.levels do
    local name = 'StardustMeteor' .. level
    vim.api.nvim_set_hl(0, name, { fg = shade('#e9c889', background, 0.15 + level * 0.1) })
    meteor[level] = name
  end
  return { stars = groups, meteor = meteor }
end

return M
