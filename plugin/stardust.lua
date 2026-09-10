if vim.g.loaded_stardust then
  return
end
vim.g.loaded_stardust = true
if vim.fn.has('nvim-0.10') == 0 then
  vim.notify('Stardust requires Neovim 0.10 or newer', vim.log.levels.ERROR)
  return
end
require('stardust').register_commands()
