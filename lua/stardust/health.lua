local M = {}

function M.check()
  vim.health.start('Stardust')
  if vim.fn.has('nvim-0.10') == 1 then
    vim.health.ok('Neovim supports the required decoration APIs')
  else
    vim.health.error('Neovim 0.10 or newer is required')
  end
  if vim.o.termguicolors then
    vim.health.ok('True color is enabled')
  else
    vim.health.warn('Set termguicolors for smooth brightness changes')
  end
  if vim.o.ambiwidth == 'double' then
    vim.health.warn(
      'ambiwidth=double makes the built-in glyphs two cells wide; artwork must use narrow characters'
    )
  else
    vim.health.ok('Glyphs render as single cells')
  end
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  vim.health.info(
    normal.bg and 'Normal has a background color; stars preserve it'
      or 'Normal has no background color; terminal transparency is preserved'
  )
  local status = require('stardust').status()
  vim.health.info(
    status.active and ('Running in %d eligible visible windows'):format(status.windows)
      or 'Stopped; use :Stardust start'
  )
  for win, reason in pairs(status.skipped) do
    vim.health.info(('Window %d skipped: %s'):format(win, reason))
  end
end

return M
