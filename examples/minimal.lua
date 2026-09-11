-- Try with: nvim -u /home/paul/Repos/Stardust/examples/minimal.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
vim.opt.termguicolors = true
vim.opt.wrap = false
vim.opt.number = true
vim.opt.swapfile = false
vim.opt.fillchars:append({ eob = ' ' })
vim.api.nvim_set_hl(0, 'Normal', { fg = '#dcdfe4' })
vim.api.nvim_set_hl(0, 'LineNr', { fg = '#5c6370' })
require('stardust').setup({
  autostart = true,
  enabled = {
    stars = true,
    meteors = true,
    ships = true,
    moons = true,
    planets = true,
    comets = true,
  },
  colors = {
    stars = { '#f4f1de', '#ffe6a3' },
    meteors = '#e9c889',
    ships = '#c5d6ed',
    moons = '#f4f1de',
    planets = '#ffe6a3',
    comets = '#e9c889',
  },
  meteor = { speed = 24 },
  objects = {
    ships = {
      { right = '╞═◉═╡', left = '╞═◉═╡' },
      {
        right = { '  ▄  ', '╰─○─╯' },
        left = { '  ▄  ', '╰─○─╯' },
        color = '#a9cfff',
      },
    },
  },
})
