-- Try with: nvim -u examples/minimal.lua (from the repository root)
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.swapfile = false
vim.opt.fillchars:append({ eob = ' ' })
vim.api.nvim_set_hl(0, 'Normal', { fg = '#dcdfe4' })
require('stardust').setup()
